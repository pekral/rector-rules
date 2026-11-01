#!/usr/bin/env bash
# audit-artifacts.sh — the deterministic half of the security-audit skill: the execution budget,
# the coverage inventory check, the root-cause fingerprint, the working-tree snapshot, the digest of
# a security path, the impact of a change since an earlier run, and the validation of the four
# artefacts a run writes.
#
# Why this exists
#   The skill promises things a model cannot promise about itself: hunting never consumes the
#   capacity reserved for verifiers and coverage critics, the inventory exists before the first
#   hunter opens, a hunter never verifies its own candidate, parallel workers leave the working
#   tree untouched, two candidates merge only on the same root-cause fingerprint, an incremental run
#   reuses a unit only when the bytes of its security path are unchanged, and the JSON artefacts
#   follow their schemas. All of it is checked here, by a script, so the answer does not depend on
#   the run that produced the artefacts.
#
#   No JSON Schema library is installed in this package, and the check must not add a dependency.
#   The validator below is a jq program that applies the subset of JSON Schema the three schemas
#   in ../schemas use: type, const, enum, required, properties, additionalProperties: false, items,
#   contains, minItems, minLength, pattern, minimum, maximum, $ref into #/$defs, allOf, anyOf, and
#   if/then/else. A schema keyword outside that subset is ignored, so a schema change that needs a
#   new keyword must extend the validator and its --self-test in the same change.
#
# Usage
#   audit-artifacts.sh budget --profile <quick|standard|deep> [--total <passes>]
#   audit-artifacts.sh snapshot [<dir>]
#   audit-artifacts.sh fingerprint <boundary> <source> <sink> <root_cause>
#   audit-artifacts.sh digest <path>...
#   audit-artifacts.sh impact <base-run-dir>
#   audit-artifacts.sh inventory <run-dir>
#   audit-artifacts.sh validate <run-dir>
#   audit-artifacts.sh --self-test
#
# budget
#   Prints the execution budget as one line of JSON. The unit is a pass: one bounded worker pass
#   (hunt one coverage unit, verify one candidate, or one coverage-critic review). The verifier
#   reserve and the coverage-critic reserve are taken from the total first, each at least one pass,
#   and the remainder is the most hunting may spend. Exits 1 when the total is too small to leave
#   hunting one pass.
#
# snapshot
#   Prints the SHA-256 of the state of the git working tree that holds <dir> (default: the current
#   directory): HEAD, the index, and the type, mode, and raw bytes of every tracked file and every
#   untracked, not ignored file. Git-ignored files, the run directory among them, do not count.
#   The same tree prints the same value. A write to a tracked file or to an untracked, not ignored
#   file changes it. The snapshot does not see a write to a git-ignored path, outside the work
#   tree, or inside a submodule or a nested git repository: such a write leaves the value as it is.
#   An unchanged value is no proof that a worker stayed read-only. The snapshot runs no program the
#   repository configures: it never runs `git status` or `git diff`, which run clean filters,
#   external diff programs, and hooks; it turns core.fsmonitor off; and it hashes raw bytes with
#   `git hash-object --no-filters`. Exits 1 outside a git work tree with a commit.
#
# fingerprint
#   Prints the 16-hex-digit fingerprint of a finding: the first 16 hex digits of the SHA-256 of
#   `boundary|source|sink|root_cause`, exactly as given. Each value must match its pattern in
#   findings.schema.json `$defs/fingerprint_basis`; exits 1 when one does not.
#
# digest
#   Prints the SHA-256 of the security path of a coverage unit: the type, the path, and the hash of
#   the raw bytes of every tracked file and every untracked, not ignored file that the given paths
#   name, read as literal paths relative to the top of the git work tree that holds the current
#   directory. Directories expand to the files under them. The order of the paths does not change
#   the value. A path that is git-ignored is refused (exit 1), because a change to it would not
#   change the digest: record a dependency by its lock file instead. A path that is a symbolic link
#   or passes through one is refused (exit 1), because the digest hashes the link and not its
#   target: the error names the target path to record instead. A symbolic link among the files the
#   paths name is refused (exit 1) unless the paths also hold its target: the error names the target
#   to add. A path that matches no tracked or untracked, not ignored file is refused (exit 1),
#   because its digest is the digest of the empty set. Like the snapshot, the digest runs no program
#   the repository configures.
#
# impact
#   Compares an earlier run, the base run, with the current working tree and prints the result as
#   one line of JSON: every path whose bytes or mode differ from the base run's commit (the git diff
#   from that commit to the working tree, read with plumbing commands only), the changed paths no
#   base unit holds, and a decision per base unit and per base finding. A covered unit is `reuse`
#   only when the digest of its paths and inputs equals the digest it recorded and every finding it
#   lists is held by reusable units only; otherwise it is `invalidated`. A unit the base run did not
#   cover is `uncovered`. A finding is `reuse` only when every unit that lists it is `reuse`;
#   otherwise it is `reverify`. Exits 3 when the base run is invalid or its commit is not in the
#   repository.
#
# inventory
#   Checks <run-dir>/coverage-ledger.json as the coverage inventory a run writes before the first
#   hunter opens: the run directory is git-ignored, the schema holds, every unit is `queued` or
#   `out_of_scope`, no unit has an agent or a finding yet, no wave is recorded, and every
#   coverage_id is unique. A run directory that is not git-ignored is refused, because the
#   coordinator's own writes to it would change the working-tree snapshot. A unit an incremental
#   run reuses from its base run is the one exception to the rules above, and it must pass the reuse
#   rules of validate already.
#
# validate
#   Checks <run-dir>/metadata.json, coverage-ledger.json, findings.json, and REPORT.md. Each JSON
#   artefact must follow its schema, then the cross-artefact rules must hold: hunting spent within
#   hunting_max, the reserves intact, the counts equal to findings.json, unique fingerprints and
#   coverage ids, every fingerprint the hash of its fingerprint_basis, no unit left queued or
#   candidate, every fingerprint a unit lists present in findings.json and hunted by that unit's
#   agent, the waves numbered in order with a fresh critic each and the working tree unchanged
#   after each, one hunter per unit, one verifier per finding, and the workers within the passes
#   spent. The budget in metadata.json must equal the split `budget` prints for its profile and
#   total. The run directory is named after its run_id. Every file a finding cites lies on the
#   paths or inputs of every unit that lists it. A covered unit's inputs_digest equals the digest of
#   its paths and inputs now, none of them is git-ignored, a symbolic link, beyond a symbolic link,
#   or a path that matches no file, and they hold the target of every symbolic link they hold. A
#   covered ai_tools unit or a covered action surface that
#   records a candidate threat or an action dimension that is not bound lists a finding. In an
#   incremental run (base_run set), the base run sits beside the run directory, every base unit is
#   in the ledger under its coverage_id, a reused unit or finding equals its base record, a reused
#   unit shares no finding with a unit this run hunts again, and a base finding is in findings.json
#   unless a base unit held it and every unit that held it is blocked or deferred. A file holding
#   more than one JSON document is not valid JSON. REPORT.md must carry every heading the template
#   defines.
#
# Output (stdout, JSON for inventory and validate)
#   { "valid": true, "run_dir": "…", "problems": [] }
#
# Exit codes
#   0  success
#   1  usage error
#   2  a required tool is missing (jq, sha256sum or shasum)
#   3  the run directory is invalid
set -euo pipefail

PROG="${0##*/}"
HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
SCHEMA_DIR="$HERE/../schemas"

scratch=''
tmp=''
UNIT_ID=''
UNIT_DIGEST=''
UNIT_ORIGIN=''
UNIT_PATHS=()
PATH_PROBLEM=''

REPORT_HEADINGS=(
  '## Scope'
  '## Budget'
  '## Confirmed findings'
  '## Needs validation'
  '## Rejected candidates'
  '## Coverage'
  '## Incremental basis'
)

usage() {
  cat >&2 <<'EOF'
Usage: audit-artifacts.sh budget --profile <quick|standard|deep> [--total <passes>]
       audit-artifacts.sh snapshot [<dir>]
       audit-artifacts.sh fingerprint <boundary> <source> <sink> <root_cause>
       audit-artifacts.sh digest <path>...
       audit-artifacts.sh impact <base-run-dir>
       audit-artifacts.sh inventory <run-dir>
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
  if ! command -v sha256sum >/dev/null 2>&1 && ! command -v shasum >/dev/null 2>&1; then
    echo "$PROG: required tool not found: sha256sum or shasum" >&2
    exit 2
  fi
}

# sha256_hex — the SHA-256 of stdin as 64 lowercase hex digits.
sha256_hex() {
  local out
  if command -v sha256sum >/dev/null 2>&1; then
    out="$(sha256sum)"
  else
    out="$(shasum -a 256)"
  fi
  printf '%s\n' "${out:0:64}"
}

