#!/usr/bin/env bash
# render-report.sh — render the routine completion report from structured run
# data, without a model.
#
# Why this exists
#   The completion report says what changed, whether validation and review
#   passed, and where the pull request is. Every one of those facts already
#   exists in the run's own artifacts by the time the report is written, so
#   producing it used to mean dispatching an agent to restate data it was handed.
#
#   Language generation still earns a model when the audience is a human being
#   addressed as one — a release announcement, changelog prose, a stakeholder
#   note. A four-line engineering status is not that, and `april` is reserved
#   for the cases that are (`agents/april.md` *When a model is warranted*).
#
# Usage
#   render-report.sh --data <path|-> [--language <code>]
#   render-report.sh --self-test
#
#   --language  the assignment's language, so the report obeys
#               `@rules/reports/general.md` *Tracker-Published Reports — Language*.
#               Supported: `en` (default) and `cs`. An unsupported code is a
#               usage error rather than a silent fallback to English: a report
#               in the wrong language on a tracker is exactly what that rule
#               exists to prevent, and a model is the escalation path for a
#               language this renderer does not carry.
#
# Input
#   {
#     "status": "completed",
#     "summary": "Rejects an empty import payload instead of importing zero rows.",
#     "changed_files": 3,
#     "validation": "passed",
#     "review": "passed",
#     "tier": "STANDARD",
#     "pr_url": "https://github.com/owner/repo/pull/42",
#     "source_url": "https://github.com/owner/repo/issues/7",
#     "how_to_test": ["Post an empty payload to /api/import", "Expect 422 and no rows created"]
#   }
#
#   `status` and `summary` are required; everything else renders only when
#   present, because a line that says `PR: none` is noise rather than a report.
#
# Exit codes
#   0  a report was rendered
#   1  usage error, unsupported language, or required data missing
#   2  missing required tool (jq)
set -euo pipefail

PROG="${0##*/}"

usage() {
  cat >&2 <<'EOF'
Usage: render-report.sh --data <path|-> [--language <en|cs>]
       render-report.sh --self-test

Renders the routine completion report as Markdown on stdout.
EOF
}

safe_display() {
  printf '%s' "$1" | LC_ALL=C tr -cd '[:print:]' | cut -c1-160
}

# One table per language. Adding a language is adding a case here; it is
# deliberately not a lookup into a translation file, because the set is small
# and a missing key must be a syntax error rather than an empty heading.
label() {
  local key="$1"
  case "$LANGUAGE:$key" in
  en:complete) printf 'Completed' ;;
  en:blocked) printf 'Blocked' ;;
  en:validation) printf 'Validation' ;;
  en:review) printf 'Review' ;;
  en:files) printf 'Changed files' ;;
  en:tier) printf 'Execution tier' ;;
  en:pr) printf 'Pull request' ;;
  en:source) printf 'Source' ;;
  en:howto) printf 'How to test' ;;
  en:passed) printf 'PASS' ;;
  en:failed) printf 'FAIL' ;;
  en:skipped) printf 'not required at this tier' ;;
  cs:complete) printf 'Hotovo' ;;
  cs:blocked) printf 'Zablokováno' ;;
  cs:validation) printf 'Validace' ;;
  cs:review) printf 'Review' ;;
  cs:files) printf 'Změněné soubory' ;;
  cs:tier) printf 'Úroveň běhu' ;;
  cs:pr) printf 'Pull request' ;;
  cs:source) printf 'Zadání' ;;
  cs:howto) printf 'Jak to otestovat' ;;
  cs:passed) printf 'PROŠLO' ;;
  cs:failed) printf 'SELHALO' ;;
  cs:skipped) printf 'na této úrovni se nevyžaduje' ;;
  *) printf '%s' "$key" ;;
  esac
}

state_label() {
  case "$1" in
  passed) label passed ;;
  failed) label failed ;;
  skipped | '') label skipped ;;
  *) printf '%s' "$1" ;;
  esac
}

render() {
  local data_arg="" LANGUAGE_ARG="en"

  while [[ $# -gt 0 ]]; do
    case "$1" in
    --data)
      [[ $# -ge 2 ]] || { usage; return 1; }
      data_arg="$2"
      shift 2
      ;;
    --language)
      [[ $# -ge 2 ]] || { usage; return 1; }
      LANGUAGE_ARG="$2"
      shift 2
      ;;
    *)
      echo "$PROG: unknown argument: $(safe_display "$1")" >&2
      usage
      return 1
      ;;
    esac
  done

  [[ -n "$data_arg" ]] || { usage; return 1; }

  case "$LANGUAGE_ARG" in
  en | cs) LANGUAGE="$LANGUAGE_ARG" ;;
  *)
    echo "$PROG: unsupported language: $(safe_display "$LANGUAGE_ARG") — escalate to april for a language this renderer does not carry" >&2
    return 1
    ;;
  esac

  local data
  if [[ "$data_arg" == "-" ]]; then
    data="$(cat)"
  elif [[ -r "$data_arg" ]]; then
    data="$(cat -- "$data_arg")"
  else
    echo "$PROG: cannot read run data: $(safe_display "$data_arg")" >&2
    return 1
  fi

  if ! printf '%s' "$data" | jq -e . >/dev/null 2>&1; then
    echo "$PROG: run data is not valid JSON" >&2
    return 1
  fi

  local status summary
  status="$(printf '%s' "$data" | jq -r '.status // ""')"
  summary="$(printf '%s' "$data" | jq -r '.summary // ""')"

  if [[ -z "$status" || -z "$summary" ]]; then
    echo "$PROG: run data must carry status and summary" >&2
    return 1
  fi

  local heading
  case "$status" in
  completed | passed) heading="$(label complete)" ;;
  *) heading="$(label blocked)" ;;
  esac

  printf '## %s\n\n' "$heading"
  printf '%s\n\n' "$summary"

  local validation review files tier pr source
  validation="$(printf '%s' "$data" | jq -r '.validation // ""')"
  review="$(printf '%s' "$data" | jq -r '.review // ""')"
  files="$(printf '%s' "$data" | jq -r 'if has("changed_files") then .changed_files else "" end')"
  tier="$(printf '%s' "$data" | jq -r '.tier // ""')"
  pr="$(printf '%s' "$data" | jq -r '.pr_url // ""')"
  source="$(printf '%s' "$data" | jq -r '.source_url // ""')"

  [[ -n "$validation" ]] && printf -- '- %s: %s\n' "$(label validation)" "$(state_label "$validation")"
  [[ -n "$review" ]] && printf -- '- %s: %s\n' "$(label review)" "$(state_label "$review")"
  [[ -n "$files" ]] && printf -- '- %s: %s\n' "$(label files)" "$files"
  [[ -n "$tier" ]] && printf -- '- %s: %s\n' "$(label tier)" "$tier"
  [[ -n "$pr" ]] && printf -- '- %s: %s\n' "$(label pr)" "$pr"
  [[ -n "$source" ]] && printf -- '- %s: %s\n' "$(label source)" "$source"

  local steps
  steps="$(printf '%s' "$data" | jq -r '.how_to_test // [] | .[]')"
  if [[ -n "$steps" ]]; then
    printf '\n### %s\n\n' "$(label howto)"
    local index=1 step
    while IFS= read -r step; do
      [[ -n "$step" ]] || continue
      printf '%s. %s\n' "$index" "$step"
      index=$((index + 1))
    done <<<"$steps"
  fi

  return 0
}

