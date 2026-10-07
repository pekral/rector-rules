#!/usr/bin/env bash
# The globals this library sets are read by the script that sources it.
# shellcheck disable=SC2034
# project-commands.sh — shared library: validate a project command and run it
# without a shell, under the environment the project manifest declares.
#
# Sourced, not executed. `run-validation.sh`, `run-gate.sh`, and `verify-gate.sh`
# all run commands an agent or a manifest names, and all three must refuse the
# same things the same way. Before this library each would have carried its own
# copy of the checks; a fix to one copy would not reach the others.
#
# What a caller gets
#   load_project_manifest   reads the default-branch manifest through
#                           read-manifest.sh, extends ALLOWED_EXECUTABLES with
#                           `validation.executables`, and exports the validated
#                           `env`. Sets PROJECT_MANIFEST (one line of JSON) and
#                           PROJECT_ENV. Returns 3 with PROJECT_REFUSAL set when
#                           an entry is refused — nothing is exported then.
#   validate_command <cmd>  prints the argv, one token per line, or returns 1
#                           with the reason on stderr.
#   run_command <cmd> <log> validates, then executes the argv directly and
#                           appends its output to <log>. Returns the command's
#                           exit status, or 126 when the command was refused.
#
# SECURITY — why a command is never handed to a shell
#   1. No shell. A command is split on whitespace into an argv array and
#      executed directly. There is no `eval`, no `sh -c`, and no command
#      substitution, so `;`, `|`, `&&`, `$(…)`, and backticks are characters in
#      an argument, never operators.
#   2. A character allow-list refuses a command that carries any of them anyway,
#      so an attempt is visible rather than merely harmless.
#   3. An executable allow-list: the first token must name a project-local tool
#      below, or a `vendor/bin/<name>` the default-branch manifest adds.
set -euo pipefail

: "${PROG:=${0##*/}}"

PROJECT_COMMANDS_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

# Executables a command may name. Everything here is a project-local developer
# tool. Anything that writes outside the project, talks to the network on its
# own, or manipulates history is deliberately absent.
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

# Characters that have meaning to a shell. No shell is ever invoked, so these
# are already inert — the check refuses a command that carries them loudly
# instead of running it with them as literal argument text.
SHELL_METACHARACTERS=';|&$`(){}<>*?!#'

PROJECT_MANIFEST='{}'
PROJECT_ENV=()
PROJECT_REFUSAL=''

safe_display() {
  printf '%s' "$1" | LC_ALL=C tr -cd '[:print:]' | cut -c1-200
}

# Validate one command string and echo its argv, one token per line.
#
# Returns 1 with a reason on stderr when the command is refused. A caller turns
# that into a refusal of the whole run: a list carrying one unacceptable command
# is not partially trustworthy.
validate_command() {
  local command="$1" executable allowed found=0

  [[ -n "$command" ]] || { echo 'empty command' >&2; return 1; }

  case "$command" in
  *$'\n'* | *$'\r'*) echo 'command contains a newline' >&2; return 1 ;;
  esac

  # A quote would only matter to a shell; the split is on whitespace, so a
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

  # No leading `-`: a first token that looks like an option means the command
  # is malformed, and passing it on would let it be read as an option.
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

# Validate a command, then execute its argv directly and append the output to
# the log. The only place a project command is executed.
run_command() {
  local command="$1" log="$2" token status=0
  local -a argv=()

  if ! validate_command "$command" >/dev/null 2>&1; then
    return 126
  fi

  while IFS= read -r token; do
    argv+=("$token")
  done < <(validate_command "$command")

  # `|| status=$?` rather than toggling `set -e`: a function that re-enables
  # errexit changes the caller's shell too, and the caller's own `set +e`
  # around this call would stop protecting it.
  "${argv[@]}" >>"$log" 2>&1 || status=$?

  return "$status"
}

# Extend the executable allow-list and the environment from the project
# manifest. Every entry is checked before any command runs; one unacceptable
# entry refuses the run.
load_project_manifest() {
  local reader project entry
  reader="$PROJECT_COMMANDS_DIR/read-manifest.sh"
  [[ -f "$reader" ]] || return 0
  project="$(bash "$reader" 2>/dev/null)" || project='{}'
  PROJECT_MANIFEST="$project"

  if ! printf '%s' "$project" | jq -e '(.validation // {}) | type == "object" and ((.executables // []) | type == "array")' >/dev/null 2>&1; then
    PROJECT_REFUSAL='project manifest: validation.executables must be an array'
    return 3
  fi
  while IFS= read -r entry; do
    if [[ ! "$entry" =~ ^vendor/bin/[A-Za-z0-9_][A-Za-z0-9._-]*$ ]]; then
      PROJECT_REFUSAL="project manifest: a validation executable must be a vendor/bin/<name> path — $(safe_display "$entry")"
      return 3
    fi
    ALLOWED_EXECUTABLES+=("$entry")
  done < <(printf '%s' "$project" | jq -r '(.validation // {}).executables // [] | .[] | tostring')

  local env_lines env_status=0 reason
  env_lines="$(bash "$reader" --env 2>/dev/null)" || env_status=$?
  if [[ "$env_status" -eq 4 ]]; then
    reason="$(bash "$reader" --env 2>&1 >/dev/null || true)"
    PROJECT_REFUSAL="project manifest: $(safe_display "${reason#*: }")"
    return 3
  fi
  [[ "$env_status" -eq 0 ]] || return 0

  while IFS= read -r entry; do
    [[ -n "$entry" ]] || continue
    export "${entry?}"
    PROJECT_ENV+=("$entry")
  done <<<"$env_lines"
  return 0
}
