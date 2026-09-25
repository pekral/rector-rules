#!/usr/bin/env bash
# record-metrics.sh — append one run's operational metrics to the local store.
#
# Why this exists
#   The router now makes decisions — which tier, which model, whether a review
#   runs — and tuning them without measurement is guesswork. One run's routing
#   ledger answers "what did this run do"; it is deleted with the run. This
#   store answers "what do runs do", which is the question a threshold has to be
#   tuned against.
#
#   Concretely it is meant to catch three things a single run cannot show:
#   a STANDARD tier whose reviews never find anything (the tier is too eager),
#   a FAST tier that keeps escalating (it is too eager the other way), and model
#   escalations that rise without failures falling.
#
# PRIVACY — what is never written
#   No source code, no diffs, no prompts, no issue or comment text, no branch or
#   file names, no URLs, no secrets, no customer data. The store holds counts,
#   tiers, and outcomes: operational facts about the run, never its content.
#   The writer enforces this rather than trusting the caller — every field below
#   is validated against a fixed shape, and an unknown field is refused.
#
# Usage
#   record-metrics.sh --initial-tier <t> --final-tier <t> --status <s>
#                     [--agent-dispatches <n>] [--escalated-dispatches <n>]
#                     [--review-rounds <n>] [--critical <n>] [--moderate <n>]
#                     [--input-tokens <n>] [--output-tokens <n>] [--cache-read-tokens <n>]
#                     [--store <path>]
#   record-metrics.sh --self-test
#
#   Token counts are optional by design: no runtime here reports them reliably,
#   and a fabricated number is worse than an absent one.
#
#   The default store is `${AI_OLYMPUS_HOME:-$HOME/.ai-olympus}/metrics.jsonl`,
#   outside any repository, so a project can never commit it by accident.
#
# Exit codes
#   0  the entry was appended
#   1  usage error, or a value that failed validation
set -euo pipefail

PROG="${0##*/}"

usage() {
  cat >&2 <<'EOF'
Usage: record-metrics.sh --initial-tier <t> --final-tier <t> --status <s> [counters]
       record-metrics.sh --self-test

Appends one JSON line of operational metrics. Never writes source, diffs,
prompts, issue text, or URLs.
EOF
}

is_tier() {
  case "$1" in
  FAST | STANDARD | CRITICAL) return 0 ;;
  *) return 1 ;;
  esac
}

is_status() {
  case "$1" in
  success | blocked | failed) return 0 ;;
  *) return 1 ;;
  esac
}

is_count() {
  [[ "$1" =~ ^[0-9]{1,12}$ ]]
}

record() {
  local initial="" final="" status=""
  local dispatches=0 escalated=0 rounds=0 critical=0 moderate=0
  local input_tokens="" output_tokens="" cache_tokens=""
  local store="${AI_OLYMPUS_HOME:-$HOME/.ai-olympus}/metrics.jsonl"

  while [[ $# -gt 0 ]]; do
    local flag="$1" value="${2:-}"
    case "$flag" in
    --initial-tier | --final-tier | --status | --store)
      [[ $# -ge 2 ]] || { usage; return 1; }
      case "$flag" in
      --initial-tier) initial="$value" ;;
      --final-tier) final="$value" ;;
      --status) status="$value" ;;
      --store) store="$value" ;;
      esac
      shift 2
      ;;
    --agent-dispatches | --escalated-dispatches | --review-rounds | --critical | --moderate | --input-tokens | --output-tokens | --cache-read-tokens)
      [[ $# -ge 2 ]] || { usage; return 1; }
      if ! is_count "$value"; then
        echo "$PROG: $flag takes a non-negative integer" >&2
        return 1
      fi
      case "$flag" in
      --agent-dispatches) dispatches="$value" ;;
      --escalated-dispatches) escalated="$value" ;;
      --review-rounds) rounds="$value" ;;
      --critical) critical="$value" ;;
      --moderate) moderate="$value" ;;
      --input-tokens) input_tokens="$value" ;;
      --output-tokens) output_tokens="$value" ;;
      --cache-read-tokens) cache_tokens="$value" ;;
      esac
      shift 2
      ;;
    *)
      echo "$PROG: unknown argument: $(printf '%s' "$flag" | LC_ALL=C tr -cd '[:print:]' | cut -c1-60)" >&2
      usage
      return 1
      ;;
    esac
  done

  if ! is_tier "$initial" || ! is_tier "$final"; then
    echo "$PROG: --initial-tier and --final-tier must be FAST, STANDARD, or CRITICAL" >&2
    return 1
  fi

  if ! is_status "$status"; then
    echo "$PROG: --status must be success, blocked, or failed" >&2
    return 1
  fi

  mkdir -p -- "$(dirname -- "$store")"

  # One line, appended. A JSONL store needs no read-modify-write, so two runs
  # finishing at once cannot lose each other's entry.
  {
    printf '{"timestamp":"%s"' "$(date -u +%Y-%m-%dT%H:%M:%SZ)"
    printf ',"initial_tier":"%s","final_tier":"%s","status":"%s"' "$initial" "$final" "$status"
    printf ',"agent_dispatches":%s,"escalated_dispatches":%s,"review_rounds":%s' "$dispatches" "$escalated" "$rounds"
    printf ',"findings":{"critical":%s,"moderate":%s}' "$critical" "$moderate"
    [[ -n "$input_tokens" ]] && printf ',"input_tokens":%s' "$input_tokens"
    [[ -n "$output_tokens" ]] && printf ',"output_tokens":%s' "$output_tokens"
    [[ -n "$cache_tokens" ]] && printf ',"cache_read_tokens":%s' "$cache_tokens"
    printf '}\n'
  } >>"$store"

  printf '%s\n' "$store"
  return 0
}

