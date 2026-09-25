#!/usr/bin/env bash
# classify-risk.sh — deterministic execution-tier classifier for the orchestration
# pipeline: FAST, STANDARD, or CRITICAL.
#
# Why this exists
#   The pipeline used to run the same depth for every task: a README typo paid
#   for the same agent sessions, the same expensive models, and the same review
#   passes as an authorization rewrite. The fix is to route by risk — but a
#   router that asks an LLM "how risky is this?" adds an LLM call to save LLM
#   calls, and its answer is neither reproducible nor auditable. This script is
#   the router instead: same input, same tier, every time, with the reason for
#   the verdict printed next to it.
#
#   It decides only *how much pipeline* to spend. It never decides whether a
#   deterministic gate runs: tests, static analysis, linting, and the project's
#   own CI are mandatory at every tier (see @rules/compound-engineering/
#   orchestration.md *Adaptive routing*).
#
# Usage
#   classify-risk.sh [--files <path|->] [--assignment <path>]
#                    [--floor <tier>] [--override <tier|thorough>]
#   classify-risk.sh --self-test
#
#   --files       newline-separated list of changed paths (`-` reads stdin),
#                 normally `git diff --name-only <base>..<head>`. When given,
#                 the verdict is based on the diff (`basis=diff`).
#   --assignment  file holding the assignment text. It is the only basis when
#                 no --files is given (`basis=assignment`); alongside --files it
#                 contributes the acceptance-criteria signal only.
#   --floor       a tier the verdict may not fall below — the previous
#                 classification of the same task. This is the ratchet that
#                 makes re-classification after implementation safe: a task can
#                 rise from FAST to CRITICAL, never the reverse.
#   --override    explicit caller intent: fast | standard | critical | thorough
#                 (`thorough` is CRITICAL). See *Override precedence* below.
#
# Output (stdout, stable key=value lines, in this order)
#   tier=FAST|STANDARD|CRITICAL
#   score=<integer>
#   basis=diff|assignment|none
#   files=<count of changed paths>
#   override=none|fast|standard|critical|thorough
#   override-refused=<tier>            (only when a force signal overrode it)
#   forced=none|<signal name>
#   floor=none|FAST|STANDARD|CRITICAL
#   signal=<+/-delta>|<name>|<evidence>   (one per fired signal, fixed order)
#
#   Every line is greppable and every point in `score` is attributable to a
#   `signal=` line, so "why was this CRITICAL?" is answered by the output
#   itself rather than by re-deriving the run.
#
# Scoring
#   +3 auth / security / secrets        (forces CRITICAL)
#   +3 migrations / data-loss risk      (forces CRITICAL)
#   +3 payments / billing               (forces CRITICAL)
#   +2 queues / concurrency / locking / cache
#   +2 public API
#   +2 shared / core architecture
#   +2 more than 10 changed files
#   +1 4-10 changed files
#   +1 production code changed at all
#   +1 missing relevant tests
#   +1 unclear acceptance criteria
#   -2 documentation only
#   -2 tests only
#   -1 formatting / metadata only
#
#   score <= 1 -> FAST    score 2-4 -> STANDARD    score >= 5 -> CRITICAL
#
# Material files
#   The path signals are matched against *material* files only — the changed
#   paths that are neither documentation nor tests. Without that narrowing a
#   README under `docs/security/` would force CRITICAL on a typo fix, and a
#   test-only change would force CRITICAL for naming a file `AuthTest.php`.
#   The negative "only" signals are what those file classes contribute instead.
#
# Deliberate bias
#   The patterns are broad on purpose: a false positive costs one tier of extra
#   review, a false negative ships an unreviewed authorization change. Where the
#   classification is genuinely uncertain — no assignment text to read — the
#   unclear-acceptance-criteria point fires, which can only move the tier up.
#
#   The `production-code-changed` point is this file's one stated departure from
#   the table it was specified with. Without it an ordinary five-file feature
#   that ships its tests and states its criteria scores 1 and routes FAST, which
#   contradicts the tier definition it belongs to ("STANDARD for normal
#   application and business logic changes"). One point for touching production
#   code at all restores that default while leaving the genuinely small change —
#   one or two files, tests included — at FAST, which is the tier that pays for
#   this whole mechanism.
#
# Override precedence
#   1. A force signal (auth / data / payments) wins over everything and yields
#      CRITICAL. A lower --override is reported as `override-refused` rather
#      than applied: the force exists precisely so a sensitive area cannot be
#      routed around, and an override that can silence it is not a force.
#   2. Otherwise an explicit --override is the tier.
#   3. Otherwise the tier is the higher of the scored tier and --floor.
#
# Exit codes
#   0  a classification was produced (this includes every tier — the tier is the
#      result, never an error condition)
#   1  usage error (unknown flag, unreadable input, unknown tier name)
#   2  missing required tool
set -euo pipefail

