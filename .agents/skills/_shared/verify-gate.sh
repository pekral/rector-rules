#!/usr/bin/env bash
# verify-gate.sh — decide whether a recorded quality-gate run covers a commit,
# then run the `gate-fresh` commands fresh.
#
# Why this exists
#   A merge, an orchestrator, and a readiness check each need to know whether
#   the gate already passed on the bytes in front of them. Re-running it to find
#   out costs minutes per run; trusting a textual line in a comment trusts
#   whoever wrote the comment. This script reads the machine record
#   `run-gate.sh` wrote and accepts it only when every condition holds.
#
# TRUST MODEL — see gate-record.sh. In short: the record is a local cache. The
#   SHA-256 of the log detects a damaged log and does not prove it authentic.
#   The defence against hostile branch code is code review, required CI, and a
#   fresh `gate-fresh` run — never the record. This script never accepts a
#   record of another tree, and never executes anything a record contains.
#
# A record is accepted only when all of these hold
#   - its TREE equals the tree of <sha> — a record is keyed to the tree, so a
#     rebase, squash, or amend that keeps the bytes keeps it
#   - its commands equal the tier's commands in the default-branch manifest
#   - its environment fingerprint equals the current one
#   - its log exists and matches the SHA-256 in the record
#   - it passed (exit 0 overall and for every command)
#   Every field is read through jq by a fixed name and checked against its
#   shape; a missing, unreadable, or malformed field fails closed.
#
# Then the `gate-fresh` commands run now, on every call, whatever the record
# says — their verdict depends on when they run, so it is never cached. A
# missing or empty `gate-fresh` runs `composer audit` when composer.lock exists.
#
# Usage
#   verify-gate.sh --tier full|pr <sha>
#   verify-gate.sh --self-test
#
#   <sha> is a full commit SHA (40 or 64 hex characters) that must name a commit.
#
# Output (stdout): one JSON document with status, tier, sha, tree, record,
#   reason, the fresh commands with their exit codes, and fresh_exit_code: the
#   gate-fresh verdict (0 passed, 11 failed or refused, null not run). Read the
#   verdict, never the array: a refused fresh run leaves the array empty.
#
# Exit codes
#   0   the record is valid and every gate-fresh command passed
#   1   usage error, including an invalid or unknown <sha>
#   2   missing required tool (git or jq)
#   3   refused: the manifest, a command, or the evidence directory is not acceptable
#   5   the manifest sets no command for this tier — the built-in gate path applies
#   10  missing: no record for this tree and tier
#   11  failed: the record is a failed run, or a gate-fresh command failed
#   12  stale: the tree, the commands, the environment, or the log do not match,
#       or the record is malformed
set -euo pipefail

PROG="${0##*/}"
# shellcheck source=gate-record.sh
. "$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)/gate-record.sh"

usage() {
  cat >&2 <<'EOF'
Usage: verify-gate.sh --tier full|pr <sha>
       verify-gate.sh --self-test

Accepts the gate record of the tree of <sha>, then runs gate-fresh.
Exit 0 valid, 10 missing, 11 failed, 12 stale, 5 not configured.
EOF
}

TIER=''
SHA=''
TREE=''
FRESH_EXIT=''

emit() {
  local status="$1" code="$2" record=''
  [[ -z "$TREE" || -z "$GATE_EVIDENCE" ]] || record="$GATE_EVIDENCE/$TREE.$TIER.json"
  jq -n --arg status "$status" --arg tier "$TIER" --arg sha "$SHA" --arg tree "$TREE" \
    --arg record "$record" --arg reason "$GATE_REASON" --arg fresh_log "$GATE_FRESH_LOG" \
    --argjson fresh "$GATE_FRESH_RESULTS" --argjson code "$code" --arg fresh_exit "$FRESH_EXIT" \
    '{status: $status, exit_code: $code, tier: $tier, sha: $sha, tree: $tree, record: $record, reason: $reason, fresh: $fresh,
      fresh_exit_code: (if $fresh_exit == "" then null else ($fresh_exit | tonumber) end), fresh_log: $fresh_log}'
  return "$code"
}

