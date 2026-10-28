#!/usr/bin/env bash
# cr-header.sh — the one parser of the header block of a code-review comment.
#
# Why this exists
#   Two scripts read the header block of a code-review comment: check-cr-header.sh (the publication check)
#   and extract-findings.sh (the finding records and --header). Each had its own parser, so the two could
#   disagree about what a header line is. This file is the only place that decides it. Both scripts source
#   it; neither parses a header line itself.
#
# Usage
#   source cr-header.sh        # then: cr_header_parse < body
#   cr-header.sh --self-test
#
# What it reads
#   A header line is `**<Label>:** <value>`, or the same line without the Markdown bold. A line inside a
#   fenced code block is a quotation and is not read. The header block is the lines before the first `## `
#   heading, without the lines of a finding: a finding heading (`### Critical 1. <title>`) opens a finding, and
#   another `###`–`######` heading or a `---` line closes it. The parser reports a header line wherever it stands
#   in the body and marks the ones that stand in the block. A byte that is not valid UTF-8 in a value does not
#   hide its line. It does not judge a label, a value, a duplicate, or a place: the caller decides.
#
#   The body is untrusted input (rules/security/general.md). It is read as data: no part of it is executed,
#   expanded, or used to build a command, a path, or a program.
#
# Result of cr_header_parse (parallel arrays, one entry per header line, in document order)
#   CR_HEADER_LABELS  the label as written, without the colon and the bold
#   CR_HEADER_BOLD    1 when the line carries the bold on both sides of the label, otherwise 0
#   CR_HEADER_BLOCK   1 when the line stands in the header block (before the first `## ` heading and outside a
#                     finding), otherwise 0
#   CR_HEADER_VALUES  the value, without the leading and the trailing whitespace
#
# Needs bash only; it uses no other tool, so a caller that runs without jq can use it.

CR_HEADER_LABELS=()
CR_HEADER_BOLD=()
CR_HEADER_BLOCK=()
CR_HEADER_VALUES=()

