#!/usr/bin/env bash
# The globals this library sets are read by the script that sources it.
# shellcheck disable=SC2034
# gate-record.sh — shared library for the machine record of a quality-gate run.
#
# Sourced, not executed, by `run-gate.sh` (writes a record) and `verify-gate.sh`
# (accepts or rejects one). Both must agree on where a record lives, what makes
# it valid, and which commands run fresh, so that logic exists here once. The
# command checks and the executor come from project-commands.sh.
#
# TRUST MODEL — what a record proves, and what it does not
#   A record is a LOCAL CACHE on one machine and one account. It is keyed to the
#   git TREE the gate ran on, so a rebase, squash, or amend that keeps the bytes
#   keeps the record, and any other tree has none.
#   - A public commenter cannot write it. Against that threat it is stronger
#     than the textual `Quality gate:` line in a review comment.
#   - The code the gate runs (tests, Composer scripts from the branch) runs under
#     the same account and can write any file, a forged record included. It can
#     do the same today by making its own gate pass. The defence against hostile
#     branch code is code review, required CI, and a fresh `gate-fresh` run —
#     never this record.
#   - The SHA-256 of the log detects a damaged or swapped log. It does not prove
#     that the log is authentic.
#   - A record is valid only on the machine that wrote it. Elsewhere it is
#     missing, and the gate runs again.
#   - The copy of this library, project-commands.sh, run-gate.sh, and
#     verify-gate.sh that runs is the one the installer wrote from
#     vendor/pekral/ai-olympus. A diff over that installed copy is a merge-gate
#     change: Critical under rules/security/general.md *Code Review Application*.
#
# Where a record lives
#   <evidence>/<tree>.<tier>.json   the record
#   <evidence>/<tree>.<tier>.log    the full gate output
#   <evidence>/gate.lock/           the run lock (an atomic `mkdir`, never flock)
#   <evidence> is the manifest `gate-evidence`, default `.claude/run/gates`. It
#   must be relative, git-ignored, free of tracked files, and free of symlinks.
#   A file name is built only from the tree `git rev-parse` returned and the
#   tier; no value read from a record ever enters a path.
set -euo pipefail

: "${PROG:=${0##*/}}"

GATE_LIB_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=project-commands.sh
. "$GATE_LIB_DIR/project-commands.sh"

GATE_DEFAULT_EVIDENCE='.claude/run/gates'
GATE_REASON=''
GATE_EVIDENCE=''
GATE_TIER_COMMANDS=()
GATE_FRESH_COMMANDS=()
GATE_FRESH_RESULTS='[]'
GATE_FRESH_LOG=''
GATE_LOCK=''
GATE_LOCK_HELD=0

gate_tier_key() {
  case "$1" in
  full) printf 'gate' ;;
  pr) printf 'pr-gate' ;;
  *) return 1 ;;
  esac
}

gate_is_tree() {
  [[ "$1" =~ ^[0-9a-f]{40}([0-9a-f]{24})?$ ]]
}

gate_sha256() {
  local file="$1" sum
  if command -v sha256sum >/dev/null 2>&1; then
    sum="$(sha256sum -- "$file" | cut -d' ' -f1)"
  else
    sum="$(shasum -a 256 -- "$file" | cut -d' ' -f1)"
  fi
  [[ "$sum" =~ ^[0-9a-f]{64}$ ]] || return 1
  printf '%s' "$sum"
}

gate_now() {
  date -u +%Y-%m-%dT%H:%M:%SZ
}

