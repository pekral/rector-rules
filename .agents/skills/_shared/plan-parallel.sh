#!/usr/bin/env bash
# plan-parallel.sh — group the units of one request into batches, so that two units
# run at the same time only when nothing can make them collide.
#
# Why this exists
#   `splinter` used to process several sources strictly one after another. That is
#   always safe, and it leaves the machine idle between slow steps. Running two
#   units at once is safe only when their work cannot touch the same files, one
#   does not wait for the other, and neither is a risky change. Those are three
#   facts, so a script decides them. The orchestrator reads the batches and does
#   not judge by itself which units may overlap.
#
# Usage
#   plan-parallel.sh < units
#   plan-parallel.sh --self-test
#
#   One unit per line, in the order they must run (dependencies first):
#     <id>|<tier>|<depends-on>|<files>
#   <id>         a source slug, matching ^[A-Za-z0-9._-]{1,64}$
#   <tier>       the unit's `classify-risk.sh` verdict: FAST, STANDARD, or CRITICAL
#   <depends-on> comma-separated ids this unit waits for; empty for none. An id that
#                is not in this input is a prerequisite that already finished.
#   <files>      the files the unit is predicted to change, separated by spaces,
#                from the analysis or the blast radius. An entry ending in `/` is a
#                directory and covers every path below it; an entry without the
#                slash covers them too when the other entry lies below it. A
#                non-canonical spelling (`./x`, `a//b`, `a/./b`) is refused.
#                Empty means no evidence.
#   A line starting with `#` and a blank line are skipped.
#
# Rule
#   A unit joins the current batch only when all of these hold; otherwise it starts
#   the next batch. Batches run one after another, and a batch of two units runs
#   its two units at the same time.
#     1. The batch holds fewer than 2 units (the fixed concurrency limit).
#     2. Neither the unit nor any unit in the batch is CRITICAL.
#     3. The unit and every unit in the batch list files, and the two file sets
#        are disjoint. A unit without file evidence never runs beside another.
#     4. The unit does not depend on a unit in the batch.
#   A unit never moves ahead of an earlier unit, so the dependency order holds.
#
# Output (stdout, key=value)
#   max_concurrent=2
#   batches=<n>
#   batch.<k>=<id>[,<id>]        the units of batch k
#   mode.<k>=parallel|sequential parallel when batch k holds two units
#   reason.<id>=<why>            only for a unit that started a new batch because
#                                it could not join the previous one:
#                                critical:<id> | no-file-evidence:<id> |
#                                depends-on:<id> | files-overlap:<id>:<path> (the
#                                path is the later unit's own entry) |
#                                batch-full
#
# Exit codes
#   0  a plan was produced
#   1  usage error or malformed input
set -euo pipefail

PROG="${0##*/}"
MAX_CONCURRENT=2

usage() {
  cat >&2 <<'USAGE'
Usage: plan-parallel.sh < units     one "<id>|<tier>|<depends-on>|<files>" per line
       plan-parallel.sh --self-test
USAGE
}

die() {
  echo "$PROG: $1" >&2
  exit 1
}

IDS=()
TIERS=()
DEPS=()
FILES=()