self_test() {
  local failures=0 script tmp
  script="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)/$PROG"
  tmp="$(mktemp -d)"
  # shellcheck disable=SC2064
  trap "rm -rf '$tmp'" EXIT

  local FULL='{ "status": "completed", "summary": "Rejects an empty import payload.", "changed_files": 3, "validation": "passed", "review": "passed", "tier": "STANDARD", "pr_url": "https://example.test/pr/42", "source_url": "https://example.test/issue/7", "how_to_test": ["Post an empty payload", "Expect 422"] }'

  expect_contains() {
    local label="$1" json="$2" language="$3"
    shift 3
    local file="$tmp/data-$RANDOM$RANDOM.json" out needle missing=0
    printf '%s' "$json" >"$file"
    if ! out="$("$script" --data "$file" --language "$language" 2>&1)"; then
      printf 'FAIL  %-54s renderer exited non-zero\n' "$label" >&2
      failures=$((failures + 1))
      return 0
    fi
    for needle in "$@"; do
      if ! printf '%s' "$out" | grep -qF -- "$needle"; then
        printf 'FAIL  %-54s missing %s\n' "$label" "$needle" >&2
        missing=1
      fi
    done
    if [[ "$missing" -eq 1 ]]; then
      failures=$((failures + 1))
      return 0
    fi
    printf 'ok    %-54s\n' "$label"
  }

  expect_absent() {
    local label="$1" json="$2"
    shift 2
    local file="$tmp/data-$RANDOM$RANDOM.json" out needle
    printf '%s' "$json" >"$file"
    out="$("$script" --data "$file" 2>&1 || true)"
    for needle in "$@"; do
      if printf '%s' "$out" | grep -qF -- "$needle"; then
        printf 'FAIL  %-54s should not contain %s\n' "$label" "$needle" >&2
        failures=$((failures + 1))
        return 0
      fi
    done
    printf 'ok    %-54s\n' "$label"
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
      printf 'ok    %-54s exit %s\n' "$label" "$actual"
    else
      printf 'FAIL  %-54s expected exit %s, got %s\n' "$label" "$expected" "$actual" >&2
      failures=$((failures + 1))
    fi
  }

  expect_contains 'a completed run renders every known field' "$FULL" en \
    '## Completed' 'Validation: PASS' 'Review: PASS' 'Changed files: 3' \
    'Execution tier: STANDARD' 'https://example.test/pr/42' '### How to test' '1. Post an empty payload'

  # The report follows the assignment's language, per @rules/reports/general.md.
  expect_contains 'the report renders in the assignment language' "$FULL" cs \
    '## Hotovo' 'Validace: PROŠLO' 'Jak to otestovat'

  expect_contains 'a failed run reports the failure, not a success' \
    '{ "status": "blocked", "summary": "Tests fail on the changed surface.", "validation": "failed" }' en \
    '## Blocked' 'Validation: FAIL'

  # A line reading "PR: none" is noise; an absent fact is simply absent.
  expect_absent 'absent fields render no empty lines' \
    '{ "status": "completed", "summary": "Docs only." }' \
    'Pull request' 'Changed files' 'How to test'

  expect_exit 'missing data is a usage error' 1 --data /nonexistent/run.json
  expect_exit 'data without a summary is a usage error' 1 --data <(printf '{ "status": "completed" }')
  expect_exit 'an unsupported language escalates rather than guessing' 1 --data <(printf '%s' "$FULL") --language de

  if [[ "$failures" -gt 0 ]]; then
    echo "render-report self-test: $failures failure(s)" >&2
    return 4
  fi
  echo 'render-report self-test: PASS'
  return 0
}

if [[ "${1:-}" == "--self-test" ]]; then
  if ! command -v jq >/dev/null 2>&1; then
    echo "$PROG: required tool not found: jq" >&2
    exit 2
  fi
  self_test
  exit $?
fi

if ! command -v jq >/dev/null 2>&1; then
  echo "$PROG: required tool not found: jq" >&2
  exit 2
fi

LANGUAGE="en"
render "$@"