# Read the tier's commands and the fresh commands from the default-branch
# manifest (PROJECT_MANIFEST, loaded by load_project_manifest), and validate all
# of them before anything runs.
#   returns 5  the manifest sets no command for this tier, or none of the record
#              keys — the built-in path applies
#   returns 3  a key is malformed or a command is refused (GATE_REASON says which)
gate_load_commands() {
  local tier="$1" key command reason
  key="$(gate_tier_key "$tier")"
  GATE_TIER_COMMANDS=()
  GATE_FRESH_COMMANDS=()

  if ! printf '%s' "$PROJECT_MANIFEST" | jq -e --arg k "$key" '(.[$k] // []) | type == "array" and all(.[]; type == "string")' >/dev/null 2>&1; then
    GATE_REASON="project manifest: $key must be an array of strings"
    return 3
  fi
  if ! printf '%s' "$PROJECT_MANIFEST" | jq -e '(.["gate-fresh"] // []) | type == "array" and all(.[]; type == "string")' >/dev/null 2>&1; then
    GATE_REASON='project manifest: gate-fresh must be an array of strings'
    return 3
  fi

  while IFS= read -r command; do
    GATE_TIER_COMMANDS+=("$command")
  done < <(printf '%s' "$PROJECT_MANIFEST" | jq -r --arg k "$key" '(.[$k] // [])[]')

  if [[ "${#GATE_TIER_COMMANDS[@]}" -eq 0 ]]; then
    GATE_REASON="project manifest sets no $key — the built-in gate path applies"
    return 5
  fi

  # The machine record is opt-in: a project that sets none of the three record
  # keys keeps the built-in gate path exactly as before they existed, even when
  # it already sets `gate`.
  if ! printf '%s' "$PROJECT_MANIFEST" | jq -e 'has("pr-gate") or has("gate-fresh") or has("gate-evidence")' >/dev/null 2>&1; then
    GATE_REASON='project manifest sets none of pr-gate, gate-fresh, gate-evidence — the built-in gate path applies'
    return 5
  fi

  while IFS= read -r command; do
    GATE_FRESH_COMMANDS+=("$command")
  done < <(printf '%s' "$PROJECT_MANIFEST" | jq -r '(.["gate-fresh"] // [])[]')

  # A missing or empty `gate-fresh` is never "audit nothing": the dependency
  # advisory audit keeps running fresh, as it did before the key existed. With
  # no composer.lock there is no Composer dependency set to audit.
  if [[ "${#GATE_FRESH_COMMANDS[@]}" -eq 0 && -f composer.lock ]]; then
    GATE_FRESH_COMMANDS=('composer audit')
  fi

  for command in "${GATE_TIER_COMMANDS[@]}" ${GATE_FRESH_COMMANDS[@]+"${GATE_FRESH_COMMANDS[@]}"}; do
    if ! reason="$(validate_command "$command" 2>&1 >/dev/null)"; then
      GATE_REASON="refused command: $(safe_display "$reason") — $(safe_display "$command")"
      return 3
    fi
  done
  return 0
}

# Refuse a path when any of its components is a symlink. Checked before every
# write and every read, so a link planted in the tree cannot redirect either.
gate_no_symlink() {
  local path="$1" prefix="" part
  local IFS='/'
  for part in $path; do
    [[ -n "$part" ]] || continue
    prefix="${prefix:+$prefix/}$part"
    if [[ -L "$prefix" ]]; then
      GATE_REASON="refused: $(safe_display "$prefix") is a symlink"
      return 3
    fi
  done
  return 0
}

