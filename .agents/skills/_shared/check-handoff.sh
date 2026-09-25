#!/usr/bin/env bash
# check-handoff.sh — validate a structured agent handoff against its schema and
# its size budget.
#
# Why this exists
#   A handoff is read by every later stage of the run, so whatever it carries is
#   re-tokenised once per stage. Prose handoffs grew: they restated the task,
#   repeated acceptance criteria nobody had changed, pasted test output, and
#   quoted the previous handoff. A three-round review paid for all of it four
#   times.
#
#   The fix is a handoff that carries decisions and pointers, with the evidence
#   left in files the next agent reads only when it needs them. This script is
#   what makes that contract real rather than aspirational: a handoff that
#   exceeds its budget, or that inlines evidence instead of referencing it, is
#   rejected at the moment it is written.
#
# Usage
#   check-handoff.sh --file <path|-> --role <implementation|review|validation|acceptance|reporting>
#                    [--budget <words>]
#   check-handoff.sh --self-test
#
#   --budget  soft budget in prose-equivalent words (default 600, roughly
#             800 tokens). Exceeding it is an error, because a budget nothing
#             enforces is a comment.
#
# Schemas (required keys per role)
#   implementation  status, sha, changed_files, validation, next
#   review          status, findings
#   validation      status, checks
#   acceptance      status, criteria
#   reporting       status
#
#   `status` is always required and always one of: completed, changes_requested,
#   passed, failed, blocked.
#
# Output (stdout, JSON)
#   { "valid": true, "role": "…", "words": 120, "budget": 600, "problems": [] }
#
# Exit codes
#   0  the handoff is valid and within budget
#   1  usage error
#   2  missing required tool (jq)
#   3  the handoff is invalid (schema, status, inlined evidence, or over budget)
set -euo pipefail

PROG="${0##*/}"

usage() {
  cat >&2 <<'EOF'
Usage: check-handoff.sh --file <path|-> --role <role> [--budget <words>]
       check-handoff.sh --self-test

Roles: implementation, review, validation, acceptance, reporting.
Exit 3 when the handoff breaks its schema, inlines evidence, or exceeds budget.
EOF
}

DEFAULT_BUDGET=600

VALID_STATUSES='completed changes_requested passed failed blocked'

safe_display() {
  printf '%s' "$1" | LC_ALL=C tr -cd '[:print:]' | cut -c1-160
}

json_string() {
  printf '%s' "$1" | LC_ALL=C sed -e 's/\\/\\\\/g' -e 's/"/\\"/g' | tr -d '\n\r'
}

required_keys_for() {
  case "$1" in
  implementation) printf 'status sha changed_files validation next' ;;
  review) printf 'status findings' ;;
  validation) printf 'status checks' ;;
  acceptance) printf 'status criteria' ;;
  reporting) printf 'status' ;;
  *) return 1 ;;
  esac
}