verify_gate() {
  while [[ $# -gt 0 ]]; do
    case "$1" in
    --tier)
      [[ $# -ge 2 ]] || { usage; return 1; }
      TIER="$2"
      shift 2
      ;;
    -*)
      echo "$PROG: unknown argument: $(safe_display "$1")" >&2
      usage
      return 1
      ;;
    *)
      [[ -z "$SHA" ]] || { usage; return 1; }
      SHA="$1"
      shift
      ;;
    esac
  done

  gate_tier_key "$TIER" >/dev/null || { usage; return 1; }

  if ! git rev-parse --is-inside-work-tree >/dev/null 2>&1; then
    echo "$PROG: not a git checkout" >&2
    return 1
  fi

  # A full SHA only, and it must name a commit — never a ref, a range, or an
  # option that git would read as a flag.
  if [[ ! "$SHA" =~ ^[0-9a-f]{40}([0-9a-f]{24})?$ ]] || ! git rev-parse --verify --quiet "$SHA^{commit}" >/dev/null 2>&1; then
    echo "$PROG: <sha> must be a full commit SHA of this repository" >&2
    usage
    return 1
  fi

  local status=0
  load_project_manifest || { GATE_REASON="$PROJECT_REFUSAL"; emit refused 3; return; }
  gate_load_commands "$TIER" || status=$?
  case "$status" in
  0) ;;
  5) emit not-configured 5; return ;;
  *) emit refused 3; return ;;
  esac
  gate_evidence_dir write || { emit refused 3; return; }
  trap gate_cleanup EXIT

  TREE="$(gate_tree_of "$SHA")" || { GATE_REASON='refused: the commit has no tree'; emit refused 3; return; }

  status=0
  gate_check_record "$TIER" "$TREE" || status=$?
  local reason="$GATE_REASON"

  # gate-fresh runs on every call, whatever the record said: a caller that falls
  # back to running the gate still learns the fresh verdict now.
  local fresh=0
  gate_run_fresh "$TIER" "$TREE" || fresh=$?
  FRESH_EXIT="$fresh"

  case "$status" in
  0)
    if [[ "$fresh" -ne 0 ]]; then
      emit failed 11
      return
    fi
    GATE_REASON="$reason"
    emit valid 0
    ;;
  10) GATE_REASON="$reason"; emit missing 10 ;;
  11) GATE_REASON="$reason"; emit failed 11 ;;
  *) GATE_REASON="$reason"; emit stale 12 ;;
  esac
}

SELF_TEST_TMP=""
# Reached only through `trap cleanup_self_test EXIT`; ShellCheck does not credit a trap as an
# invocation (SC2317, and SC2329 in 0.11), so both are suppressed.
# shellcheck disable=SC2317,SC2329
cleanup_self_test() {
  [[ -n "$SELF_TEST_TMP" ]] && rm -rf "$SELF_TEST_TMP"
  return 0
}