PROG="${0##*/}"

usage() {
  cat >&2 <<'EOF'
Usage: classify-risk.sh [--files <path|->] [--assignment <path>]
                        [--floor <tier>] [--override <tier|thorough>]
       classify-risk.sh --self-test

Prints key=value lines: tier, score, basis, files, override, forced, floor,
and one signal= line per fired signal. Exit 1 on a usage error.
EOF
}

# --- Signal patterns ---------------------------------------------------------
#
# All matching is done on the lower-cased path (or lower-cased assignment text),
# so every pattern here is written in lower case and needs no case folding of
# its own.

DOC_RE='(^|/)(docs?|documentation)/|\.(md|mdx|markdown|rst|txt|adoc)$|(^|/)(readme|changelog|license|contributing|code_of_conduct)([.-][a-z0-9]+)?$'
TEST_RE='(^|/)tests?/|(^|/)spec/|tests?\.php$|\.test\.[a-z]+$|\.spec\.[a-z]+$|_test\.[a-z]+$|(^|/)test_[a-z0-9_]+\.py$|(^|/)phpunit\.xml|(^|/)pest\.php$'
FORMAT_RE='(^|/)\.(editorconfig|gitignore|gitattributes|prettierrc|eslintrc|styleci)([.-][a-z0-9]+)*$|(^|/)(pint|\.php-cs-fixer)\.[a-z.]+$|(^|/)(ruleset|phpcs)\.xml(\.dist)?$|(^|/)rector\.php$|(^|/)phpstan\.neon(\.dist)?$'

AUTH_RE='auth|login|logout|password|credential|secret|token|jwt|oauth|saml|session|crypt|cipher|(^|/)policies/|policy|(^|/)gates?/|permission|privilege|(^|/)acl|(^|/)roles?/|admin|guard|csrf|cors|sanctum|passport|2fa|mfa'
DATA_RE='(^|/)migrations?/|migration|\.sql$|(^|/)schema[./]|truncate|drop_'
PAY_RE='payment|billing|invoice|subscription|checkout|stripe|paypal|braintree|adyen|gopay|refund|pricing|currency'
QUEUE_RE='(^|/)jobs?/|(^|/)queues?/|queue|worker|(^|/)listeners?/|(^|/)events?/|lock|mutex|semaphore|concurren|cache|redis|schedul|cron|broadcast'
API_RE='(^|/)routes/api|(^|/)api/|api[a-z0-9_-]*controller|openapi|swagger|graphql|\.proto$'
CORE_RE='(^|/)config/|serviceprovider|(^|/)bootstrap/|(^|/)routes/|kernel\.php$|(^|/)composer\.json$|(^|/)package\.json$|\.github/workflows/|(^|/)providers?/|(^|/)middleware/|(^|/)src/(support|core|foundation)/|dockerfile|docker-compose'

# Markers that prove the assignment states what "done" means. Both project
# languages are covered: the assignment is written in whatever language the
# reporter used, and an English-only marker set would score every Czech
# assignment as unclear.
AC_RE='acceptance criteria|acceptance-criteria|expected behaviou?r|expected result|definition of done|akceptačn|očekávan|kritéria|- \[ \]'

lower() { printf '%s' "$1" | tr '[:upper:]' '[:lower:]'; }

