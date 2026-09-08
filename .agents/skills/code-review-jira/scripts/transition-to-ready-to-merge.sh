#!/usr/bin/env bash
# transition-to-ready-to-merge.sh — move a JIRA issue to the project's Ready to
# Merge status when the code review converges, and nothing else.
#
# Status transitions are otherwise human-only (rules/jira/general.md). This
# script is the third sanctioned exception: it can ONLY land an issue in a
# ready-to-merge status. It structurally refuses any other target (Done, In
# Progress, Code Review, Closed, Merged, …) so an AI agent cannot use it to push
# work through the board.
#
# This is phase 3 of rules/compound-engineering/general.md *Tracker status
# tracks the phase of work*. It says the review converged and the work waits on
# a merge — it never merges anything and never closes anything.
#
# Usage:
#   transition-to-ready-to-merge.sh <KEY|URL> [<STATUS>]
#
# Inputs:
#   KEY|URL  Bare JIRA key (e.g. ACME-1234), a /browse/<KEY> URL, or any URL
#            containing ?selectedIssue=<KEY>.
#   STATUS   Optional exact target status name. Resolution order:
#              1. this argument
#              2. $JIRA_READY_TO_MERGE_STATUS
#              3. default "Ready to Merge"
#            Every project may name this column differently (e.g. "Ready to
#            Merge", "Ready for merge", "Approved / mergeable"), so the target
#            is validated by the merge-name guard below rather than hardcoded.
#
# Merge-name guard:
#   The target is accepted only when it case-insensitively contains "merge" OR
#   is listed in $JIRA_READY_TO_MERGE_SYNONYMS (comma-separated). Anything else
#   is refused with exit 1 and the issue is left untouched.
#
# Resolution deny check:
#   "merge" is also a substring of the terminal columns many boards use
#   ("Merged", "Merged to master", "Done - merged"), and a phase write is never
#   a resolution write. A second check therefore refuses every target naming a
#   resolution state. It runs AFTER the accept check, so a
#   $JIRA_READY_TO_MERGE_SYNONYMS entry cannot re-open the hole either.
#   "Ready to Merge" and "Ready for merge" still pass; "Merged" does not.
#
# Behavior:
#   1. Normalise the KEY.
#   2. Validate the requested target against the merge-name guard, then refuse
#      it when it names a resolution state.
#   3. Read the current status via load-issue.sh. If already in the target
#      status, no-op (idempotent) and exit 0.
#   4. Run `acli jira workitem transition --key <KEY> --status <target> --yes`.
#
# Reverting this transition when a later commit re-opens the review is NOT this
# script's job: the revert direction is a move back to the review column, and
# transition-to-code-review.sh already performs it as an existing sanctioned
# transition. No new capability is added for the revert.
#
# acli cannot list a project's available transitions (see load-issue.sh "Known
# limitations"). When the transition fails because the target status does not
# exist in this project / is not reachable from the current status, the script
# exits 5 so the caller can discover the real ready-to-merge status name via the
# JIRA MCP server (available next transitions), re-validate it against the
# guard, and re-run with the correct STATUS — or ask a human when it cannot be
# determined.
#
# Output:
#   The issue URL on stdout. `action=transitioned|noop` plus the resolved status
#   on stderr.
#
# Exit codes:
#   1  usage / argument error, or refused target (not a ready-to-merge status,
#      or a resolution status)
#   2  missing required tool (acli, jq)
#   3  JIRA API call failed (read or transition, for reasons other than 5)
#   5  target status not available in this project — discover via MCP / ask
set -euo pipefail

usage() {
  cat >&2 <<'EOF'
Usage: transition-to-ready-to-merge.sh <KEY|URL> [<STATUS>]

  KEY     JIRA issue key (e.g. ACME-1234)
  URL     /browse/<KEY> URL or any URL containing ?selectedIssue=<KEY>
  STATUS  optional exact target status name (default: $JIRA_READY_TO_MERGE_STATUS
          or "Ready to Merge"); must be a ready-to-merge status per the merge-name
          guard, and never a resolution status ("Merged", "Done - merged", …)
EOF
}

