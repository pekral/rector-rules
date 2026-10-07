#!/usr/bin/env bash
# run-gate.sh — run the project's quality gate once per git tree, under a lock,
# and write a machine record of the run.
#
# Why this exists
#   The gate used to leave only a textual `Quality gate:` line in a review
#   comment. Nothing could verify it, so the implementer, the orchestrator, the
#   merge, and the main session each ran the full gate again on the same head —
#   three or four runs of several minutes per pull request. The agents also share
#   one working tree, and two gates at once broke each other's test database.
#   This script runs the gate once per tree, writes a record any later step can
#   verify with `verify-gate.sh`, and serialises runs on one lock.
#
# TRUST MODEL — see gate-record.sh. In short: the record is a local cache. The
#   SHA-256 of the log detects a damaged log and does not prove it authentic.
#   The defence against hostile branch code is code review, required CI, and a
#   fresh `gate-fresh` run — never the record.
#
# What it does
#   1. Reads the tier's commands (`gate` for full, `pr-gate` for pr) and
#      `gate-fresh` from the default-branch manifest through read-manifest.sh,
#      and exports only `read-manifest.sh --env`. It never derives a command from
#      the working tree. Every command is validated before anything runs, and
#      runs as an argv without a shell (project-commands.sh).
#   2. Takes the lock `<evidence>/gate.lock` (atomic `mkdir`; `flock` is absent on
#      macOS), waiting for a live holder up to AI_OLYMPUS_GATE_LOCK_TIMEOUT
#      seconds (default 3600).
#   3. Refuses a tree with any uncommitted or untracked change, on both tiers.
#   4. When a valid record for this tree and tier already exists — a run that
#      finished while this one waited — takes its result over through the same
#      check `verify-gate.sh` applies, and runs only `gate-fresh`.
#   5. Otherwise runs the commands in order, stopping at the first failure. A
#      change of HEAD^{tree} or of `git status` during the run fails the gate.
#   6. Writes the log, then the record, each through a temporary file and a
#      rename, then runs `gate-fresh`, whose result is never written to the
#      record.
#
# Usage
#   run-gate.sh --tier full|pr [--actor <name>]
#   run-gate.sh --self-test
#
# Output (stdout): one JSON document with status, tier, tree, record, log, reason.
#
# Exit codes
#   0  the gate passed (run here or taken over) and gate-fresh passed
#   1  usage error
#   2  missing required tool (git or jq)
#   3  refused: the manifest, a command, or the evidence directory is not acceptable
#   4  the gate or gate-fresh failed
#   5  the manifest sets no command for this tier — the built-in gate path applies
#   6  the lock is held by a live run past the timeout; nothing ran
#   7  the working tree is not clean; nothing ran
set -euo pipefail

PROG="${0##*/}"
# shellcheck source=gate-record.sh
. "$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)/gate-record.sh"

usage() {
  cat >&2 <<'EOF'
Usage: run-gate.sh --tier full|pr [--actor <name>]
       run-gate.sh --self-test

Runs the manifest gate of the tier once per git tree, under a lock, and writes
a record that verify-gate.sh accepts. Exit 0 passed, 4 failed, 5 not configured.
EOF
}

TIER=''
TREE=''
RECORD=''
LOG=''

emit() {
  local status="$1" code="$2"
  jq -n --arg status "$status" --arg tier "$TIER" --arg tree "$TREE" \
    --arg record "$RECORD" --arg log "$LOG" --arg reason "$GATE_REASON" \
    --arg fresh_log "$GATE_FRESH_LOG" --argjson fresh "$GATE_FRESH_RESULTS" --argjson code "$code" \
    '{status: $status, exit_code: $code, tier: $tier, tree: $tree, record: $record, log: $log, reason: $reason, fresh: $fresh, fresh_log: $fresh_log}'
  return "$code"
}