self_test() {
  local failures=0 script tmp
  script="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)/$PROG"
  tmp="$(mktemp -d)"
  # shellcheck disable=SC2064
  trap "rm -rf '$tmp'" EXIT
  local store="$tmp/metrics.jsonl"

  expect_exit() {
    local label="$1" expected="$2"
    shift 2
    local actual
    set +e
    "$script" "$@" --store "$store" >/dev/null 2>&1
    actual=$?
    set -e
    if [[ "$actual" -eq "$expected" ]]; then
      printf 'ok    %-54s exit %s\n' "$label" "$actual"
    else
      printf 'FAIL  %-54s expected exit %s, got %s\n' "$label" "$expected" "$actual" >&2
      failures=$((failures + 1))
    fi
  }

  expect_exit 'a valid entry is appended' 0 \
    --initial-tier FAST --final-tier FAST --status success --agent-dispatches 1
  expect_exit 'an escalated run is appended' 0 \
    --initial-tier FAST --final-tier CRITICAL --status success \
    --agent-dispatches 3 --escalated-dispatches 2 --review-rounds 1 --critical 1 --moderate 2

  expect_exit 'an unknown tier is refused' 1 --initial-tier HOT --final-tier FAST --status success
  expect_exit 'an unknown status is refused' 1 --initial-tier FAST --final-tier FAST --status vibes
  expect_exit 'a non-numeric counter is refused' 1 \
    --initial-tier FAST --final-tier FAST --status success --agent-dispatches many
  expect_exit 'an unknown flag is refused' 1 \
    --initial-tier FAST --final-tier FAST --status success --branch feature/secret

  # Every line must parse, and the store must hold exactly the two valid entries.
  local lines
  lines="$(wc -l <"$store" | tr -d ' ')"
  if [[ "$lines" == "2" ]]; then
    printf 'ok    %-54s %s entries\n' 'only valid entries reach the store' "$lines"
  else
    printf 'FAIL  %-54s expected 2 entries, got %s\n' 'only valid entries reach the store' "$lines" >&2
    failures=$((failures + 1))
  fi

  if jq -e . "$store" >/dev/null 2>&1; then
    printf 'ok    %-54s\n' 'every stored line is valid JSON'
  else
    printf 'FAIL  %-54s a stored line does not parse\n' 'every stored line is valid JSON' >&2
    failures=$((failures + 1))
  fi

  # The privacy contract, asserted rather than asserted-in-prose: the store may
  # not carry anything that could identify the work.
  if grep -qiE 'branch|diff|prompt|http|/[a-z]+\.php' "$store"; then
    printf 'FAIL  %-54s the store carries content, not just counts\n' 'no task content is persisted' >&2
    failures=$((failures + 1))
  else
    printf 'ok    %-54s\n' 'no task content is persisted'
  fi

  # Token fields are optional: the first entry carries none and still parses.
  if jq -e 'select(.input_tokens == null)' <(head -1 "$store") >/dev/null 2>&1; then
    printf 'ok    %-54s\n' 'token fields are optional'
  else
    printf 'FAIL  %-54s\n' 'token fields are optional' >&2
    failures=$((failures + 1))
  fi

  if [[ "$failures" -gt 0 ]]; then
    echo "record-metrics self-test: $failures failure(s)" >&2
    return 4
  fi
  echo 'record-metrics self-test: PASS'
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

record "$@"