self_test() {
  local failures=0 script runner
  script="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)/$PROG"
  runner="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)/run-gate.sh"
  SELF_TEST_TMP="$(mktemp -d)"
  trap cleanup_self_test EXIT
  local tmp="$SELF_TEST_TMP"
  export GATE_SELFTEST_CALLS="$tmp/calls"

  local base='"validation": { "executables": ["vendor/bin/gate-ok", "vendor/bin/gate-fail", "vendor/bin/fresh-ok", "vendor/bin/fresh-fail", "vendor/bin/pwn"] }'

  OUT=''
  verify_in() {
    local dir="$1"
    shift
    local code
    set +e
    OUT="$(cd "$dir" && "$script" "$@" 2>/dev/null)"
    code=$?
    set -e
    return "$code"
  }

  # The condition is evaluated by the caller, `"$(<condition> && echo pass)"`, so
  # nothing here evaluates a string.
  check() {
    local label="$1" verdict="$2"
    if [[ "$verdict" == pass ]]; then
      printf 'ok    %s\n' "$label"
    else
      printf 'FAIL  %s\n' "$label" >&2
      failures=$((failures + 1))
    fi
  }

  calls() {
    if [[ -f "$GATE_SELFTEST_CALLS" ]]; then grep -c "^$1" "$GATE_SELFTEST_CALLS" || true; else printf '0'; fi
  }

  # Rewrite one field of the record through jq — the forged-record cases below.
  forge() {
    local file="$1" program="$2" forged
    forged="$(jq "$program" "$file")"
    printf '%s\n' "$forged" >"$file"
  }

  local project="$tmp/project" head tree record code
  local manifest="{ \"extra\": { \"ai-olympus\": { $base, \"gate\": [\"vendor/bin/gate-ok\"], \"gate-fresh\": [\"vendor/bin/fresh-ok\"] } } }"
  gate_selftest_project "$project" "$manifest"
  head="$(git -C "$project" rev-parse HEAD)"
  tree="$(git -C "$project" rev-parse 'HEAD^{tree}')"
  record="$project/.claude/run/gates/$tree.full.json"

  code=0; verify_in "$project" --tier full "$head" || code=$?
  check 'no record is missing' "$([[ "$code" -eq 10 && "$(printf "%s" "$OUT" | jq -r .reason)" == missing:* ]] && echo pass)"

  (cd "$project" && "$runner" --tier full >/dev/null 2>&1)
  : >"$GATE_SELFTEST_CALLS"
  code=0; verify_in "$project" --tier full "$head" || code=$?
  check 'a valid record verifies' "$([[ "$code" -eq 0 && "$(printf "%s" "$OUT" | jq -r .status)" == valid && "$(calls gate-ok)" -eq 0 ]] && echo pass)"
  code=0; verify_in "$project" --tier full "$head" || code=$?
  check 'gate-fresh runs on every verification and never from the record' \
    "$([[ "$code" -eq 0 && "$(calls fresh-ok)" -eq 2 ]] && ! grep -q fresh "$record" && echo pass)"

  # --- The record is keyed to the tree, never the SHA -----------------------------
  local squash rebased
  squash="$(git -C "$project" -c user.name=s -c user.email=s@s commit-tree "$tree" -m 'squashed')"
  code=0; verify_in "$project" --tier full "$squash" || code=$?
  check 'a squash with the same tree keeps the record' "$([[ "$code" -eq 0 ]] && echo pass)"
  rebased="$(git -C "$project" -c user.name=r -c user.email=r@r commit-tree "$tree" -p "$squash" -m 'rebased')"
  code=0; verify_in "$project" --tier full "$rebased" || code=$?
  check 'a rebase with the same tree keeps the record' "$([[ "$code" -eq 0 ]] && echo pass)"

  printf 'other\n' >>"$project/tracked.txt"
  git -C "$project" -c user.name=t -c user.email=t@t commit -q -am 'other bytes'
  local other other_tree
  other="$(git -C "$project" rev-parse HEAD)"
  other_tree="$(git -C "$project" rev-parse 'HEAD^{tree}')"
  code=0; verify_in "$project" --tier full "$other" || code=$?
  check 'a different tree is rejected' "$([[ "$code" -eq 10 ]] && echo pass)"

  # A record copied under another tree's name still names its own tree inside.
  cp "$record" "$project/.claude/run/gates/$other_tree.full.json"
  cp "${record%.json}.log" "$project/.claude/run/gates/$other_tree.full.log"
  code=0; verify_in "$project" --tier full "$other" || code=$?
  check 'a record renamed to another tree is stale' "$([[ "$code" -eq 12 ]] && echo pass)"
  rm -f "$project/.claude/run/gates/$other_tree".full.*

  # --- Commands, environment, and the log --------------------------------------------
  gate_selftest_manifest "$project" "{ \"extra\": { \"ai-olympus\": { $base, \"gate\": [\"vendor/bin/gate-ok\", \"vendor/bin/gate-ok more\"], \"gate-fresh\": [\"vendor/bin/fresh-ok\"] } } }"
  code=0; verify_in "$project" --tier full "$head" || code=$?
  check 'changed gate commands make the record stale' "$([[ "$code" -eq 12 && "$(printf "%s" "$OUT" | jq -r .reason)" == *commands* ]] && echo pass)"

  gate_selftest_manifest "$project" "{ \"extra\": { \"ai-olympus\": { $base, \"gate\": [\"vendor/bin/gate-ok\"], \"gate-fresh\": [\"vendor/bin/fresh-ok\"], \"env\": { \"CLAUDECODE\": \"1\" } } } }"
  code=0; verify_in "$project" --tier full "$head" || code=$?
  check 'a changed environment makes the record stale' "$([[ "$code" -eq 12 && "$(printf "%s" "$OUT" | jq -r .reason)" == *environment* ]] && echo pass)"

  gate_selftest_manifest "$project" "$manifest"
  code=0; verify_in "$project" --tier full "$head" || code=$?
  check 'the original environment verifies again' "$([[ "$code" -eq 0 ]] && echo pass)"

  cp "${record%.json}.log" "$tmp/log.bak"
  printf 'tampered\n' >>"${record%.json}.log"
  code=0; verify_in "$project" --tier full "$head" || code=$?
  check 'a tampered log makes the record stale' "$([[ "$code" -eq 12 ]] && echo pass)"
  cp "$tmp/log.bak" "${record%.json}.log"

  # --- Fail closed on every field ------------------------------------------------------
  cp "$record" "$tmp/record.bak"
  local field
  for field in schema tier tree head merge_base commands environment actor started_at finished_at duration_seconds exit_code log_sha256; do
    cp "$tmp/record.bak" "$record"
    forge "$record" "del(.$field)"
    code=0; verify_in "$project" --tier full "$head" || code=$?
    check "a record without $field fails closed" "$([[ "$code" -ne 0 ]] && echo pass)"
  done
  cp "$tmp/record.bak" "$record"
  printf '{ not json' >"$record"
  code=0; verify_in "$project" --tier full "$head" || code=$?
  check 'an unreadable record fails closed' "$([[ "$code" -eq 12 ]] && echo pass)"

  # --- A record is data, never code ----------------------------------------------------
  cp "$tmp/record.bak" "$record"
  forge "$record" '.commands = [{command: "vendor/bin/pwn", exit_code: 0, duration_seconds: 0}]'
  code=0; verify_in "$project" --tier full "$head" || code=$?
  check 'a record carrying a command never executes it' "$([[ "$code" -eq 12 && ! -e "$project/pwned" ]] && echo pass)"

  cp "$tmp/record.bak" "$record"
  # The `$(…)` must reach the record as literal text — it is the payload under test.
  # shellcheck disable=SC2016
  forge "$record" '.actor = "$(touch pwned)"'
  code=0; verify_in "$project" --tier full "$head" || code=$?
  check 'shell syntax in a record field is never evaluated' "$([[ "$code" -eq 12 && ! -e "$project/pwned" ]] && echo pass)"

  cp "$tmp/record.bak" "$record"
  forge "$record" '.exit_code = 2'
  code=0; verify_in "$project" --tier full "$head" || code=$?
  check 'a failed record is failed' "$([[ "$code" -eq 11 ]] && echo pass)"
  check 'a failed record still reports a passing gate-fresh verdict' \
    "$([[ "$(printf "%s" "$OUT" | jq -r .fresh_exit_code)" == 0 && "$(printf "%s" "$OUT" | jq -r '.fresh | length')" -eq 1 ]] && echo pass)"
  cp "$tmp/record.bak" "$record"

  # A run stops at its first failing command, so the record lists only a prefix.
  local failing="$tmp/failing" failing_head failing_record
  gate_selftest_project "$failing" "{ \"extra\": { \"ai-olympus\": { $base, \"gate\": [\"vendor/bin/gate-fail\", \"vendor/bin/gate-ok\"], \"gate-fresh\": [\"vendor/bin/fresh-ok\"] } } }"
  failing_head="$(git -C "$failing" rev-parse HEAD)"
  failing_record="$failing/.claude/run/gates/$(git -C "$failing" rev-parse 'HEAD^{tree}').full.json"
  (cd "$failing" && "$runner" --tier full >/dev/null 2>&1) || true
  code=0; verify_in "$failing" --tier full "$failing_head" || code=$?
  check 'a record that failed on the first of two commands is failed, not stale' \
    "$([[ "$code" -eq 11 && "$(printf "%s" "$OUT" | jq -r .reason)" == failed:* ]] && jq -e '.commands | length == 1' "$failing_record" >/dev/null && echo pass)"
  forge "$failing_record" '.exit_code = 0 | .commands[0].exit_code = 0'
  code=0; verify_in "$failing" --tier full "$failing_head" || code=$?
  check 'a passing record that lists only a prefix of the commands is stale' \
    "$([[ "$code" -eq 12 && "$(printf "%s" "$OUT" | jq -r .reason)" == *commands* ]] && echo pass)"

  mv "$record" "$tmp/record.real"
  ln -s "$tmp/record.real" "$record"
  code=0; verify_in "$project" --tier full "$head" || code=$?
  check 'a symlinked record is refused' "$([[ "$code" -ne 0 ]] && echo pass)"
  rm -f "$record"
  cp "$tmp/record.bak" "$record"

  # --- gate-fresh -----------------------------------------------------------------------
  gate_selftest_manifest "$project" "{ \"extra\": { \"ai-olympus\": { $base, \"gate\": [\"vendor/bin/gate-ok\"], \"gate-fresh\": [\"vendor/bin/fresh-fail\"] } } }"
  code=0; verify_in "$project" --tier full "$head" || code=$?
  check 'a failing gate-fresh fails a valid record' "$([[ "$code" -eq 11 ]] && echo pass)"
  check 'a failing gate-fresh reports its verdict' "$([[ "$(printf "%s" "$OUT" | jq -r .fresh_exit_code)" == 11 ]] && echo pass)"

  # A refused fresh run leaves the array empty, so only the verdict tells it from a pass.
  local fresh_log="$project/.claude/run/gates/$tree.full.fresh.log"
  gate_selftest_manifest "$project" "$manifest"
  rm -f "$fresh_log"
  ln -s "$tmp/elsewhere" "$fresh_log"
  code=0; verify_in "$project" --tier full "$head" || code=$?
  check 'a refused gate-fresh is a failed verdict with an empty array' \
    "$([[ "$code" -eq 11 && "$(printf "%s" "$OUT" | jq -r .fresh_exit_code)" == 11 && "$(printf "%s" "$OUT" | jq -r '.fresh | length')" -eq 0 ]] && echo pass)"
  rm -f "$fresh_log"

  # The default fresh command needs a fake `composer` on PATH and a composer.lock.
  mkdir -p "$tmp/fakebin"
  cat >"$tmp/fakebin/composer" <<'STUB'
#!/usr/bin/env bash
echo "composer $*" >>"$GATE_SELFTEST_CALLS"
STUB
  chmod +x "$tmp/fakebin/composer"
  printf '{}\n' >"$project/composer.lock"
  local value
  for value in 'absent' '[]'; do
    if [[ "$value" == absent ]]; then
      gate_selftest_manifest "$project" "{ \"extra\": { \"ai-olympus\": { $base, \"gate-evidence\": \".claude/run/gates\", \"gate\": [\"vendor/bin/gate-ok\"] } } }"
    else
      gate_selftest_manifest "$project" "{ \"extra\": { \"ai-olympus\": { $base, \"gate\": [\"vendor/bin/gate-ok\"], \"gate-fresh\": [] } } }"
    fi
    : >"$GATE_SELFTEST_CALLS"
    code=0
    PATH="$tmp/fakebin:$PATH" verify_in "$project" --tier full "$head" || code=$?
    check "a gate-fresh that is $value still runs composer audit" "$([[ "$(calls "composer audit")" -eq 1 ]] && echo pass)"
  done
  rm -f "$project/composer.lock"

  # --- Arguments and configuration -----------------------------------------------------------
  code=0; verify_in "$project" --tier full --output=/tmp/x || code=$?
  check 'an option in place of the sha is refused' "$([[ "$code" -eq 1 && ! -e /tmp/x ]] && echo pass)"
  code=0; verify_in "$project" --tier full "${head:0:12}" || code=$?
  check 'an abbreviated sha is refused' "$([[ "$code" -eq 1 ]] && echo pass)"
  code=0; verify_in "$project" --tier full 0000000000000000000000000000000000000000 || code=$?
  check 'a sha that names no commit is refused' "$([[ "$code" -eq 1 ]] && echo pass)"
  code=0; verify_in "$project" --tier pr "$head" || code=$?
  check 'without pr-gate nothing is verified' "$([[ "$code" -eq 5 && "$(printf "%s" "$OUT" | jq -r .fresh_exit_code)" == null ]] && echo pass)"
  gate_selftest_manifest "$project" "{ \"extra\": { \"ai-olympus\": { $base, \"gate\": [\"vendor/bin/gate-ok\"] } } }"
  code=0; verify_in "$project" --tier full "$head" || code=$?
  check 'a manifest with gate alone is not configured' "$([[ "$code" -eq 5 ]] && echo pass)"

  if [[ "$failures" -gt 0 ]]; then
    echo "verify-gate self-test: $failures failure(s)" >&2
    return 4
  fi
  echo 'verify-gate self-test: PASS'
  return 0
}

for tool in git jq; do
  if ! command -v "$tool" >/dev/null 2>&1; then
    echo "$PROG: required tool not found: $tool" >&2
    exit 2
  fi
done

if [[ "${1:-}" == "--self-test" ]]; then
  self_test
  exit $?
fi

verify_gate "$@"
