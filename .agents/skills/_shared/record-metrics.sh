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
#                     [--context-gate-executed <n>] [--context-requested <n>] [--context-skipped <n>]
#                     [--sources-searched <n>] [--items-returned <n>] [--estimated-tokens-returned <n>]
#                     [--items-inspected <n>] [--context-cache-hits <n>] [--context-cache-misses <n>]
#                     [--retrieval-seconds <n>]
#                     [--graph-hits <n>] [--graph-misses <n>] [--items-from-graph <n>]
#                     [--items-from-search <n>] [--files-avoided <n>]
#                     [--gate-record <path>]... [--review-state <path>] [--store <path>]
#   record-metrics.sh --self-test
#
#   Token counts are optional by design: no runtime here reports them reliably,
#   and a fabricated number is worse than an absent one.
#
#   The --context-* counters, --sources-searched, --items-returned, and
#   --estimated-tokens-returned come from the run's `gate-context.sh` verdicts:
#   how often the gate ran, how often it asked for context or skipped it, and
#   what the retrieval it allowed actually returned. They measure the context
#   the gate saved.
#
#   --items-inspected, --context-cache-hits, --context-cache-misses, and
#   --retrieval-seconds come from the Context Packages `pack-context.sh` wrote:
#   how many candidates the retriever ranked, how often a cached package was
#   reused or rebuilt, and how long retrieval took. They measure how well the
#   retrieval worked.
#
#   --graph-hits, --graph-misses, --items-from-graph, --items-from-search, and
#   --files-avoided come from the `graph` fields of the same packages
#   (`metadata.graph`, and the summary line `pack-context.sh` printed): how often
#   the repository graph knew a task symbol, how often it did not, how many
#   returned items the graph named versus only search found, and how many
#   indexed files the retriever did not need to open. They measure the
#   repository exploration the graph replaced.
#
#   --gate-record names a gate record that `run-gate.sh` wrote; repeat it once
#   per record. Only its `duration_seconds` is read, and the entry stores the
#   number of records and the sum of their durations — never a path or a field
#   of the record itself.
#
#   --review-state names the review-loop state that `review-state.sh` kept for the run's
#   pull request. The state is validated by that script's own `evaluate`, and the entry
#   stores only its counts and codes under `review`: the rounds, the new findings per
#   round, the confirmed, resolved, dismissed, reopened, deferred, and unverified
#   findings, the blocking findings left, the result, and the escalation reason —
#   never a finding text, a path, or a URL.
#
#   The default store is `${AI_OLYMPUS_HOME:-$HOME/.ai-olympus}/metrics.jsonl`,
#   outside any repository, so a project can never commit it by accident.
#
# Exit codes
#   0  the entry was appended
#   1  usage error, or a value that failed validation
set -euo pipefail