# Render untrusted text safely: file paths and assignment text come from a
# tracker anyone may write to, and they are printed in this script's own
# verdict. ANSI escapes could rewrite that verdict and bidi overrides could
# reverse it, so display is restricted to printable ASCII and truncated.
safe_display() {
  printf '%s' "$1" | LC_ALL=C tr -cd '[:print:]' | cut -c1-120
}

TIER_FAST=0
TIER_STANDARD=1
TIER_CRITICAL=2

tier_name() {
  case "$1" in
  "$TIER_FAST") printf 'FAST' ;;
  "$TIER_STANDARD") printf 'STANDARD' ;;
  *) printf 'CRITICAL' ;;
  esac
}

tier_rank() {
  case "$(lower "$1")" in
  fast) printf '%s' "$TIER_FAST" ;;
  standard) printf '%s' "$TIER_STANDARD" ;;
  critical | thorough) printf '%s' "$TIER_CRITICAL" ;;
  *) return 1 ;;
  esac
}

tier_from_score() {
  local score="$1"
  if [[ "$score" -le 1 ]]; then
    printf '%s' "$TIER_FAST"
  elif [[ "$score" -le 4 ]]; then
    printf '%s' "$TIER_STANDARD"
  else
    printf '%s' "$TIER_CRITICAL"
  fi
}