# Resolve and check the evidence directory. With `write`, create it 0700.
#   returns 3 with GATE_REASON when the directory is not acceptable
gate_evidence_dir() {
  local mode="$1" dir probe
  if ! printf '%s' "$PROJECT_MANIFEST" | jq -e '(.["gate-evidence"] // "") | type == "string"' >/dev/null 2>&1; then
    GATE_REASON='project manifest: gate-evidence must be a string'
    return 3
  fi
  dir="$(printf '%s' "$PROJECT_MANIFEST" | jq -r '.["gate-evidence"] // ""')"
  [[ -n "$dir" ]] || dir="$GATE_DEFAULT_EVIDENCE"
  dir="${dir%/}"

  if [[ ! "$dir" =~ ^[A-Za-z0-9._/-]+$ || "$dir" == /* || "$dir" == '..' || "$dir" == ../* || "$dir" == */.. || "$dir" == */../* ]]; then
    GATE_REASON="refused: gate-evidence must be a relative path inside the project — $(safe_display "$dir")"
    return 3
  fi

  gate_no_symlink "$dir" || return 3

  # Every path the scripts write must be ignored, so a record never dirties the
  # tree it describes and a branch can never commit one.
  for probe in "$dir/0.full.json" "$dir/0.full.log" "$dir/gate.lock/holder"; do
    if ! git check-ignore -q -- "$probe" 2>/dev/null; then
      GATE_REASON="refused: $(safe_display "$dir") is not git-ignored — add it to .gitignore"
      return 3
    fi
  done
  if [[ -n "$(git ls-files -- "$dir" 2>/dev/null)" ]]; then
    GATE_REASON="refused: $(safe_display "$dir") contains a tracked file"
    return 3
  fi

  if [[ "$mode" == "write" ]]; then
    (umask 077 && mkdir -p -- "$dir")
    gate_no_symlink "$dir" || return 3
    # BSD chmod (macOS) reads a `--` after the mode as a file name. $dir is
    # validated relative above, and the `./` prefix keeps it from reading as an option.
    chmod 700 "./$dir"
  fi

  GATE_EVIDENCE="$dir"
  return 0
}

# The environment the gate's verdict depends on beyond the tree: the PHP
# version, the lockfiles in the working tree (some projects do not track them),
# and the manifest `env`. Hashes and a version string only — never a value of
# any other variable.
gate_fingerprint() {
  local php_version='none' file sum lockfiles='{}' env_sum='none'
  if command -v php >/dev/null 2>&1; then
    php_version="$(php -r 'echo PHP_VERSION;' 2>/dev/null || true)"
    [[ "$php_version" =~ ^[0-9A-Za-z.+-]{1,40}$ ]] || php_version='unknown'
  fi
  for file in composer.lock package-lock.json yarn.lock pnpm-lock.yaml; do
    [[ -f "$file" && ! -L "$file" ]] || continue
    sum="$(gate_sha256 "$file")" || sum='unreadable'
    lockfiles="$(printf '%s' "$lockfiles" | jq -c --arg f "$file" --arg s "$sum" '. + {($f): $s}')"
  done
  if [[ "${#PROJECT_ENV[@]}" -gt 0 ]]; then
    env_sum="$(printf '%s\n' "${PROJECT_ENV[@]}" | gate_sha256 -)" || env_sum='unreadable'
  fi
  jq -cnS --arg php "$php_version" --argjson lockfiles "$lockfiles" --arg env "$env_sum" \
    '{php: $php, lockfiles: $lockfiles, manifest_env: $env}'
}

# The one acceptance test for a record. `verify-gate.sh` calls it, and so does
# `run-gate.sh` before it takes a finished run's result over — a second test
# would be a second definition of "valid".
#   returns 0 valid, 10 missing, 11 failed, 12 stale or unusable; GATE_REASON says why
gate_check_record() {
  local tier="$1" tree="$2" record log expected_commands fingerprint field
  record="$GATE_EVIDENCE/$tree.$tier.json"
  log="$GATE_EVIDENCE/$tree.$tier.log"

  gate_no_symlink "$record" || return 12
  gate_no_symlink "$log" || return 12

  if [[ ! -e "$record" ]]; then
    GATE_REASON="missing: no $tier record for tree $tree"
    return 10
  fi

  # Fail closed: every field is read through jq by a fixed name and checked
  # against its shape. Nothing in a record is sourced, evaluated, or executed.
  for field in \
    '.schema == 1' \
    '.tier | type == "string"' \
    '.tree | type == "string" and test("^[0-9a-f]{40}([0-9a-f]{24})?$")' \
    '.head | type == "string" and test("^[0-9a-f]{40}([0-9a-f]{24})?$")' \
    '.merge_base | type == "string" and test("^([0-9a-f]{40}([0-9a-f]{24})?)?$")' \
    '.commands | type == "array" and length > 0 and all(.[]; (.command | type == "string") and (.exit_code | type == "number") and (.duration_seconds | type == "number"))' \
    '.environment | type == "object"' \
    '.actor | type == "string" and test("^[A-Za-z0-9._-]{1,64}$")' \
    '.started_at | type == "string" and test("^[0-9]{4}-[0-9]{2}-[0-9]{2}T[0-9]{2}:[0-9]{2}:[0-9]{2}Z$")' \
    '.finished_at | type == "string" and test("^[0-9]{4}-[0-9]{2}-[0-9]{2}T[0-9]{2}:[0-9]{2}:[0-9]{2}Z$")' \
    '.duration_seconds | type == "number"' \
    '.exit_code | type == "number"' \
    '.log_sha256 | type == "string" and test("^[0-9a-f]{64}$")'; do
    if ! jq -e "$field" "$record" >/dev/null 2>&1; then
      GATE_REASON="stale: the record is unreadable or fails the check $field"
      return 12
    fi
  done

  if ! jq -e --arg tier "$tier" --arg tree "$tree" '.tier == $tier and .tree == $tree' "$record" >/dev/null 2>&1; then
    GATE_REASON="stale: the record does not describe the $tier gate on tree $tree"
    return 12
  fi

  # A failed run stops at the first failing command, so its record lists only a
  # prefix of the commands. That prefix is still this gate: the exit_code check
  # below then reports the record as failed, never as stale. A passing record
  # must list every command.
  expected_commands="$(printf '%s\n' "${GATE_TIER_COMMANDS[@]}" | jq -Rsc 'split("\n") | map(select(length > 0))')"
  if ! jq -e --argjson c "$expected_commands" \
    '[.commands[].command] as $r | $r == $c or (.exit_code != 0 and ($r | length) < ($c | length) and $r == $c[0:($r | length)])' \
    "$record" >/dev/null 2>&1; then
    GATE_REASON='stale: the gate commands differ from the default-branch manifest'
    return 12
  fi

  fingerprint="$(gate_fingerprint)"
  if ! jq -e --argjson f "$fingerprint" '.environment == $f' "$record" >/dev/null 2>&1; then
    GATE_REASON='stale: the environment fingerprint differs (PHP version, a lockfile, or the manifest env)'
    return 12
  fi

  if [[ ! -f "$log" ]] || ! jq -e --arg s "$(gate_sha256 "$log" || true)" '.log_sha256 == $s' "$record" >/dev/null 2>&1; then
    GATE_REASON='stale: the log is missing or does not match the hash in the record'
    return 12
  fi

  if ! jq -e '.exit_code == 0 and all(.commands[]; .exit_code == 0)' "$record" >/dev/null 2>&1; then
    GATE_REASON="failed: the recorded $tier gate on tree $tree did not pass"
    return 11
  fi

  GATE_REASON="valid: the $tier gate passed on tree $tree"
  return 0
}

# Run every `gate-fresh` command now. Their verdict depends on when they run
# (an advisory database changes), so it is never written to a record and never
# read from one.
#   returns 0 every fresh command passed, 11 one failed
gate_run_fresh() {
  local tier="$1" tree="$2" command status tmp
  GATE_FRESH_RESULTS='[]'
  GATE_FRESH_LOG=''
  [[ "${#GATE_FRESH_COMMANDS[@]}" -gt 0 ]] || return 0

  GATE_FRESH_LOG="$GATE_EVIDENCE/$tree.$tier.fresh.log"
  gate_no_symlink "$GATE_FRESH_LOG" || return 11
  tmp="$(umask 077 && mktemp "$GATE_EVIDENCE/.fresh.XXXXXX")"
  GATE_TEMP_FILES+=("$tmp")

  local failed=0
  for command in "${GATE_FRESH_COMMANDS[@]}"; do
    printf '### %s\n' "$command" >>"$tmp"
    status=0
    run_command "$command" "$tmp" || status=$?
    printf '### exit %s\n' "$status" >>"$tmp"
    GATE_FRESH_RESULTS="$(printf '%s' "$GATE_FRESH_RESULTS" | jq -c --arg c "$command" --argjson e "$status" '. + [{command: $c, exit_code: $e}]')"
    if [[ "$status" -ne 0 && "$failed" -eq 0 ]]; then
      failed=1
      GATE_REASON="failed: gate-fresh command exited $status — $(safe_display "$command")"
    fi
  done
  mv -f -- "$tmp" "$GATE_FRESH_LOG"

  [[ "$failed" -eq 0 ]] || return 11
  return 0
}

GATE_TEMP_FILES=()

gate_cleanup() {
  local file
  for file in ${GATE_TEMP_FILES[@]+"${GATE_TEMP_FILES[@]}"}; do
    rm -f -- "$file"
  done
  if [[ "$GATE_LOCK_HELD" -eq 1 && -n "$GATE_LOCK" ]]; then
    rm -rf -- "$GATE_LOCK"
    GATE_LOCK_HELD=0
  fi
  return 0
}

# `ps -o etime=` prints [[dd-]hh:]mm:ss.
gate_etime_seconds() {
  local etime="${1//[[:space:]]/}"
  [[ "$etime" =~ ^(([0-9]+)-)?(([0-9]+):)?([0-9]+):([0-9]+)$ ]] || return 1
  printf '%s' $((10#${BASH_REMATCH[2]:-0} * 86400 + 10#${BASH_REMATCH[4]:-0} * 3600 + 10#${BASH_REMATCH[5]} * 60 + 10#${BASH_REMATCH[6]}))
}

# The holder of a lock is gone when its PID is confirmed dead, or when the PID
# now belongs to a process that started after the lock was written (recycled).
# Anything inconclusive counts as a live holder: reclaiming a live run's lock
# would let two gates corrupt one test database.
gate_lock_is_stale() {
  local holder="$GATE_LOCK/holder" pid started probe etime elapsed now
  [[ -f "$holder" && ! -L "$holder" ]] || return 1
  pid="$(sed -n 's/^PID=\([0-9]\{1,7\}\)$/\1/p' "$holder" | head -1)"
  started="$(sed -n 's/^STARTED_EPOCH=\([0-9]\{1,12\}\)$/\1/p' "$holder" | head -1)"
  [[ -n "$pid" ]] || return 1

  if ! probe="$(LC_ALL=C kill -0 "$pid" 2>&1)"; then
    [[ "$probe" == *'not permitted'* ]] && return 1
    return 0
  fi

  [[ -n "$started" ]] || return 1
  etime="$(ps -o etime= -p "$pid" 2>/dev/null || true)"
  elapsed="$(gate_etime_seconds "$etime")" || return 1
  now="$(date +%s)"
  # A process cannot have written a timestamp before it existed; 60 s absorbs skew.
  [[ $((now - elapsed)) -gt $((started + 60)) ]]
}

# Take the gate lock: an atomic `mkdir`, a holder file, and a stale reclaim on
# confirmed death only (@rules/compound-engineering/concurrency.md). `flock(1)`
# does not exist on macOS, so it is not used.
#   returns 6 when a live holder keeps the lock past the timeout
gate_lock_acquire() {
  local timeout="$1" waited=0
  GATE_LOCK="$GATE_EVIDENCE/gate.lock"
  gate_no_symlink "$GATE_LOCK" || return 3

  until (umask 077 && mkdir -- "$GATE_LOCK") 2>/dev/null; do
    if gate_lock_is_stale; then
      rm -rf -- "$GATE_LOCK"
      continue
    fi
    if [[ "$waited" -ge "$timeout" ]]; then
      GATE_REASON="locked: another gate run holds $(safe_display "$GATE_LOCK") — it was not reclaimed because its holder is alive or unproven dead"
      return 6
    fi
    sleep 1
    waited=$((waited + 1))
  done

  GATE_LOCK_HELD=1
  # This script's own PID: the script, not a per-call subshell, holds the lock
  # for exactly as long as the run lasts.
  printf 'PID=%s\nSTARTED=%s\nSTARTED_EPOCH=%s\n' "$$" "$(gate_now)" "$(date +%s)" >"$GATE_LOCK/holder"
  return 0
}

gate_tree_of() {
  local tree
  tree="$(git rev-parse --verify --quiet "$1^{tree}" 2>/dev/null)" || return 1
  gate_is_tree "$tree" || return 1
  printf '%s' "$tree"
}

# --- self-test fixtures, shared by both scripts' --self-test ------------------

# A throwaway project: a git repository whose default branch carries the given
# manifest, with stub tools in vendor/bin that append their name to
# $GATE_SELFTEST_CALLS so a test can count what ran.
gate_selftest_project() {
  local dir="$1" manifest="$2"
  mkdir -p "$dir/vendor/bin"
  cat >"$dir/vendor/bin/gate-ok" <<'STUB'
#!/usr/bin/env bash
echo "gate-ok ${*:-}" >>"$GATE_SELFTEST_CALLS"
[[ -n "${GATE_SELFTEST_SLEEP:-}" ]] && sleep "$GATE_SELFTEST_SLEEP"
echo "gate output"
exit 0
STUB
  cat >"$dir/vendor/bin/gate-fail" <<'STUB'
#!/usr/bin/env bash
echo "gate-fail" >>"$GATE_SELFTEST_CALLS"
exit 3
STUB
  cat >"$dir/vendor/bin/gate-dirty" <<'STUB'
#!/usr/bin/env bash
echo "gate-dirty" >>"$GATE_SELFTEST_CALLS"
echo "changed" >>tracked.txt
STUB
  cat >"$dir/vendor/bin/gate-kill" <<'STUB'
#!/usr/bin/env bash
echo "gate-kill" >>"$GATE_SELFTEST_CALLS"
kill -TERM "$PPID"
STUB
  cat >"$dir/vendor/bin/fresh-ok" <<'STUB'
#!/usr/bin/env bash
echo "fresh-ok" >>"$GATE_SELFTEST_CALLS"
STUB
  cat >"$dir/vendor/bin/fresh-fail" <<'STUB'
#!/usr/bin/env bash
echo "fresh-fail" >>"$GATE_SELFTEST_CALLS"
exit 1
STUB
  cat >"$dir/vendor/bin/pwn" <<'STUB'
#!/usr/bin/env bash
touch pwned
STUB
  chmod +x "$dir"/vendor/bin/*
  printf '/.claude/run/\n/elsewhere/\n/composer.lock\n' >"$dir/.gitignore"
  printf 'tracked\n' >"$dir/tracked.txt"
  printf '%s\n' "$manifest" >"$dir/composer.json"
  git -C "$dir" init -q
  git -C "$dir" add -A
  git -C "$dir" -c user.name=t -c user.email=t@t commit -q -m init
  git -C "$dir" update-ref refs/remotes/origin/master HEAD
}

# Replace the default-branch manifest without touching the working tree.
gate_selftest_manifest() {
  local dir="$1" manifest="$2" blob tree commit index
  index="$dir/.git/selftest-index"
  blob="$(printf '%s\n' "$manifest" | git -C "$dir" hash-object -w --stdin)"
  GIT_INDEX_FILE="$index" git -C "$dir" read-tree origin/master
  GIT_INDEX_FILE="$index" git -C "$dir" update-index --cacheinfo "100644,$blob,composer.json"
  tree="$(GIT_INDEX_FILE="$index" git -C "$dir" write-tree)"
  rm -f "$index"
  commit="$(git -C "$dir" -c user.name=t -c user.email=t@t commit-tree "$tree" -p origin/master -m manifest)"
  git -C "$dir" update-ref refs/remotes/origin/master "$commit"
}

# GNU first: GNU `stat -f` reports the file system and succeeds, so it would
# hide the fallback. BSD `stat -c` fails, so the BSD form then runs.
gate_selftest_mode() {
  stat -c %a "$1" 2>/dev/null || stat -f %Lp "$1"
}