# Two file entries collide when they are equal, or when one is a directory that
# contains the other. An entry names a directory with a trailing slash, and an
# entry without one counts as a directory too when the other entry lies below it
# (`src` against `src/A.php`), so the caller's spelling never decides.
paths_collide() {
  local a="${1%/}" b="${2%/}"
  [[ "$a" == "$b" ]] && return 0
  [[ "$b" == "$a"/* ]] && return 0
  [[ "$a" == "$b"/* ]] && return 0
  return 1
}

# Print the first colliding path between two units, or return 1.
first_collision() {
  local left="$1" right="$2" a b
  for a in $left; do
    for b in $right; do
      if paths_collide "$a" "$b"; then
        printf '%s' "$a"
        return 0
      fi
    done
  done
  return 1
}

has_dependency() {
  local unit_deps="$1" other="$2" dep
  local IFS=','
  for dep in $unit_deps; do
    [[ "$dep" == "$other" ]] && return 0
  done
  return 1
}

read_units() {
  local line id tier deps files index seen dep file extra
  while IFS= read -r line || [[ -n "$line" ]]; do
    [[ -z "${line//[[:space:]]/}" || "$line" == '#'* ]] && continue
    IFS='|' read -r id tier deps files extra <<<"$line"
    [[ -z "$extra" ]] || die "a unit has more than four fields: $line"
    [[ "$id" =~ ^[A-Za-z0-9._-]{1,64}$ ]] || die "invalid unit id: $id"
    case "$tier" in
    FAST | STANDARD | CRITICAL) ;;
    *) die "invalid tier for $id: $tier" ;;
    esac
    for seen in ${IDS[@]+"${IDS[@]}"}; do
      [[ "$seen" != "$id" ]] || die "duplicate unit id: $id"
    done
    deps="${deps//[[:space:]]/}"
    local IFS=','
    for dep in $deps; do
      [[ "$dep" =~ ^[A-Za-z0-9._-]{1,64}$ ]] || die "invalid dependency of $id: $dep"
    done
    unset IFS
    for file in $files; do
      [[ "$file" =~ ^[A-Za-z0-9._@+/-]+$ && "$file" != /* && "$file" != *..* ]] || die "invalid file entry of $id: $file"
      # A second spelling of one path must not decide the plan: refuse it.
      [[ "$file" != ./* && "$file" != */. && "$file" != . && "$file" != *//* && "$file" != */./* ]] || die "non-canonical file entry of $id: $file"
    done
    IDS+=("$id")
    TIERS+=("$tier")
    DEPS+=("$deps")
    FILES+=("$files")
  done

  [[ "${#IDS[@]}" -gt 0 ]] || die 'no unit given'

  # A dependency on a later unit means the input order is wrong.
  for index in "${!IDS[@]}"; do
    local later
    for ((later = index + 1; later < ${#IDS[@]}; later++)); do
      if has_dependency "${DEPS[$index]}" "${IDS[$later]}"; then
        die "${IDS[$index]} depends on ${IDS[$later]}, which comes later — list dependencies first"
      fi
    done
  done
}

plan() {
  local batches=0 index member reason collision
  local -a batch_members=() batch_reason=()
  local -a current=()

  for index in "${!IDS[@]}"; do
    reason=''
    if [[ "${#current[@]}" -gt 0 ]]; then
      if [[ "${#current[@]}" -ge "$MAX_CONCURRENT" ]]; then
        reason='batch-full'
      fi
      for member in ${current[@]+"${current[@]}"}; do
        [[ -z "$reason" ]] || break
        if [[ "${TIERS[$index]}" == CRITICAL ]]; then
          reason="critical:${IDS[$index]}"
        elif [[ "${TIERS[$member]}" == CRITICAL ]]; then
          reason="critical:${IDS[$member]}"
        elif [[ -z "${FILES[$index]}" ]]; then
          reason="no-file-evidence:${IDS[$index]}"
        elif [[ -z "${FILES[$member]}" ]]; then
          reason="no-file-evidence:${IDS[$member]}"
        elif has_dependency "${DEPS[$index]}" "${IDS[$member]}"; then
          reason="depends-on:${IDS[$member]}"
        elif collision="$(first_collision "${FILES[$index]}" "${FILES[$member]}")"; then
          reason="files-overlap:${IDS[$member]}:$collision"
        fi
      done
    fi

    if [[ "${#current[@]}" -gt 0 && -z "$reason" ]]; then
      current+=("$index")
    else
      if [[ "${#current[@]}" -gt 0 ]]; then
        batch_members+=("${current[*]}")
      fi
      [[ -z "$reason" ]] || batch_reason[${#batch_members[@]}]="${IDS[$index]}=$reason"
      current=("$index")
    fi
  done
  batch_members+=("${current[*]}")
  batches="${#batch_members[@]}"

  printf 'max_concurrent=%s\n' "$MAX_CONCURRENT"
  printf 'batches=%s\n' "$batches"
  local position members names mode
  for ((position = 0; position < batches; position++)); do
    names=''
    mode=sequential
    # shellcheck disable=SC2206
    members=(${batch_members[$position]})
    for member in "${members[@]}"; do
      names+="${names:+,}${IDS[$member]}"
    done
    [[ "${#members[@]}" -ge 2 ]] && mode=parallel
    printf 'batch.%s=%s\n' "$((position + 1))" "$names"
    printf 'mode.%s=%s\n' "$((position + 1))" "$mode"
    if [[ -n "${batch_reason[$position]:-}" ]]; then
      printf 'reason.%s\n' "${batch_reason[$position]}"
    fi
  done
}

SELF_TEST_FAILURES=0

expect_plan() {
  local label="$1" input="$2" expected="$3" actual
  actual="$(printf '%s\n' "$input" | "$0" 2>&1 | tr '\n' ' ')" || true
  if [[ "$actual" == "$expected" ]]; then
    printf 'ok    %s\n' "$label"
  else
    printf 'FAIL  %s\n        expected: %s\n        actual:   %s\n' "$label" "$expected" "$actual" >&2
    SELF_TEST_FAILURES=$((SELF_TEST_FAILURES + 1))
  fi
}

expect_refusal() {
  local label="$1" input="$2" code=0
  printf '%s\n' "$input" | "$0" >/dev/null 2>&1 || code=$?
  if [[ "$code" -eq 1 ]]; then
    printf 'ok    %s\n' "$label"
  else
    printf 'FAIL  %s (exit %s)\n' "$label" "$code" >&2
    SELF_TEST_FAILURES=$((SELF_TEST_FAILURES + 1))
  fi
}

self_test() {
  local head='max_concurrent=2 '

  expect_plan 'one unit is one sequential batch' \
    'a|STANDARD||src/A.php' \
    "${head}batches=1 batch.1=a mode.1=sequential "

  expect_plan 'two units with disjoint files run in parallel' \
    $'a|STANDARD||src/A.php\nb|FAST||src/B.php docs/b.md' \
    "${head}batches=1 batch.1=a,b mode.1=parallel "

  expect_plan 'two units that change the same file run one after the other' \
    $'a|STANDARD||src/A.php CHANGELOG.md\nb|STANDARD||src/B.php CHANGELOG.md' \
    "${head}batches=2 batch.1=a mode.1=sequential batch.2=b mode.2=sequential reason.b=files-overlap:a:CHANGELOG.md "

  expect_plan 'a directory entry covers every file below it' \
    $'a|STANDARD||src/Actions/\nb|STANDARD||src/Actions/Make.php' \
    "${head}batches=2 batch.1=a mode.1=sequential batch.2=b mode.2=sequential reason.b=files-overlap:a:src/Actions/Make.php "

  expect_plan 'a directory entry without the trailing slash covers every file below it' \
    $'a|STANDARD||src\nb|STANDARD||src/A.php' \
    "${head}batches=2 batch.1=a mode.1=sequential batch.2=b mode.2=sequential reason.b=files-overlap:a:src/A.php "

  expect_plan 'a file below a directory entry without the trailing slash is a collision from the other side' \
    $'a|STANDARD||src/A.php\nb|STANDARD||src' \
    "${head}batches=2 batch.1=a mode.1=sequential batch.2=b mode.2=sequential reason.b=files-overlap:a:src "

  expect_plan 'a sibling path with a common prefix is not a collision' \
    $'a|STANDARD||src/Action/\nb|STANDARD||src/ActionBar.php' \
    "${head}batches=1 batch.1=a,b mode.1=parallel "

  expect_plan 'a dependency keeps the dependent in a later batch' \
    $'a|STANDARD||src/A.php\nb|STANDARD|a|src/B.php' \
    "${head}batches=2 batch.1=a mode.1=sequential batch.2=b mode.2=sequential reason.b=depends-on:a "

  expect_plan 'a dependency on a unit outside the request is already done' \
    $'a|STANDARD|old-issue|src/A.php\nb|STANDARD||src/B.php' \
    "${head}batches=1 batch.1=a,b mode.1=parallel "

  expect_plan 'a CRITICAL unit never runs beside another unit' \
    $'a|CRITICAL||src/A.php\nb|FAST||docs/b.md' \
    "${head}batches=2 batch.1=a mode.1=sequential batch.2=b mode.2=sequential reason.b=critical:a "

  expect_plan 'a CRITICAL unit that follows a free unit starts its own batch' \
    $'a|FAST||docs/a.md\nb|CRITICAL||src/B.php' \
    "${head}batches=2 batch.1=a mode.1=sequential batch.2=b mode.2=sequential reason.b=critical:b "

  expect_plan 'a unit without file evidence never runs beside another unit' \
    $'a|STANDARD||src/A.php\nb|STANDARD||' \
    "${head}batches=2 batch.1=a mode.1=sequential batch.2=b mode.2=sequential reason.b=no-file-evidence:b "

  expect_plan 'at most two units run at the same time' \
    $'a|FAST||a.md\nb|FAST||b.md\nc|FAST||c.md\nd|FAST||d.md\ne|FAST||e.md' \
    "${head}batches=3 batch.1=a,b mode.1=parallel batch.2=c,d mode.2=parallel reason.c=batch-full batch.3=e mode.3=sequential reason.e=batch-full "

  expect_plan 'a unit never moves ahead of an earlier unit' \
    $'a|STANDARD||src/A.php\nb|STANDARD||src/A.php\nc|STANDARD||src/C.php' \
    "${head}batches=2 batch.1=a mode.1=sequential batch.2=b,c mode.2=parallel reason.b=files-overlap:a:src/A.php "

  expect_plan 'comments and blank lines are skipped' \
    $'# a comment\n\na|FAST||a.md\nb|FAST||b.md' \
    "${head}batches=1 batch.1=a,b mode.1=parallel "

  expect_refusal 'an unknown tier is refused' 'a|HUGE||a.md'
  expect_refusal 'an id with a path separator is refused' '../a|FAST||a.md'
  expect_refusal 'a duplicate id is refused' $'a|FAST||a.md\na|FAST||b.md'
  expect_refusal 'a dependency on a later unit is refused' $'a|FAST|b|a.md\nb|FAST||b.md'
  expect_refusal 'a file entry that climbs out of the project is refused' 'a|FAST||../x.md'
  expect_refusal 'an absolute file entry is refused' 'a|FAST||/etc/passwd'
  expect_refusal 'a file entry with a leading dot segment is refused' 'a|FAST||./src/A.php'
  expect_refusal 'a file entry with a doubled slash is refused' 'a|FAST||src//A.php'
  expect_refusal 'a file entry with an inner dot segment is refused' 'a|FAST||src/./A.php'
  expect_refusal 'a unit with five fields is refused' 'a|FAST||a.md|extra'
  expect_refusal 'empty input is refused' ''

  if [[ "$SELF_TEST_FAILURES" -gt 0 ]]; then
    echo "plan-parallel self-test: $SELF_TEST_FAILURES failure(s)" >&2
    return 1
  fi
  echo 'plan-parallel self-test: PASS'
}

if [[ "${1:-}" == '--self-test' ]]; then
  self_test
  exit $?
fi

if [[ $# -gt 0 ]]; then
  usage
  exit 1
fi

read_units
plan
