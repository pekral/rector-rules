#!/usr/bin/env bash
# audit-artifacts.sh — the deterministic half of the security-audit skill: the execution budget
# and the validation of the four artefacts a run writes.
#
# Why this exists
#   The skill promises two things a model cannot promise about itself: hunting never consumes the
#   capacity reserved for verifiers and coverage critics, and the JSON artefacts follow their
#   schemas. Both are checked here, by a script, so the answer does not depend on the run that
#   produced the artefacts.
#
#   No JSON Schema library is installed in this package, and the check must not add a dependency.
#   The validator below is a jq program that applies the subset of JSON Schema the three schemas
#   in ../schemas use: type, const, enum, required, properties, additionalProperties: false, items,
#   contains, minItems, minLength, pattern, minimum, maximum, $ref into #/$defs, allOf, anyOf, and
#   if/then. A schema keyword outside that subset is ignored, so a schema change that needs a new
#   keyword must extend the validator and its --self-test in the same change.
#
# Usage
#   audit-artifacts.sh budget --profile <quick|standard|deep> [--total <passes>]
#   audit-artifacts.sh validate <run-dir>
#   audit-artifacts.sh --self-test
#
# budget
#   Prints the execution budget as one line of JSON. The unit is a pass: one bounded worker pass
#   (hunt one subsystem, verify one candidate, or one coverage-critic review). The verifier reserve
#   and the coverage-critic reserve are taken from the total first, each at least one pass, and the
#   remainder is the most hunting may spend. Exits 1 when the total is too small to leave hunting
#   one pass.
#
# validate
#   Checks <run-dir>/metadata.json, coverage-ledger.json, findings.json, and REPORT.md. Each JSON
#   artefact must follow its schema, then the cross-artefact rules must hold: hunting spent within
#   hunting_max, the reserves intact, the counts equal to findings.json, unique fingerprints and
#   ledger ids, no ledger row left queued or in review, and every fingerprint a ledger row lists
#   present in findings.json. The budget in metadata.json must equal the split `budget` prints for
#   its profile and total. A file holding more than one JSON
#   document is not valid JSON. REPORT.md must carry every heading the template defines.
#
# Output (stdout, JSON for validate)
#   { "valid": true, "run_dir": "…", "problems": [] }
#
# Exit codes
#   0  success
#   1  usage error
#   2  a required tool is missing (jq)
#   3  the run directory is invalid
set -euo pipefail

PROG="${0##*/}"
HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
SCHEMA_DIR="$HERE/../schemas"

tmp=''

REPORT_HEADINGS=(
  '## Scope'
  '## Budget'
  '## Confirmed findings'
  '## Needs validation'
  '## Rejected candidates'
  '## Coverage'
)

usage() {
  cat >&2 <<'EOF'
Usage: audit-artifacts.sh budget --profile <quick|standard|deep> [--total <passes>]
       audit-artifacts.sh validate <run-dir>
       audit-artifacts.sh --self-test

Exit 3 when the run directory breaks a schema, a budget rule, or a cross-artefact rule.
EOF
}

require_tools() {
  if ! command -v jq >/dev/null 2>&1; then
    echo "$PROG: required tool not found: jq" >&2
    exit 2
  fi
}

# --- budget ---------------------------------------------------------------------------------------

# profile_params <profile> — sets DEFAULT_TOTAL, VERIFIER_PCT, and CRITIC_PCT. The profiles are audit
# depths. They are not the risk tiers FAST, STANDARD, and CRITICAL of classify-risk.sh.
profile_params() {
  case "$1" in
  quick)
    DEFAULT_TOTAL=20
    VERIFIER_PCT=30
    CRITIC_PCT=10
    ;;
  standard)
    DEFAULT_TOTAL=60
    VERIFIER_PCT=30
    CRITIC_PCT=15
    ;;
  deep)
    DEFAULT_TOTAL=180
    VERIFIER_PCT=35
    CRITIC_PCT=20
    ;;
  *) return 1 ;;
  esac
}

# ceil_share <total> <percent> — the share rounded up, never below one pass.
ceil_share() {
  local share=$((($1 * $2 + 99) / 100))
  [[ $share -lt 1 ]] && share=1
  printf '%s' "$share"
}