PROG="${0##*/}"
HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

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
  local gate_runs=0 gate_seconds=0 gate_duration
  local context_gate_executed="" context_requested="" context_skipped=""
  local sources_searched="" items_returned="" estimated_tokens_returned=""
  local items_inspected="" cache_hits="" cache_misses="" retrieval_seconds=""
  local graph_hits="" graph_misses="" items_from_graph="" items_from_search="" files_avoided=""
  local review="" review_json
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
    --gate-record)
      [[ $# -ge 2 ]] || { usage; return 1; }
      if ! gate_duration="$(jq -e '.duration_seconds | select(type == "number" and . >= 0 and . == floor)' "$value" 2>/dev/null)"; then
        echo "$PROG: --gate-record must name a gate record with a whole duration_seconds" >&2
        return 1
      fi
      gate_runs=$((gate_runs + 1))
      gate_seconds=$((gate_seconds + gate_duration))
      shift 2
      ;;
    --review-state)
      [[ $# -ge 2 ]] || { usage; return 1; }
      if ! review_json="$("$HERE/review-state.sh" evaluate --state "$value" 2>/dev/null)"; then
        echo "$PROG: --review-state must name a valid review state" >&2
        return 1
      fi
      review="$(jq -c '{iterations: .iteration, new_per_iteration: (.rounds | map(.new)), new: .counts.new,
        confirmed: .counts.confirmed, resolved: .counts.resolved, dismissed: .counts.dismissed, reopened: .counts.reopened,
        deferred: .counts.deferred, needs_verification: .counts.needs_verification,
        remaining_blocking: .counts.remaining_blocking, result: .status, escalation_reason}' <<<"$review_json")"
      shift 2
      ;;
    --agent-dispatches | --escalated-dispatches | --review-rounds | --critical | --moderate | --input-tokens | --output-tokens | --cache-read-tokens | --context-gate-executed | --context-requested | --context-skipped | --sources-searched | --items-returned | --estimated-tokens-returned | --items-inspected | --context-cache-hits | --context-cache-misses | --retrieval-seconds | --graph-hits | --graph-misses | --items-from-graph | --items-from-search | --files-avoided)
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
      --context-gate-executed) context_gate_executed="$value" ;;
      --context-requested) context_requested="$value" ;;
      --context-skipped) context_skipped="$value" ;;
      --sources-searched) sources_searched="$value" ;;
      --items-returned) items_returned="$value" ;;
      --estimated-tokens-returned) estimated_tokens_returned="$value" ;;
      --items-inspected) items_inspected="$value" ;;
      --context-cache-hits) cache_hits="$value" ;;
      --context-cache-misses) cache_misses="$value" ;;
      --retrieval-seconds) retrieval_seconds="$value" ;;
      --graph-hits) graph_hits="$value" ;;
      --graph-misses) graph_misses="$value" ;;
      --items-from-graph) items_from_graph="$value" ;;
      --items-from-search) items_from_search="$value" ;;
      --files-avoided) files_avoided="$value" ;;
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
    [[ "$gate_runs" -gt 0 ]] && printf ',"gate_runs":%s,"gate_seconds":%s' "$gate_runs" "$gate_seconds"
    [[ -n "$context_gate_executed" ]] && printf ',"context_gate_executed":%s' "$context_gate_executed"
    [[ -n "$context_requested" ]] && printf ',"context_requested":%s' "$context_requested"
    [[ -n "$context_skipped" ]] && printf ',"context_skipped":%s' "$context_skipped"
    [[ -n "$sources_searched" ]] && printf ',"sources_searched":%s' "$sources_searched"
    [[ -n "$items_returned" ]] && printf ',"items_returned":%s' "$items_returned"
    [[ -n "$estimated_tokens_returned" ]] && printf ',"estimated_tokens_returned":%s' "$estimated_tokens_returned"
    [[ -n "$items_inspected" ]] && printf ',"items_inspected":%s' "$items_inspected"
    [[ -n "$cache_hits" ]] && printf ',"context_cache_hits":%s' "$cache_hits"
    [[ -n "$cache_misses" ]] && printf ',"context_cache_misses":%s' "$cache_misses"
    [[ -n "$retrieval_seconds" ]] && printf ',"retrieval_seconds":%s' "$retrieval_seconds"
    [[ -n "$graph_hits" ]] && printf ',"graph_hits":%s' "$graph_hits"
    [[ -n "$graph_misses" ]] && printf ',"graph_misses":%s' "$graph_misses"
    [[ -n "$items_from_graph" ]] && printf ',"items_from_graph":%s' "$items_from_graph"
    [[ -n "$items_from_search" ]] && printf ',"items_from_search":%s' "$items_from_search"
    [[ -n "$files_avoided" ]] && printf ',"files_avoided":%s' "$files_avoided"
    [[ -n "$review" ]] && printf ',"review":%s' "$review"
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

  printf '{"tier":"full","duration_seconds":120}\n' >"$tmp/gate-full.json"
  printf '{"tier":"pr","duration_seconds":30}\n' >"$tmp/gate-pr.json"
  printf '{"tier":"pr"}\n' >"$tmp/gate-broken.json"
  expect_exit 'gate run durations are read from each record' 0 \
    --initial-tier STANDARD --final-tier STANDARD --status success \
    --gate-record "$tmp/gate-full.json" --gate-record "$tmp/gate-pr.json"
  expect_exit 'a gate record without a duration is refused' 1 \
    --initial-tier STANDARD --final-tier STANDARD --status success --gate-record "$tmp/gate-broken.json"

  expect_exit 'context gate counters are appended' 0 \
    --initial-tier FAST --final-tier FAST --status success \
    --context-gate-executed 2 --context-requested 1 --context-skipped 1 \
    --sources-searched 2 --items-returned 3 --estimated-tokens-returned 900
  expect_exit 'retrieval counters are appended' 0 \
    --initial-tier STANDARD --final-tier STANDARD --status success \
    --items-inspected 12 --context-cache-hits 1 --context-cache-misses 0 --retrieval-seconds 41
  printf '%s\n' '{"schema":1,"repo":"acme/shop","pr":7,"iteration":1,"max_iterations":3,"blocking_threshold":"critical",
    "status":"open","escalation_reason":null,"revision":"1111111111111111111111111111111111111111","scope":null,
    "findings":[{"schema":2,"finding_id":"r-0123456789abcdef","repo":"acme/shop","pr":7,
      "revision":"1111111111111111111111111111111111111111","time":"2026-10-01T10:00:00Z","category":"rules/php/core-standards",
      "cause_key":"structure","severity":"medium","security":false,"file":"src/Foo/Bar.php","line":3,
      "description":"Copied step","impact":"drift","evidence":"rule-violation — copied","recommendation":"extract it",
      "status":"new"}],
    "deferrals":[],"transitions":[{"iteration":1,"finding_id":"r-0123456789abcdef","from":null,"to":"new","actor":"reviewer"}],
    "rounds":[{"iteration":1,"revision":"1111111111111111111111111111111111111111","new":1,"confirmed":0,"resolved":0,
      "dismissed":0,"reopened":0,"needs_verification":0,"remaining_blocking":1,"verdict":"continue"}]}' >"$tmp/review.json"
  printf '{"schema":1}\n' >"$tmp/review-broken.json"
  expect_exit 'review-loop counters are appended' 0 \
    --initial-tier STANDARD --final-tier STANDARD --status success --review-state "$tmp/review.json"
  expect_exit 'an invalid review state is refused' 1 \
    --initial-tier STANDARD --final-tier STANDARD --status success --review-state "$tmp/review-broken.json"
  expect_exit 'graph counters are appended' 0 \
    --initial-tier STANDARD --final-tier STANDARD --status success \
    --graph-hits 1 --graph-misses 2 --items-from-graph 4 --items-from-search 3 --files-avoided 35
  expect_exit 'a non-numeric graph counter is refused' 1 \
    --initial-tier FAST --final-tier FAST --status success --files-avoided many
  expect_exit 'a non-numeric context counter is refused' 1 \
    --initial-tier FAST --final-tier FAST --status success --items-returned some

  expect_exit 'an unknown tier is refused' 1 --initial-tier HOT --final-tier FAST --status success
  expect_exit 'an unknown status is refused' 1 --initial-tier FAST --final-tier FAST --status vibes
  expect_exit 'a non-numeric counter is refused' 1 \
    --initial-tier FAST --final-tier FAST --status success --agent-dispatches many
  expect_exit 'an unknown flag is refused' 1 \
    --initial-tier FAST --final-tier FAST --status success --branch feature/secret

  # Every line must parse, and the store must hold exactly the seven valid entries.
  local lines
  lines="$(wc -l <"$store" | tr -d ' ')"
  if [[ "$lines" == "7" ]]; then
    printf 'ok    %-54s %s entries\n' 'only valid entries reach the store' "$lines"
  else
    printf 'FAIL  %-54s expected 7 entries, got %s\n' 'only valid entries reach the store' "$lines" >&2
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

  if jq -e 'select(.gate_runs == 2 and .gate_seconds == 150)' <(sed -n 3p "$store") >/dev/null 2>&1; then
    printf 'ok    %-54s\n' 'gate durations are summed, never copied'
  else
    printf 'FAIL  %-54s\n' 'gate durations are summed, never copied' >&2
    failures=$((failures + 1))
  fi

  if jq -e 'select(.context_gate_executed == 2 and .context_requested == 1 and .context_skipped == 1
      and .sources_searched == 2 and .items_returned == 3 and .estimated_tokens_returned == 900)' \
    <(sed -n 4p "$store") >/dev/null 2>&1; then
    printf 'ok    %-54s\n' 'context gate counters are stored as counts'
  else
    printf 'FAIL  %-54s\n' 'context gate counters are stored as counts' >&2
    failures=$((failures + 1))
  fi

  if jq -e 'select(.items_inspected == 12 and .context_cache_hits == 1 and .context_cache_misses == 0
      and .retrieval_seconds == 41)' <(sed -n 5p "$store") >/dev/null 2>&1; then
    printf 'ok    %-54s\n' 'retrieval counters are stored as counts'
  else
    printf 'FAIL  %-54s\n' 'retrieval counters are stored as counts' >&2
    failures=$((failures + 1))
  fi

  if jq -e 'select(.review == {iterations: 1, new_per_iteration: [1], new: 1, confirmed: 0, resolved: 0, dismissed: 0,
      reopened: 0, deferred: 0, needs_verification: 0, remaining_blocking: 1, result: "open", escalation_reason: null})' \
    <(sed -n 6p "$store") >/dev/null 2>&1; then
    printf 'ok    %-54s\n' 'review-loop counters are stored as counts and codes'
  else
    printf 'FAIL  %-54s\n' 'review-loop counters are stored as counts and codes' >&2
    failures=$((failures + 1))
  fi

  if jq -e 'select(.graph_hits == 1 and .graph_misses == 2 and .items_from_graph == 4
      and .items_from_search == 3 and .files_avoided == 35)' <(tail -1 "$store") >/dev/null 2>&1; then
    printf 'ok    %-54s\n' 'graph counters are stored as counts'
  else
    printf 'FAIL  %-54s\n' 'graph counters are stored as counts' >&2
    failures=$((failures + 1))
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