# printable <value> — the value reduced to printable bytes, for an error message.
printable() {
  printf '%s' "$1" | LC_ALL=C tr -cd '[:print:]' | cut -c1-160
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
    echo "$PROG: unknown profile '$(printable "$profile" | cut -c1-40)' (expected quick, standard, or deep)" >&2
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

# --- snapshot -------------------------------------------------------------------------------------

# git_plain <dir> <git-args...> — git in <dir> with core.fsmonitor off, so it starts no fsmonitor hook.
git_plain() {
  local dir="$1"
  shift
  git -c core.fsmonitor=false -C "$dir" "$@"
}

cmd_snapshot() {
  [[ $# -le 1 ]] || { usage; exit 1; }
  local dir="${1:-.}" top
  if ! top="$(git_plain "$dir" rev-parse --show-toplevel 2>/dev/null)" || ! git_plain "$top" rev-parse -q --verify HEAD >/dev/null 2>&1; then
    echo "$PROG: not a git work tree with a commit: $(printable "$dir")" >&2
    exit 1
  fi
  {
    git_plain "$top" rev-parse HEAD
    git_plain "$top" ls-files -s -z
    digest_files "$top" | file_states "$top"
  } | sha256_hex
}

# file_states <top> — for every NUL-separated path on stdin, in order, one NUL-separated record:
# the type (file, exec, link, or absent), the path, and the git blob hash of its raw bytes, or of
# the target of a symbolic link. An absent path has an empty hash.
file_states() {
  local top="$1" file path i=0 hash
  local -a types=() files=() hashes=() batch=() slots=()
  while IFS= read -r -d '' file; do
    path="$top/$file"
    files[i]="$file"
    hashes[i]=''
    if [[ -L "$path" ]]; then
      types[i]='link'
      hashes[i]="$(printf '%s' "$(readlink "$path")" | git_plain "$top" hash-object --no-filters --stdin)"
    elif [[ ! -f "$path" ]]; then
      types[i]='absent'
    else
      if [[ -x "$path" ]]; then types[i]='exec'; else types[i]='file'; fi
      if [[ "$file" == *$'\n'* || "$file" == '"'* ]]; then
        hashes[i]="$(git_plain "$top" hash-object --no-filters -- "$file")"
      else
        batch+=("$file")
        slots+=("$i")
      fi
    fi
    i=$((i + 1))
  done
  if [[ ${#batch[@]} -gt 0 ]]; then
    local n=0
    while IFS= read -r hash; do
      hashes[slots[n]]="$hash"
      n=$((n + 1))
    done < <(printf '%s\n' "${batch[@]}" | git_plain "$top" hash-object --no-filters --stdin-paths)
  fi
  local k
  for ((k = 0; k < i; k++)); do
    printf '%s\0%s\0%s\0' "${types[k]}" "${files[k]}" "${hashes[k]}"
  done
}

# --- digest of a security path ---------------------------------------------------------------------

# ignored_paths <top> <path>... — the given paths that git ignores, separated by a space.
ignored_paths() {
  local top="$1" found
  shift
  found="$(printf '%s\0' "$@" | git_plain "$top" check-ignore -z --stdin | tr '\0' ' ')" || true
  printf '%s' "${found% }"
}

# The path logic every program that reads the paths of a unit shares. A unit holds a path when one
# of its paths or inputs is that path or a directory above it.
JQ_PATHS=''
IFS= read -r -d '' JQ_PATHS <<'EOF' || true
def holds($q; $p): ($q | rtrimstr("/")) as $r | ($r == "." or $p == $r or ($p | startswith($r + "/")));
def unit_paths: (.paths + [(.inputs // [])[].path]) | unique;
EOF

# link_target <top> <path> — the path, relative to <top>, that <path> resolves to through its
# symbolic links, or nothing when it resolves outside <top>.
link_target() {
  local top path dir hops=0
  top="$(cd "$1" && pwd -P)"
  path="$1/$2"
  while [[ -L "$path" && $hops -lt 40 ]]; do
    dir="$(dirname "$path")"
    path="$(readlink "$path")"
    [[ "$path" == /* ]] || path="$dir/$path"
    hops=$((hops + 1))
  done
  if [[ -d "$path" ]]; then
    path="$(cd "$path" && pwd -P)" || return 0
  else
    dir="$(cd "$(dirname "$path")" 2>/dev/null && pwd -P)" || return 0
    path="$dir/$(basename "$path")"
  fi
  if [[ "$path" == "$top" ]]; then
    printf '.'
  elif [[ "$path" == "$top/"* ]]; then
    printf '%s' "${path#"$top/"}"
  fi
}

# path_problem <top> <path> [listed] — sets PATH_PROBLEM to the reason the digest cannot prove the
# path unchanged, or to nothing. A symbolic link on the path hides a change to its target, and a
# path that matches no file hashes to the digest of the empty set. With `listed`, the caller
# already knows that git lists a file for the path.
path_problem() {
  local top="$1" path="${2%/}" rest prefix='' part target
  PATH_PROBLEM=''
  rest="$path"
  while [[ -n "$rest" && "$rest" != . ]]; do
    part="${rest%%/*}"
    if [[ "$rest" == */* ]]; then rest="${rest#*/}"; else rest=''; fi
    [[ -n "$part" ]] || continue
    prefix="${prefix:+$prefix/}$part"
    [[ -L "$top/$prefix" ]] || continue
    if [[ "$prefix" == "$path" ]]; then
      PATH_PROBLEM='is a symbolic link'
    else
      PATH_PROBLEM="passes through the symbolic link $(printable "$prefix")"
    fi
    target="$(link_target "$top" "$path")"
    if [[ -n "$target" ]]; then
      PATH_PROBLEM+=", so a change to its target would not change the digest; record $(printable "$target") instead"
    else
      PATH_PROBLEM+=" that resolves outside the work tree, which the digest does not see"
    fi
    return 0
  done
  if [[ "${3:-}" != listed ]] && ! digest_lists "$top" "$2"; then
    PATH_PROBLEM='matches no tracked or untracked, not ignored file, so its digest would prove nothing'
  fi
}

# link_problems <top> <path>... — one line for every symbolic link among the files the paths name
# whose target the paths do not hold, or whose target git does not list. The digest hashes the link
# and not its target, so a change to that target would not change the digest.
link_problems() {
  local top="$1" file target
  shift
  local -a pairs=()
  while IFS= read -r -d '' file; do
    [[ -L "$top/$file" ]] || continue
    target="$(link_target "$top" "$file")"
    if [[ -z "$target" ]] || ! digest_lists "$top" "$target"; then
      printf 'the symbolic link %s, whose target the digest does not see\n' "$(printable "$file")"
    else
      pairs+=("$file" "$target")
    fi
  done < <(digest_files "$top" "$@")
  [[ ${#pairs[@]} -gt 0 ]] || return 0
  while IFS= read -r -d '' file && IFS= read -r -d '' target; do
    printf 'the symbolic link %s, so a change to its target would not change the digest; record %s as an input too\n' "$(printable "$file")" "$(printable "$target")"
  done < <(printf '%s\0' "${pairs[@]}" | jq -R -s -j --args "$JQ_PATHS"'split("\u0000")[:-1] as $l | $ARGS.positional as $ps
    | range(0; $l | length; 2) as $i | select(any($ps[]; holds(.; $l[$i + 1])) | not) | "\($l[$i])\u0000\($l[$i + 1])\u0000"' "$@")
}

# digest_files <top> [<path>...] — the files the digest and the snapshot see, NUL-separated: every
# tracked and every untracked, not ignored file the literal paths name, or every such file of the
# work tree when no path is given. git prints each file once and in sorted order.
digest_files() {
  local top="$1"
  shift
  git_plain "$top" --literal-pathspecs ls-files -z --cached --others --exclude-standard -- "$@"
}

# digest_lists <top> <path>... — succeeds when every literal path names at least one file that
# digest_files lists.
digest_lists() {
  local top="$1"
  shift
  git_plain "$top" --literal-pathspecs ls-files --cached --others --exclude-standard --error-unmatch -- "$@" >/dev/null 2>&1
}

# paths_digest <top> <path>... — the SHA-256 of the states of the files digest_files lists for the
# paths. digest_files lists each file once and in sorted order, so the order of the paths does not
# change the value.
paths_digest() {
  local top="$1"
  shift
  digest_files "$top" "$@" | file_states "$top" | sha256_hex
}

# covered_units <ledger-file> — one NUL-separated record per covered unit: its coverage_id, its
# inputs_digest, `reused` or `hunted`, the number of its paths, and its paths and input paths, each
# once. Read it with next_unit.
covered_units() {
  jq -j "$JQ_PATHS"'.entries[] | select(.status == "covered")
    | [.coverage_id, .inputs_digest, (if has("reused_from") then "reused" else "hunted" end),
       (unit_paths | (length | tostring), .[])]
    | map(. + "\u0000") | add' "$1"
}

# next_unit — reads the next record of covered_units from file descriptor 3 into UNIT_ID,
# UNIT_DIGEST, UNIT_ORIGIN, and UNIT_PATHS. Returns non-zero at the end of the stream.
next_unit() {
  local count k path
  IFS= read -r -d '' -u 3 UNIT_ID || return 1
  IFS= read -r -d '' -u 3 UNIT_DIGEST
  IFS= read -r -d '' -u 3 UNIT_ORIGIN
  IFS= read -r -d '' -u 3 count
  UNIT_PATHS=()
  for ((k = 0; k < count; k++)); do
    IFS= read -r -d '' -u 3 path
    UNIT_PATHS+=("$path")
  done
}

# unit_digests <top> <ledger-file> [hunted] — a JSON object that maps the coverage_id of every
# covered unit, or with `hunted` of every covered unit this run hunted, to its digest now.
unit_digests() {
  local top="$1"
  while next_unit; do
    if [[ "${3:-}" != hunted || "$UNIT_ORIGIN" == hunted ]]; then
      printf '%s\0%s\0' "$UNIT_ID" "$(paths_digest "$top" "${UNIT_PATHS[@]}")"
    fi
  done 3< <(covered_units "$2") | jq -Rsc 'split("\u0000") | [range(0; length - 1; 2) as $i | {key: .[$i], value: .[$i + 1]}] | from_entries'
}

cmd_digest() {
  [[ $# -ge 1 ]] || { usage; exit 1; }
  local top path ignored found
  if ! top="$(git_plain . rev-parse --show-toplevel 2>/dev/null)"; then
    echo "$PROG: not a git work tree: $(printable "$PWD")" >&2
    exit 1
  fi
  for path in "$@"; do
    if ! jq -en --arg p "$path" --slurpfile schema "$SCHEMA_DIR/coverage.schema.json" '$p | test($schema[0]["$defs"].path.pattern)' >/dev/null; then
      echo "$PROG: not a path relative to the top of the work tree: $(printable "$path")" >&2
      exit 1
    fi
  done
  ignored="$(ignored_paths "$top" "$@")"
  if [[ -n "$ignored" ]]; then
    echo "$PROG: git ignores $(printable "$ignored"), so a change to it would not change the digest; record its lock file instead" >&2
    exit 1
  fi
  for path in "$@"; do
    path_problem "$top" "$path"
    if [[ -n "$PATH_PROBLEM" ]]; then
      echo "$PROG: $(printable "$path") $PATH_PROBLEM" >&2
      exit 1
    fi
  done
  found="$(link_problems "$top" "$@")"
  if [[ -n "$found" ]]; then
    while IFS= read -r path; do
      echo "$PROG: the paths hold $path" >&2
    done <<<"$found"
    exit 1
  fi
  paths_digest "$top" "$@"
}

# --- fingerprint ----------------------------------------------------------------------------------

# fingerprint_of <basis> — the first 16 hex digits of the SHA-256 of `boundary|source|sink|root_cause`.
fingerprint_of() {
  printf '%s' "$1" | sha256_hex | cut -c1-16
}

cmd_fingerprint() {
  [[ $# -eq 4 ]] || { usage; exit 1; }
  local found
  found="$(schema_problems "$SCHEMA_DIR/findings.schema.json" \
    <(jq -n --arg b "$1" --arg so "$2" --arg si "$3" --arg r "$4" '{boundary: $b, source: $so, sink: $si, root_cause: $r}') \
    "#/\$defs/fingerprint_basis")"
  if [[ -n "$found" ]]; then
    printf '%s: fingerprint basis is invalid\n%s\n' "$PROG" "$found" >&2
    exit 1
  fi
  fingerprint_of "$1|$2|$3|$4"
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

errs($schema[0]; (if $start == "" then $schema[0] else {"$ref": $start} end); $doc[0]; "$")[]
EOF

# The inventory rules JSON Schema cannot express: the ledger is a plan, nothing has been hunted yet.
# A unit reused from the base run is already covered; the reuse rules check it instead.
JQ_INVENTORY=''
IFS= read -r -d '' JQ_INVENTORY <<'EOF' || true
$lg[0].entries as $es
| ($es | map(select(has("reused_from") | not))) as $planned
| ($es | map(.coverage_id)) as $ids
| (
    (if ($ids | length) != ($ids | unique | length) then "coverage: a coverage_id appears more than once" else empty end),
    ($planned[] | select(.status != "queued" and .status != "out_of_scope") | "inventory: \(.coverage_id) is \(.status) before the first hunter opened"),
    ($planned[] | select(.agent != null) | "inventory: \(.coverage_id) already names agent \(.agent)"),
    ($planned[] | select((.findings | length) > 0) | "inventory: \(.coverage_id) already lists findings"),
    (if ($lg[0].waves | length) > 0 then "inventory: a hunting wave is recorded before the inventory was checked" else empty end)
  )
EOF

# The rules JSON Schema cannot express: they relate fields, or relate the three artefacts.
JQ_CROSS=''
IFS= read -r -d '' JQ_CROSS <<'EOF' || true
def cited: [
    (.evidence[].location, (.controls[] | select(has("location")) | .location) | sub(":[0-9]+(-[0-9]+)?$"; "")),
    (.fingerprint_basis.sink | split("#")[0]),
    (.fingerprint_basis.source | select(test("^[^ ]+#[^ ]+$")) | split("#")[0])
  ] | unique;
$md[0].budget as $b
| $md[0].spent as $sp
| $fd[0].findings as $fs
| $lg[0].entries as $es
| $lg[0].waves as $ws
| ($fs | map(.fingerprint)) as $fps
| ($es | map(.coverage_id)) as $ids
| ([$ws[].hunters[]]) as $wh
| ($es | map(select(has("reused_from") | not) | .agent | select(. != null))) as $agents
| ($fs | map(select(has("reused_from") | not) | .verifier | select(. != null))) as $vs
| ($ws | map(.critic)) as $cs
| (
    (if $md[0].run_id != $name then "metadata: run_id is \($md[0].run_id) but the run directory is \($name); a run directory is named after its run_id" else empty end),
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
    (if ($ids | length) != ($ids | unique | length) then "coverage: a coverage_id appears more than once" else empty end),
    ($es[] | select(.status == "queued" or .status == "candidate") | "coverage: \(.coverage_id) is still \(.status) in a finished run"),
    ($es[] | .coverage_id as $id | .findings[] | . as $f | select(any($fps[]; . == $f) | not) | "coverage: \($id) lists fingerprint \($f) that findings.json does not hold"),
    ($es[] | . as $e | .findings[] | . as $f | ($fs | map(select(.fingerprint == $f)) | first) as $x
     | select($x != null and ($e.agent == null or (any($x.hunters[]; . == $e.agent) | not)))
     | "coverage: \($e.coverage_id) lists \($f), but its agent is not one of that finding's hunters"),
    (if ($ws | map(.wave)) != [range(1; ($ws | length) + 1)] then "coverage: the waves are not numbered 1 to \($ws | length) in order" else empty end),
    (if ($cs | length) != ($cs | unique | length) then "critic: a coverage critic reviewed more than one wave; every wave gets a fresh critic" else empty end),
    (if ($ws | length) > $sp.coverage_critic then "critic: \($ws | length) waves but \($sp.coverage_critic) coverage-critic passes spent; every wave needs its own critic pass" else empty end),
    (if ($wh | length) != ($wh | unique | length) then "coverage: a hunter is opened more than once; one hunter is one pass on one coverage unit" else empty end),
    (if ($wh | length) > $sp.hunting then "coverage: the waves open \($wh | length) hunters but spent.hunting is \($sp.hunting)" else empty end),
    (if ($agents | length) != ($agents | unique | length) then "coverage: a hunter holds more than one coverage unit" else empty end),
    ($es[] | select(.agent != null and (has("reused_from") | not)) | . as $e | select(any($wh[]; . == $e.agent) | not) | "coverage: \(.coverage_id) names agent \(.agent), which no wave opened"),
    ($ws[] | .wave as $n | .gaps[] | select(has("coverage_id")) | .coverage_id as $c | select(any($ids[]; . == $c) | not)
     | "critic: wave \($n) closes a gap with \($c), which the ledger does not hold"),
    ($ws[] | select(.worktree != $md[0].worktree_baseline) | "parallel: the working tree changed during wave \(.wave); every worker must stay read-only"),
    (if ($vs | length) != ($vs | unique | length) then "findings: a verifier verified more than one finding; every candidate gets a new verifier" else empty end),
    (if ($vs | length) > $sp.verification then "findings: \($vs | length) verifiers but spent.verification is \($sp.verification)" else empty end),
    ($fs[] | select(has("reused_from") | not) | .fingerprint as $f | .hunters[] | . as $h | select(any($wh[]; . == $h) | not) | "findings: \($f) names hunter \($h), which no wave opened"),
    ($es[] | . as $e | unit_paths as $up | .findings[] as $f | ($fs | map(select(.fingerprint == $f)) | first) as $x | select($x != null)
     | ($x | cited)[] | . as $p | select(any($up[]; holds(.; $p)) | not)
     | "coverage: \($e.coverage_id) lists \($f), which cites \($p) outside the unit's paths and inputs; a change there would not invalidate the unit"),
    ($es[] | select(.status == "covered" and (.findings | length) == 0)
     | select(any((.threats // [])[]; .outcome == "candidate") or any((.action_binding // {})[]; .status != "bound"))
     | "coverage: \(.coverage_id) records a candidate threat or an action dimension that is not bound, but lists no finding")
  )
EOF

# The rule for a full run, whose ledger names no base_run: it reuses nothing. $fd is findings.json,
# or nothing before findings.json exists.
JQ_NO_BASE=''
IFS= read -r -d '' JQ_NO_BASE <<'EOF' || true
($lg[0].entries[] | select(has("reused_from")) | "incremental: \(.coverage_id) is reused from \(.reused_from), but the ledger names no base_run"),
(($fd[0].findings // [])[] | select(has("reused_from")) | "incremental: finding \(.fingerprint) is reused from \(.reused_from), but the ledger names no base_run")
EOF

# The reuse rules for coverage units of an incremental run. $blg is the base run's ledger. They hold
# at inventory time already, so a run never spends a pass before an unprovable reuse is caught.
JQ_REUSE_UNITS=''
IFS= read -r -d '' JQ_REUSE_UNITS <<'EOF' || true
$lg[0].entries as $es
| ($es | map(select(has("reused_from")))) as $reused
| $blg[0].entries as $bes
| $lg[0].base_run as $base
| (
    ($bes[] | .coverage_id as $id | select(any($es[]; .coverage_id == $id) | not)
     | "incremental: base unit \($id) is missing; an invalidated or uncovered unit is inventoried again under its coverage_id"),
    ($reused[] | . as $e | ($bes | map(select(.coverage_id == $e.coverage_id)) | first) as $bu
     | if $bu == null then "incremental: \($e.coverage_id) is reused, but the base run holds no such unit"
       elif ($bu | .reused_from //= $base) != $e then "incremental: \($e.coverage_id) differs from the base unit; a reused unit is copied unchanged, with reused_from naming the run that hunted it"
       else empty end),
    ($reused[] | . as $e | .findings[] as $f | $bes[] | select(any(.findings[]; . == $f)) | .coverage_id as $o
     | select(any($es[]; .coverage_id == $o and has("reused_from")) | not)
     | "incremental: \($e.coverage_id) is reused, but its finding \($f) is also held by \($o), which this run does not reuse")
  )
EOF

# The reuse rules for findings of an incremental run, which validate applies once findings.json exists.
JQ_REUSE_FINDINGS=''
IFS= read -r -d '' JQ_REUSE_FINDINGS <<'EOF' || true
$lg[0].entries as $es
| $fd[0].findings as $fs
| ($fs | map(select(has("reused_from")))) as $reused
| $bfd[0].findings as $bfs
| $blg[0].entries as $bes
| $lg[0].base_run as $base
| (
    ($bfs[] | .fingerprint as $f | select(any($fs[]; .fingerprint == $f) | not)
     | ($bes | map(select(any(.findings[]; . == $f)))) as $holders
     | select(($holders | length) == 0
              or any($holders[]; .coverage_id as $id | any($es[]; .coverage_id == $id and .status != "blocked" and .status != "deferred")))
     | "incremental: base finding \($f) is missing; an invalidated finding is verified again in this run"),
    ($reused[] | . as $x | ($bfs | map(select(.fingerprint == $x.fingerprint)) | first) as $bf
     | if $bf == null then "incremental: finding \($x.fingerprint) is reused, but the base run holds no such finding"
       elif ($bf | .reused_from //= $base) != $x then "incremental: finding \($x.fingerprint) differs from the base finding; a reused finding is copied unchanged"
       else empty end),
    ($reused[] | .fingerprint as $f | ($es | map(select(any(.findings[]; . == $f)))) as $holders
     | if ($holders | length) == 0 then "incremental: finding \($f) is reused, but no unit lists it"
       elif any($holders[]; has("reused_from") | not) then "incremental: finding \($f) is reused, but a unit this run hunts again lists it; that finding is verified again"
       else empty end),
    ($es[] | select(has("reused_from")) | .coverage_id as $id | .findings[] | . as $f
     | select(any($reused[]; .fingerprint == $f) | not)
     | "incremental: \($id) is reused, but its finding \($f) is not carried forward unchanged")
  )
EOF

# The impact of a change since the base run. $cur and $old are NUL-separated file states: the
# working tree now (file_states) and the base commit (ls-tree -z). $digests maps a coverage_id to
# the digest of its paths and inputs now.
JQ_IMPACT=''
IFS= read -r -d '' JQ_IMPACT <<'EOF' || true
def current_states: split("\u0000") as $p
  | [range(0; ($p | length) - 2; 3) as $i
     | {key: $p[$i + 1], value: ({file: "100644", exec: "100755", link: "120000"}[$p[$i]] as $m | if $m == null then "absent" else "\($m):\($p[$i + 2])" end)}]
  | from_entries;
def base_states: split("\u0000")
  | map(select(length > 0) | split("\t") as $s | ($s[0] | split(" ")) as $m
        | {key: ($s[1:] | join("\t")), value: (if $m[0] == "160000" then "absent" else "\($m[0]):\($m[2])" end)})
  | from_entries;
def close($es; $bad):
  ($es | map(select(.coverage_id as $id | any($bad[]; . == $id)) | .findings[]) | unique) as $tainted
  | (($bad + ($es | map(select(any(.findings[]; . as $f | any($tainted[]; . == $f))) | .coverage_id))) | unique) as $next
  | if ($next | length) == ($bad | length) then $bad else close($es; $next) end;
$lg[0].entries as $es
| ($cur | current_states) as $c
| ($old | base_states) as $o
| ([$c, $o] | map(keys[]) | unique | map(select(($c[.] // "absent") != ($o[.] // "absent")))) as $changed
| close($es; [$es[] | select(.status != "covered" or $digests[.coverage_id] != .inputs_digest) | .coverage_id]) as $invalid
| {
    base_run: $base_run,
    base_commit: $base_commit,
    changed_paths: $changed,
    new_paths: [$changed[] | . as $p | select(any($es[]; any(unit_paths[]; holds(.; $p))) | not)],
    units: [$es[] | . as $e | unit_paths as $up | {
      coverage_id,
      decision: (if .status != "covered" then "uncovered" elif any($invalid[]; . == $e.coverage_id) then "invalidated" else "reuse" end),
      digest_changed: (.status == "covered" and $digests[.coverage_id] != .inputs_digest),
      changed_inputs: [(.inputs // [])[] | select(.path as $q | any($changed[]; holds($q; .)))],
      changed_paths: [$changed[] | . as $p | select(any($up[]; holds(.; $p)))]
    }],
    findings: [$fd[0].findings[] | .fingerprint as $f | ($es | map(select(any(.findings[]; . == $f)))) as $holders | {
      fingerprint: $f,
      decision: (if ($holders | length) > 0 and all($holders[]; .coverage_id as $id | any($invalid[]; . == $id) | not) then "reuse" else "reverify" end)
    }]
  }
EOF

# schema_problems <schema-file> <document-file> [<$ref to start at>] — one problem per line on stdout.
schema_problems() {
  jq -n -r --slurpfile schema "$1" --slurpfile doc "$2" --arg start "${3:-}" "$JQ_SCHEMA"
}

# json_document <file> — exits non-zero unless the file holds exactly one JSON document.
json_document() {
  [[ "$(jq -s 'length' "$1" 2>/dev/null)" == 1 ]]
}

# emit_result <run-dir> <problems> — prints the result document and exits 3 on any problem.
emit_result() {
  local problems valid=true
  problems="$(printf '%s' "$2" | sed '/^$/d')"
  [[ -n "$problems" ]] && valid=false
  printf '%s' "$problems" | jq -Rsc --arg dir "$1" --argjson valid "$valid" \
    '{valid: $valid, run_dir: $dir, problems: (split("\n") | map(select(length > 0)))}'
  [[ "$valid" == true ]] || exit 3
}

require_run_dir() {
  if [[ ! -d "$1" ]]; then
    echo "$PROG: not a directory: $(printable "$1")" >&2
    exit 1
  fi
}

# artefact_problems <run-dir> <label> — one line per JSON artefact of the run directory that is
# missing, not one JSON document, or not valid against its schema. <label> prefixes every line.
artefact_problems() {
  local dir="$1" label="$2" name file schema found
  for name in metadata coverage-ledger findings; do
    file="$dir/$name.json"
    if [[ ! -f "$file" ]]; then
      printf '%s%s.json: missing\n' "$label" "$name"
      continue
    fi
    if ! json_document "$file"; then
      printf '%s%s.json: not valid JSON\n' "$label" "$name"
      continue
    fi
    case "$name" in
    metadata) schema="$SCHEMA_DIR/metadata.schema.json" ;;
    coverage-ledger) schema="$SCHEMA_DIR/coverage.schema.json" ;;
    *) schema="$SCHEMA_DIR/findings.schema.json" ;;
    esac
    found="$(schema_problems "$schema" "$file")"
    if [[ -n "$found" ]]; then
      printf '%s\n' "$found" | sed "s|^|$label$name.json |"
    fi
  done
}

# base_run_problems <run-dir> <base-run-id> — the base run must be another run beside this one, with
# valid artefacts of this schema version and the run_id its directory is named after.
base_run_problems() {
  local dir="$1" base="$2" base_dir found
  base_dir="$(dirname "$dir")/$base"
  if [[ "$base" == "$(basename "$dir")" ]]; then
    echo "incremental: the run names itself as its base run"
    return
  fi
  if [[ ! -d "$base_dir" ]]; then
    echo "incremental: the base run $base is not beside this run directory"
    return
  fi
  found="$(artefact_problems "$base_dir" "incremental: base run $base ")"
  if [[ -n "$found" ]]; then
    printf '%s\n' "$found"
    return
  fi
  jq -e --arg base "$base" '.run_id == $base' "$base_dir/metadata.json" >/dev/null \
    || echo "incremental: the base run directory $base holds a different run_id"
}

# digest_problems <run-dir> <ledger-file> — for every covered unit: no input is git-ignored, no path
# has a problem path_problem or link_problems names, and its inputs_digest equals the digest of its
# paths and inputs in the working tree now.
digest_problems() {
  local dir="$1" ledger="$2" top actual ignored any_ignored listed=listed any_link='' path refused found
  if ! top="$(git_plain "$dir" rev-parse --show-toplevel 2>/dev/null)"; then
    echo "digest: the run directory is not inside a git work tree"
    return
  fi
  local -a all=()
  while next_unit; do
    all+=("${UNIT_PATHS[@]}")
  done 3< <(covered_units "$ledger")
  [[ ${#all[@]} -gt 0 ]] || return 0
  any_ignored="$(ignored_paths "$top" "${all[@]}")"
  digest_lists "$top" "${all[@]}" || listed=''
  while IFS= read -r -d '' path; do
    if [[ -L "$top/$path" ]]; then
      any_link=yes
      break
    fi
  done < <(digest_files "$top" "${all[@]}")
  while next_unit; do
    if [[ -n "$any_ignored" ]]; then
      ignored="$(ignored_paths "$top" "${UNIT_PATHS[@]}")"
      if [[ -n "$ignored" ]]; then
        printf 'digest: %s names %s, which git ignores, so a change to it would not change the digest\n' "$UNIT_ID" "$(printable "$ignored")"
        continue
      fi
    fi
    refused=''
    for path in "${UNIT_PATHS[@]}"; do
      path_problem "$top" "$path" "$listed"
      if [[ -n "$PATH_PROBLEM" ]]; then
        printf 'digest: %s names %s, which %s\n' "$UNIT_ID" "$(printable "$path")" "$PATH_PROBLEM"
        refused=yes
      fi
    done
    [[ -z "$refused" ]] || continue
    if [[ -n "$any_link" ]]; then
      found="$(link_problems "$top" "${UNIT_PATHS[@]}")"
      if [[ -n "$found" ]]; then
        while IFS= read -r path; do
          printf 'digest: %s holds %s\n' "$UNIT_ID" "$path"
        done <<<"$found"
        continue
      fi
    fi
    if ! actual="$(paths_digest "$top" "${UNIT_PATHS[@]}")"; then
      printf 'digest: %s names a path the work tree cannot list\n' "$UNIT_ID"
      continue
    fi
    if [[ "$actual" != "$UNIT_DIGEST" ]]; then
      printf 'digest: %s records inputs_digest %s, but its paths and inputs now hash to %s; the security path changed\n' "$UNIT_ID" "$UNIT_DIGEST" "$actual"
    fi
  done 3< <(covered_units "$ledger")
}

# reuse_problems <run-dir> <ledger-file> [findings] — for an incremental run, the base run checks and
# the reuse rules for units, and with `findings` the reuse rules for findings too.
reuse_problems() {
  local dir="$1" ledger="$2" base found
  base="$(jq -r '.base_run // empty' "$ledger")"
  if [[ -z "$base" ]]; then
    local findings=/dev/null
    if [[ "${3:-}" == findings ]]; then
      findings="$dir/findings.json"
    fi
    jq -n -r --slurpfile lg "$ledger" --slurpfile fd "$findings" "$JQ_NO_BASE"
    return
  fi
  found="$(base_run_problems "$dir" "$base")"
  if [[ -n "$found" ]]; then
    printf '%s\n' "$found"
    return
  fi
  local base_dir
  base_dir="$(dirname "$dir")/$base"
  jq -n -r --slurpfile lg "$ledger" --slurpfile blg "$base_dir/coverage-ledger.json" "$JQ_REUSE_UNITS"
  if [[ "${3:-}" == findings ]]; then
    jq -n -r --slurpfile lg "$ledger" --slurpfile fd "$dir/findings.json" \
      --slurpfile blg "$base_dir/coverage-ledger.json" --slurpfile bfd "$base_dir/findings.json" "$JQ_REUSE_FINDINGS"
  fi
}

cmd_inventory() {
  [[ $# -eq 1 ]] || { usage; exit 1; }
  local dir="$1" file problems='' found
  require_run_dir "$dir"
  file="$dir/coverage-ledger.json"
  if [[ ! -f "$file" ]]; then
    problems="coverage-ledger.json: missing"
  elif ! git_plain "$dir" check-ignore -q coverage-ledger.json 2>/dev/null; then
    problems="inventory: the run directory is not git-ignored, so the coordinator's own writes would change the working-tree snapshot"
  elif ! json_document "$file"; then
    problems="coverage-ledger.json: not valid JSON"
  else
    found="$(schema_problems "$SCHEMA_DIR/coverage.schema.json" "$file")"
    if [[ -n "$found" ]]; then
      problems="$(printf '%s\n' "$found" | sed 's|^|coverage-ledger.json |')"
    else
      problems="$(jq -n -r --slurpfile lg "$file" "$JQ_INVENTORY")"$'\n'
      problems+="$(reuse_problems "$dir" "$file")"$'\n'
      problems+="$(digest_problems "$dir" "$file")"
    fi
  fi
  emit_result "$dir" "$problems"
}

# fingerprint_problems <findings-file> — one line per finding whose fingerprint is not the hash of
# its fingerprint_basis.
fingerprint_problems() {
  local count i fingerprint basis expected
  count="$(jq '.findings | length' "$1")"
  for ((i = 0; i < count; i++)); do
    fingerprint="$(jq -r --argjson i "$i" '.findings[$i].fingerprint' "$1")"
    basis="$(jq -r --argjson i "$i" '.findings[$i].fingerprint_basis | [.boundary, .source, .sink, .root_cause] | join("|")' "$1")"
    expected="$(fingerprint_of "$basis")"
    if [[ "$fingerprint" != "$expected" ]]; then
      printf 'findings: %s is not the fingerprint of its fingerprint_basis, which hashes to %s\n' "$fingerprint" "$expected"
    fi
  done
}

cmd_validate() {
  [[ $# -eq 1 ]] || { usage; exit 1; }
  local dir="$1" problems='' found
  require_run_dir "$dir"

  found="$(artefact_problems "$dir" '')"
  problems+="$found"$'\n'

  if [[ -z "$found" ]]; then
    local expected
    expected="$(cmd_budget --profile "$(jq -r .profile "$dir/metadata.json")" --total "$(jq -r .budget.total "$dir/metadata.json")" 2>/dev/null)" || expected=''
    jq -e --argjson want "${expected:-null}" '.budget == $want' "$dir/metadata.json" >/dev/null \
      || problems+="metadata: budget is not the split audit-artifacts.sh budget prints for this profile and total"$'\n'
    problems+="$(jq -n -r --arg name "$(basename "$dir")" --slurpfile md "$dir/metadata.json" --slurpfile lg "$dir/coverage-ledger.json" --slurpfile fd "$dir/findings.json" "$JQ_PATHS$JQ_CROSS")"$'\n'
    problems+="$(fingerprint_problems "$dir/findings.json")"$'\n'
    problems+="$(reuse_problems "$dir" "$dir/coverage-ledger.json" findings)"$'\n'
    problems+="$(digest_problems "$dir" "$dir/coverage-ledger.json")"$'\n'
  fi

  if [[ ! -s "$dir/REPORT.md" ]]; then
    problems+="REPORT.md: missing or empty"$'\n'
  else
    local heading
    for heading in "${REPORT_HEADINGS[@]}"; do
      grep -qxF "$heading" "$dir/REPORT.md" || problems+="REPORT.md: missing heading '$heading'"$'\n'
    done
  fi

  emit_result "$dir" "$problems"
}

cmd_impact() {
  [[ $# -eq 1 ]] || { usage; exit 1; }
  local dir="$1" problems top commit
  require_run_dir "$dir"
  problems="$(artefact_problems "$dir" 'base run ')"
  if [[ -n "$problems" ]]; then
    emit_result "$dir" "$problems"
  fi
  if ! top="$(git_plain "$dir" rev-parse --show-toplevel 2>/dev/null)"; then
    emit_result "$dir" "impact: the base run directory is not inside a git work tree"
  fi
  commit="$(jq -r .commit "$dir/metadata.json")"
  if ! git_plain "$top" cat-file -e "$commit^{commit}" 2>/dev/null; then
    emit_result "$dir" "impact: the base commit $commit is not in this repository; run a full audit"
  fi
  commit="$(git_plain "$top" rev-parse "$commit^{commit}")"

  jq -n -c --rawfile cur <(digest_files "$top" | file_states "$top") \
    --rawfile old <(git_plain "$top" ls-tree -r -z --full-tree "$commit") --argjson digests "$(unit_digests "$top" "$dir/coverage-ledger.json")" \
    --arg base_run "$(jq -r .run_id "$dir/metadata.json")" --arg base_commit "$commit" \
    --slurpfile lg "$dir/coverage-ledger.json" --slurpfile fd "$dir/findings.json" "$JQ_PATHS$JQ_IMPACT"
}

# --- self-test ------------------------------------------------------------------------------------

self_test() {
  require_tools
  local checks=0 failed=0
  scratch="$(mktemp -d)"
  trap 'rm -rf "$scratch"' EXIT
  # Every fixture run directory lives in the git-ignored run directory of a scratch project, as a
  # real run does, so inventory accepts it.
  git init -q "$scratch/project"
  printf '.claude/run/\n' >"$scratch/project/.gitignore"
  # write_sources <dir> — the source files the paths and inputs of the fixture units name.
  write_sources() {
    local file
    for file in src/Auth/Login.php routes/web.php src/Admin/Users.php src/Policies/UserPolicy.php src/Admin/Export.php \
      src/Billing/Invoices.php config/tools.php src/Assistant/RefundTool.php; do
      mkdir -p "$(dirname "$1/$file")"
      printf 'v1 %s\n' "$file" >"$1/$file"
    done
  }
  write_sources "$scratch/project"
  tmp="$scratch/project/.claude/run/security-audit"
  mkdir -p "$tmp"

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

  # expect_problem <label> <text> — the last command's output names the problem.
  expect_problem() {
    if grep -qF "$2" "$tmp/out"; then pass "$1"; else fail "$1 (no problem containing '$2')"; fi
  }

  # expect_error <label> <text> — the last command's error message contains the text.
  expect_error() {
    if grep -qF "$2" "$tmp/err"; then pass "$1"; else fail "$1 (no error containing '$2')"; fi
  }

  local baseline='eeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeee'
  local basis_a='unauthenticated_to_authenticated|POST /login|src/Auth/Login.php#LoginController::store|CWE-89'
  local basis_b='user_to_administrator|GET /admin/users|src/Admin/Users.php#UsersController::index|CWE-285'
  local basis_c='tenant_to_tenant|GET /invoices/{id}|src/Billing/Invoices.php#InvoiceRepository::find|CWE-639'
  local fp_a fp_b fp_c
  fp_a="$(fingerprint_of "$basis_a")"
  fp_b="$(fingerprint_of "$basis_b")"
  fp_c="$(fingerprint_of "$basis_c")"
  local threats binding
  threats="$(jq -nc '["prompt_provenance_confusion", "persistent_memory_poisoning", "cross_session_context_bleed",
    "tool_argument_injection", "confused_deputy", "excessive_tool_authority", "mcp_tool_identity_confusion",
    "action_confirmation_binding_failure", "schema_dispatcher_disagreement", "unbounded_agent_action_loop"]
    | map({class: ., outcome: "no_candidate", observation: "the hunter traced the tool call and found no candidate"})')"
  binding="$(jq -nc '["principal", "authority", "action", "resource", "arguments"]
    | map({key: ., value: {status: "bound", location: "src/Assistant/RefundTool.php:20", observation: "the tool checks it against the confirmed request"}})
    | from_entries')"

  # build_run <dir> <profile> — a valid run directory for the profile: five coverage units, two
  # waves with a fresh critic each, and one finding per verdict. Finding A was found by two hunters
  # and merged on its fingerprint. All three findings share the same prose and differ in their basis.
  # C5 is an AI tool unit that records the ten threat classes and the five action dimensions. The
  # run_id is the name of the run directory, and every covered unit is sealed with its digest. Each
  # profile is written once, into a template, and copied for every fixture.
  build_run() {
    local dir="$1" profile="$2" template
    template="$scratch/project/.claude/run/templates/$profile"
    [[ -d "$template" ]] || write_run "$template" "$profile"
    rm -rf "${dir:?}"
    mkdir -p "$(dirname "$dir")"
    cp -R "$template" "$dir"
    mutate "$dir" metadata.json ".run_id = \"${dir##*/}\""
    [[ "$dir" == "$scratch/project/"* ]] || seal "$dir"
  }

  # write_run <dir> <profile> — writes the fixture run of build_run.
  write_run() {
    local dir="$1" profile="$2" budget
    mkdir -p "$dir"
    budget="$(cmd_budget --profile "$profile")"
    jq -n --arg id "${dir##*/}" --arg profile "$profile" --argjson budget "$budget" --arg baseline "$baseline" '{
      schema_version: 3, run_id: $id, profile: $profile,
      scope: {kind: "repository", target: "."}, commit: "0123456789abcdef0123456789abcdef01234567",
      worktree_baseline: $baseline,
      started_at: "2026-01-01T10:00:00Z", finished_at: "2026-01-01T11:00:00Z",
      budget: $budget,
      spent: {hunting: ($budget.hunting_max - 1), verification: 3, coverage_critic: 2},
      counts: {confirmed: 1, needs_validation: 1, rejected: 1}}' >"$dir/metadata.json"
    jq -n --arg a "$fp_a" --arg b "$fp_b" --arg c "$fp_c" --arg baseline "$baseline" --argjson threats "$threats" --argjson binding "$binding" '{
      schema_version: 3, base_run: null, entries: [
      {coverage_id: "C1", surface: "http_entrypoint", boundary: "unauthenticated_to_authenticated", subsystem: "Auth",
       attack_class: "injection_input", paths: ["src/Auth/Login.php"], status: "covered", agent: "hunter-1", findings: [$a, $b],
       inputs: [{kind: "source", path: "src/Auth/Login.php"}, {kind: "middleware", path: "routes/web.php"},
                {kind: "sink", path: "src/Admin/Users.php"}, {kind: "authorization", path: "src/Policies/UserPolicy.php"}],
       inputs_digest: $baseline},
      {coverage_id: "C2", surface: "ci_deploy", boundary: "repository_to_ci_runner", subsystem: "Docs build",
       attack_class: "wildcard", paths: ["docs"], status: "out_of_scope", agent: null, findings: [],
       reason: "the user scoped the audit to the application code"},
      {coverage_id: "C3", surface: "authorization", boundary: "user_to_administrator", subsystem: "Admin",
       attack_class: "auth_authz", paths: ["src/Admin"], status: "covered", agent: "hunter-2", findings: [$a, $c],
       inputs: [{kind: "source", path: "src/Auth/Login.php"}, {kind: "middleware", path: "routes/web.php"},
                {kind: "framework_protection", path: "src/Billing/Invoices.php"}],
       inputs_digest: $baseline},
      {coverage_id: "C4", surface: "http_entrypoint", boundary: "user_to_administrator", subsystem: "Admin",
       attack_class: "injection_input", paths: ["src/Admin/Export.php"], status: "covered", agent: "hunter-3", findings: [],
       inputs: [{kind: "sink", path: "src/Admin/Export.php"}], inputs_digest: $baseline},
      {coverage_id: "C5", surface: "ai_tool", boundary: "untrusted_content_to_agent", subsystem: "Assistant",
       attack_class: "ai_tools", paths: ["src/Assistant"], status: "covered", agent: "hunter-4", findings: [],
       inputs: [{kind: "tool_authority", path: "config/tools.php"}, {kind: "action_binding", path: "src/Assistant/RefundTool.php"}],
       inputs_digest: $baseline, threats: $threats, action_binding: $binding}],
      waves: [
        {wave: 1, hunters: ["hunter-1", "hunter-2"], critic: "critic-1", worktree: $baseline, gaps: [
          {kind: "missing_attack_class", detail: "no unit hunted the admin export for injection",
           resolution: "opened C4 and hunted it in wave 2", coverage_id: "C4"}]},
        {wave: 2, hunters: ["hunter-3", "hunter-4"], critic: "critic-2", worktree: $baseline, gaps: []}]}' >"$dir/coverage-ledger.json"
    jq -n --arg ba "$basis_a" --arg bb "$basis_b" --arg bc "$basis_c" --arg a "$fp_a" --arg b "$fp_b" --arg c "$fp_c" '
      def basis($s): ($s | split("|")) as $p | {boundary: $p[0], source: $p[1], sink: $p[2], root_cause: $p[3]};
      def base($fp; $s; $verdict; $severity; $demonstrated; $hunters; $verifier; $controls): {
        fingerprint: $fp, fingerprint_basis: basis($s), verdict: $verdict, severity: $severity,
        boundary: "unauthenticated request to account data",
        entrypoint: "POST /login", sink: "DB::select with an interpolated email", root_cause: "the email is concatenated into the query",
        evidence: [{location: "src/Auth/Login.php:42", observation: "the request email reaches the query string"}],
        remediation: "bind the email as a parameter", boundary_failure_demonstrated: $demonstrated,
        hunters: $hunters, verifier: $verifier, controls: $controls};
      def walked: [
        {kind: "middleware", effect: "does_not_stop", location: "routes/web.php:12", observation: "the route carries only the throttle middleware"},
        {kind: "policy", effect: "absent"}, {kind: "framework_protection", effect: "absent"},
        {kind: "validation", effect: "absent"}, {kind: "sanitization", effect: "absent"}, {kind: "configuration", effect: "absent"}];
      {schema_version: 3, findings: [
        base($a; $ba; "confirmed"; "high"; true; ["hunter-1", "hunter-2"]; "verifier-1"; walked),
        (base($b; $bb; "needs_validation"; "unrated"; false; ["hunter-1"]; "verifier-2";
          [{kind: "policy", effect: "unclear", location: "src/Policies/UserPolicy.php:20", observation: "the policy reads a role the code does not set"}])
          + {validation_needed: "confirm the route is reachable without a session"}),
        (base($c; $bc; "rejected"; "unrated"; false; ["hunter-2"]; "verifier-3";
          [{kind: "framework_protection", effect: "stops", location: "src/Billing/Invoices.php:30", observation: "the global tenant scope filters the query"}])
          + {rejection_reason: "the global tenant scope stops the cross-tenant read"})]}' >"$dir/findings.json"
    {
      printf '# Security audit — fixture\n\n'
      local heading
      for heading in "${REPORT_HEADINGS[@]}"; do
        printf '%s\n\nNone.\n\n' "$heading"
      done
    } >"$dir/REPORT.md"
    seal "$dir"
  }

  # seal <dir> — records the digest every covered unit has in the working tree now, as a coordinator
  # does once the unit's inputs are known.
  seal() {
    jq --argjson d "$(unit_digests "$(git_plain "$1" rev-parse --show-toplevel)" "$1/coverage-ledger.json" hunted)" \
      '.entries |= map(if $d[.coverage_id] then .inputs_digest = $d[.coverage_id] else . end)' \
      "$1/coverage-ledger.json" >"$1/coverage-ledger.json.new" && mv "$1/coverage-ledger.json.new" "$1/coverage-ledger.json"
  }

  # mutate <dir> <file> <jq-filter> — rewrites one artefact of a run directory.
  mutate() {
    jq "$3" "$1/$2" >"$1/$2.new" && mv "$1/$2.new" "$1/$2"
  }

  # in_dir <dir> <command...> — runs the command with <dir> as the current directory.
  in_dir() {
    cd "$1" && shift && "$@"
  }

  # fresh <label> — a new valid standard run in $tmp/<label>.
  fresh() {
    build_run "$tmp/$1" standard
  }

  # inventory_of <label> — the inventory the fixture run wrote before the first hunter opened.
  inventory_of() {
    fresh "$1"
    mutate "$tmp/$1" coverage-ledger.json '.waves = [] | .entries |= map(.findings = [] | if .status == "out_of_scope" then . else (.status = "queued" | .agent = null) end)'
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
  expect_problem 'edge: the problem names the consumed reserve' 'consumed the reserve'

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
  expect_problem 'cross: the problem names the budget mismatch' 'budget is not the split'

  fresh budget-total-zero
  mutate "$tmp/budget-total-zero" metadata.json '.budget.total = 0'
  expect_exit 'cross: a total the budget command refuses is a mismatch, not a crash' 3 cmd_validate "$tmp/budget-total-zero"

  fresh bad-verdict
  mutate "$tmp/bad-verdict" findings.json '.findings[0].verdict = "probable"'
  expect_exit 'lifecycle: a verdict outside the three is invalid' 3 cmd_validate "$tmp/bad-verdict"

  local field
  for field in fingerprint fingerprint_basis verdict severity boundary entrypoint sink root_cause evidence remediation hunters verifier controls; do
    fresh "missing-${field//_/-}"
    mutate "$tmp/missing-${field//_/-}" findings.json "del(.findings[0].$field)"
    expect_exit "schema: a finding without $field is invalid" 3 cmd_validate "$tmp/missing-${field//_/-}"
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

  # --- coverage inventory and units ---

  inventory_of inventory
  expect_exit 'inventory: the ledger written before hunting is a valid inventory' 0 cmd_inventory "$tmp/inventory"
  if jq -e '[.entries[] | select(.status == "queued")] | length == 4' "$tmp/inventory/coverage-ledger.json" >/dev/null; then
    pass 'inventory: every unit in scope starts queued'
  else
    fail 'inventory: queued units'
  fi

  inventory_of inventory-hunted
  mutate "$tmp/inventory-hunted" coverage-ledger.json '.entries[0].status = "covered" | .entries[0].agent = "hunter-1"'
  expect_exit 'inventory: a unit hunted before the inventory check is refused' 3 cmd_inventory "$tmp/inventory-hunted"
  expect_problem 'inventory: the problem names the unit hunted too early' 'before the first hunter opened'

  inventory_of inventory-wave
  mutate "$tmp/inventory-wave" coverage-ledger.json ".waves = [{wave: 1, hunters: [\"hunter-1\"], critic: \"critic-1\", worktree: \"$baseline\", gaps: []}]"
  expect_exit 'inventory: a wave recorded before the inventory check is refused' 3 cmd_inventory "$tmp/inventory-wave"

  inventory_of inventory-duplicate-id
  mutate "$tmp/inventory-duplicate-id" coverage-ledger.json '.entries[1].coverage_id = "C1"'
  expect_exit 'inventory: a coverage_id appears once' 3 cmd_inventory "$tmp/inventory-duplicate-id"

  inventory_of inventory-agent
  mutate "$tmp/inventory-agent" coverage-ledger.json '.entries[0].agent = "hunter-1"'
  expect_exit 'inventory: a queued unit names no agent yet' 3 cmd_inventory "$tmp/inventory-agent"
  expect_problem 'inventory: the problem names the unit that already has an agent' 'C1 already names agent hunter-1'

  inventory_of inventory-findings
  mutate "$tmp/inventory-findings" coverage-ledger.json '.entries[0].findings = ["dddddddddddddddd"]'
  expect_exit 'inventory: a queued unit lists no finding yet' 3 cmd_inventory "$tmp/inventory-findings"
  expect_problem 'inventory: the problem names the unit that already lists findings' 'C1 already lists findings'

  local unignored="$scratch/unignored/.claude/run/security-audit"
  git init -q "$scratch/unignored"
  mkdir -p "$unignored"
  inventory_of inventory-unignored
  mv "$tmp/inventory-unignored" "$unignored/"
  expect_exit 'inventory: a run directory that is not git-ignored is refused' 3 cmd_inventory "$unignored/inventory-unignored"
  expect_problem 'inventory: the problem names the run directory that is not git-ignored' 'the run directory is not git-ignored'
  printf '.claude/run/\n' >"$scratch/unignored/.gitignore"
  expect_exit 'inventory: the same run directory passes once the project ignores it' 0 cmd_inventory "$unignored/inventory-unignored"

  mkdir -p "$tmp/inventory-missing"
  expect_exit 'inventory: a missing coverage-ledger.json is refused' 3 cmd_inventory "$tmp/inventory-missing"
  expect_exit 'usage: inventory without a directory' 1 cmd_inventory

  for field in coverage_id surface boundary subsystem attack_class paths status agent findings; do
    inventory_of "unit-missing-${field//_/-}"
    mutate "$tmp/unit-missing-${field//_/-}" coverage-ledger.json "del(.entries[0].$field)"
    expect_exit "schema: a coverage unit without $field is invalid" 3 cmd_inventory "$tmp/unit-missing-${field//_/-}"
  done

  local area
  for area in auth_authz injection_input files_ssrf queues_webhooks data_isolation ai_tools wildcard; do
    inventory_of "area-${area//_/-}"
    mutate "$tmp/area-${area//_/-}" coverage-ledger.json ".entries[0].attack_class = \"$area\""
    expect_exit "hunting area: $area is a valid attack class" 0 cmd_inventory "$tmp/area-${area//_/-}"
  done

  inventory_of unknown-area
  mutate "$tmp/unknown-area" coverage-ledger.json '.entries[0].attack_class = "csrf"'
  expect_exit 'hunting area: an attack class outside the seven is invalid' 3 cmd_inventory "$tmp/unknown-area"

  inventory_of unknown-surface
  mutate "$tmp/unknown-surface" coverage-ledger.json '.entries[0].surface = "everything"'
  expect_exit 'schema: a surface outside the reconnaissance list is invalid' 3 cmd_inventory "$tmp/unknown-surface"

  fresh in-review-status
  mutate "$tmp/in-review-status" coverage-ledger.json '.entries[0].status = "in_review"'
  expect_exit 'schema: a status outside the six is invalid' 3 cmd_validate "$tmp/in-review-status"

  fresh queued-row
  mutate "$tmp/queued-row" coverage-ledger.json '.entries[0].status = "queued"'
  expect_exit 'cross: a finished run leaves no queued unit' 3 cmd_validate "$tmp/queued-row"

  fresh candidate-row
  mutate "$tmp/candidate-row" coverage-ledger.json '.entries[0].status = "candidate"'
  expect_exit 'cross: a finished run leaves no unverified candidate unit' 3 cmd_validate "$tmp/candidate-row"

  fresh ghost-fingerprint
  mutate "$tmp/ghost-fingerprint" coverage-ledger.json '.entries[0].findings += ["dddddddddddddddd"]'
  expect_exit 'cross: a unit lists only fingerprints findings.json holds' 3 cmd_validate "$tmp/ghost-fingerprint"

  fresh skip-no-reason
  mutate "$tmp/skip-no-reason" coverage-ledger.json 'del(.entries[1].reason)'
  expect_exit 'schema: an out_of_scope unit states why' 3 cmd_validate "$tmp/skip-no-reason"

  local status
  for status in blocked deferred; do
    fresh "$status-row"
    mutate "$tmp/$status-row" coverage-ledger.json ".entries[1].status = \"$status\" | .entries[1].reason = \"the unit could not be hunted\""
    expect_exit "coverage: a $status unit with a reason is a valid final state" 0 cmd_validate "$tmp/$status-row"
    mutate "$tmp/$status-row" coverage-ledger.json 'del(.entries[1].reason)'
    expect_exit "schema: a $status unit states why" 3 cmd_validate "$tmp/$status-row"
  done

  fresh covered-no-hunter
  mutate "$tmp/covered-no-hunter" coverage-ledger.json '.entries[3].agent = null'
  expect_exit 'schema: a covered unit names the hunter that covered it' 3 cmd_validate "$tmp/covered-no-hunter"

  # --- waves, coverage critics, and read-only parallel hunting ---

  fresh no-wave
  mutate "$tmp/no-wave" coverage-ledger.json '.waves = []'
  expect_exit 'coverage: a run whose units name hunters but records no wave is invalid' 3 cmd_validate "$tmp/no-wave"
  expect_problem 'coverage: the problem names the hunter no wave opened' 'C1 names agent hunter-1, which no wave opened'

  build_run "$tmp/quick-all-deferred" quick
  mutate "$tmp/quick-all-deferred" coverage-ledger.json '.waves = [] | .entries |= map(.findings = [] | .agent = null
    | if .status == "out_of_scope" then . else (.status = "deferred" | .attack_class = "wildcard" | .reason = "outside the quick profile") end)'
  mutate "$tmp/quick-all-deferred" findings.json '.findings = []'
  mutate "$tmp/quick-all-deferred" metadata.json '.spent = {hunting: 0, verification: 0, coverage_critic: 0} | .counts = {confirmed: 0, needs_validation: 0, rejected: 0}'
  expect_exit 'coverage: a quick run that hunts no unit validates with no wave' 0 cmd_validate "$tmp/quick-all-deferred"

  fresh reused-critic
  mutate "$tmp/reused-critic" coverage-ledger.json '.waves[1].critic = "critic-1"'
  expect_exit 'critic: every wave gets a fresh coverage critic' 3 cmd_validate "$tmp/reused-critic"
  expect_problem 'critic: the problem names the reused critic' 'every wave gets a fresh critic'

  fresh critic-unpaid
  mutate "$tmp/critic-unpaid" metadata.json '.spent.coverage_critic = 1'
  expect_exit 'critic: every wave spends its own coverage-critic pass' 3 cmd_validate "$tmp/critic-unpaid"

  fresh wave-order
  mutate "$tmp/wave-order" coverage-ledger.json '.waves[0].wave = 2 | .waves[1].wave = 1'
  expect_exit 'critic: the waves are numbered in order' 3 cmd_validate "$tmp/wave-order"

  local kind
  for kind in missing_surface missing_attack_class uncovered_entrypoint unanalysed_boundary shallow_review assumption_based_finding; do
    fresh "gap-${kind//_/-}"
    mutate "$tmp/gap-${kind//_/-}" coverage-ledger.json ".waves[1].gaps = [{kind: \"$kind\", detail: \"the critic reported it\", resolution: \"recorded as a stated limit\"}]"
    expect_exit "critic: a $kind gap is a report the ledger keeps" 0 cmd_validate "$tmp/gap-${kind//_/-}"
  done

  fresh gap-unknown-kind
  mutate "$tmp/gap-unknown-kind" coverage-ledger.json '.waves[0].gaps[0].kind = "looks_fine"'
  expect_exit 'critic: a gap kind outside the six is invalid' 3 cmd_validate "$tmp/gap-unknown-kind"

  fresh gap-unresolved
  mutate "$tmp/gap-unresolved" coverage-ledger.json 'del(.waves[0].gaps[0].resolution)'
  expect_exit 'critic: every gap states how it was closed' 3 cmd_validate "$tmp/gap-unresolved"

  fresh gap-ghost-unit
  mutate "$tmp/gap-ghost-unit" coverage-ledger.json '.waves[0].gaps[0].coverage_id = "C9"'
  expect_exit 'critic: a gap closes only with a unit the ledger holds' 3 cmd_validate "$tmp/gap-ghost-unit"

  fresh tree-changed
  mutate "$tmp/tree-changed" coverage-ledger.json '.waves[1].worktree = "ffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffff"'
  expect_exit 'parallel: a wave that changed the working tree is invalid' 3 cmd_validate "$tmp/tree-changed"
  expect_problem 'parallel: the problem names the wave that wrote' 'the working tree changed during wave 2'

  fresh hunter-reopened
  mutate "$tmp/hunter-reopened" coverage-ledger.json '.waves[1].hunters = ["hunter-3", "hunter-1"]'
  expect_exit 'parallel: a hunter is opened in one wave only' 3 cmd_validate "$tmp/hunter-reopened"
  expect_problem 'parallel: the problem names the reopened hunter' 'a hunter is opened more than once'

  fresh duplicate-unit
  mutate "$tmp/duplicate-unit" coverage-ledger.json '.entries[1].coverage_id = "C1"'
  expect_exit 'cross: a finished run holds every coverage_id once' 3 cmd_validate "$tmp/duplicate-unit"
  expect_problem 'cross: the problem names the duplicate coverage_id' 'a coverage_id appears more than once'

  fresh hunter-twice
  mutate "$tmp/hunter-twice" coverage-ledger.json '.waves[1].hunters = ["hunter-1"] | .entries[3].agent = "hunter-1"'
  expect_exit 'parallel: a hunter is opened once' 3 cmd_validate "$tmp/hunter-twice"

  fresh hunter-two-units
  mutate "$tmp/hunter-two-units" coverage-ledger.json '.entries[3].agent = "hunter-1"'
  expect_exit 'parallel: one hunter holds one coverage unit' 3 cmd_validate "$tmp/hunter-two-units"

  fresh agent-unopened
  mutate "$tmp/agent-unopened" coverage-ledger.json '.entries[3].agent = "hunter-9"'
  expect_exit 'parallel: a unit names only a hunter a wave opened' 3 cmd_validate "$tmp/agent-unopened"

  fresh hunters-unpaid
  mutate "$tmp/hunters-unpaid" metadata.json '.spent.hunting = 2'
  expect_exit 'budget: every hunter a wave opens spends a hunting pass' 3 cmd_validate "$tmp/hunters-unpaid"

  # --- independent verification ---

  fresh confirmed-unverified
  mutate "$tmp/confirmed-unverified" findings.json '.findings[0].verifier = null'
  expect_exit 'independence: a confirmed finding names its verifier' 3 cmd_validate "$tmp/confirmed-unverified"

  fresh rejected-unverified
  mutate "$tmp/rejected-unverified" findings.json '.findings[2].verifier = null'
  expect_exit 'independence: a rejected finding names its verifier' 3 cmd_validate "$tmp/rejected-unverified"

  fresh unreached
  mutate "$tmp/unreached" findings.json '.findings[1].verifier = null | .findings[1].controls = []'
  mutate "$tmp/unreached" metadata.json '.spent.verification = 2'
  expect_exit 'independence: a candidate no verifier reached stays needs_validation' 0 cmd_validate "$tmp/unreached"

  fresh self-confirmed
  mutate "$tmp/self-confirmed" findings.json '.findings[0].verifier = "hunter-1"'
  expect_exit 'independence: a hunter cannot confirm its own finding' 3 cmd_validate "$tmp/self-confirmed"

  fresh reused-verifier
  mutate "$tmp/reused-verifier" findings.json '.findings[2].verifier = "verifier-1"'
  expect_exit 'independence: every candidate gets a new verifier' 3 cmd_validate "$tmp/reused-verifier"
  expect_problem 'independence: the problem names the reused verifier' 'every candidate gets a new verifier'

  fresh verifiers-unpaid
  mutate "$tmp/verifiers-unpaid" metadata.json '.spent.verification = 2'
  expect_exit 'budget: every verifier spends a verification pass' 3 cmd_validate "$tmp/verifiers-unpaid"

  fresh finding-unopened-hunter
  mutate "$tmp/finding-unopened-hunter" findings.json '.findings[1].hunters = ["hunter-7"]'
  expect_exit 'independence: a finding names only hunters a wave opened' 3 cmd_validate "$tmp/finding-unopened-hunter"

  fresh finding-extra-hunter
  mutate "$tmp/finding-extra-hunter" findings.json '.findings[1].hunters = ["hunter-1", "hunter-7"]'
  expect_exit 'independence: every hunter a finding names was opened by a wave' 3 cmd_validate "$tmp/finding-extra-hunter"
  expect_problem 'independence: the problem names the hunter no wave opened' 'names hunter hunter-7, which no wave opened'

  fresh unit-not-hunter
  mutate "$tmp/unit-not-hunter" findings.json '.findings[2].hunters = ["hunter-1"]'
  expect_exit 'independence: a unit lists only findings its own hunter proposed' 3 cmd_validate "$tmp/unit-not-hunter"

  # --- refutation: a control on the path never ends in confirmed ---

  local effect
  for kind in policy framework_protection middleware; do
    for effect in stops unclear; do
      fresh "confirmed-${kind//_/-}-${effect//_/-}"
      mutate "$tmp/confirmed-${kind//_/-}-${effect//_/-}" findings.json "(.findings[0].controls[] | select(.kind == \"$kind\")) |= {kind: \"$kind\", effect: \"$effect\", location: \"routes/web.php:5\", observation: \"the control is on the path\"}"
      expect_exit "refute: a $kind with the effect $effect cannot be confirmed" 3 cmd_validate "$tmp/confirmed-${kind//_/-}-${effect//_/-}"
    done
  done

  for kind in middleware policy framework_protection validation sanitization configuration; do
    fresh "confirmed-unchecked-${kind//_/-}"
    mutate "$tmp/confirmed-unchecked-${kind//_/-}" findings.json ".findings[0].controls |= map(select(.kind != \"$kind\"))"
    expect_exit "refute: a confirmed finding records the $kind it checked" 3 cmd_validate "$tmp/confirmed-unchecked-${kind//_/-}"
  done

  fresh control-no-location
  mutate "$tmp/control-no-location" findings.json 'del(.findings[2].controls[0].location)'
  expect_exit 'refute: a control the verifier found cites its location' 3 cmd_validate "$tmp/control-no-location"

  fresh control-unknown-kind
  mutate "$tmp/control-unknown-kind" findings.json '.findings[2].controls[0].kind = "firewall"'
  expect_exit 'refute: a control kind outside the six is invalid' 3 cmd_validate "$tmp/control-unknown-kind"

  # --- root-cause fingerprint and deduplication ---

  fresh basis-changed
  mutate "$tmp/basis-changed" findings.json '.findings[0].fingerprint_basis.root_cause = "CWE-78"'
  expect_exit 'dedup: a fingerprint is the hash of its fingerprint_basis' 3 cmd_validate "$tmp/basis-changed"
  expect_problem 'dedup: the problem names the fingerprint mismatch' 'is not the fingerprint of its fingerprint_basis'

  fresh duplicate-fingerprint
  mutate "$tmp/duplicate-fingerprint" findings.json '.findings[1].fingerprint_basis = .findings[0].fingerprint_basis | .findings[1].fingerprint = .findings[0].fingerprint'
  expect_exit 'dedup: two findings with the same root-cause fingerprint are one finding' 3 cmd_validate "$tmp/duplicate-fingerprint"
  expect_problem 'dedup: the problem names the duplicate fingerprint' 'a fingerprint appears more than once'

  if jq -e '[.findings[] | [.boundary, .entrypoint, .sink, .root_cause]] | unique | length == 1' "$tmp/standard/findings.json" >/dev/null \
    && jq -e '[.findings[].fingerprint] | unique | length == 3' "$tmp/standard/findings.json" >/dev/null; then
    pass 'dedup: identical prose with three root-cause bases stays three findings'
  else
    fail 'dedup: text similarity fixture'
  fi

  fresh basis-prose
  mutate "$tmp/basis-prose" findings.json '.findings[0].fingerprint_basis.root_cause = "the email is concatenated"'
  expect_exit 'dedup: a root cause in the basis is a CWE identifier, not prose' 3 cmd_validate "$tmp/basis-prose"

  expect_exit 'fingerprint: a valid basis prints its fingerprint' 0 cmd_fingerprint unauthenticated_to_authenticated 'POST /login' 'src/Auth/Login.php#LoginController::store' CWE-89
  if [[ "$(cmd_fingerprint unauthenticated_to_authenticated 'POST /login' 'src/Auth/Login.php#LoginController::store' CWE-89)" == "$fp_a" ]]; then
    pass 'fingerprint: the command prints the hash validate checks'
  else
    fail 'fingerprint: command and validator disagree'
  fi
  if [[ "$fp_a" =~ ^[a-f0-9]{16}$ && "$fp_a" != "$fp_b" ]]; then
    pass 'fingerprint: 16 hex digits, distinct per basis'
  else
    fail 'fingerprint: shape'
  fi
  expect_exit 'fingerprint: a sink without a symbol is refused' 1 cmd_fingerprint tenant_to_tenant 'GET /x' 'src/X.php' CWE-639
  expect_exit 'fingerprint: a basis value carrying the separator is refused' 1 cmd_fingerprint tenant_to_tenant 'GET /x|y' 'src/X.php#find' CWE-639
  expect_exit 'usage: fingerprint needs four values' 1 cmd_fingerprint tenant_to_tenant 'GET /x' 'src/X.php#find'

  # --- snapshot of the working tree ---

  local repo="$tmp/repo" before after
  mkdir -p "$repo"
  git -C "$repo" init -q
  printf 'run/\n' >"$repo/.gitignore"
  printf 'one\n' >"$repo/app.php.txt"
  git -C "$repo" add .gitignore app.php.txt
  git -C "$repo" -c user.name=audit -c user.email=audit@example.invalid -c commit.gpgsign=false -c core.hooksPath=/dev/null commit -q -m init
  before="$(cmd_snapshot "$repo")"
  if [[ "$before" =~ ^[a-f0-9]{64}$ && "$(cmd_snapshot "$repo")" == "$before" ]]; then
    pass 'snapshot: the same tree prints the same 64-hex value'
  else
    fail 'snapshot: stable value'
  fi
  mkdir -p "$repo/run/security-audit"
  printf '{}\n' >"$repo/run/security-audit/findings.json"
  if [[ "$(cmd_snapshot "$repo")" == "$before" ]]; then
    pass 'snapshot: writing the git-ignored run directory leaves the snapshot unchanged'
  else
    fail 'snapshot: ignored run directory'
  fi
  printf 'two\n' >>"$repo/app.php.txt"
  after="$(cmd_snapshot "$repo")"
  if [[ "$after" != "$before" ]]; then pass 'snapshot: a worker that edits a tracked file changes the snapshot'; else fail 'snapshot: tracked edit'; fi
  printf 'scratch\n' >"$repo/notes.txt"
  before="$after"
  after="$(cmd_snapshot "$repo")"
  if [[ "$after" != "$before" ]]; then pass 'snapshot: a worker that creates an untracked file changes the snapshot'; else fail 'snapshot: untracked create'; fi
  printf 'more\n' >>"$repo/notes.txt"
  before="$after"
  after="$(cmd_snapshot "$repo")"
  if [[ "$after" != "$before" ]]; then pass 'snapshot: a worker that edits an untracked file changes the snapshot'; else fail 'snapshot: untracked edit'; fi
  git -C "$repo" add app.php.txt
  before="$after"
  after="$(cmd_snapshot "$repo")"
  if [[ "$after" != "$before" ]]; then pass 'snapshot: a worker that stages an edit it already made changes the snapshot'; else fail 'snapshot: staged edit'; fi
  chmod +x "$repo/app.php.txt"
  before="$after"
  after="$(cmd_snapshot "$repo")"
  if [[ "$after" != "$before" ]]; then pass 'snapshot: a worker that makes a tracked file executable changes the snapshot'; else fail 'snapshot: mode change'; fi
  ln -s app.php.txt "$repo/link.txt"
  before="$after"
  after="$(cmd_snapshot "$repo")"
  if [[ "$after" != "$before" ]]; then pass 'snapshot: a worker that creates a symbolic link changes the snapshot'; else fail 'snapshot: symbolic link'; fi
  rm "$repo/app.php.txt"
  before="$after"
  after="$(cmd_snapshot "$repo")"
  if [[ "$after" != "$before" ]]; then pass 'snapshot: a worker that deletes a tracked file changes the snapshot'; else fail 'snapshot: tracked delete'; fi
  printf 'decoy\n' >"$repo/q"
  printf 'quoted\n' >"$repo/\"q\""
  before="$(cmd_snapshot "$repo")"
  printf 'edit\n' >>"$repo/\"q\""
  if [[ "$(cmd_snapshot "$repo")" != "$before" ]]; then pass 'snapshot: an edit to a file whose name starts with a quote changes the snapshot'; else fail 'snapshot: quoted name'; fi
  printf 'same\n' >"$repo/a.txt"
  printf 'same\n' >"$repo/b.txt"
  ln -s a.txt "$repo/l.txt"
  git -C "$repo" add a.txt b.txt l.txt
  before="$(cmd_snapshot "$repo")"
  ln -sfn b.txt "$repo/l.txt"
  if [[ "$(cmd_snapshot "$repo")" != "$before" ]]; then
    pass 'snapshot: retargeting a tracked symbolic link to a file with identical content changes the snapshot'
  else
    fail 'snapshot: retargeted symbolic link'
  fi
  mkdir -p "$scratch/not-a-repo"
  expect_exit 'snapshot: a directory outside a git work tree is refused' 1 cmd_snapshot "$scratch/not-a-repo"

  local configured="$tmp/configured" marker="$tmp/configured-program-ran"
  mkdir -p "$configured"
  git -C "$configured" init -q
  printf '* filter=audit diff=audit\n' >"$configured/.gitattributes"
  printf 'one\n' >"$configured/app.php.txt"
  git -C "$configured" add .gitattributes app.php.txt
  git -C "$configured" -c user.name=audit -c user.email=audit@example.invalid -c commit.gpgsign=false -c core.hooksPath=/dev/null commit -q -m init
  mkdir -p "$configured/.git/audit-hooks"
  printf '#!/bin/sh\ntouch "%s"\n' "$marker" >"$configured/.git/audit-hooks/post-index-change"
  chmod +x "$configured/.git/audit-hooks/post-index-change"
  git -C "$configured" config filter.audit.clean "sh -c 'touch \"$marker\"; cat'"
  git -C "$configured" config diff.external "sh -c 'touch \"$marker\"'"
  git -C "$configured" config diff.audit.textconv "sh -c 'touch \"$marker\"; cat \"\$0\"'"
  git -C "$configured" config core.fsmonitor "sh -c 'touch \"$marker\"'"
  git -C "$configured" config core.hooksPath "$configured/.git/audit-hooks"
  printf 'two\n' >>"$configured/app.php.txt"
  printf 'new\n' >"$configured/notes.txt"
  printf 'x\n' >"$configured/\"q\""
  if [[ "$(cmd_snapshot "$configured")" =~ ^[a-f0-9]{64}$ && ! -e "$marker" ]]; then
    pass 'snapshot: taking the snapshot runs no program the repository configures'
  else
    fail 'snapshot: a configured clean filter, diff program, textconv, fsmonitor, or hook ran'
  fi

  # --- artefacts ---

  fresh missing-baseline
  mutate "$tmp/missing-baseline" metadata.json 'del(.worktree_baseline)'
  expect_exit 'schema: metadata records the working-tree baseline' 3 cmd_validate "$tmp/missing-baseline"

  fresh old-ledger
  mutate "$tmp/old-ledger" coverage-ledger.json '.schema_version = 2'
  expect_exit 'schema: a ledger of schema version 2, written before the incremental audit, is refused' 3 cmd_validate "$tmp/old-ledger"

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
  printf '{"schema_version":3,"findings":"garbage"}\n' >>"$tmp/two-documents/findings.json"
  expect_exit 'artefacts: a findings.json holding two JSON documents is invalid' 3 cmd_validate "$tmp/two-documents"

  fresh report-heading
  grep -vxF '## Coverage' "$tmp/report-heading/REPORT.md" >"$tmp/report-heading/REPORT.new" && mv "$tmp/report-heading/REPORT.new" "$tmp/report-heading/REPORT.md"
  expect_exit 'artefacts: REPORT.md keeps every template heading' 3 cmd_validate "$tmp/report-heading"

  # --- security inputs and the digest of a security path ---

  fresh no-inputs
  mutate "$tmp/no-inputs" coverage-ledger.json 'del(.entries[0].inputs)'
  expect_exit 'inputs: a covered unit records the security inputs on its path' 3 cmd_validate "$tmp/no-inputs"

  fresh no-digest
  mutate "$tmp/no-digest" coverage-ledger.json 'del(.entries[0].inputs_digest)'
  expect_exit 'inputs: a covered unit records the digest of its security path' 3 cmd_validate "$tmp/no-digest"

  fresh input-kind
  mutate "$tmp/input-kind" coverage-ledger.json '.entries[0].inputs[0].kind = "comment"'
  expect_exit 'inputs: an input kind outside the eleven is invalid' 3 cmd_validate "$tmp/input-kind"

  local bad_path
  for bad_path in /etc/passwd ../outside src/../../outside ./src/Auth/Login.php; do
    fresh input-path
    mutate "$tmp/input-path" coverage-ledger.json ".entries[0].inputs[0].path = \"$bad_path\""
    expect_exit "inputs: the input path $bad_path is not a path inside the work tree" 3 cmd_validate "$tmp/input-path"
    rm -rf "$tmp/input-path"
  done

  fresh input-ignored
  mutate "$tmp/input-ignored" coverage-ledger.json '.entries[3].inputs += [{kind: "configuration", path: ".claude/run/settings.php"}]'
  expect_exit 'inputs: an input git ignores is refused, because a change to it would not change the digest' 3 cmd_validate "$tmp/input-ignored"
  expect_problem 'inputs: the problem names the ignored input' 'C4 names .claude/run/settings.php, which git ignores'

  fresh reused-uncovered
  mutate "$tmp/reused-uncovered" coverage-ledger.json '.entries[1].reused_from = "standard"'
  expect_exit 'reuse: only a covered unit can be reused' 3 cmd_validate "$tmp/reused-uncovered"

  fresh outside-inputs
  mutate "$tmp/outside-inputs" coverage-ledger.json '.entries[0].inputs |= map(select(.path != "routes/web.php"))'
  seal "$tmp/outside-inputs"
  expect_exit 'inputs: every file a finding cites lies on the paths or inputs of the unit that lists it' 3 cmd_validate "$tmp/outside-inputs"
  expect_problem 'inputs: the problem names the cited file outside the unit' 'which cites routes/web.php outside the unit'"'"'s paths and inputs'

  fresh run-id-mismatch
  mutate "$tmp/run-id-mismatch" metadata.json '.run_id = "standard-20260101t100000z-0123456"'
  expect_exit 'run directory: a run directory is named after its run_id' 3 cmd_validate "$tmp/run-id-mismatch"
  expect_problem 'run directory: the problem names the mismatch' 'a run directory is named after its run_id'

  # --- the AI and agent threat model ---

  fresh no-threats
  mutate "$tmp/no-threats" coverage-ledger.json 'del(.entries[4].threats)'
  expect_exit 'threats: a covered ai_tools unit records the AI and agent threat classes' 3 cmd_validate "$tmp/no-threats"

  local threat
  for threat in prompt_provenance_confusion persistent_memory_poisoning cross_session_context_bleed tool_argument_injection confused_deputy \
    excessive_tool_authority mcp_tool_identity_confusion action_confirmation_binding_failure schema_dispatcher_disagreement unbounded_agent_action_loop; do
    fresh "threat-missing-${threat//_/-}"
    mutate "$tmp/threat-missing-${threat//_/-}" coverage-ledger.json ".entries[4].threats |= map(select(.class != \"$threat\"))"
    expect_exit "threats: a covered ai_tools unit cannot leave out $threat" 3 cmd_validate "$tmp/threat-missing-${threat//_/-}"
  done

  fresh threat-unknown
  mutate "$tmp/threat-unknown" coverage-ledger.json '.entries[4].threats += [{class: "jailbreak", outcome: "no_candidate", observation: "x"}]'
  expect_exit 'threats: a threat class outside the ten is invalid' 3 cmd_validate "$tmp/threat-unknown"

  fresh threat-candidate
  mutate "$tmp/threat-candidate" coverage-ledger.json '.entries[4].threats[3].outcome = "candidate"'
  expect_exit 'threats: a candidate threat with no finding is invalid' 3 cmd_validate "$tmp/threat-candidate"
  expect_problem 'threats: the problem names the unit' 'C5 records a candidate threat or an action dimension that is not bound, but lists no finding'

  # with_finding <label> — the fixture with finding C listed by the AI tool unit C5 as well.
  with_finding() {
    fresh "$1"
    mutate "$tmp/$1" findings.json '.findings[2].hunters += ["hunter-4"]'
    mutate "$tmp/$1" coverage-ledger.json '.entries[4].findings = [.entries[2].findings[1]]
      | .entries[4].inputs += [{kind: "source", path: "src/Auth/Login.php"}, {kind: "sink", path: "src/Billing/Invoices.php"}]'
    seal "$tmp/$1"
  }

  with_finding threat-with-finding
  mutate "$tmp/threat-with-finding" coverage-ledger.json '.entries[4].threats[3].outcome = "candidate"'
  expect_exit 'threats: a candidate threat that the unit lists as a finding is valid' 0 cmd_validate "$tmp/threat-with-finding"

  build_run "$tmp/ai-deferred" standard
  mutate "$tmp/ai-deferred" coverage-ledger.json '.waves[1].hunters = ["hunter-3"] | .entries[4] |= (del(.threats, .action_binding, .inputs, .inputs_digest) | .status = "deferred" | .agent = null | .reason = "hunting budget spent")'
  expect_exit 'threats: a deferred ai_tools unit records no threat classes' 0 cmd_validate "$tmp/ai-deferred"

  # --- action binding of privileged and agent-triggered actions ---

  local surface
  for surface in privileged_action agent_side_effect ai_tool mcp_integration; do
    fresh "binding-missing-${surface//_/-}"
    mutate "$tmp/binding-missing-${surface//_/-}" coverage-ledger.json ".entries[4].surface = \"$surface\" | del(.entries[4].action_binding)"
    expect_exit "binding: a covered $surface unit records its action binding" 3 cmd_validate "$tmp/binding-missing-${surface//_/-}"
  done

  local dimension
  for dimension in principal authority action resource arguments; do
    fresh "binding-without-$dimension"
    mutate "$tmp/binding-without-$dimension" coverage-ledger.json "del(.entries[4].action_binding.$dimension)"
    expect_exit "binding: an action binding cannot leave out the $dimension" 3 cmd_validate "$tmp/binding-without-$dimension"
  done

  fresh binding-arguments-unbound
  mutate "$tmp/binding-arguments-unbound" coverage-ledger.json '.entries[4].action_binding.arguments.status = "unbound"'
  expect_exit 'binding: an authorized principal with unbound arguments and no finding is invalid' 3 cmd_validate "$tmp/binding-arguments-unbound"
  expect_problem 'binding: the problem names the unit' 'C5 records a candidate threat or an action dimension that is not bound'

  fresh binding-resource-unclear
  mutate "$tmp/binding-resource-unclear" coverage-ledger.json '.entries[4].action_binding.resource.status = "unclear"'
  expect_exit 'binding: an unclear resource binding with no finding is invalid' 3 cmd_validate "$tmp/binding-resource-unclear"

  with_finding binding-with-finding
  mutate "$tmp/binding-with-finding" coverage-ledger.json '.entries[4].action_binding.arguments.status = "unbound"'
  expect_exit 'binding: unbound arguments that the unit lists as a finding are valid' 0 cmd_validate "$tmp/binding-with-finding"

  fresh binding-not-required
  mutate "$tmp/binding-not-required" coverage-ledger.json '.entries[4].surface = "external_api" | del(.entries[4].action_binding)'
  expect_exit 'binding: a surface that is not an action records no action binding' 0 cmd_validate "$tmp/binding-not-required"

  # --- incremental audit ---

  local inc="$scratch/incremental" runs base_sha
  runs="$inc/.claude/run/security-audit"
  git init -q "$inc"
  printf '.claude/run/\nvendor/\n' >"$inc/.gitignore"
  printf 'v1 README.md\n' >"$inc/README.md"
  write_sources "$inc"
  git -C "$inc" add -A
  git -C "$inc" -c user.name=audit -c user.email=audit@example.invalid -c commit.gpgsign=false -c core.hooksPath=/dev/null commit -q -m base
  base_sha="$(git -C "$inc" rev-parse HEAD)"

  build_run "$runs/base-run" standard
  mutate "$runs/base-run" metadata.json ".commit = \"$base_sha\""
  expect_exit 'incremental: the base run validates on the tree it audited' 0 cmd_validate "$runs/base-run"

  # restore — the audited project back at the base commit, with nothing untracked.
  restore() {
    git -C "$inc" -c core.hooksPath=/dev/null reset -q --hard "$base_sha"
    git -C "$inc" clean -fdq
  }

  # reuse_all <label> [<base>] — an incremental run that reuses every covered unit and every finding
  # of the base run (default: base-run) and hunts nothing.
  reuse_all() {
    local base="${2:-base-run}"
    rm -rf "${runs:?}/$1"
    cp -R "$runs/$base" "$runs/$1"
    mutate "$runs/$1" metadata.json ".run_id = \"$1\" | .spent = {hunting: 0, verification: 0, coverage_critic: 0}"
    mutate "$runs/$1" coverage-ledger.json ".base_run = \"$base\" | .waves = [] | .entries |= map(if .status == \"covered\" then .reused_from = \"$base\" else . end)"
    mutate "$runs/$1" findings.json ".findings |= map(.reused_from = \"$base\")"
  }

  # rehunt <label> — an incremental run that hunts C1 and C3 again in one wave, verifies their
  # findings again, and reuses C4 and C5.
  rehunt() {
    rm -rf "${runs:?}/$1"
    cp -R "$runs/base-run" "$runs/$1"
    mutate "$runs/$1" metadata.json ".run_id = \"$1\" | .spent = {hunting: 2, verification: 3, coverage_critic: 1}"
    mutate "$runs/$1" coverage-ledger.json '.base_run = "base-run" | .waves = [.waves[0]]
      | .entries |= map(if .coverage_id == "C4" or .coverage_id == "C5" then .reused_from = "base-run" else . end)'
    seal "$runs/$1"
  }

  # impact_says <label> <jq-condition> — the impact of the change since the base run meets the condition.
  impact_says() {
    if cmd_impact "$runs/base-run" >"$tmp/impact.json" 2>"$tmp/err" && jq -e "$2" "$tmp/impact.json" >/dev/null; then
      pass "$1"
    else
      fail "$1 ($(head -c 400 "$tmp/impact.json"))"
    fi
  }

  reuse_all reuse-unchanged
  expect_exit 'incremental: a run that reuses every unit of an unchanged tree validates' 0 cmd_validate "$runs/reuse-unchanged"
  impact_says 'impact: an unchanged tree changes no path and reuses every covered unit and finding' \
    '.changed_paths == [] and .new_paths == [] and ([.units[] | select(.decision == "reuse")] | length) == 4
     and (.units[] | select(.coverage_id == "C2") | .decision) == "uncovered" and all(.findings[]; .decision == "reuse")'

  printf 'v2\n' >>"$inc/README.md"
  mkdir -p "$inc/app/Webhooks"
  printf 'new\n' >"$inc/app/Webhooks/Stripe.php"
  impact_says 'impact: a limited diff lists its changed paths, edited and untracked, and the ones no unit holds' \
    '.changed_paths == ["README.md", "app/Webhooks/Stripe.php"] and .new_paths == ["README.md", "app/Webhooks/Stripe.php"]'
  impact_says 'impact: a change no unit holds leaves every covered unit and finding reusable' \
    '([.units[] | select(.decision == "reuse")] | length) == 4 and all(.findings[]; .decision == "reuse")'
  reuse_all reuse-new-surface
  mutate "$runs/reuse-new-surface" metadata.json '.spent = {hunting: 1, verification: 0, coverage_critic: 1}'
  mutate "$runs/reuse-new-surface" coverage-ledger.json '.entries += [{coverage_id: "C6", surface: "webhook",
    boundary: "unauthenticated_to_authenticated", subsystem: "Webhooks", attack_class: "queues_webhooks", paths: ["app/Webhooks/Stripe.php"],
    status: "queued", agent: null, findings: []}]'
  expect_exit 'incremental: the inventory reuses the unchanged units and queues the new surface' 0 cmd_inventory "$runs/reuse-new-surface"
  mutate "$runs/reuse-new-surface" coverage-ledger.json ".entries[5] += {status: \"covered\", agent: \"hunter-1\",
    inputs: [{kind: \"source\", path: \"app/Webhooks/Stripe.php\"}], inputs_digest: \"$baseline\"}
    | .waves = [{wave: 1, hunters: [\"hunter-1\"], critic: \"critic-1\", worktree: \"$baseline\", gaps: []}]"
  seal "$runs/reuse-new-surface"
  expect_exit 'incremental: a run that reuses the unchanged units and hunts only the new surface validates' 0 cmd_validate "$runs/reuse-new-surface"
  restore

  printf 'v2\n' >>"$inc/src/Policies/UserPolicy.php"
  impact_says 'impact: a changed authorization layer invalidates the unit and names the input' \
    '(.units[] | select(.coverage_id == "C1")) | .decision == "invalidated" and .digest_changed == true
     and .changed_inputs == [{kind: "authorization", path: "src/Policies/UserPolicy.php"}]'
  impact_says 'impact: a unit that shares a finding with an invalidated unit is invalidated too' \
    '(.units[] | select(.coverage_id == "C3")) | .decision == "invalidated" and .digest_changed == false'
  impact_says 'impact: every finding of an invalidated unit is verified again, and the untouched units are reused' \
    'all(.findings[]; .decision == "reverify") and ([.units[] | select(.decision == "reuse") | .coverage_id] == ["C4", "C5"])'
  reuse_all reuse-changed-policy
  expect_exit 'incremental: a unit whose authorization layer changed cannot be reused' 3 cmd_validate "$runs/reuse-changed-policy"
  expect_problem 'incremental: the problem names the changed security path' 'digest: C1 records inputs_digest'
  rehunt rehunt-policy
  expect_exit 'incremental: a run that hunts the invalidated units again and reuses the rest validates' 0 cmd_validate "$runs/rehunt-policy"
  mutate "$runs/rehunt-policy" findings.json '.findings[1].reused_from = "base-run"'
  expect_exit 'incremental: a finding of a unit this run hunts again cannot keep its old verdict' 3 cmd_validate "$runs/rehunt-policy"
  expect_problem 'incremental: the problem names the finding verified again' 'a unit this run hunts again lists it'
  rehunt rehunt-dropped
  mutate "$runs/rehunt-dropped" findings.json '.findings |= map(select(.fingerprint != "'"$fp_b"'"))'
  mutate "$runs/rehunt-dropped" coverage-ledger.json '.entries[0].findings |= map(select(. != "'"$fp_b"'"))'
  mutate "$runs/rehunt-dropped" metadata.json '.counts.needs_validation = 0 | .spent.verification = 2'
  expect_exit 'incremental: an invalidated finding does not disappear from a unit this run hunts again' 3 cmd_validate "$runs/rehunt-dropped"
  expect_problem 'incremental: the problem names the missing base finding' "base finding $fp_b is missing"
  rehunt rehunt-deferred
  mutate "$runs/rehunt-deferred" findings.json '.findings = []'
  mutate "$runs/rehunt-deferred" coverage-ledger.json '.waves = [] | .entries |= map(if .coverage_id == "C1" or .coverage_id == "C3"
    then (del(.inputs, .inputs_digest) | .status = "deferred" | .agent = null | .findings = [] | .reason = "hunting budget spent") else . end)'
  mutate "$runs/rehunt-deferred" metadata.json '.counts = {confirmed: 0, needs_validation: 0, rejected: 0} | .spent = {hunting: 0, verification: 0, coverage_critic: 0}'
  expect_exit 'incremental: the findings of an invalidated unit the budget did not reach leave findings.json' 0 cmd_validate "$runs/rehunt-deferred"
  rehunt reuse-one-of-two
  jq --slurpfile b "$runs/base-run/coverage-ledger.json" '.entries[2] = ($b[0].entries[2] + {reused_from: "base-run"})' \
    "$runs/reuse-one-of-two/coverage-ledger.json" >"$tmp/reuse-one-of-two.json"
  mv "$tmp/reuse-one-of-two.json" "$runs/reuse-one-of-two/coverage-ledger.json"
  expect_exit 'incremental: a unit that shares a finding with a unit this run hunts again cannot be reused' 3 cmd_validate "$runs/reuse-one-of-two"
  expect_problem 'incremental: the problem names the shared finding' 'which this run does not reuse'
  restore

  printf 'v2\n' >>"$inc/config/tools.php"
  impact_says 'impact: a changed tool authority invalidates the AI tool unit' \
    '(.units[] | select(.coverage_id == "C5")) | .decision == "invalidated" and .changed_inputs == [{kind: "tool_authority", path: "config/tools.php"}]'
  reuse_all reuse-changed-authority
  expect_exit 'incremental: an AI tool unit whose tool authority changed cannot be reused' 3 cmd_validate "$runs/reuse-changed-authority"
  restore

  printf 'v2\n' >>"$inc/src/Assistant/RefundTool.php"
  impact_says 'impact: changed arguments of a privileged action invalidate the unit that binds them' \
    '(.units[] | select(.coverage_id == "C5")) | .decision == "invalidated" and .changed_inputs == [{kind: "action_binding", path: "src/Assistant/RefundTool.php"}]'
  reuse_all reuse-changed-binding
  expect_exit 'incremental: a unit whose action binding changed cannot be reused' 3 cmd_validate "$runs/reuse-changed-binding"
  restore

  printf 'new\n' >"$inc/src/Assistant/McpBridge.php"
  mkdir -p "$inc/app/Agents"
  printf 'new\n' >"$inc/app/Agents/MemoryStore.php"
  impact_says 'regression: a new MCP bridge under an AI unit invalidates it although no recorded input changed' \
    '(.units[] | select(.coverage_id == "C5")) | .decision == "invalidated" and .changed_inputs == [] and .changed_paths == ["src/Assistant/McpBridge.php"]'
  impact_says 'regression: a new agent memory store outside every unit is a new surface' '.new_paths == ["app/Agents/MemoryStore.php"]'
  reuse_all reuse-new-ai-surface
  expect_exit 'regression: the earlier coverage of an AI unit cannot hide a new trust boundary under its path' 3 cmd_validate "$runs/reuse-new-ai-surface"
  restore

  printf 'v2\n' >>"$inc/src/Admin/Export.php"
  rm "$inc/src/Billing/Invoices.php"
  git -C "$inc" add -A
  git -C "$inc" -c user.name=audit -c user.email=audit@example.invalid -c commit.gpgsign=false -c core.hooksPath=/dev/null commit -q -m change
  impact_says 'impact: a committed edit and a committed deletion are changed paths' \
    '.changed_paths == ["src/Admin/Export.php", "src/Billing/Invoices.php"] and ((.units[] | select(.coverage_id == "C4")) | .decision) == "invalidated"'
  restore

  reuse_all no-base
  mutate "$runs/no-base" coverage-ledger.json '.base_run = null'
  expect_exit 'incremental: a reused unit needs a base run' 3 cmd_validate "$runs/no-base"
  expect_problem 'incremental: the problem names the missing base run' 'but the ledger names no base_run'
  expect_exit 'incremental: the inventory refuses a reused unit without a base run' 3 cmd_inventory "$runs/no-base"
  expect_problem 'incremental: the inventory names the missing base run' 'C1 is reused from base-run, but the ledger names no base_run'

  reuse_all base-missing
  mutate "$runs/base-missing" coverage-ledger.json '.base_run = "deep-20250101t000000z-0123456"'
  expect_exit 'incremental: the base run sits beside the run directory' 3 cmd_validate "$runs/base-missing"
  expect_problem 'incremental: the problem names the absent base run' 'is not beside this run directory'

  reuse_all base-self
  mutate "$runs/base-self" coverage-ledger.json '.base_run = "base-self"'
  expect_exit 'incremental: a run is not its own base run' 3 cmd_validate "$runs/base-self"

  rm -rf "$runs/old-base"
  cp -R "$runs/base-run" "$runs/old-base"
  mutate "$runs/old-base" metadata.json '.run_id = "old-base"'
  mutate "$runs/old-base" coverage-ledger.json '.schema_version = 2'
  reuse_all reuse-old-base
  mutate "$runs/reuse-old-base" coverage-ledger.json '.base_run = "old-base" | .entries |= map(if has("reused_from") then .reused_from = "old-base" else . end)'
  mutate "$runs/reuse-old-base" findings.json '.findings |= map(.reused_from = "old-base")'
  expect_exit 'regression: a base run written before the AI threat model cannot be reused' 3 cmd_validate "$runs/reuse-old-base"
  expect_problem 'regression: the problem names the old base run' 'incremental: base run old-base coverage-ledger.json'
  expect_exit 'impact: a base run of an older schema version is refused' 3 cmd_impact "$runs/old-base"

  reuse_all base-unit-missing
  mutate "$runs/base-unit-missing" coverage-ledger.json '.entries |= map(select(.coverage_id != "C2"))'
  expect_exit 'incremental: every base unit is in the ledger under its coverage_id' 3 cmd_validate "$runs/base-unit-missing"
  expect_problem 'incremental: the problem names the missing base unit' 'base unit C2 is missing'

  reuse_all reused-edited
  mutate "$runs/reused-edited" coverage-ledger.json '.entries[3].paths = ["src/Admin"]'
  expect_exit 'incremental: a reused unit is copied unchanged' 3 cmd_validate "$runs/reused-edited"
  expect_problem 'incremental: the problem names the edited unit' 'C4 differs from the base unit'

  reuse_all reused-finding-edited
  mutate "$runs/reused-finding-edited" findings.json '.findings[0].severity = "low"'
  expect_exit 'incremental: a reused finding is copied unchanged' 3 cmd_validate "$runs/reused-finding-edited"

  reuse_all reused-inventory
  mutate "$runs/reused-inventory" coverage-ledger.json '.entries[2] |= (del(.reused_from, .inputs, .inputs_digest) | .status = "queued" | .agent = null | .findings = [])'
  expect_exit 'incremental: the inventory refuses a reused unit that shares a finding with a queued unit' 3 cmd_inventory "$runs/reused-inventory"
  expect_problem 'incremental: the inventory names the shared finding' "C1 is reused, but its finding $fp_a is also held by C3"

  rm -rf "$runs/unlisted-base"
  cp -R "$runs/base-run" "$runs/unlisted-base"
  mutate "$runs/unlisted-base" metadata.json '.run_id = "unlisted-base"'
  mutate "$runs/unlisted-base" coverage-ledger.json '.entries[2].findings = ["'"$fp_a"'"]'
  reuse_all unlisted-dropped unlisted-base
  mutate "$runs/unlisted-dropped" findings.json '.findings |= map(select(.fingerprint != "'"$fp_c"'"))'
  mutate "$runs/unlisted-dropped" metadata.json '.counts.rejected = 0'
  expect_exit 'regression: a base finding no base unit lists does not disappear from an incremental run' 3 cmd_validate "$runs/unlisted-dropped"
  expect_problem 'regression: the problem names the base finding no unit listed' "base finding $fp_c is missing"

  rm -rf "$runs/lost-commit"
  cp -R "$runs/base-run" "$runs/lost-commit"
  mutate "$runs/lost-commit" metadata.json '.run_id = "lost-commit" | .commit = "deadbeefdeadbeefdeadbeefdeadbeefdeadbeef"'
  expect_exit 'impact: a base commit the repository does not hold is refused' 3 cmd_impact "$runs/lost-commit"
  expect_problem 'impact: the problem asks for a full audit' 'run a full audit'
  expect_exit 'usage: impact without a directory' 1 cmd_impact

  local d1 d2 d3
  d1="$(cd "$inc" && cmd_digest src/Auth/Login.php routes/web.php)"
  d2="$(cd "$inc" && cmd_digest routes/web.php src/Auth/Login.php src/Auth/Login.php)"
  if [[ "$d1" =~ ^[a-f0-9]{64}$ && "$d1" == "$d2" ]]; then pass 'digest: the order and repetition of the paths do not change the digest'; else fail 'digest: order'; fi
  d1="$(cd "$inc" && cmd_digest src/Assistant)"
  printf 'new\n' >"$inc/src/Assistant/Other.php"
  d2="$(cd "$inc" && cmd_digest src/Assistant)"
  chmod +x "$inc/src/Assistant/RefundTool.php"
  d3="$(cd "$inc" && cmd_digest src/Assistant)"
  if [[ "$d1" != "$d2" && "$d2" != "$d3" ]]; then pass 'digest: a new file or a mode change under a directory changes its digest'; else fail 'digest: directory'; fi
  restore
  expect_exit 'digest: a git-ignored path is refused' 1 in_dir "$inc" cmd_digest vendor/laravel/framework/src/Auth.php
  expect_exit 'digest: a path outside the work tree is refused' 1 in_dir "$inc" cmd_digest ../outside
  expect_exit 'digest: a path that matches no file is refused, because its digest would prove nothing' 1 in_dir "$inc" cmd_digest src/Missing.php
  expect_error 'digest: the error names the path that matches no file' 'src/Missing.php matches no tracked or untracked, not ignored file'

  mkdir -p "$inc/shared/policies" "$inc/app"
  printf 'v1\n' >"$inc/shared/policies/Order.php"
  ln -s ../shared/policies "$inc/app/Policies"
  expect_exit 'digest: a symbolic link is refused, because a change to its target would not change the digest' 1 in_dir "$inc" cmd_digest app/Policies
  expect_error 'digest: the error names the symbolic link' 'app/Policies is a symbolic link'
  expect_error 'digest: the error names the target path of the link' 'record shared/policies instead'
  expect_exit 'digest: a path beyond a symbolic link is refused, although git lists no file for it' 1 in_dir "$inc" cmd_digest app/Policies/Order.php
  expect_error 'digest: the error names the link the path passes through' 'app/Policies/Order.php passes through the symbolic link app/Policies'
  expect_error 'digest: the error names the target path beyond the link' 'record shared/policies/Order.php instead'
  expect_exit 'digest: a directory that holds a symbolic link is refused unless the paths hold its target' 1 in_dir "$inc" cmd_digest app
  expect_error 'digest: the error names the link inside the directory and the target to add' \
    'the paths hold the symbolic link app/Policies, so a change to its target would not change the digest; record shared/policies as an input too'
  d1="$(cd "$inc" && cmd_digest app shared/policies)"
  printf 'v2\n' >>"$inc/shared/policies/Order.php"
  d2="$(cd "$inc" && cmd_digest app shared/policies)"
  if [[ "$d1" =~ ^[a-f0-9]{64}$ && "$d1" != "$d2" ]]; then pass 'digest: a change to the target of a link changes the digest once the paths hold the target'; else fail 'digest: link target'; fi
  printf 'v1\n' >"$inc/shared/policies/Order.php"
  build_run "$runs/link-dir" standard
  mutate "$runs/link-dir" coverage-ledger.json '.entries[3].inputs += [{kind: "authorization", path: "app"}]'
  seal "$runs/link-dir"
  expect_exit 'regression: a unit whose input directory holds a symbolic link fails validation' 3 cmd_validate "$runs/link-dir"
  expect_problem 'regression: the problem names the link and the target to add' \
    'digest: C4 holds the symbolic link app/Policies, so a change to its target would not change the digest; record shared/policies as an input too'
  mutate "$runs/link-dir" coverage-ledger.json '.entries[3].inputs += [{kind: "authorization", path: "shared/policies"}]'
  seal "$runs/link-dir"
  expect_exit 'incremental: a unit that also records the target of the link validates' 0 cmd_validate "$runs/link-dir"
  build_run "$runs/link-input" standard
  mutate "$runs/link-input" coverage-ledger.json '.entries[3].inputs += [{kind: "authorization", path: "app/Policies"}]'
  seal "$runs/link-input"
  printf 'v2\n' >>"$inc/shared/policies/Order.php"
  expect_exit 'regression: a unit whose input is a symbolic link fails validation after its target changed' 3 cmd_validate "$runs/link-input"
  expect_problem 'regression: the problem names the symbolic link input' 'digest: C4 names app/Policies, which is a symbolic link'
  restore
  expect_exit 'usage: digest without a path' 1 cmd_digest

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
  snapshot)
    require_tools
    shift
    cmd_snapshot "$@"
    ;;
  fingerprint)
    require_tools
    shift
    cmd_fingerprint "$@"
    ;;
  digest)
    require_tools
    shift
    cmd_digest "$@"
    ;;
  impact)
    require_tools
    shift
    cmd_impact "$@"
    ;;
  inventory)
    require_tools
    shift
    cmd_inventory "$@"
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
