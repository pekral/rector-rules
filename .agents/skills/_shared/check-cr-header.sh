#!/usr/bin/env bash
# check-cr-header.sh — verify the `Merge verdict:` and `Security assessment:` header lines of a code-review
# comment before it is published.
#
# Why this exists
#   Both lines are defined in prose only: rules/code-review/general.md *Merge verdict* and *Security
#   assessment*, rendered from skills/code-review-github/templates/pr-comment-output.md. A content test pins
#   the template text, but nothing checked the comment a run actually rendered, so a review could publish
#   without the line, with the four security answers missing or out of order, or with a verdict that
#   contradicts its own two halves. This script reads the rendered body and says so before it is published.
#
#   The check covers BOTH lines, in one pass: the shape of each line is the whole contract, and a body that
#   fails either line is not published (skills/code-review-github/references/cr-wrapper-contract.md).
#
# Usage
#   check-cr-header.sh --file <body-file|->
#   check-cr-header.sh --self-test
#
#   --file  the rendered comment body (Markdown), or `-` to read it from standard input.
#
# What is checked
#   Merge verdict:       exactly one line, `<yes|no> — assignment met: <yes|no|no linked issue> · open Critical: <n>`,
#                        followed by ` · <blockers>` when the verdict is no. A no names at least one blocker. A yes
#                        never states an unmet assignment and never states an open Critical.
#   Security assessment: exactly one line, either `not applicable — the diff changes no code` or the four answers
#                        in this order: `untrusted data:` · `public exposure:` · `regression test:` ·
#                        `automatic rule:`. The regression test answer is `not required`, `present — <test>`, or
#                        `required — <unpinned guarantees>`.
#   A line may be written with or without the Markdown bold around its label. A line inside a fenced code block
#   is a quotation and is not read. The whole body is read, not only the header block, by the parser in
#   skills/_shared/cr-header.sh that extract-findings.sh also uses.
#
#   The body is untrusted input (rules/security/general.md). It is read as data: no part of it is executed,
#   expanded, or used to build a command, a path, or a program, and no problem message repeats it.
#
# Output (stdout, JSON)
#   { "valid": true, "problems": [] }
#
# Exit codes
#   0  both lines are present and well-formed
#   1  usage error, or the body cannot be read
#   2  the check did not run to its end; nothing is written to stdout
#   3  at least one line is missing or malformed; the problems are in the output
set -euo pipefail

PROG="${0##*/}"
HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

# The header block is parsed by the one parser both this script and extract-findings.sh share.
# shellcheck source=cr-header.sh
source "$HERE/cr-header.sh"

# json_string comes from the one shared definition.
# shellcheck source=json-string.sh
source "$HERE/json-string.sh"

usage() {
  cat >&2 <<'EOF'
Usage: check-cr-header.sh --file <body-file|->
       check-cr-header.sh --self-test

Exit 3 when the `Merge verdict:` or the `Security assessment:` header line is missing or malformed.
EOF
}

NOT_APPLICABLE='not applicable — the diff changes no code'
VERDICT_SHAPE='^(yes|no) — assignment met: (yes|no|no linked issue) · open Critical: ([0-9]+)( · (.+))?$'
ASSESSMENT_SHAPE='^untrusted data: (.+) · public exposure: (.+) · regression test: (.+) · automatic rule: (.+)$'
REGRESSION_SHAPE='^(not required|present — .+|required — .+)$'
ASSESSMENT_LABELS=('untrusted data:' 'public exposure:' 'regression test:' 'automatic rule:')