# cr_header_parse — read a comment body on standard input and fill the four arrays above.
cr_header_parse() {
  local i value retrim=0
  local -a trimmed=()

  CR_HEADER_LABELS=()
  CR_HEADER_BOLD=()
  CR_HEADER_BLOCK=()
  CR_HEADER_VALUES=()

  cr_header_scan

  # The scan trims ASCII whitespace only. When a value still starts or ends with a non-ASCII byte, every value is
  # trimmed again in the caller's locale, so a non-ASCII space the locale counts as whitespace is dropped as before.
  # The values are walked with `for … in` and written to a new array, never read by index: bash 3.2 walks the whole
  # array on every indexed read. The trim leaves a value that starts and ends with an ASCII character as it is.
  [[ "$retrim" -eq 1 ]] || return 0
  i=0
  for value in "${CR_HEADER_VALUES[@]}"; do
    value="${value#"${value%%[![:space:]]*}"}"
    trimmed[i]="${value%"${value##*[![:space:]]}"}"
    i=$((i + 1))
  done
  CR_HEADER_VALUES=("${trimmed[@]}")
}

# cr_header_scan — the body is read in the C locale, byte by byte. Under a UTF-8 locale a line that carries a byte
# which is not valid UTF-8 matches no pattern at all, so its header line would be lost; the C locale also makes
# every match cheaper. Bash restores the caller's locale when the function returns. A Markdown heading and a fence
# take ASCII whitespace only, as CommonMark defines them. The four arrays and `retrim` belong to the caller.
cr_header_scan() {
  local LC_ALL=C
  local line value count=0 in_fence=0 in_block=1 in_finding=0 shape='^(\*\*)?([^*:]+):(\*\*)?[[:space:]]*(.*)$'
  local finding='^#{3,6}[[:space:]]+([^[:space:]]+[[:space:]]+)?(Critical|Moderate)[[:space:]]+[0-9]+\.'
  local high=$'[\x80-\xff]'

  while IFS= read -r line || [[ -n "$line" ]]; do
    line="${line%$'\r'}"
    # Each regular expression runs only on a line that can match it: a glob test is cheaper.
    if [[ ( "$line" == *'```'* || "$line" == *'~~~'* ) && "$line" =~ ^[[:space:]]*(\`\`\`|~~~) ]]; then
      in_fence=$((1 - in_fence))
      continue
    fi
    [[ "$in_fence" -eq 0 ]] || continue
    if [[ "$line" == '#'* ]]; then
      if [[ "$line" =~ ^##[[:space:]] ]]; then
        in_block=0
        continue
      fi
      # A finding heading (`### Critical 1. <title>`) opens a finding; another deeper heading closes it, and so does
      # a `---` line. A header line inside a finding is not in the header block, as in extract-findings.sh.
      if [[ "$line" =~ $finding ]]; then
        in_finding=1
      elif [[ "$line" =~ ^#{3,6}[[:space:]] ]]; then
        in_finding=0
      fi
    elif [[ "$line" == '---'* && "$line" =~ ^---[[:space:]]*$ ]]; then
      in_finding=0
    fi
    if [[ "$line" == *:* && "$line" =~ $shape ]]; then
      value="${BASH_REMATCH[4]}"
      value="${value%"${value##*[![:space:]]}"}"
      # An entry is written at its index, never appended with +=: bash 3.2 walks the whole array on every
      # append, so a body with many header lines would take quadratic time.
      CR_HEADER_LABELS[count]="${BASH_REMATCH[2]}"
      if [[ -n "${BASH_REMATCH[1]}" && -n "${BASH_REMATCH[3]}" ]]; then
        CR_HEADER_BOLD[count]=1
      else
        CR_HEADER_BOLD[count]=0
      fi
      CR_HEADER_BLOCK[count]=$((in_block && !in_finding))
      CR_HEADER_VALUES[count]="$value"
      if [[ "$value" == $high* || "$value" == *$high ]]; then
        retrim=1
      fi
      count=$((count + 1))
    fi
  done
}

cr_header_self_test() {
  local failures=0 fence tmp
  fence=$'\x60\x60\x60'
  tmp="$(mktemp -d)"
  # shellcheck disable=SC2064
  trap "rm -rf '$tmp'" EXIT

  # expect <label> <expected> <body> — the arrays, flattened to `label|bold|block|value` lines, must equal <expected>.
  expect() {
    local label="$1" expected="$2" body="$3" actual="" i
    cr_header_parse <<<"$body"
    for ((i = 0; i < ${#CR_HEADER_LABELS[@]}; i++)); do
      actual+="${CR_HEADER_LABELS[$i]}|${CR_HEADER_BOLD[$i]}|${CR_HEADER_BLOCK[$i]}|${CR_HEADER_VALUES[$i]}"$'\n'
    done
    if [[ "$actual" == "$expected" ]]; then
      printf 'ok    %s\n' "$label"
    else
      printf 'FAIL  %s: expected "%s", got "%s"\n' "$label" "$expected" "$actual" >&2
      failures=$((failures + 1))
    fi
  }

  expect 'a bold header line is read with its label, its bold, and its value' $'Status|1|1|needs-fix\n' '**Status:** needs-fix'
  expect 'a line without the bold is read, and is marked as not bold' $'Status|0|1|needs-fix\n' 'Status: needs-fix'
  expect 'a bold on one side only is not a full bold' $'Status|0|1|needs-fix\n' '**Status: needs-fix'
  expect 'a value with colons keeps them and loses the whitespace around it' $'Last updated|1|1|2026-10-01T10:00:00Z\n' $'**Last updated:**   2026-10-01T10:00:00Z \t'
  expect 'a repeated header line is reported every time' $'Status|1|1|a\nStatus|1|1|b\n' $'**Status:** a\n**Status:** b'
  expect 'the lines come out in document order' $'Counts|1|1|x\nStatus|1|1|y\n' $'**Counts:** x\n**Status:** y'
  expect 'a line without a colon is not a header line' '' $'just some prose\n# Code Review'
  expect 'an empty value is a header line with an empty value' $'Status|1|1|\n' '**Status:**'
  expect 'a trailing carriage return is dropped' $'Status|1|1|clean\n' $'**Status:** clean\r'
  expect 'a line inside a fenced code block is not read' $'After|1|1|y\n' "$(printf '%stext\n**Before:** x\n%s\n**After:** y\n' "$fence" "$fence")"
  expect 'a tilde fence is a fence too' $'After|1|1|y\n' "$(printf '~~~\n**Before:** x\n~~~\n**After:** y\n')"
  expect 'a line after the first section heading is reported outside the header block' $'Status|1|1|a\nLate|1|0|b\n' $'**Status:** a\n## TL;DR\n**Late:** b'
  expect 'a heading of a deeper level does not end the header block' $'Status|1|1|a\nLate|1|1|b\n' $'**Status:** a\n### Sub\n**Late:** b'
  expect 'a section heading inside a fence does not end the header block' $'Status|1|1|a\nLate|1|1|b\n' "$(printf '**Status:** a\n%s\n## quoted\n%s\n**Late:** b\n' "$fence" "$fence")"
  expect 'an empty body has no header line' '' ''
  expect 'a header line inside a finding is outside the header block' $'Status|1|1|a\nLate|1|0|b\n' $'**Status:** a\n### 🔴 Critical 1. A title\n**Late:** b'
  expect 'a finding heading without the icon opens a finding too' $'Status|1|1|a\nLate|1|0|b\n' $'**Status:** a\n#### Moderate 2. A title\n**Late:** b'
  expect 'a rule line closes the finding, and the header block goes on' $'Status|1|1|a\nIn|1|0|b\nAfter|1|1|c\n' \
    $'**Status:** a\n### Critical 1. T\n**In:** b\n---\n**After:** c'
  expect 'a deeper heading closes the finding, and the header block goes on' $'Status|1|1|a\nIn|1|0|b\nAfter|1|1|c\n' \
    $'**Status:** a\n### Critical 1. T\n**In:** b\n### Notes\n**After:** c'
  expect 'a section heading ends the header block after a closed finding too' $'In|1|0|b\nLate|1|0|c\n' \
    $'### Critical 1. T\n**In:** b\n---\n## TL;DR\n**Late:** c'
  expect 'a heading that only names a severity does not end the header block' $'Status|1|1|a\nLate|1|1|b\n' $'**Status:** a\n### Critical findings\n**Late:** b'

  # The two cases below need a UTF-8 locale: under it, a regular expression matches nothing on a line that carries
  # a byte which is not valid UTF-8. A system without a UTF-8 locale has no such failure to test.
  local utf8='' candidate
  for candidate in C.UTF-8 C.utf8 en_US.UTF-8 en_US.utf8; do
    if (LC_ALL="$candidate" && [[ $'\xc3\xa9' == ? ]]) 2>/dev/null; then
      utf8="$candidate"
      break
    fi
  done
  # expect_utf8 <label> <expected> <body> — expect, run under the UTF-8 locale.
  expect_utf8() {
    local LC_ALL="$utf8"
    expect "$@"
  }
  if [[ -n "$utf8" ]]; then
    expect_utf8 'a value with a byte that is not valid UTF-8 is read' $'Status|1|1|a\xffb\nCounts|1|1|c\n' \
      $'**Status:** a\xffb \n**Counts:** c'
    expect_utf8 'a non-ASCII space the locale counts as whitespace is trimmed' $'Status|1|1|a\n' $'**Status:**\xe2\x80\x83a\xe2\x80\x83'
  else
    printf 'skip  %s\n' 'no UTF-8 locale: the cases for a byte that is not valid UTF-8'
  fi

  local injected="\$(touch $tmp/pwned)"
  expect 'instruction-like text in a value is read as data' "Status|1|1|$injected"$'\n' "**Status:** $injected"
  if [[ -e "$tmp/pwned" ]]; then
    printf 'FAIL  %s\n' 'a value was executed' >&2
    failures=$((failures + 1))
  else
    printf 'ok    %s\n' 'a value is never executed'
  fi

  if [[ "$failures" -gt 0 ]]; then
    echo "cr-header self-test: $failures failure(s)" >&2
    return 4
  fi
  echo 'cr-header self-test: PASS'
  return 0
}

if [[ "${BASH_SOURCE[0]}" == "$0" ]]; then
  set -euo pipefail
  if [[ "${1:-}" == "--self-test" ]]; then
    cr_header_self_test
    exit $?
  fi
  echo 'Usage: cr-header.sh --self-test (the file is meant to be sourced)' >&2
  exit 1
fi
