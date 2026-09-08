#!/usr/bin/env bash
# transition-to-in-progress.sh — claim a JIRA issue for the authenticated acli
# user and move it to the project's In Progress status before work starts.
#
# Status transitions are otherwise human-only (rules/jira/general.md). This
# script is one of three sanctioned exceptions: it can ONLY land an issue in an
# In Progress (start-of-work) status. It structurally refuses any other target
# (Done, Closed, Review, …) so an AI agent cannot use it to push work through
# the board in unintended directions.
#
# Usage:
#   transition-to-in-progress.sh <KEY|URL> [<STATUS>]
#
# Inputs:
#   KEY|URL  Bare JIRA key (e.g. ACME-1234), a /browse/<KEY> URL, or any URL
#            containing ?selectedIssue=<KEY>.
#   STATUS   Optional exact target status name. Resolution order:
#              1. this argument
#              2. $JIRA_IN_PROGRESS_STATUS
#              3. default "In Progress"
#            Every project may name its in-progress column differently
#            (e.g. "In Progress", "In Development", "Doing"), so the
#            target is validated by the progress-name guard below rather than
#            hardcoded.
#
# Progress-name guard:
#   The target is accepted only when it case-insensitively contains "progress",
#   equals the built-in Czech name "Rozpracováno" (diacritics optional), OR is
#   listed in $JIRA_IN_PROGRESS_SYNONYMS (comma-separated). Anything else is
#   refused with exit 1 and the issue is left untouched.
#
# Behavior:
#   1. Normalise the KEY.
#   2. Validate the requested target against the progress-name guard.
#   3. Read the current status via load-issue.sh. If already in the target
#      status, continue only when currentUser() already owns it; otherwise abort
#      instead of stealing another run's claim.
#   4. If already in a status that is lexically past In Progress (contains
#      "review", "done", "closed", "resolved", "cancelled"), treat it as
#      claimed-by-another-run and exit 4 (caller should abort).
#   5. Run `acli jira workitem transition --key <KEY> --status <target> --yes`.
#   6. Run `acli jira workitem assign --key <KEY> --assignee "@me" --yes` and
#      verify it with JQL `key = <KEY> AND assignee = currentUser()`.
#
# acli cannot list a project's available transitions (see load-issue.sh "Known
# limitations"). When the transition fails because the target status does not
# exist in this project / is not reachable from the current status, the script
# exits 5 so the caller can discover the real in-progress status name via the
# JIRA MCP server (available next transitions), re-validate it against the
# guard, and re-run with the correct STATUS — or ask a human when it cannot be
# determined.
#
# Output:
#   The issue URL on stdout. `action=transitioned|noop` plus the resolved status
#   and `assignee=@me` on stderr.
#
# Exit codes:
#   1  usage / argument error, or refused target (not a progress status)
#   2  missing required tool (acli, jq)
#   3  JIRA API call failed (read, transition, assignment, or verification;
#      transition failures classified as 4/5 retain those exit codes)
#   4  issue is already past In Progress — treat as claimed-by-another, abort
#   5  target status not available in this project — discover via MCP / ask
set -euo pipefail

usage() {
  cat >&2 <<'EOF'
Usage: transition-to-in-progress.sh <KEY|URL> [<STATUS>]

  KEY     JIRA issue key (e.g. ACME-1234)
  URL     /browse/<KEY> URL or any URL containing ?selectedIssue=<KEY>
  STATUS  optional exact target status name (default: $JIRA_IN_PROGRESS_STATUS
          or "In Progress"); must be a progress status per the progress-name guard
EOF
}