cmd_budget() {
  local profile='' total=''
  while [[ $# -gt 0 ]]; do
    case "$1" in
    --profile)
      [[ $# -ge 2 ]] || { usage; exit 1; }
      profile="$2"
      shift 2
      ;;
    --total)
      [[ $# -ge 2 ]] || { usage; exit 1; }
      total="$2"
      shift 2
      ;;
    *)
      usage
      exit 1
      ;;
    esac
  done

  if ! profile_params "$profile"; then
    echo "$PROG: unknown profile '$(printf '%s' "$profile" | LC_ALL=C tr -cd '[:print:]' | cut -c1-40)' (expected quick, standard, or deep)" >&2
    exit 1
  fi
  total="${total:-$DEFAULT_TOTAL}"
  if [[ ! "$total" =~ ^[1-9][0-9]{0,5}$ ]]; then
    echo "$PROG: --total must be a whole number of passes without a leading zero" >&2
    exit 1
  fi

  local verifier critic hunting
  verifier="$(ceil_share "$total" "$VERIFIER_PCT")"
  critic="$(ceil_share "$total" "$CRITIC_PCT")"
  hunting=$((total - verifier - critic))
  if [[ $hunting -lt 1 ]]; then
    echo "$PROG: a total of $total passes leaves hunting no pass after the reserves of $verifier and $critic" >&2
    exit 1
  fi

  jq -cn --argjson total "$total" --argjson hunting "$hunting" --argjson verifier "$verifier" --argjson critic "$critic" \
    '{unit: "passes", total: $total, hunting_max: $hunting, verifier_reserve: $verifier, coverage_critic_reserve: $critic}'
}

# --- validation -----------------------------------------------------------------------------------

# The program text below ships with this script. An artefact never contributes to it.
JQ_SCHEMA=''
IFS= read -r -d '' JQ_SCHEMA <<'EOF' || true
def typeok($v; $t):
  ($v | type) as $jt
  | if $t == "integer" then ($jt == "number" and $v == ($v | floor))
    elif $t == "number" then $jt == "number"
    else $jt == $t end;

def errs($root; $s0; $v; $p):
  (if $s0 | has("$ref") then ($root | getpath($s0["$ref"] | ltrimstr("#/") | split("/"))) else $s0 end) as $s
  | ($v | type) as $vt
  | [
      (if $s | has("type") then
         ([$s["type"]] | flatten) as $ts
         | if any($ts[]; typeok($v; .)) then empty else "\($p): expected \($ts | join(" or ")), got \($vt)" end
       else empty end),
      (if $s | has("const") then
         (if $v == $s["const"] then empty else "\($p): must equal \($s["const"] | tojson), got \($v | tojson)" end)
       else empty end),
      (if $s | has("enum") then
         (if any($s["enum"][]; . == $v) then empty else "\($p): must be one of \($s["enum"] | map(tojson) | join(", ")), got \($v | tojson)" end)
       else empty end),
      (if $vt == "string" then
         (if ($s | has("minLength")) and (($v | length) < $s["minLength"]) then "\($p): shorter than \($s["minLength"])" else empty end),
         (if ($s | has("pattern")) and (($v | test($s["pattern"])) | not) then "\($p): does not match \($s["pattern"])" else empty end)
       else empty end),
      (if $vt == "number" then
         (if ($s | has("minimum")) and ($v < $s["minimum"]) then "\($p): below the minimum \($s["minimum"])" else empty end),
         (if ($s | has("maximum")) and ($v > $s["maximum"]) then "\($p): above the maximum \($s["maximum"])" else empty end)
       else empty end),
      (if $vt == "array" then
         (if ($s | has("minItems")) and (($v | length) < $s["minItems"]) then "\($p): fewer than \($s["minItems"]) items" else empty end),
         (if $s | has("items") then (range(0; $v | length) as $i | errs($root; $s["items"]; $v[$i]; "\($p)[\($i)]")[]) else empty end),
         (if ($s | has("contains")) and (all($v[]; errs($root; $s["contains"]; .; $p) | length > 0)) then "\($p): no item matches \($s["contains"] | tojson)" else empty end)
       else empty end),
      (if $vt == "object" then
         (if $s | has("required") then ($s["required"][] | select(. as $k | ($v | has($k)) | not) | "\($p): missing required property \(.)") else empty end),
         (if $s | has("properties") then ($s["properties"] | to_entries[] | select(. as $e | $v | has($e.key)) | . as $e | errs($root; $e.value; $v[$e.key]; "\($p).\($e.key)")[]) else empty end),
         (if ($s | has("additionalProperties")) and ($s["additionalProperties"] == false) then
            ($v | keys[] | select(. as $k | ($s["properties"] // {}) | has($k) | not) | "\($p): unexpected property \(.)")
          else empty end)
       else empty end),
      (if $s | has("allOf") then ($s["allOf"][] | errs($root; .; $v; $p)[]) else empty end),
      (if ($s | has("anyOf")) and (all($s["anyOf"][]; errs($root; .; $v; $p) | length > 0)) then "\($p): matches none of the anyOf alternatives" else empty end),
      (if $s | has("if") then
         (if (errs($root; $s["if"]; $v; $p) | length) == 0 then
            (if $s | has("then") then errs($root; $s["then"]; $v; $p)[] else empty end)
          else
            (if $s | has("else") then errs($root; $s["else"]; $v; $p)[] else empty end)
          end)
       else empty end)
    ];

errs($schema[0]; $schema[0]; $doc[0]; "$")[]
EOF

# The rules JSON Schema cannot express: they relate fields, or relate the three artefacts.
JQ_CROSS=''
IFS= read -r -d '' JQ_CROSS <<'EOF' || true
$md[0].budget as $b
| $md[0].spent as $sp
| $fd[0].findings as $fs
| $lg[0].entries as $es
| ($fs | map(.fingerprint)) as $fps
| ($es | map(.id)) as $ids
| (
    (if ($b.hunting_max + $b.verifier_reserve + $b.coverage_critic_reserve) > $b.total
     then "budget: hunting_max plus both reserves exceed the total" else empty end),
    (if $sp.hunting > $b.hunting_max
     then "budget: hunting spent \($sp.hunting) passes, above hunting_max \($b.hunting_max), so it consumed the reserve for verifiers and coverage critics" else empty end),
    (if ($sp.hunting + $sp.verification + $sp.coverage_critic) > $b.total
     then "budget: \($sp.hunting + $sp.verification + $sp.coverage_critic) passes spent, above the total \($b.total)" else empty end),
    (["confirmed", "needs_validation", "rejected"][] as $v
     | ($fs | map(select(.verdict == $v)) | length) as $n
     | if $md[0].counts[$v] != $n then "metadata: counts.\($v) is \($md[0].counts[$v]) but findings.json holds \($n)" else empty end),
    (if ($fps | length) != ($fps | unique | length) then "findings: a fingerprint appears more than once" else empty end),
    (if ($ids | length) != ($ids | unique | length) then "coverage: a row id appears more than once" else empty end),
    ($es[] | select(.status == "queued" or .status == "in_review") | "coverage: \(.id) is still \(.status) in a finished run"),
    ($es[] | .id as $id | .findings[] | . as $f | select(any($fps[]; . == $f) | not) | "coverage: \($id) lists fingerprint \($f) that findings.json does not hold")
  )
EOF

# schema_problems <schema-file> <document-file> — one problem per line on stdout.
schema_problems() {
  jq -n -r --slurpfile schema "$1" --slurpfile doc "$2" "$JQ_SCHEMA"
}

cmd_validate() {
  [[ $# -eq 1 ]] || { usage; exit 1; }
  local dir="$1" problems='' ok_json=true name file schema

  if [[ ! -d "$dir" ]]; then
    echo "$PROG: not a directory: $(printf '%s' "$dir" | LC_ALL=C tr -cd '[:print:]' | cut -c1-160)" >&2
    exit 1
  fi

  for name in metadata coverage-ledger findings; do
    file="$dir/$name.json"
    if [[ ! -f "$file" ]]; then
      problems+="$name.json: missing"$'\n'
      ok_json=false
      continue
    fi
    if [[ "$(jq -s 'length' "$file" 2>/dev/null)" != 1 ]]; then
      problems+="$name.json: not valid JSON"$'\n'
      ok_json=false
      continue
    fi
    case "$name" in
    metadata) schema="$SCHEMA_DIR/metadata.schema.json" ;;
    coverage-ledger) schema="$SCHEMA_DIR/coverage.schema.json" ;;
    *) schema="$SCHEMA_DIR/findings.schema.json" ;;
    esac
    local found
    found="$(schema_problems "$schema" "$file")"
    if [[ -n "$found" ]]; then
      problems+="$(printf '%s\n' "$found" | sed "s|^|$name.json |")"$'\n'
      ok_json=false
    fi
  done

  if [[ "$ok_json" == true ]]; then
    local expected
    expected="$(cmd_budget --profile "$(jq -r .profile "$dir/metadata.json")" --total "$(jq -r .budget.total "$dir/metadata.json")" 2>/dev/null)" || expected=''
    jq -e --argjson want "${expected:-null}" '.budget == $want' "$dir/metadata.json" >/dev/null \
      || problems+="metadata: budget is not the split audit-artifacts.sh budget prints for this profile and total"$'\n'
    problems+="$(jq -n -r --slurpfile md "$dir/metadata.json" --slurpfile lg "$dir/coverage-ledger.json" --slurpfile fd "$dir/findings.json" "$JQ_CROSS")"$'\n'
  fi

  if [[ ! -s "$dir/REPORT.md" ]]; then
    problems+="REPORT.md: missing or empty"$'\n'
  else
    local heading
    for heading in "${REPORT_HEADINGS[@]}"; do
      grep -qxF "$heading" "$dir/REPORT.md" || problems+="REPORT.md: missing heading '$heading'"$'\n'
    done
  fi

  problems="$(printf '%s' "$problems" | sed '/^$/d')"
  local valid=true
  [[ -n "$problems" ]] && valid=false
  printf '%s' "$problems" | jq -Rsc --arg dir "$dir" --argjson valid "$valid" \
    '{valid: $valid, run_dir: $dir, problems: (split("\n") | map(select(length > 0)))}'
  [[ "$valid" == true ]] || exit 3
}

# --- self-test ------------------------------------------------------------------------------------

self_test() {
  require_tools
  local checks=0 failed=0
  tmp="$(mktemp -d)"
  trap 'rm -rf "$tmp"' EXIT

  pass() {
    checks=$((checks + 1))
    printf 'ok    %s\n' "$1"
  }
  fail() {
    failed=$((failed + 1))
    printf 'FAIL  %s\n' "$1" >&2
  }

  # expect_exit <label> <expected> <command...>
  expect_exit() {
    local label="$1" want="$2" rc=0
    shift 2
    ("$@") >"$tmp/out" 2>"$tmp/err" || rc=$?
    if [[ "$rc" -eq "$want" ]]; then pass "$label"; else fail "$label (exit $rc, wanted $want)"; fi
  }

  # build_run <dir> <profile> — a valid run directory for the profile.
  build_run() {
    local dir="$1" profile="$2" budget
    mkdir -p "$dir"
    budget="$(cmd_budget --profile "$profile")"
    jq -n --arg profile "$profile" --argjson budget "$budget" '{
      schema_version: 1, run_id: ("audit-" + $profile), profile: $profile,
      scope: {kind: "repository", target: "."}, commit: "0123456789abcdef0123456789abcdef01234567",
      started_at: "2026-01-01T10:00:00Z", finished_at: "2026-01-01T11:00:00Z",
      budget: $budget,
      spent: {hunting: ($budget.hunting_max - 1), verification: 1, coverage_critic: 1},
      counts: {confirmed: 1, needs_validation: 1, rejected: 1}}' >"$dir/metadata.json"
    jq -n '{schema_version: 1, entries: [
      {id: "S1", subsystem: "Auth", boundary: "src/Auth", files: ["src/Auth/Login.php"], status: "covered",
       reviewed_by: ["hunter", "verifier", "coverage_critic"], findings: ["aaaaaaaaaaaaaaaa", "bbbbbbbbbbbbbbbb", "cccccccccccccccc"]},
      {id: "S2", subsystem: "Docs", boundary: "docs", files: ["docs/index.md"], status: "skipped",
       reviewed_by: [], findings: [], reason: "no executable code and no attacker-reachable input"}]}' >"$dir/coverage-ledger.json"
    jq -n '
      def base($fp; $verdict; $severity; $demonstrated): {
        fingerprint: $fp, verdict: $verdict, severity: $severity, boundary: "unauthenticated request to account data",
        entrypoint: "POST /login", sink: "DB::select with an interpolated email", root_cause: "the email is concatenated into the query",
        evidence: [{location: "src/Auth/Login.php:42", observation: "the request email reaches the query string"}],
        remediation: "bind the email as a parameter", boundary_failure_demonstrated: $demonstrated};
      {schema_version: 1, findings: [
        base("aaaaaaaaaaaaaaaa"; "confirmed"; "high"; true),
        (base("bbbbbbbbbbbbbbbb"; "needs_validation"; "unrated"; false) + {validation_needed: "confirm the route is reachable without a session"}),
        (base("cccccccccccccccc"; "rejected"; "unrated"; false) + {rejection_reason: "the value is cast to an integer before the query"})]}' >"$dir/findings.json"
    {
      printf '# Security audit — fixture\n\n'
      local heading
      for heading in "${REPORT_HEADINGS[@]}"; do
        printf '%s\n\nNone.\n\n' "$heading"
      done
    } >"$dir/REPORT.md"
  }

  # mutate <dir> <file> <jq-filter> — rewrites one artefact of a run directory.
  mutate() {
    jq "$3" "$1/$2" >"$1/$2.new" && mv "$1/$2.new" "$1/$2"
  }

  # fresh <label> — a new valid standard run in $tmp/<label>.
  fresh() {
    build_run "$tmp/$1" standard
  }

  local profile
  for profile in quick standard deep; do
    build_run "$tmp/$profile" "$profile"
    expect_exit "profile $profile: four artefacts exist and validate" 0 cmd_validate "$tmp/$profile"
    if [[ -f "$tmp/$profile/metadata.json" && -f "$tmp/$profile/coverage-ledger.json" && -f "$tmp/$profile/findings.json" && -f "$tmp/$profile/REPORT.md" ]]; then
      pass "profile $profile: metadata.json, coverage-ledger.json, findings.json, REPORT.md written"
    else
      fail "profile $profile: an artefact is missing"
    fi
    if jq -e '.budget | .hunting_max >= 1 and .verifier_reserve >= 1 and .coverage_critic_reserve >= 1
      and (.hunting_max + .verifier_reserve + .coverage_critic_reserve) == .total' "$tmp/$profile/metadata.json" >/dev/null; then
      pass "profile $profile: budget keeps both reserves and sums to the total"
    else
      fail "profile $profile: budget reserves"
    fi
  done

  expect_exit 'budget: an unknown profile is refused' 1 cmd_budget --profile exhaustive
  expect_exit 'budget: the risk tier names are not profiles' 1 cmd_budget --profile CRITICAL
  expect_exit 'budget: a total that leaves hunting nothing is refused' 1 cmd_budget --profile standard --total 2
  expect_exit 'budget: a non-numeric total is refused' 1 cmd_budget --profile standard --total many
  expect_exit 'budget: a total with a leading zero is refused, not read as octal' 1 cmd_budget --profile standard --total 010
  expect_exit 'budget: a total of 08 is refused with the usage message' 1 cmd_budget --profile standard --total 08
  expect_exit 'budget: a total of zero is refused' 1 cmd_budget --profile standard --total 0
  expect_exit 'budget: the smallest total that leaves hunting one pass is accepted' 0 cmd_budget --profile quick --total 3
  if [[ "$(cmd_budget --profile quick --total 3)" == '{"unit":"passes","total":3,"hunting_max":1,"verifier_reserve":1,"coverage_critic_reserve":1}' ]]; then
    pass 'budget: an explicit total is split deterministically'
  else
    fail 'budget: explicit total split'
  fi
  if [[ "$(cmd_budget --profile deep --total 100)" == '{"unit":"passes","total":100,"hunting_max":45,"verifier_reserve":35,"coverage_critic_reserve":20}' ]]; then
    pass 'budget: deep reserves 35 and 20 of 100 passes'
  else
    fail 'budget: deep split'
  fi

  fresh hunting-exhausts
  mutate "$tmp/hunting-exhausts" metadata.json '.spent.hunting = .budget.total'
  expect_exit 'edge: hunting cannot spend the whole budget' 3 cmd_validate "$tmp/hunting-exhausts"
  if grep -q 'consumed the reserve' "$tmp/out"; then
    pass 'edge: the problem names the consumed reserve'
  else
    fail 'edge: reserve problem text'
  fi

  fresh hunting-over-max
  mutate "$tmp/hunting-over-max" metadata.json '.spent.hunting = .budget.hunting_max + 1'
  expect_exit 'edge: hunting cannot pass hunting_max by one pass' 3 cmd_validate "$tmp/hunting-over-max"

  fresh no-reserve
  mutate "$tmp/no-reserve" metadata.json '.budget.verifier_reserve = 0'
  expect_exit 'edge: a budget with no verifier reserve is invalid' 3 cmd_validate "$tmp/no-reserve"

  fresh no-critic-reserve
  mutate "$tmp/no-critic-reserve" metadata.json '.budget.coverage_critic_reserve = 0'
  expect_exit 'edge: a budget with no coverage-critic reserve is invalid' 3 cmd_validate "$tmp/no-critic-reserve"

  fresh overspent
  mutate "$tmp/overspent" metadata.json '.spent.verification = .budget.total'
  expect_exit 'edge: spending above the total is invalid' 3 cmd_validate "$tmp/overspent"

  fresh severity-without-proof
  mutate "$tmp/severity-without-proof" findings.json '.findings[1].severity = "high"'
  expect_exit 'edge: needs_validation with a definitive severity and no demonstrated failure is invalid' 3 cmd_validate "$tmp/severity-without-proof"

  fresh severity-with-proof
  mutate "$tmp/severity-with-proof" findings.json '.findings[1].severity = "high" | .findings[1].boundary_failure_demonstrated = true'
  expect_exit 'edge: needs_validation with a demonstrated boundary failure may carry a severity' 0 cmd_validate "$tmp/severity-with-proof"

  fresh confirmed-unrated
  mutate "$tmp/confirmed-unrated" findings.json '.findings[0].severity = "unrated"'
  expect_exit 'lifecycle: a confirmed finding needs a definitive severity' 3 cmd_validate "$tmp/confirmed-unrated"

  fresh confirmed-undemonstrated
  mutate "$tmp/confirmed-undemonstrated" findings.json '.findings[0].boundary_failure_demonstrated = false'
  expect_exit 'lifecycle: a confirmed finding needs a demonstrated boundary failure' 3 cmd_validate "$tmp/confirmed-undemonstrated"

  fresh needs-no-step
  mutate "$tmp/needs-no-step" findings.json 'del(.findings[1].validation_needed)'
  expect_exit 'lifecycle: needs_validation names what must be validated' 3 cmd_validate "$tmp/needs-no-step"

  fresh rejected-no-reason
  mutate "$tmp/rejected-no-reason" findings.json 'del(.findings[2].rejection_reason)'
  expect_exit 'lifecycle: a rejected finding states why' 3 cmd_validate "$tmp/rejected-no-reason"

  fresh rejected-demonstrated
  mutate "$tmp/rejected-demonstrated" findings.json '.findings[2].boundary_failure_demonstrated = true'
  expect_exit 'lifecycle: a rejected finding cannot claim a demonstrated boundary failure' 3 cmd_validate "$tmp/rejected-demonstrated"

  fresh budget-resplit
  mutate "$tmp/budget-resplit" metadata.json '.budget.hunting_max = 58 | .budget.verifier_reserve = 1 | .budget.coverage_critic_reserve = 1'
  expect_exit 'cross: the budget is the split the budget command prints for the profile and total' 3 cmd_validate "$tmp/budget-resplit"
  if grep -q 'budget is not the split' "$tmp/out"; then
    pass 'cross: the problem names the budget mismatch'
  else
    fail 'cross: budget mismatch problem text'
  fi

  fresh budget-total-zero
  mutate "$tmp/budget-total-zero" metadata.json '.budget.total = 0'
  expect_exit 'cross: a total the budget command refuses is a mismatch, not a crash' 3 cmd_validate "$tmp/budget-total-zero"

  fresh bad-verdict
  mutate "$tmp/bad-verdict" findings.json '.findings[0].verdict = "probable"'
  expect_exit 'lifecycle: a verdict outside the three is invalid' 3 cmd_validate "$tmp/bad-verdict"

  local field
  for field in fingerprint verdict severity boundary entrypoint sink root_cause evidence remediation; do
    fresh "missing-$field"
    mutate "$tmp/missing-$field" findings.json "del(.findings[0].$field)"
    expect_exit "schema: a finding without $field is invalid" 3 cmd_validate "$tmp/missing-$field"
  done

  fresh empty-evidence
  mutate "$tmp/empty-evidence" findings.json '.findings[0].evidence = []'
  expect_exit 'schema: a finding needs at least one evidence item' 3 cmd_validate "$tmp/empty-evidence"

  fresh extra-property
  mutate "$tmp/extra-property" findings.json '.findings[0].note = "x"'
  expect_exit 'schema: an unknown finding property is invalid' 3 cmd_validate "$tmp/extra-property"

  fresh bad-fingerprint
  mutate "$tmp/bad-fingerprint" findings.json '.findings[0].fingerprint = "not-a-hash"'
  expect_exit 'schema: a fingerprint is 16 lowercase hex digits' 3 cmd_validate "$tmp/bad-fingerprint"

  fresh duplicate-fingerprint
  mutate "$tmp/duplicate-fingerprint" findings.json '.findings[1].fingerprint = .findings[0].fingerprint'
  expect_exit 'cross: a fingerprint appears once' 3 cmd_validate "$tmp/duplicate-fingerprint"

  fresh count-mismatch
  mutate "$tmp/count-mismatch" metadata.json '.counts.confirmed = 2'
  expect_exit 'cross: counts equal findings.json' 3 cmd_validate "$tmp/count-mismatch"

  fresh queued-row
  mutate "$tmp/queued-row" coverage-ledger.json '.entries[0].status = "queued"'
  expect_exit 'cross: a finished run leaves no queued row' 3 cmd_validate "$tmp/queued-row"

  fresh ghost-fingerprint
  mutate "$tmp/ghost-fingerprint" coverage-ledger.json '.entries[0].findings += ["dddddddddddddddd"]'
  expect_exit 'cross: a ledger row lists only fingerprints findings.json holds' 3 cmd_validate "$tmp/ghost-fingerprint"

  fresh skip-no-reason
  mutate "$tmp/skip-no-reason" coverage-ledger.json 'del(.entries[1].reason)'
  expect_exit 'schema: a skipped row states why' 3 cmd_validate "$tmp/skip-no-reason"

  fresh covered-no-hunter
  mutate "$tmp/covered-no-hunter" coverage-ledger.json '.entries[0].reviewed_by = ["verifier"]'
  expect_exit 'schema: a covered row was hunted' 3 cmd_validate "$tmp/covered-no-hunter"

  fresh gap-row
  mutate "$tmp/gap-row" coverage-ledger.json '.entries[1].status = "gap" | .entries[1].reason = "hunting budget spent before this row"'
  expect_exit 'coverage: a gap with a reason is a valid final state' 0 cmd_validate "$tmp/gap-row"

  fresh missing-report
  rm "$tmp/missing-report/REPORT.md"
  expect_exit 'artefacts: a missing REPORT.md is invalid' 3 cmd_validate "$tmp/missing-report"

  fresh missing-ledger
  rm "$tmp/missing-ledger/coverage-ledger.json"
  expect_exit 'artefacts: a missing coverage-ledger.json is invalid' 3 cmd_validate "$tmp/missing-ledger"

  fresh broken-json
  printf '{ not json' >"$tmp/broken-json/findings.json"
  expect_exit 'artefacts: a findings.json that is not JSON is invalid' 3 cmd_validate "$tmp/broken-json"

  fresh two-documents
  printf '{"schema_version":1,"findings":"garbage"}\n' >>"$tmp/two-documents/findings.json"
  expect_exit 'artefacts: a findings.json holding two JSON documents is invalid' 3 cmd_validate "$tmp/two-documents"

  fresh report-heading
  grep -vxF '## Coverage' "$tmp/report-heading/REPORT.md" >"$tmp/report-heading/REPORT.new" && mv "$tmp/report-heading/REPORT.new" "$tmp/report-heading/REPORT.md"
  expect_exit 'artefacts: REPORT.md keeps every template heading' 3 cmd_validate "$tmp/report-heading"

  expect_exit 'usage: validate without a directory' 1 cmd_validate
  expect_exit 'usage: validate on a path that is not a directory' 1 cmd_validate "$tmp/nope"

  if [[ $failed -gt 0 ]]; then
    printf '%s of %s checks failed\n' "$failed" "$((checks + failed))" >&2
    exit 1
  fi
  printf 'self-test OK (%s checks)\n' "$checks"
}

main() {
  case "${1:-}" in
  --self-test)
    self_test
    ;;
  budget)
    require_tools
    shift
    cmd_budget "$@"
    ;;
  validate)
    require_tools
    shift
    cmd_validate "$@"
    ;;
  *)
    usage
    exit 1
    ;;
  esac
}

main "$@"