run_gate() {
  local actor timeout
  actor="$(id -un 2>/dev/null || printf 'unknown')"

  while [[ $# -gt 0 ]]; do
    case "$1" in
    --tier)
      [[ $# -ge 2 ]] || { usage; return 1; }
      TIER="$2"
      shift 2
      ;;
    --actor)
      [[ $# -ge 2 ]] || { usage; return 1; }
      actor="$2"
      shift 2
      ;;
    *)
      echo "$PROG: unknown argument: $(safe_display "$1")" >&2
      usage
      return 1
      ;;
    esac
  done

  gate_tier_key "$TIER" >/dev/null || { usage; return 1; }
  [[ "$actor" =~ ^[A-Za-z0-9._-]{1,64}$ ]] || actor='unknown'
  timeout="${AI_OLYMPUS_GATE_LOCK_TIMEOUT:-3600}"
  [[ "$timeout" =~ ^[0-9]{1,6}$ ]] || { echo "$PROG: AI_OLYMPUS_GATE_LOCK_TIMEOUT must be whole seconds" >&2; return 1; }

  if ! git rev-parse --is-inside-work-tree >/dev/null 2>&1; then
    echo "$PROG: not a git checkout" >&2
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
  trap 'exit 130' INT
  trap 'exit 143' TERM

  status=0
  gate_lock_acquire "$timeout" || status=$?
  case "$status" in
  0) ;;
  6) emit locked 6; return ;;
  *) emit refused 3; return ;;
  esac

  local porcelain
  porcelain="$(git status --porcelain --untracked-files=all)"
  if [[ -n "$porcelain" ]]; then
    GATE_REASON='dirty: the working tree has uncommitted or untracked changes — commit them first'
    emit dirty 7
    return
  fi

  TREE="$(gate_tree_of HEAD)" || { GATE_REASON='refused: HEAD has no tree'; emit refused 3; return; }
  RECORD="$GATE_EVIDENCE/$TREE.$TIER.json"
  LOG="$GATE_EVIDENCE/$TREE.$TIER.log"
  gate_no_symlink "$RECORD" || { emit refused 3; return; }
  gate_no_symlink "$LOG" || { emit refused 3; return; }

  # A run that finished while this one waited for the lock already proved these
  # bytes. Take it over through the one acceptance test, never a second one.
  if gate_check_record "$TIER" "$TREE"; then
    if gate_run_fresh "$TIER" "$TREE"; then
      GATE_REASON='taken over: a valid record for this tree already exists'
      emit taken-over 0
      return
    fi
    emit failed 4
    return
  fi

  local head merge_base started started_epoch log_tmp record_tmp commands='[]' failed=0 command
  head="$(git rev-parse --verify HEAD)"
  merge_base="$(git merge-base HEAD origin/HEAD 2>/dev/null || true)"
  gate_is_tree "$merge_base" || merge_base=''
  started="$(gate_now)"
  started_epoch="$(date +%s)"
  log_tmp="$(umask 077 && mktemp "$GATE_EVIDENCE/.log.XXXXXX")"
  GATE_TEMP_FILES+=("$log_tmp")

  for command in "${GATE_TIER_COMMANDS[@]}"; do
    local command_start command_status=0
    command_start="$(date +%s)"
    printf '### %s\n' "$command" >>"$log_tmp"
    run_command "$command" "$log_tmp" || command_status=$?
    printf '### exit %s after %ss\n' "$command_status" "$(($(date +%s) - command_start))" >>"$log_tmp"
    commands="$(printf '%s' "$commands" | jq -c --arg c "$command" --argjson e "$command_status" --argjson d "$(($(date +%s) - command_start))" \
      '. + [{command: $c, exit_code: $e, duration_seconds: $d}]')"
    if [[ "$command_status" -ne 0 ]]; then
      failed="$command_status"
      GATE_REASON="failed: the gate command exited $command_status — $(safe_display "$command")"
      break
    fi
  done

  # The record may only claim the bytes the gate actually checked. A fixer that
  # rewrote a file, or another agent that touched the tree, voids the pass.
  if [[ "$(gate_tree_of HEAD || true)" != "$TREE" || "$(git status --porcelain --untracked-files=all)" != "$porcelain" ]]; then
    [[ "$failed" -ne 0 ]] || failed=1
    GATE_REASON='failed: the working tree changed during the run — commit the change and run the gate again'
    printf '### the working tree changed during the run\n' >>"$log_tmp"
  fi

  local finished log_sum
  finished="$(gate_now)"
  log_sum="$(gate_sha256 "$log_tmp")"
  record_tmp="$(umask 077 && mktemp "$GATE_EVIDENCE/.record.XXXXXX")"
  GATE_TEMP_FILES+=("$record_tmp")
  jq -n --arg tier "$TIER" --arg tree "$TREE" --arg head "$head" --arg merge_base "$merge_base" \
    --argjson commands "$commands" --argjson environment "$(gate_fingerprint)" --arg actor "$actor" \
    --arg started "$started" --arg finished "$finished" --argjson duration "$(($(date +%s) - started_epoch))" \
    --argjson code "$failed" --arg log_sha256 "$log_sum" \
    '{schema: 1, tier: $tier, tree: $tree, head: $head, merge_base: $merge_base, commands: $commands,
      environment: $environment, actor: $actor, started_at: $started, finished_at: $finished,
      duration_seconds: $duration, exit_code: $code, log_sha256: $log_sha256}' >"$record_tmp"

  # The log first, then the record: a record never points at a log that is not
  # there yet.
  mv -f -- "$log_tmp" "$LOG"
  mv -f -- "$record_tmp" "$RECORD"

  if [[ "$failed" -ne 0 ]]; then
    emit failed 4
    return
  fi

  if ! gate_run_fresh "$TIER" "$TREE"; then
    emit failed 4
    return
  fi

  GATE_REASON="passed: the $TIER gate passed on tree $TREE"
  emit passed 0
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
  local failures=0 script
  script="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)/$PROG"
  SELF_TEST_TMP="$(mktemp -d)"
  trap cleanup_self_test EXIT
  local tmp="$SELF_TEST_TMP"
  export GATE_SELFTEST_CALLS="$tmp/calls"
  export AI_OLYMPUS_GATE_LOCK_TIMEOUT=2

  local base='"validation": { "executables": ["vendor/bin/gate-ok", "vendor/bin/gate-fail", "vendor/bin/gate-dirty", "vendor/bin/gate-kill", "vendor/bin/fresh-ok", "vendor/bin/fresh-fail", "vendor/bin/pwn"] }'
  # Any one of pr-gate, gate-fresh, gate-evidence opts a project into the record.
  local optin='"gate-evidence": ".claude/run/gates"'

  OUT=''
  run_in() {
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

  local project="$tmp/project" code tree record
  gate_selftest_project "$project" "{ \"extra\": { \"ai-olympus\": { $base, \"gate\": [\"vendor/bin/gate-ok\"], \"gate-fresh\": [\"vendor/bin/fresh-ok\"] } } }"
  tree="$(git -C "$project" rev-parse 'HEAD^{tree}')"
  record="$project/.claude/run/gates/$tree.full.json"

  # --- A passing run writes the record and the log ----------------------------
  code=0; run_in "$project" --tier full --actor donatello || code=$?
  check 'a passing gate writes a record and a log' \
    "$([[ "$code" -eq 0 && -f "$record" && -f "${record%.json}.log" ]] && echo pass)"
  check 'the record carries tier, tree, head, commands, environment, actor, times, exit, log hash' \
    "$(jq -e --arg t "$tree" --arg h "$(git -C "$project" rev-parse HEAD)" ".tier == \"full\" and .tree == \$t and .head == \$h and .commands[0].command == \"vendor/bin/gate-ok\" and .commands[0].exit_code == 0 and (.commands[0].duration_seconds | type == \"number\") and (.environment.php | type == \"string\") and .actor == \"donatello\" and (.started_at | length) == 20 and (.finished_at | length) == 20 and .exit_code == 0" "$record" >/dev/null && echo pass)"
  check 'the log hash in the record matches the log' \
    "$([[ "$(jq -r .log_sha256 "$record")" == "$(gate_sha256 "${record%.json}.log")" ]] && echo pass)"
  check 'the evidence directory is 0700 and its files are 0600' \
    "$([[ "$(gate_selftest_mode "$project/.claude/run/gates")" == 700 && "$(gate_selftest_mode "$record")" == 600 && "$(gate_selftest_mode "${record%.json}.log")" == 600 ]] && echo pass)"
  check 'gate-fresh runs after a passing gate and never enters the record' \
    "$([[ "$(calls fresh-ok)" -eq 1 ]] && ! grep -q fresh "$record" && echo pass)"
  check 'the lock is released after the run' "$([[ ! -e "$project/.claude/run/gates/gate.lock" ]] && echo pass)"

  # --- The record carries no environment value outside the fingerprint ---------
  local secret_record
  rm -f "$record"
  export GATE_SELFTEST_SECRET='hunter2-secret'
  run_in "$project" --tier full --actor 'bad actor;rm' || true
  unset GATE_SELFTEST_SECRET
  secret_record="$(cat "$record")"
  check 'the record carries no environment value and no unvalidated actor' \
    "$([[ "$secret_record" != *hunter2* && "$secret_record" != *"bad actor"* ]] && jq -e --arg re '^[A-Za-z0-9._-]{1,64}$' '.actor == "unknown" and (.actor | test($re))' "$record" >/dev/null && echo pass)"

  # --- A second run on the same tree takes the result over ---------------------
  : >"$GATE_SELFTEST_CALLS"
  code=0; run_in "$project" --tier full || code=$?
  check 'a second run on the same tree takes the result over' \
    "$([[ "$code" -eq 0 && "$(calls gate-ok)" -eq 0 && "$(printf "%s" "$OUT" | jq -r .status)" == taken-over && "$(calls fresh-ok)" -eq 1 ]] && echo pass)"

  gate_selftest_manifest "$project" "{ \"extra\": { \"ai-olympus\": { $base, \"gate\": [\"vendor/bin/gate-ok\", \"vendor/bin/gate-ok again\"], \"gate-fresh\": [\"vendor/bin/fresh-ok\"] } } }"
  : >"$GATE_SELFTEST_CALLS"
  code=0; run_in "$project" --tier full || code=$?
  check 'a record of other commands is not taken over' \
    "$([[ "$code" -eq 0 && "$(calls gate-ok)" -eq 2 && "$(printf "%s" "$OUT" | jq -r .status)" == passed ]] && echo pass)"

  # --- Concurrency: one tree, one gate run --------------------------------------
  rm -f "$record"
  : >"$GATE_SELFTEST_CALLS"
  local first second first_code=0 second_code=0
  export AI_OLYMPUS_GATE_LOCK_TIMEOUT=30
  (cd "$project" && GATE_SELFTEST_SLEEP=2 "$script" --tier full >"$tmp/first.json" 2>/dev/null) &
  first=$!
  sleep 0.5
  (cd "$project" && GATE_SELFTEST_SLEEP=2 "$script" --tier full >"$tmp/second.json" 2>/dev/null) &
  second=$!
  wait "$first" || first_code=$?
  wait "$second" || second_code=$?
  export AI_OLYMPUS_GATE_LOCK_TIMEOUT=2
  check 'concurrent runs on one tree run the gate once' \
    "$([[ "$first_code" -eq 0 && "$second_code" -eq 0 && "$(calls "gate-ok again")" -eq 1 && "$(jq -r .status "$tmp/second.json")" == taken-over ]] && echo pass)"

  # --- The lock -----------------------------------------------------------------
  rm -f "$record"
  : >"$GATE_SELFTEST_CALLS"
  mkdir -p "$project/.claude/run/gates/gate.lock"
  printf 'PID=%s\nSTARTED=%s\nSTARTED_EPOCH=%s\n' "$$" "$(gate_now)" "$(date +%s)" >"$project/.claude/run/gates/gate.lock/holder"
  code=0; run_in "$project" --tier full || code=$?
  check 'a live lock holder times out without running the gate' \
    "$([[ "$code" -eq 6 && "$(calls gate-ok)" -eq 0 && -d "$project/.claude/run/gates/gate.lock" ]] && echo pass)"

  local dead
  sh -c 'exit 0' &
  dead=$!
  wait "$dead" || true
  printf 'PID=%s\nSTARTED=%s\nSTARTED_EPOCH=%s\n' "$dead" "$(gate_now)" "$(date +%s)" >"$project/.claude/run/gates/gate.lock/holder"
  code=0; run_in "$project" --tier full || code=$?
  check 'a lock left by a dead holder is reclaimed' \
    "$([[ "$code" -eq 0 && "$(calls gate-ok)" -eq 2 && ! -e "$project/.claude/run/gates/gate.lock" ]] && echo pass)"

  # --- Failures never record a pass -----------------------------------------------
  local failing="$tmp/failing"
  gate_selftest_project "$failing" "{ \"extra\": { \"ai-olympus\": { $base, $optin, \"gate\": [\"vendor/bin/gate-fail\", \"vendor/bin/gate-ok\"] } } }"
  tree="$(git -C "$failing" rev-parse 'HEAD^{tree}')"
  : >"$GATE_SELFTEST_CALLS"
  code=0; run_in "$failing" --tier full || code=$?
  check 'a failing command fails the gate and records the failure' \
    "$([[ "$code" -eq 4 && "$(calls gate-ok)" -eq 0 ]] && jq -e ".exit_code == 3 and .commands[0].exit_code == 3" "$failing/.claude/run/gates/$tree.full.json" >/dev/null && echo pass)"

  local dirty="$tmp/dirty"
  gate_selftest_project "$dirty" "{ \"extra\": { \"ai-olympus\": { $base, $optin, \"gate\": [\"vendor/bin/gate-dirty\"] } } }"
  tree="$(git -C "$dirty" rev-parse 'HEAD^{tree}')"
  code=0; run_in "$dirty" --tier full || code=$?
  check 'a gate that changes the tree during the run never records a pass' \
    "$([[ "$code" -eq 4 ]] && jq -e ".exit_code != 0" "$dirty/.claude/run/gates/$tree.full.json" >/dev/null && echo pass)"

  local unclean="$tmp/unclean"
  gate_selftest_project "$unclean" "{ \"extra\": { \"ai-olympus\": { $base, \"gate\": [\"vendor/bin/gate-ok\"], \"pr-gate\": [\"vendor/bin/gate-ok\"] } } }"
  printf 'new\n' >"$unclean/untracked.txt"
  : >"$GATE_SELFTEST_CALLS"
  local full_code=0 pr_code=0
  run_in "$unclean" --tier full || full_code=$?
  run_in "$unclean" --tier pr || pr_code=$?
  check 'a dirty tree at the start refuses both tiers and writes nothing' \
    "$([[ "$full_code" -eq 7 && "$pr_code" -eq 7 && "$(calls gate-ok)" -eq 0 && -z "$(ls -A "$unclean/.claude/run/gates" 2>/dev/null)" ]] && echo pass)"

  local interrupted="$tmp/interrupted"
  gate_selftest_project "$interrupted" "{ \"extra\": { \"ai-olympus\": { $base, $optin, \"gate\": [\"vendor/bin/gate-kill\"] } } }"
  code=0; run_in "$interrupted" --tier full || code=$?
  check 'an interrupted run leaves no record, no temporary file, and no lock' \
    "$([[ "$code" -ne 0 && -z "$(ls -A "$interrupted/.claude/run/gates" 2>/dev/null)" ]] && echo pass)"

  # --- What the manifest decides -------------------------------------------------
  code=0; run_in "$project" --tier pr || code=$?
  check 'a missing pr-gate runs nothing' "$([[ "$code" -eq 5 ]] && echo pass)"
  local bare="$tmp/bare"
  gate_selftest_project "$bare" '{ "require": {} }'
  : >"$GATE_SELFTEST_CALLS"
  code=0; run_in "$bare" --tier full || code=$?
  check 'a missing gate runs nothing' "$([[ "$code" -eq 5 && "$(calls gate-ok)" -eq 0 && ! -e "$bare/.claude/run/gates" ]] && echo pass)"

  local legacy="$tmp/legacy"
  gate_selftest_project "$legacy" "{ \"extra\": { \"ai-olympus\": { $base, \"gate\": [\"vendor/bin/gate-ok\"] } } }"
  : >"$GATE_SELFTEST_CALLS"
  code=0; run_in "$legacy" --tier full || code=$?
  check 'a manifest with gate alone keeps the built-in path' \
    "$([[ "$code" -eq 5 && "$(calls gate-ok)" -eq 0 && ! -e "$legacy/.claude/run/gates" ]] && echo pass)"

  local chained="$tmp/chained"
  gate_selftest_project "$chained" "{ \"extra\": { \"ai-olympus\": { $base, $optin, \"gate\": [\"composer build; touch pwned\"] } } }"
  code=0; run_in "$chained" --tier full || code=$?
  check 'a chained gate command is refused and never runs' "$([[ "$code" -eq 3 && ! -e "$chained/pwned" ]] && echo pass)"

  local branch="$tmp/branch"
  gate_selftest_project "$branch" "{ \"extra\": { \"ai-olympus\": { $base, $optin, \"gate\": [\"vendor/bin/gate-ok\"] } } }"
  printf '%s\n' "{ \"extra\": { \"ai-olympus\": { $base, \"gate\": [\"vendor/bin/pwn\"], \"gate-fresh\": [\"vendor/bin/pwn\"], \"gate-evidence\": \"elsewhere\" } } }" >"$branch/composer.json"
  git -C "$branch" -c user.name=t -c user.email=t@t commit -q -am 'branch proposes a manifest'
  code=0; run_in "$branch" --tier full || code=$?
  check 'a manifest only the branch carries changes nothing' \
    "$([[ "$code" -eq 0 && ! -e "$branch/pwned" && ! -e "$branch/elsewhere" && -n "$(ls "$branch/.claude/run/gates"/*.full.json)" ]] && echo pass)"

  local preload="$tmp/preload"
  gate_selftest_project "$preload" "{ \"extra\": { \"ai-olympus\": { $base, $optin, \"gate\": [\"vendor/bin/gate-ok\"], \"env\": { \"LD_PRELOAD\": \"evil.so\" } } } }"
  : >"$GATE_SELFTEST_CALLS"
  code=0; run_in "$preload" --tier full || code=$?
  check 'a manifest env that preloads a library runs nothing' "$([[ "$code" -eq 3 && "$(calls gate-ok)" -eq 0 ]] && echo pass)"

  local evidence value
  # The tilde is a literal payload, never a home directory to expand.
  # shellcheck disable=SC2088
  for value in '../x' '/tmp/x' 'a/../../x' '~/x'; do
    evidence="$tmp/evidence-$RANDOM"
    gate_selftest_project "$evidence" "{ \"extra\": { \"ai-olympus\": { $base, \"gate\": [\"vendor/bin/gate-ok\"], \"gate-evidence\": \"$value\" } } }"
    code=0; run_in "$evidence" --tier full || code=$?
    check "an evidence directory of $value is refused" "$([[ "$code" -eq 3 ]] && echo pass)"
  done

  local unignored="$tmp/unignored"
  gate_selftest_project "$unignored" "{ \"extra\": { \"ai-olympus\": { $base, \"gate\": [\"vendor/bin/gate-ok\"], \"gate-evidence\": \"records\" } } }"
  code=0; run_in "$unignored" --tier full || code=$?
  check 'an evidence directory outside gitignore is refused' "$([[ "$code" -eq 3 && ! -e "$unignored/records" ]] && echo pass)"

  local linked="$tmp/linked"
  gate_selftest_project "$linked" "{ \"extra\": { \"ai-olympus\": { $base, $optin, \"gate\": [\"vendor/bin/gate-ok\"] } } }"
  mkdir -p "$linked/.claude" "$tmp/outside"
  ln -s "$tmp/outside" "$linked/.claude/run"
  code=0; run_in "$linked" --tier full || code=$?
  check 'a symlinked evidence directory is refused' "$([[ "$code" -eq 3 && -z "$(ls -A "$tmp/outside")" ]] && echo pass)"

  # --- Usage ----------------------------------------------------------------------
  code=0; run_in "$project" --tier nightly || code=$?
  check 'an unknown tier is a usage error' "$([[ "$code" -eq 1 ]] && echo pass)"

  if [[ "$failures" -gt 0 ]]; then
    echo "run-gate self-test: $failures failure(s)" >&2
    return 4
  fi
  echo 'run-gate self-test: PASS'
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

run_gate "$@"