if [[ $# -lt 1 || $# -gt 2 || -z "${1:-}" ]]; then
  usage
  exit 1
fi

for bin in acli jq; do
  if ! command -v "$bin" >/dev/null 2>&1; then
    echo "transition-to-in-progress.sh: required tool not found: $bin" >&2
    exit 2
  fi
done

INPUT="$1"
TARGET="${2:-${JIRA_IN_PROGRESS_STATUS:-In Progress}}"

KEY=""
if [[ "$INPUT" =~ ^[A-Z][A-Z0-9_]+-[0-9]+$ ]]; then
  KEY="$INPUT"
elif [[ "$INPUT" == *"/browse/"* ]]; then
  KEY="$(printf '%s' "$INPUT" | sed -nE 's#.*/browse/([A-Z][A-Z0-9_]+-[0-9]+).*#\1#p')"
elif [[ "$INPUT" == *"selectedIssue="* ]]; then
  KEY="$(printf '%s' "$INPUT" | sed -nE 's#.*selectedIssue=([A-Z][A-Z0-9_]+-[0-9]+).*#\1#p')"
fi

if [[ -z "$KEY" ]]; then
  echo "transition-to-in-progress.sh: could not extract JIRA key from input: $INPUT" >&2
  exit 1
fi

# Progress-name guard: accept only in-progress-ish targets. Substring "progress"
# covers the common cross-project names; the env list is the escape hatch for a
# project whose in-progress column has no "progress" in its name.
target_lower="$(printf '%s' "$TARGET" | tr '[:upper:]' '[:lower:]')"
is_progress=false
if [[ "$target_lower" == *progress* || "$target_lower" == "rozpracováno" || "$target_lower" == "rozpracovano" ]]; then
  is_progress=true
elif [[ -n "${JIRA_IN_PROGRESS_SYNONYMS:-}" ]]; then
  IFS=',' read -ra SYNONYMS <<<"$JIRA_IN_PROGRESS_SYNONYMS"
  for syn in "${SYNONYMS[@]}"; do
    syn_trimmed="$(printf '%s' "$syn" | sed -E 's#^[[:space:]]+|[[:space:]]+$##g' | tr '[:upper:]' '[:lower:]')"
    if [[ -n "$syn_trimmed" && "$target_lower" == "$syn_trimmed" ]]; then
      is_progress=true
      break
    fi
  done
fi

if [[ "$is_progress" != true ]]; then
  echo "transition-to-in-progress.sh: refused — '$TARGET' is not an In Progress status. This script only transitions to an in-progress (start-of-work) status; every other transition is human-only (rules/jira/general.md)." >&2
  exit 1
fi

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

assign_to_current_user() {
  local assignment_error assignment_status

  if ! assignment_error="$(acli jira workitem assign --key "$KEY" --assignee "@me" --yes --json 2>&1 >/dev/null)"; then
    echo "transition-to-in-progress.sh: could not assign $KEY to the current acli user: $assignment_error" >&2
    return 3
  fi

  if current_user_owns_issue; then
    return 0
  else
    assignment_status=$?
  fi

  if [[ "$assignment_status" -eq 3 ]]; then
    echo "transition-to-in-progress.sh: could not verify the current acli user assignment for $KEY" >&2
    return 3
  fi

  echo "transition-to-in-progress.sh: acli reported success but $KEY is not assigned to currentUser()" >&2
  return 3
}

current_user_owns_issue() {
  local assignment_json

  if ! assignment_json="$(acli jira workitem search --jql "key = $KEY AND assignee = currentUser()" --fields key --limit 1 --json 2>/dev/null)"; then
    return 3
  fi

  printf '%s' "$assignment_json" | jq -e --arg key "$KEY" '[.. | objects | .key? // empty] | index($key) != null' >/dev/null
}

# Read current status for the idempotence check and past-In-Progress guard.
if ! ISSUE_JSON="$("$SCRIPT_DIR/load-issue.sh" "$KEY")"; then
  echo "transition-to-in-progress.sh: failed to read current status of $KEY" >&2
  exit 3
fi
CURRENT_STATUS="$(printf '%s' "$ISSUE_JSON" | jq -r '.status // empty')"
SITE="$(printf '%s' "$ISSUE_JSON" | jq -r '.url // empty' | sed -nE 's#https?://([^/]+)/.*#\1#p')"
# Fall back to the authenticated acli site when the loaded JSON carries no URL,
# so the emitted link never degrades to a malformed https:///browse/<KEY>.
if [[ -z "$SITE" ]]; then
  SITE="$(acli jira auth status 2>/dev/null | awk -F': *' 'tolower($0) ~ /site:/ { gsub(/[[:space:]]+$/, "", $2); print $2; exit }')"
fi

# Idempotent no-op: already in the target status.
if [[ -n "$CURRENT_STATUS" && "$(printf '%s' "$CURRENT_STATUS" | tr '[:upper:]' '[:lower:]')" == "$target_lower" ]]; then
  if current_user_owns_issue; then
    echo "https://${SITE:-}/browse/${KEY}"
    echo "action=noop status=${CURRENT_STATUS} assignee=@me (already in progress)" >&2
    exit 0
  else
    ownership_status=$?
  fi

  if [[ "$ownership_status" -eq 3 ]]; then
    echo "transition-to-in-progress.sh: could not verify who owns the existing claim on $KEY" >&2
    exit 3
  fi

  echo "transition-to-in-progress.sh: $KEY is already in '${CURRENT_STATUS}' and is not assigned to currentUser() — claimed by another run; abort." >&2
  exit 4
fi

# Past-In-Progress guard: if the issue is already in a review/done/closed status,
# treat it as claimed-by-another-run so the caller can abort rather than re-transition.
current_lower="$(printf '%s' "${CURRENT_STATUS:-}" | tr '[:upper:]' '[:lower:]')"
is_past=false
for keyword in review 'done' closed resolved cancelled; do
  if [[ "$current_lower" == *"$keyword"* ]]; then
    is_past=true
    break
  fi
done

if [[ "$is_past" == true ]]; then
  echo "transition-to-in-progress.sh: $KEY is already in '${CURRENT_STATUS}' (past In Progress) — treat as claimed-by-another-run and abort." >&2
  exit 4
fi

# acli transitions by target status name. Capture stderr so a "status not
# available / not found" failure can be distinguished and surfaced as exit 5.
TRANSITION_ERR="$(acli jira workitem transition --key "$KEY" --status "$TARGET" --yes 2>&1 >/dev/null)" && TRANSITION_OK=true || TRANSITION_OK=false

# acli can return success for a "looped transition" that performs an action but
# keeps the current status, or match a transition that does not actually land in
# the requested target. Re-read the status and only report success when the
# issue genuinely reached the target — otherwise treat it as not-reachable (5)
# so the caller discovers the real in-progress status name instead of trusting a
# false positive.
if [[ "$TRANSITION_OK" == true ]]; then
  NEW_STATUS="$("$SCRIPT_DIR/load-issue.sh" "$KEY" 2>/dev/null | jq -r '.status // empty')"
  if [[ "$(printf '%s' "$NEW_STATUS" | tr '[:upper:]' '[:lower:]')" == "$target_lower" ]]; then
    assign_to_current_user
    echo "https://${SITE:-}/browse/${KEY}"
    echo "action=transitioned from=${CURRENT_STATUS:-?} to=${NEW_STATUS} assignee=@me" >&2
    exit 0
  fi
  echo "transition-to-in-progress.sh: acli reported success but $KEY is still '${NEW_STATUS:-?}', not '$TARGET' (likely a looped transition or a name mismatch)." >&2
  echo "transition-to-in-progress.sh: discover the real in-progress status via JIRA MCP (available next transitions), then re-run with it as STATUS, or ask a human." >&2
  exit 5
fi

if printf '%s' "$TRANSITION_ERR" | grep -qiE 'not (found|available|valid)|no transition|invalid|does not exist'; then
  echo "transition-to-in-progress.sh: status '$TARGET' is not available for $KEY (current: ${CURRENT_STATUS:-?})." >&2
  echo "transition-to-in-progress.sh: discover the real in-progress status via JIRA MCP (available next transitions), then re-run with it as STATUS, or ask a human." >&2
  exit 5
fi

echo "transition-to-in-progress.sh: acli transition failed for $KEY: $TRANSITION_ERR" >&2
exit 3