if [[ $# -lt 1 || $# -gt 2 || -z "${1:-}" ]]; then
  usage
  exit 1
fi

for bin in acli jq; do
  if ! command -v "$bin" >/dev/null 2>&1; then
    echo "transition-to-ready-to-merge.sh: required tool not found: $bin" >&2
    exit 2
  fi
done

INPUT="$1"
TARGET="${2:-${JIRA_READY_TO_MERGE_STATUS:-Ready to Merge}}"

KEY=""
if [[ "$INPUT" =~ ^[A-Z][A-Z0-9_]+-[0-9]+$ ]]; then
  KEY="$INPUT"
elif [[ "$INPUT" == *"/browse/"* ]]; then
  KEY="$(printf '%s' "$INPUT" | sed -nE 's#.*/browse/([A-Z][A-Z0-9_]+-[0-9]+).*#\1#p')"
elif [[ "$INPUT" == *"selectedIssue="* ]]; then
  KEY="$(printf '%s' "$INPUT" | sed -nE 's#.*selectedIssue=([A-Z][A-Z0-9_]+-[0-9]+).*#\1#p')"
fi

if [[ -z "$KEY" ]]; then
  echo "transition-to-ready-to-merge.sh: could not extract JIRA key from input: $INPUT" >&2
  exit 1
fi

# Merge-name guard: accept only ready-to-merge-ish targets. Substring "merge"
# covers the common cross-project names; the env list is the escape hatch for a
# project whose ready-to-merge column has no "merge" in its name.
target_lower="$(printf '%s' "$TARGET" | tr '[:upper:]' '[:lower:]')"
is_ready_to_merge=false
if [[ "$target_lower" == *merge* ]]; then
  is_ready_to_merge=true
elif [[ -n "${JIRA_READY_TO_MERGE_SYNONYMS:-}" ]]; then
  IFS=',' read -ra SYNONYMS <<<"$JIRA_READY_TO_MERGE_SYNONYMS"
  for syn in "${SYNONYMS[@]}"; do
    syn_trimmed="$(printf '%s' "$syn" | sed -E 's#^[[:space:]]+|[[:space:]]+$##g' | tr '[:upper:]' '[:lower:]')"
    if [[ -n "$syn_trimmed" && "$target_lower" == "$syn_trimmed" ]]; then
      is_ready_to_merge=true
      break
    fi
  done
fi

if [[ "$is_ready_to_merge" != true ]]; then
  echo "transition-to-ready-to-merge.sh: refused — '$TARGET' is not a Ready to Merge status. This script only transitions to a ready-to-merge status; every other transition is human-only (rules/jira/general.md)." >&2
  exit 1
fi

# Resolution deny check. Runs after the accept check so it also overrides a
# JIRA_READY_TO_MERGE_SYNONYMS entry: a phase write is never a resolution write,
# and "merge" is a substring of the terminal column names many boards use
# ("Merged", "Merged to master", "Done - merged"). "Ready to Merge" and "Ready
# for merge" carry "merge", not "merged", so they still pass.
if [[ "$target_lower" =~ (^|[^a-z])(done|closed|resolved|completed?|fixed|merged)([^a-z]|$) ]]; then
  echo "transition-to-ready-to-merge.sh: refused — '$TARGET' names a resolution status. Phase 3 says the work is ready to merge; closing or merging stays human-only (rules/jira/general.md)." >&2
  exit 1
fi

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

# Read current status for the idempotence check.
if ! ISSUE_JSON="$("$SCRIPT_DIR/load-issue.sh" "$KEY")"; then
  echo "transition-to-ready-to-merge.sh: failed to read current status of $KEY" >&2
  exit 3
fi
CURRENT_STATUS="$(printf '%s' "$ISSUE_JSON" | jq -r '.status // empty')"
SITE="$(printf '%s' "$ISSUE_JSON" | jq -r '.url // empty' | sed -nE 's#https?://([^/]+)/.*#\1#p')"
# Fall back to the authenticated acli site when the loaded JSON carries no URL,
# so the emitted link never degrades to a malformed https:///browse/<KEY>.
if [[ -z "$SITE" ]]; then
  SITE="$(acli jira auth status 2>/dev/null | awk -F': *' 'tolower($0) ~ /site:/ { gsub(/[[:space:]]+$/, "", $2); print $2; exit }')"
fi

if [[ -n "$CURRENT_STATUS" && "$(printf '%s' "$CURRENT_STATUS" | tr '[:upper:]' '[:lower:]')" == "$target_lower" ]]; then
  echo "https://${SITE:-}/browse/${KEY}"
  echo "action=noop status=${CURRENT_STATUS} (already ready to merge)" >&2
  exit 0
fi

# acli transitions by target status name. Capture stderr so a "status not
# available / not found" failure can be distinguished and surfaced as exit 5.
TRANSITION_ERR="$(acli jira workitem transition --key "$KEY" --status "$TARGET" --yes 2>&1 >/dev/null)" && TRANSITION_OK=true || TRANSITION_OK=false

# acli can return success for a "looped transition" that performs an action but
# keeps the current status, or match a transition that does not actually land in
# the requested target. Re-read the status and only report success when the
# issue genuinely reached the target — otherwise treat it as not-reachable (5)
# so the caller discovers the real ready-to-merge status name instead of
# trusting a false positive.
if [[ "$TRANSITION_OK" == true ]]; then
  NEW_STATUS="$("$SCRIPT_DIR/load-issue.sh" "$KEY" 2>/dev/null | jq -r '.status // empty')"
  if [[ "$(printf '%s' "$NEW_STATUS" | tr '[:upper:]' '[:lower:]')" == "$target_lower" ]]; then
    echo "https://${SITE:-}/browse/${KEY}"
    echo "action=transitioned from=${CURRENT_STATUS:-?} to=${NEW_STATUS}" >&2
    exit 0
  fi
  echo "transition-to-ready-to-merge.sh: acli reported success but $KEY is still '${NEW_STATUS:-?}', not '$TARGET' (likely a looped transition or a name mismatch)." >&2
  echo "transition-to-ready-to-merge.sh: discover the real ready-to-merge status via JIRA MCP (available next transitions), then re-run with it as STATUS, or ask a human." >&2
  exit 5
fi

if printf '%s' "$TRANSITION_ERR" | grep -qiE 'not (found|available|valid)|no transition|invalid|does not exist'; then
  echo "transition-to-ready-to-merge.sh: status '$TARGET' is not available for $KEY (current: ${CURRENT_STATUS:-?})." >&2
  echo "transition-to-ready-to-merge.sh: discover the real ready-to-merge status via JIRA MCP (available next transitions), then re-run with it as STATUS, or ask a human." >&2
  exit 5
fi

echo "transition-to-ready-to-merge.sh: acli transition failed for $KEY: $TRANSITION_ERR" >&2
exit 3