emit() {
  local first=1 problem

  printf '{\n'
  printf '  "valid": %s,\n' "$([[ $# -eq 0 ]] && printf 'true' || printf 'false')"
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

check_merge_verdict() {
  local value="$1"

  if [[ ! "$value" =~ $VERDICT_SHAPE ]]; then
    printf '%s\n' 'Merge verdict: the line does not read "<yes|no> — assignment met: <yes|no|no linked issue> · open Critical: <n>"'
    return 0
  fi

  local verdict="${BASH_REMATCH[1]}" assignment="${BASH_REMATCH[2]}" critical="${BASH_REMATCH[3]}" blockers="${BASH_REMATCH[5]}"

  if [[ "$verdict" == 'no' && -z "$blockers" ]]; then
    printf '%s\n' 'Merge verdict: a "no" names no blocker after the open Critical count'
  fi
  if [[ "$verdict" == 'yes' && "$assignment" == 'no' ]]; then
    printf '%s\n' 'Merge verdict: a "yes" states that the assignment is not met'
  fi
  if [[ "$verdict" == 'yes' && "$((10#$critical))" -gt 0 ]]; then
    printf '%s\n' 'Merge verdict: a "yes" states an open Critical finding'
  fi
}

check_security_assessment() {
  local value="$1"

  [[ "$value" == "$NOT_APPLICABLE" ]] && return 0

  if [[ ! "$value" =~ $ASSESSMENT_SHAPE ]]; then
    local label missing=0
    for label in "${ASSESSMENT_LABELS[@]}"; do
      if [[ "$value" != *"$label"* ]]; then
        printf 'Security assessment: missing answer %s\n' "$label"
        missing=1
      fi
    done
    if [[ "$missing" -eq 0 ]]; then
      printf '%s\n' 'Security assessment: the four answers are out of order or one is empty'
    fi
    return 0
  fi

  if [[ ! "${BASH_REMATCH[3]}" =~ $REGRESSION_SHAPE ]]; then
    printf '%s\n' 'Security assessment: the regression test answer is not "not required", "present — <test>", or "required — <guarantees>"'
  fi
}

# check_line <label> <checker> — judge every header line parsed by cr_header_parse whose label is <label>.
# The labels are walked with `for … in`, never by index: bash 3.2 walks the whole array on every indexed read,
# so a body with many header lines would take quadratic time. Only a matching line is read by index.
check_line() {
  local label="$1" checker="$2"
  local -a values=()
  local i=0 count=0 name value problem

  # The `+` form keeps an empty array from failing under `set -u` in bash 3.2.
  for name in ${CR_HEADER_LABELS[@]+"${CR_HEADER_LABELS[@]}"}; do
    if [[ "$name" == "$label" ]]; then
      values[count]="${CR_HEADER_VALUES[$i]}"
      count=$((count + 1))
    fi
    i=$((i + 1))
  done

  if [[ "${#values[@]}" -eq 0 ]]; then
    printf '%s: the header line is missing\n' "$label"
    return 0
  fi
  if [[ "${#values[@]}" -gt 1 ]]; then
    printf '%s: the header line appears %s times, not once\n' "$label" "${#values[@]}"
  fi
  # The checker runs in a command substitution, never a process substitution: its exit code is read, so a
  # checker that dies stops this check too.
  local found
  for value in "${values[@]}"; do
    found="$(set -e; "$checker" "$value")"
    while IFS= read -r problem; do
      [[ -z "$problem" ]] || printf '%s\n' "$problem"
    done <<<"$found"
  done
}

check() {
  local file_arg=""

  while [[ $# -gt 0 ]]; do
    case "$1" in
    --file)
      [[ $# -ge 2 ]] || { usage; return 1; }
      file_arg="$2"
      shift 2
      ;;
    *)
      echo "$PROG: unknown argument" >&2
      usage
      return 1
      ;;
    esac
  done

  [[ -n "$file_arg" ]] || { usage; return 1; }

  local body
  if [[ "$file_arg" == "-" ]]; then
    body="$(cat)"
  elif [[ -r "$file_arg" ]]; then
    body="$(cat -- "$file_arg")"
  else
    echo "$PROG: cannot read the comment body" >&2
    return 1
  fi

  local -a problems=()
  local problem found status

  cr_header_parse <<<"$body"
  # The check runs in a subshell with `set -e`, and its exit code is read. A check that dies before its end is a
  # refusal, never an empty list of problems that would read as a valid body.
  set +e
  found="$(
    set -e
    check_line 'Merge verdict' check_merge_verdict
    check_line 'Security assessment' check_security_assessment
  )"
  status=$?
  set -e
  if [[ "$status" -ne 0 ]]; then
    echo "$PROG: the check of the header lines did not run to its end (exit $status)" >&2
    return 2
  fi
  while IFS= read -r problem; do
    [[ -z "$problem" ]] || problems+=("$problem")
  done <<<"$found"

  if [[ "${#problems[@]}" -gt 0 ]]; then
    emit "${problems[@]}"
    return 3
  fi

  emit
  return 0
}

self_test() {
  local failures=0 script tmp
  script="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)/$PROG"
  tmp="$(mktemp -d)"
  # shellcheck disable=SC2064
  trap "rm -rf '$tmp'" EXIT

  local verdict_ok='**Merge verdict:** yes — assignment met: yes · open Critical: 0'
  local assessment_ok='**Security assessment:** untrusted data: none · public exposure: none · regression test: not required · automatic rule: not applicable'

  # Render a comment body from the two lines under test; an empty argument leaves its line out.
  render() {
    printf '**Status:** needs-fix\n**Counts:** Critical 0 · Moderate 0\n'
    [[ -z "$1" ]] || printf '%s\n' "$1"
    printf '**Reuse (DRY):** no duplication found\n'
    [[ -z "$2" ]] || printf '%s\n' "$2"
    printf '**Reviewed revision:** 0123456789abcdef\n\n## TL;DR\n- changed one line\n'
  }

  # Run the script on a body and compare the exit code; a non-empty $4 must also appear in the output.
  scenario() {
    local label="$1" expected="$2" body="$3" needle="${4:-}" actual output
    printf '%s\n' "$body" >"$tmp/body.md"
    set +e
    output="$("$script" --file "$tmp/body.md" 2>/dev/null)"
    actual=$?
    set -e
    if [[ "$actual" -eq "$expected" ]] && { [[ -z "$needle" ]] || grep -qF -- "$needle" <<<"$output"; }; then
      printf 'ok    %-62s exit %s\n' "$label" "$actual"
    else
      printf 'FAIL  %-62s expected exit %s with "%s", got %s\n' "$label" "$expected" "$needle" "$actual" >&2
      failures=$((failures + 1))
    fi
  }

  scenario 'a body with both well-formed lines is valid' 0 "$(render "$verdict_ok" "$assessment_ok")" '"valid": true'
  scenario 'the not-applicable security value is valid' 0 \
    "$(render "$verdict_ok" '**Security assessment:** not applicable — the diff changes no code')"
  scenario 'a no verdict that names its blockers is valid' 0 \
    "$(render '**Merge verdict:** no — assignment met: no linked issue · open Critical: 2 · two open Critical findings' "$assessment_ok")"
  scenario 'a verdict without a linked issue is valid' 0 \
    "$(render '**Merge verdict:** yes — assignment met: no linked issue · open Critical: 0' "$assessment_ok")"
  scenario 'a present regression test answer with its test is valid' 0 \
    "$(render "$verdict_ok" '**Security assessment:** untrusted data: none · public exposure: none · regression test: present — tests/AuthTest.php · automatic rule: none practical')"
  scenario 'a required regression test answer with its guarantee is valid' 0 \
    "$(render "$verdict_ok" '**Security assessment:** untrusted data: new upload path (src/Upload.php:12) · public exposure: none · regression test: required — the size limit · automatic rule: a PHPStan rule')"
  scenario 'lines without the Markdown bold are valid' 0 \
    "$(render 'Merge verdict: yes — assignment met: yes · open Critical: 0' 'Security assessment: not applicable — the diff changes no code')"
  scenario 'a body with Windows line endings is valid' 0 \
    "$(render "$verdict_ok" "$assessment_ok" | sed 's/$/\r/')"
  local injected fence
  injected="\$(touch $tmp/pwned)"
  fence=$'\x60\x60\x60'
  scenario 'instruction-like text in an answer is read as data' 0 \
    "$(render "$verdict_ok" '**Security assessment:** untrusted data: '"$injected"' · public exposure: none · regression test: not required · automatic rule: not applicable')"
  if [[ -e "$tmp/pwned" ]]; then
    printf 'FAIL  %-62s\n' 'an answer was executed' >&2
    failures=$((failures + 1))
  else
    printf 'ok    %-62s\n' 'an answer is never executed'
  fi

  scenario 'a body without the Merge verdict line is refused' 3 "$(render '' "$assessment_ok")" 'Merge verdict: the header line is missing'
  scenario 'a body without the Security assessment line is refused' 3 "$(render "$verdict_ok" '')" 'Security assessment: the header line is missing'
  scenario 'an empty body is refused on both lines' 3 '' 'Security assessment: the header line is missing'
  scenario 'a verdict that is neither yes nor no is refused' 3 \
    "$(render '**Merge verdict:** maybe — assignment met: yes · open Critical: 0' "$assessment_ok")" 'Merge verdict: the line does not read'
  scenario 'a verdict without the open Critical half is refused' 3 \
    "$(render '**Merge verdict:** yes — assignment met: yes' "$assessment_ok")" 'Merge verdict: the line does not read'
  scenario 'a no verdict without a blocker is refused' 3 \
    "$(render '**Merge verdict:** no — assignment met: yes · open Critical: 0' "$assessment_ok")" 'names no blocker'
  scenario 'a yes verdict with an unmet assignment is refused' 3 \
    "$(render '**Merge verdict:** yes — assignment met: no · open Critical: 0' "$assessment_ok")" 'states that the assignment is not met'
  scenario 'a yes verdict with an open Critical is refused' 3 \
    "$(render '**Merge verdict:** yes — assignment met: yes · open Critical: 1' "$assessment_ok")" 'states an open Critical finding'
  scenario 'a security line with a missing answer is refused' 3 \
    "$(render "$verdict_ok" '**Security assessment:** untrusted data: none · public exposure: none · regression test: not required')" \
    'missing answer automatic rule:'
  scenario 'a security line with the answers out of order is refused' 3 \
    "$(render "$verdict_ok" '**Security assessment:** public exposure: none · untrusted data: none · regression test: not required · automatic rule: not applicable')" \
    'out of order or one is empty'
  scenario 'a security line with an empty answer is refused' 3 \
    "$(render "$verdict_ok" '**Security assessment:** untrusted data: · public exposure: none · regression test: not required · automatic rule: not applicable')" \
    'out of order or one is empty'
  scenario 'a regression test answer outside the three values is refused' 3 \
    "$(render "$verdict_ok" '**Security assessment:** untrusted data: none · public exposure: none · regression test: maybe · automatic rule: not applicable')" \
    'the regression test answer is not'
  scenario 'a present regression test answer without its test is refused' 3 \
    "$(render "$verdict_ok" '**Security assessment:** untrusted data: none · public exposure: none · regression test: present · automatic rule: not applicable')" \
    'the regression test answer is not'
  scenario 'a not-applicable value with other wording is refused' 3 \
    "$(render "$verdict_ok" '**Security assessment:** not applicable')" 'missing answer untrusted data:'
  scenario 'a header line written twice is refused' 3 \
    "$(render "$verdict_ok"$'\n'"$verdict_ok" "$assessment_ok")" 'appears 2 times'
  scenario 'a line quoted inside a fenced code block is not read' 3 \
    "$(printf '**Status:** clean\n%stext\n%s\n%s\n%s\n' "$fence" "$verdict_ok" "$assessment_ok" "$fence")" 'Merge verdict: the header line is missing'
  scenario 'a real line beside a quoted one is valid' 0 \
    "$(printf '%stext\n**Merge verdict:** broken\n%s\n%s\n%s\n' "$fence" "$fence" "$verdict_ok" "$assessment_ok")"

  local rc
  render "$verdict_ok" "$assessment_ok" >"$tmp/stdin.md"
  set +e
  "$script" --file - <"$tmp/stdin.md" >/dev/null 2>&1
  rc=$?
  set -e
  if [[ "$rc" -eq 0 ]]; then
    printf 'ok    %-62s exit 0\n' 'a body on standard input is read'
  else
    printf 'FAIL  %-62s expected exit 0, got %s\n' 'a body on standard input is read' "$rc" >&2
    failures=$((failures + 1))
  fi

  usage_error() {
    local label="$1" actual
    shift
    set +e
    "$script" "$@" >/dev/null 2>&1
    actual=$?
    set -e
    if [[ "$actual" -eq 1 ]]; then
      printf 'ok    %-62s exit 1\n' "$label"
    else
      printf 'FAIL  %-62s expected exit 1, got %s\n' "$label" "$actual" >&2
      failures=$((failures + 1))
    fi
  }

  usage_error 'no argument is a usage error'
  usage_error 'an unknown argument is a usage error' --bogus
  usage_error 'a --file without a value is a usage error' --file
  usage_error 'an unreadable body is refused' --file "$tmp/does-not-exist.md"

  # The time grows with the body in a straight line. A body five times longer may take at most eight times as long;
  # a parse that walks its whole array on every header line takes about eleven times as long under bash 3.2.
  # Each body is timed twice and the faster run counts, so one slow run on a busy machine does not fail the case.
  # The second body has values that end with a non-ASCII character, which the parser trims again in the locale.
  many_lines() {
    local i
    render "$verdict_ok" "$assessment_ok"
    for ((i = 0; i < $1; i++)); do
      printf '**Label %s:** value %s\n' "$i" "$2"
    done
  }
  fastest() {
    local first second TIMEFORMAT=%R
    first="$({ time "$script" --file "$1" >/dev/null 2>&1; } 2>&1)"
    second="$({ time "$script" --file "$1" >/dev/null 2>&1; } 2>&1)"
    awk -v a="$first" -v b="$second" 'BEGIN { print (a < b ? a : b) }'
  }
  local short long suffix label
  for suffix in ascii 'é'; do
    many_lines 4000 "$suffix" >"$tmp/short.md"
    many_lines 20000 "$suffix" >"$tmp/long.md"
    short="$(fastest "$tmp/short.md")"
    long="$(fastest "$tmp/long.md")"
    label="a five times longer body takes at most eight times as long ($suffix)"
    if awk -v s="$short" -v l="$long" 'BEGIN { exit !(l <= 8 * (s > 0.01 ? s : 0.01)) }'; then
      printf 'ok    %-62s %ss / %ss\n' "$label" "$short" "$long"
    else
      printf 'FAIL  %-62s %ss / %ss\n' "$label" "$short" "$long" >&2
      failures=$((failures + 1))
    fi
  done

  # A check that dies before its end never reports a valid body: the subshell that runs it is read for its exit code.
  local died
  render "$verdict_ok" "$assessment_ok" >"$tmp/died.md"
  set +e
  died="$(
    # The checker is called by name from check_line, so ShellCheck sees no call
    # (SC2317, and SC2329 in ShellCheck 0.11). Both are suppressed.
    # shellcheck disable=SC2317,SC2329
    check_merge_verdict() { exit 9; }
    check --file "$tmp/died.md" 2>"$tmp/died.err"
  )"
  rc=$?
  set -e
  if [[ "$rc" -eq 2 && -z "$died" ]] && grep -qF 'the check of the header lines did not run to its end' "$tmp/died.err"; then
    printf 'ok    %-62s exit %s\n' 'a check that dies is a refusal, never a valid body' "$rc"
  else
    printf 'FAIL  %-62s expected exit 2, got %s\n' 'a check that dies is a refusal, never a valid body' "$rc" >&2
    failures=$((failures + 1))
  fi

  if [[ "$failures" -gt 0 ]]; then
    echo "check-cr-header self-test: $failures failure(s)" >&2
    return 4
  fi
  echo 'check-cr-header self-test: PASS'
  return 0
}

if [[ "${1:-}" == "--self-test" ]]; then
  self_test
  exit $?
fi

check "$@"