check() {
  local file_arg="" role="" budget="$DEFAULT_BUDGET"

  while [[ $# -gt 0 ]]; do
    case "$1" in
    --file)
      [[ $# -ge 2 ]] || { usage; return 1; }
      file_arg="$2"
      shift 2
      ;;
    --role)
      [[ $# -ge 2 ]] || { usage; return 1; }
      role="$2"
      shift 2
      ;;
    --budget)
      [[ $# -ge 2 ]] || { usage; return 1; }
      budget="$2"
      shift 2
      ;;
    *)
      echo "$PROG: unknown argument: $(safe_display "$1")" >&2
      usage
      return 1
      ;;
    esac
  done

  [[ -n "$file_arg" && -n "$role" ]] || { usage; return 1; }
  [[ "$budget" =~ ^[0-9]+$ ]] || { echo "$PROG: --budget must be a number" >&2; return 1; }

  local required
  if ! required="$(required_keys_for "$role")"; then
    echo "$PROG: unknown role: $(safe_display "$role")" >&2
    return 1
  fi

  local body
  if [[ "$file_arg" == "-" ]]; then
    body="$(cat)"
  elif [[ -r "$file_arg" ]]; then
    body="$(cat -- "$file_arg")"
  else
    echo "$PROG: cannot read handoff: $(safe_display "$file_arg")" >&2
    return 1
  fi

  local -a problems=()

  if ! printf '%s' "$body" | jq -e . >/dev/null 2>&1; then
    emit "$role" 0 "$budget" 'handoff is not valid JSON'
    return 3
  fi

  local key
  for key in $required; do
    if ! printf '%s' "$body" | jq -e --arg k "$key" 'has($k)' >/dev/null 2>&1; then
      problems+=("missing required key: $key")
    fi
  done

  local status
  status="$(printf '%s' "$body" | jq -r '.status // ""')"
  if [[ -n "$status" ]] && ! printf '%s' " $VALID_STATUSES " | grep -q " $status "; then
    problems+=("unknown status: $status")
  fi

  # --- Inlined evidence ------------------------------------------------------
  #
  # The budget alone does not catch this: a short handoff can still inline the
  # wrong KIND of content, and the next one will be longer. Evidence is
  # referenced by path; it is never pasted.
  local suspicious
  suspicious="$(printf '%s' "$body" | jq -r '
    [ .. | strings ] | .[]
  ' 2>/dev/null || true)"

  if printf '%s' "$suspicious" | grep -qE '^(diff --git|@@ -|\+\+\+ |--- )'; then
    problems+=('handoff inlines a diff — reference the artifact path instead')
  fi
  if printf '%s' "$suspicious" | grep -qiE 'PHPUnit [0-9]|Tests:[[:space:]]+[0-9]+ (passed|failed)|PASS +tests/|FAIL +tests/'; then
    problems+=('handoff inlines test output — reference the log path instead')
  fi

  # --- Budget ----------------------------------------------------------------
  local words
  words="$(printf '%s' "$body" | jq -r '[ .. | strings ] | join(" ")' 2>/dev/null | wc -w | tr -d ' ')"
  if [[ "$words" -gt "$budget" ]]; then
    problems+=("handoff carries $words prose words, over the budget of $budget — move evidence to an artifact and reference it")
  fi

  if [[ "${#problems[@]}" -gt 0 ]]; then
    emit "$role" "$words" "$budget" "${problems[@]}"
    return 3
  fi

  emit "$role" "$words" "$budget"
  return 0
}

emit() {
  local role="$1" words="$2" budget="$3"
  shift 3
  local first=1 problem

  printf '{\n'
  printf '  "valid": %s,\n' "$([[ $# -eq 0 ]] && printf 'true' || printf 'false')"
  printf '  "role": "%s",\n' "$(json_string "$role")"
  printf '  "words": %s,\n' "$words"
  printf '  "budget": %s,\n' "$budget"
  printf '  "problems": ['
  for problem in "$@"; do
    [[ "$first" -eq 1 ]] || printf ','
    first=0
    printf '\n    "%s"' "$(json_string "$problem")"
  done
  [[ "$first" -eq 1 ]] || printf '\n  '
  printf ']\n'
  printf '}\n'
}

self_test() {
  local failures=0 script tmp
  script="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)/$PROG"
  tmp="$(mktemp -d)"
  # shellcheck disable=SC2064
  trap "rm -rf '$tmp'" EXIT

  verdict() {
    local label="$1" role="$2" json="$3" expected="$4"
    local file="$tmp/handoff-$RANDOM$RANDOM.json" actual
    printf '%s' "$json" >"$file"
    set +e
    "$script" --file "$file" --role "$role" >/dev/null 2>&1
    actual=$?
    set -e
    if [[ "$actual" -eq "$expected" ]]; then
      printf 'ok    %-54s exit %s\n' "$label" "$actual"
    else
      printf 'FAIL  %-54s expected exit %s, got %s\n' "$label" "$expected" "$actual" >&2
      failures=$((failures + 1))
    fi
  }

  local IMPL='{ "status": "completed", "sha": "abc123", "changed_files": ["app/Actions/CreateOrder.php"], "validation": { "status": "passed", "artifact": "logs/validation.json" }, "risks": [], "next": "review" }'

  verdict 'a well-formed implementation handoff is valid' implementation "$IMPL" 0
  verdict 'a well-formed review handoff is valid' review \
    '{ "status": "changes_requested", "findings": [ { "severity": "moderate", "file": "app/Actions/CreateOrder.php", "summary": "Race condition remains possible." } ] }' 0
  verdict 'a validation handoff is valid' validation \
    '{ "status": "passed", "checks": { "tests": "passed", "lint": "passed" } }' 0

  verdict 'malformed JSON is rejected' implementation '{ not json' 3
  verdict 'a missing required key is rejected' implementation \
    '{ "status": "completed", "sha": "abc123" }' 3
  verdict 'an unknown status is rejected' review \
    '{ "status": "vibes", "findings": [] }' 3

  # Evidence belongs in an artifact the next agent opens on demand, not in the
  # document every later stage re-reads.
  verdict 'an inlined diff is rejected' implementation \
    '{ "status": "completed", "sha": "abc123", "changed_files": ["a.php"], "validation": { "status": "passed" }, "next": "review", "detail": "diff --git a/a.php b/a.php" }' 3
  verdict 'inlined test output is rejected' validation \
    '{ "status": "passed", "checks": {}, "log": "PASS  tests/Unit/FooTest.php" }' 3

  # Over budget: built from a repeated word so the count is unambiguous.
  local filler
  filler="$(awk 'BEGIN { for (i = 0; i < 700; i++) printf "word " }')"
  printf '{ "status": "completed", "sha": "abc123", "changed_files": ["a.php"], "validation": {"status":"passed"}, "next": "review", "notes": "%s" }' "$filler" >"$tmp/big.json"
  set +e
  "$script" --file "$tmp/big.json" --role implementation >/dev/null 2>&1
  local big=$?
  set -e
  if [[ "$big" -eq 3 ]]; then
    printf 'ok    %-54s exit 3\n' 'an over-budget handoff is rejected'
  else
    printf 'FAIL  %-54s expected exit 3, got %s\n' 'an over-budget handoff is rejected' "$big" >&2
    failures=$((failures + 1))
  fi

  # The budget is configurable, so a project that measures a different figure can
  # move it without editing the script.
  set +e
  "$script" --file "$tmp/big.json" --role implementation --budget 5000 >/dev/null 2>&1
  local raised=$?
  set -e
  if [[ "$raised" -eq 0 ]]; then
    printf 'ok    %-54s exit 0\n' 'a raised budget accepts the same handoff'
  else
    printf 'FAIL  %-54s expected exit 0, got %s\n' 'a raised budget accepts the same handoff' "$raised" >&2
    failures=$((failures + 1))
  fi

  local rc
  set +e
  "$script" --file "$tmp/big.json" --role nonsense >/dev/null 2>&1
  rc=$?
  set -e
  if [[ "$rc" -eq 1 ]]; then
    printf 'ok    %-54s exit 1\n' 'an unknown role is a usage error'
  else
    printf 'FAIL  %-54s expected exit 1, got %s\n' 'an unknown role is a usage error' "$rc" >&2
    failures=$((failures + 1))
  fi

  if [[ "$failures" -gt 0 ]]; then
    echo "check-handoff self-test: $failures failure(s)" >&2
    return 4
  fi
  echo 'check-handoff self-test: PASS'
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

check "$@"