classify() {
  local files_arg="" assignment_arg="" floor_arg="" override_arg=""

  while [[ $# -gt 0 ]]; do
    case "$1" in
    --files)
      [[ $# -ge 2 ]] || { usage; return 1; }
      files_arg="$2"
      shift 2
      ;;
    --assignment)
      [[ $# -ge 2 ]] || { usage; return 1; }
      assignment_arg="$2"
      shift 2
      ;;
    --floor)
      [[ $# -ge 2 ]] || { usage; return 1; }
      floor_arg="$2"
      shift 2
      ;;
    --override)
      [[ $# -ge 2 ]] || { usage; return 1; }
      override_arg="$2"
      shift 2
      ;;
    *)
      echo "$PROG: unknown argument: $(safe_display "$1")" >&2
      usage
      return 1
      ;;
    esac
  done

  # --- Read the inputs -------------------------------------------------------
  local raw_files="" assignment_text="" have_assignment=0

  if [[ -n "$files_arg" ]]; then
    if [[ "$files_arg" == "-" ]]; then
      raw_files="$(cat)"
    elif [[ -r "$files_arg" ]]; then
      raw_files="$(cat -- "$files_arg")"
    else
      echo "$PROG: cannot read file list: $(safe_display "$files_arg")" >&2
      return 1
    fi
  fi

  if [[ -n "$assignment_arg" ]]; then
    if [[ -r "$assignment_arg" ]]; then
      assignment_text="$(lower "$(cat -- "$assignment_arg")")"
      have_assignment=1
    else
      echo "$PROG: cannot read assignment: $(safe_display "$assignment_arg")" >&2
      return 1
    fi
  fi

  local floor_rank="" floor_label="none"
  if [[ -n "$floor_arg" ]]; then
    if ! floor_rank="$(tier_rank "$floor_arg")"; then
      echo "$PROG: unknown --floor tier: $(safe_display "$floor_arg")" >&2
      return 1
    fi
    floor_label="$(tier_name "$floor_rank")"
  fi

  local override_rank="" override_label="none"
  if [[ -n "$override_arg" ]]; then
    if ! override_rank="$(tier_rank "$override_arg")"; then
      echo "$PROG: unknown --override tier: $(safe_display "$override_arg")" >&2
      return 1
    fi
    override_label="$(lower "$override_arg")"
  fi

  # --- Split the changed paths into material / doc / test --------------------
  local -a material=() docs=() tests=() formats=() all=()
  local path lowered

  while IFS= read -r path; do
    [[ -n "$path" ]] || continue
    all+=("$path")
    lowered="$(lower "$path")"
    if [[ "$lowered" =~ $DOC_RE ]]; then
      docs+=("$path")
      continue
    fi
    if [[ "$lowered" =~ $TEST_RE ]]; then
      tests+=("$path")
      continue
    fi
    if [[ "$lowered" =~ $FORMAT_RE ]]; then
      formats+=("$path")
    fi
    material+=("$path")
  done <<<"$raw_files"

  local file_count="${#all[@]}"
  local basis="none"
  if [[ "$file_count" -gt 0 ]]; then
    basis="diff"
  elif [[ "$have_assignment" -eq 1 ]]; then
    basis="assignment"
  fi

  # --- Match the path signals ------------------------------------------------
  #
  # On `basis=diff` the haystack is the material paths; on `basis=assignment`
  # it is the assignment prose, which is all that exists before any code does.
  local haystack=""
  if [[ "$basis" == "diff" ]]; then
    if [[ "${#material[@]}" -gt 0 ]]; then
      haystack="$(lower "$(printf '%s\n' "${material[@]}")")"
    fi
  elif [[ "$basis" == "assignment" ]]; then
    haystack="$assignment_text"
  fi

  local score=0 forced="none"
  local -a signals=()

  add_signal() {
    local delta="$1" name="$2" evidence="$3"
    score=$((score + delta))
    local sign="+"
    [[ "$delta" -lt 0 ]] && sign=""
    signals+=("signal=${sign}${delta}|${name}|${evidence}")
  }

  # First match wins per haystack line, so the evidence names one concrete path
  # (or the word in the assignment) rather than the whole input.
  first_match() {
    local regex="$1" line
    while IFS= read -r line; do
      [[ -n "$line" ]] || continue
      if [[ "$line" =~ $regex ]]; then
        printf '%s' "${BASH_REMATCH[0]}:$(printf '%s' "$line" | cut -c1-60)"
        return 0
      fi
    done <<<"$haystack"
    return 1
  }

  local evidence
  if evidence="$(first_match "$AUTH_RE")"; then
    add_signal 3 'auth-security-secrets' "$evidence"
    forced='auth-security-secrets'
  fi
  if evidence="$(first_match "$DATA_RE")"; then
    add_signal 3 'migrations-data-loss' "$evidence"
    [[ "$forced" == "none" ]] && forced='migrations-data-loss'
  fi
  if evidence="$(first_match "$PAY_RE")"; then
    add_signal 3 'payments-billing' "$evidence"
    [[ "$forced" == "none" ]] && forced='payments-billing'
  fi
  if evidence="$(first_match "$QUEUE_RE")"; then
    add_signal 2 'queues-concurrency-locking' "$evidence"
  fi
  if evidence="$(first_match "$API_RE")"; then
    add_signal 2 'public-api' "$evidence"
  fi
  if evidence="$(first_match "$CORE_RE")"; then
    add_signal 2 'shared-core-architecture' "$evidence"
  fi

  # --- Size, coverage, and clarity ------------------------------------------
  if [[ "$file_count" -gt 10 ]]; then
    add_signal 2 'changed-files-many' "$file_count files"
  elif [[ "$file_count" -ge 4 ]]; then
    add_signal 1 'changed-files-moderate' "$file_count files"
  fi

  if [[ "${#material[@]}" -gt 0 ]]; then
    add_signal 1 'production-code-changed' "${#material[@]} material file(s)"
  fi

  if [[ "${#material[@]}" -gt 0 && "${#tests[@]}" -eq 0 ]]; then
    add_signal 1 'missing-relevant-tests' "${#material[@]} material file(s), no test file changed"
  fi

  # No assignment text is itself unclear: nothing states what done means, so the
  # point fires and the verdict can only move up.
  if [[ "$have_assignment" -eq 0 ]]; then
    add_signal 1 'unclear-acceptance-criteria' 'no assignment text supplied'
  elif [[ ! "$assignment_text" =~ $AC_RE ]]; then
    add_signal 1 'unclear-acceptance-criteria' 'assignment states no acceptance criteria'
  fi

  # --- The "only" reductions -------------------------------------------------
  if [[ "$file_count" -gt 0 && "${#docs[@]}" -eq "$file_count" ]]; then
    add_signal -2 'documentation-only' "$file_count documentation file(s)"
  elif [[ "$file_count" -gt 0 && "${#tests[@]}" -eq "$file_count" ]]; then
    add_signal -2 'tests-only' "$file_count test file(s)"
  elif [[ "$file_count" -gt 0 && "${#formats[@]}" -eq "$file_count" ]]; then
    add_signal -1 'formatting-metadata-only' "$file_count formatting / metadata file(s)"
  fi

  # --- Resolve the tier ------------------------------------------------------
  local scored_rank tier_rank_final override_refused=""
  scored_rank="$(tier_from_score "$score")"
  tier_rank_final="$scored_rank"

  if [[ -n "$floor_rank" && "$floor_rank" -gt "$tier_rank_final" ]]; then
    tier_rank_final="$floor_rank"
  fi

  if [[ "$forced" != "none" ]]; then
    tier_rank_final="$TIER_CRITICAL"
    if [[ -n "$override_rank" && "$override_rank" -lt "$TIER_CRITICAL" ]]; then
      override_refused="$(tier_name "$override_rank")"
    fi
  elif [[ -n "$override_rank" ]]; then
    tier_rank_final="$override_rank"
  fi

  # --- Emit ------------------------------------------------------------------
  printf 'tier=%s\n' "$(tier_name "$tier_rank_final")"
  printf 'score=%s\n' "$score"
  printf 'basis=%s\n' "$basis"
  printf 'files=%s\n' "$file_count"
  printf 'override=%s\n' "$override_label"
  [[ -n "$override_refused" ]] && printf 'override-refused=%s\n' "$override_refused"
  printf 'forced=%s\n' "$forced"
  printf 'floor=%s\n' "$floor_label"

  local entry
  for entry in ${signals[@]+"${signals[@]}"}; do
    printf '%s\n' "$(safe_display "$entry")"
  done

  return 0
}

# Global, not local: the EXIT trap fires after the function's locals are gone,
# and reading an unset local under `set -u` would abort the cleanup.
SELF_TEST_TMP=""
# Reached only through `trap cleanup_self_test EXIT`. ShellCheck's reachability pass does not
# credit a trap as an invocation (SC2317, and SC2329 in ShellCheck 0.11), so both are suppressed.
# shellcheck disable=SC2317,SC2329
cleanup_self_test() {
  [[ -n "$SELF_TEST_TMP" ]] && rm -rf "$SELF_TEST_TMP"
  return 0
}

self_test() {
  local failures=0 script
  script="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)/$PROG"
  SELF_TEST_TMP="$(mktemp -d)"
  trap cleanup_self_test EXIT

  local tmp="$SELF_TEST_TMP"

  # An assignment that does state its acceptance criteria, so the clarity point
  # does not fire and each scenario below measures what it means to measure.
  printf 'Acceptance criteria:\n- the button saves the form\n' >"$tmp/clear.txt"
  printf 'Please make it better somehow.\n' >"$tmp/vague.txt"

  writefiles() {
    local target="$tmp/files-$RANDOM$RANDOM.txt"
    printf '%s\n' "$@" >"$target"
    printf '%s' "$target"
  }

  # Assert the tier AND, where it matters, the attribution — a right tier
  # reached through the wrong signal is a bug that changes verdict on the next
  # input.
  expect_tier() {
    local label="$1" expected="$2"
    shift 2
    local out actual
    if ! out="$("$script" "$@" 2>&1)"; then
      printf 'FAIL  %-52s script exited non-zero: %s\n' "$label" "$out" >&2
      failures=$((failures + 1))
      return 0
    fi
    actual="$(printf '%s' "$out" | awk -F= '$1 == "tier" { print $2; exit }')"
    if [[ "$actual" != "$expected" ]]; then
      printf 'FAIL  %-52s expected %s, got %s\n' "$label" "$expected" "$actual" >&2
      printf '%s\n' "$out" >&2
      failures=$((failures + 1))
      return 0
    fi
    printf 'ok    %-52s %s\n' "$label" "$actual"
  }

  expect_line() {
    local label="$1" needle="$2"
    shift 2
    local out
    out="$("$script" "$@" 2>&1 || true)"
    if printf '%s' "$out" | grep -qF -- "$needle"; then
      printf 'ok    %-52s %s\n' "$label" "$needle"
    else
      printf 'FAIL  %-52s missing %s\n' "$label" "$needle" >&2
      printf '%s\n' "$out" >&2
      failures=$((failures + 1))
    fi
  }

  expect_exit() {
    local label="$1" expected="$2"
    shift 2
    local actual
    set +e
    "$script" "$@" >/dev/null 2>&1
    actual=$?
    set -e
    if [[ "$actual" -eq "$expected" ]]; then
      printf 'ok    %-52s exit %s\n' "$label" "$actual"
    else
      printf 'FAIL  %-52s expected exit %s, got %s\n' "$label" "$expected" "$actual" >&2
      failures=$((failures + 1))
    fi
  }

  # --- The scenarios the routing contract is required to cover ---------------

  # 1. Documentation-only change: a README typo must not buy a review pass.
  expect_tier 'README typo is FAST' FAST \
    --files "$(writefiles 'README.md')" --assignment "$tmp/clear.txt"

  # A doc file whose path contains a sensitive word must stay FAST: the path
  # signals read material files only, and a document is not material.
  expect_tier 'security doc is still FAST' FAST \
    --files "$(writefiles 'docs/security/threat-model.md')" --assignment "$tmp/clear.txt"

  # 2. Tests-only change.
  expect_tier 'tests-only change is FAST' FAST \
    --files "$(writefiles 'tests/Unit/InvoiceTest.php' 'tests/Unit/OrderTest.php')" \
    --assignment "$tmp/clear.txt"

  # 3. Small isolated bug fix that ships its test.
  expect_tier 'small fix with its test is FAST' FAST \
    --files "$(writefiles 'src/Formatter.php' 'tests/Unit/FormatterTest.php')" \
    --assignment "$tmp/clear.txt"

  # An authorization middleware is often named for what it authorizes rather
  # than for authorization itself — `EnsureUserIsAdmin` carries neither "auth"
  # nor "authorize", and matched nothing until `admin` was added.
  expect_line 'authorization middleware named for its role' 'forced=auth-security-secrets' \
    --files "$(writefiles 'app/Http/Middleware/EnsureUserIsAdmin.php')" --assignment "$tmp/clear.txt"

  # 4. Normal business-logic feature.
  expect_tier 'ordinary feature is STANDARD' STANDARD \
    --files "$(writefiles \
      'app/Actions/Order/CreateOrder.php' \
      'app/Dto/Order/OrderData.php' \
      'app/Models/Order.php' \
      'resources/views/order/create.blade.php' \
      'tests/Feature/CreateOrderTest.php')" \
    --assignment "$tmp/clear.txt"

  # 5. Security-sensitive change: authorization middleware forces CRITICAL even
  #    though its own score is far below the CRITICAL threshold.
  expect_tier 'authorization middleware is CRITICAL' CRITICAL \
    --files "$(writefiles 'app/Http/Middleware/EnsureUserIsAdmin.php' 'tests/Feature/AdminAccessTest.php')" \
    --assignment "$tmp/clear.txt"
  expect_line 'the force names its own signal' 'forced=auth-security-secrets' \
    --files "$(writefiles 'app/Http/Middleware/EnsureUserIsAdmin.php')" --assignment "$tmp/clear.txt"

  expect_tier 'a migration is CRITICAL' CRITICAL \
    --files "$(writefiles 'database/migrations/2026_01_01_drop_legacy_column.php')" \
    --assignment "$tmp/clear.txt"
  expect_tier 'a payment path is CRITICAL' CRITICAL \
    --files "$(writefiles 'app/Services/Billing/StripeCharge.php')" --assignment "$tmp/clear.txt"

  # 6. Post-implementation escalation: the task began as a FAST docs change and
  #    the diff turned out to touch authentication across a dozen files.
  local grown
  grown="$(writefiles \
    'app/Http/Middleware/Authenticate.php' 'app/Models/User.php' 'app/Actions/A.php' \
    'app/Actions/B.php' 'app/Actions/C.php' 'app/Actions/D.php' 'app/Actions/E.php' \
    'app/Actions/F.php' 'app/Actions/G.php' 'app/Actions/H.php' 'app/Actions/I.php' \
    'app/Actions/J.php')"
  expect_tier 'grown diff re-classifies to CRITICAL' CRITICAL \
    --files "$grown" --assignment "$tmp/clear.txt" --floor fast

  # The ratchet: a later, smaller diff never drops below the tier already paid
  # for, or an escalation could be undone by a follow-up commit.
  expect_tier 'floor is never lowered by a later small diff' STANDARD \
    --files "$(writefiles 'README.md')" --assignment "$tmp/clear.txt" --floor standard

  # 7. Explicit overrides.
  expect_tier '--thorough forces the full pipeline' CRITICAL \
    --files "$(writefiles 'README.md')" --assignment "$tmp/clear.txt" --override thorough
  expect_tier '--critical escalates a FAST change' CRITICAL \
    --files "$(writefiles 'README.md')" --assignment "$tmp/clear.txt" --override critical
  expect_tier '--standard applies when nothing forces' STANDARD \
    --files "$(writefiles 'README.md')" --assignment "$tmp/clear.txt" --override standard
  expect_tier '--fast applies when nothing forces' FAST \
    --files "$(writefiles 'app/A.php' 'app/B.php' 'app/C.php' 'app/D.php' 'app/E.php')" \
    --assignment "$tmp/clear.txt" --override fast

  # A downgrade override never silences a sensitive-area force.
  expect_tier '--fast is refused on an auth change' CRITICAL \
    --files "$(writefiles 'app/Http/Middleware/Authenticate.php')" \
    --assignment "$tmp/clear.txt" --override fast
  expect_line 'a refused override is recorded' 'override-refused=FAST' \
    --files "$(writefiles 'app/Http/Middleware/Authenticate.php')" \
    --assignment "$tmp/clear.txt" --override fast

  # --- Pre-implementation classification, before a diff exists ---------------
  local authtext="$tmp/auth-assignment.txt"
  printf 'Acceptance criteria: the login form must reject an expired password reset token.\n' >"$authtext"
  expect_tier 'assignment text alone can force CRITICAL' CRITICAL --assignment "$authtext"
  expect_line 'assignment-only classification says so' 'basis=assignment' --assignment "$authtext"

  # --- Clarity and coverage signals ------------------------------------------
  expect_line 'a vague assignment scores the clarity point' 'unclear-acceptance-criteria' \
    --files "$(writefiles 'src/Formatter.php' 'tests/Unit/FormatterTest.php')" --assignment "$tmp/vague.txt"
  expect_line 'a source change with no test is flagged' 'missing-relevant-tests' \
    --files "$(writefiles 'src/Formatter.php')" --assignment "$tmp/clear.txt"
  # Without this point an ordinary feature that ships its tests scored 1 and
  # routed FAST, which is the tier definition's own counter-example.
  expect_line 'touching production code scores a point' 'production-code-changed' \
    --files "$(writefiles 'src/Formatter.php' 'tests/Unit/FormatterTest.php')" --assignment "$tmp/clear.txt"
  expect_line 'every point is attributable to a signal line' 'signal=-2|documentation-only' \
    --files "$(writefiles 'README.md' 'docs/agents.md')" --assignment "$tmp/clear.txt"

  # --- Input handling --------------------------------------------------------
  expect_line 'stdin file list is accepted' 'basis=diff' --files - --assignment "$tmp/clear.txt" <<<'README.md'
  expect_exit 'unknown flag is a usage error' 1 --nonsense
  expect_exit 'unknown tier name is a usage error' 1 --override paranoid
  expect_exit 'unreadable file list is a usage error' 1 --files "$tmp/does-not-exist"
  expect_exit 'no input still classifies' 0

  # An escape sequence in a path must not rewrite the verdict it is printed in.
  expect_line 'untrusted paths are rendered safely' 'signal=' \
    --files "$(writefiles "$(printf 'app/\033[2JEvil.php')")" --assignment "$tmp/clear.txt"

  if [[ "$failures" -gt 0 ]]; then
    echo "classify-risk self-test: $failures failure(s)" >&2
    return 4
  fi
  echo 'classify-risk self-test: PASS'
  return 0
}

if [[ "${1:-}" == "--self-test" ]]; then
  self_test
  exit $?
fi

classify "$@"
