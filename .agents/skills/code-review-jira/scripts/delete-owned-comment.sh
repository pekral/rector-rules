#!/usr/bin/env bash
# delete-owned-comment.sh — delete one JIRA issue comment after proving that it
# belongs to the current acli actor and to the exact issue. The JIRA
# counterpart of skills/_shared/delete-owned-github-comment.sh: protected IDs
# make publication-before-deletion and preservation of current merge evidence
# enforceable.
#
# Usage:
#   delete-owned-comment.sh <KEY|URL> <COMMENT_ID> <FINAL_TLDR_ID> <CURRENT_CR_ID>
#
# Inputs:
#   KEY|URL        Bare JIRA issue key (e.g. ACME-1234), a /browse/<KEY> URL, or
#                  any URL containing ?selectedIssue=<KEY>.
#   COMMENT_ID     The comment to delete.
#   FINAL_TLDR_ID  The final TL;DR this run published and read back.
#   CURRENT_CR_ID  The current CR evidence comment on this issue. JIRA keeps one
#                  update-in-place `cr-comment` per actor, so when the final
#                  TL;DR is that comment, pass its ID for both protected slots.
#
# Ownership proof — every condition must hold, or nothing is deleted:
#   1. COMMENT_ID is neither protected ID.
#   2. The actor digest is derived from the e-mail `acli jira auth status`
#      reports, through the same jira-actor.sh function upsert-comment.sh uses
#      to write the `_cr-comment:actor=<actor-digest>_` marker.
#   3. Both protected comments exist on this issue. The author `accountId` of
#      FINAL_TLDR_ID anchors the actor's account: this run published that comment
#      itself and read it back, while acli exposes no account ID for the current
#      user. CURRENT_CR_ID must share that `accountId`. A protected comment's own
#      anchor never depends on a marker being present on it — it comes from the
#      accountId this run read back. So a TL;DR published through the sanctioned
#      JIRA MCP fallback after `upsert-comment.sh` failed still anchors the
#      cleanup of the duplicates that failed run left behind: that fallback TL;DR carries the `cr-comment:actor=` marker too, per `@rules/code-review/general.md`
#      *Authorship trust*, but this step does not depend on it. Pass only a
#      comment ID this run published as FINAL_TLDR_ID.
#   4. The target exists on this issue, carries the marker, and its author
#      `accountId` equals the anchor. The marker alone is visible text anyone
#      can copy, and a display name is not an identity, so neither proves
#      ownership on its own.
#   5. Wherever the response carries `author.emailAddress`, it must equal the
#      acli e-mail. Jira Cloud usually hides it, so it corroborates, never
#      replaces, the checks above.
#
# A comment carrying no marker (for example an empty comment a failed publish
# left behind) cannot be proven and is never deleted here; report it for a
# human. The comments are read through `acli jira workitem view <KEY> --fields
# comment --json`; a comment the view does not embed cannot be proven either.
#
# After `acli jira workitem comment delete --key <KEY> --id <ID>` the issue is
# re-read, and success is reported only when that read still lists both
# protected comments and no longer lists the target — a read that lists neither
# proves nothing.
#
# Exit codes:
#   1  usage / argument error
#   2  missing required tool (acli, jq, php)
#   3  JIRA call failed, or the deletion could not be verified
#   4  ownership or protection check refused the deletion
set -euo pipefail

PROG="${0##*/}"

usage() {
  cat >&2 <<'EOF'
Usage: delete-owned-comment.sh <KEY|URL> <COMMENT_ID> <FINAL_TLDR_ID> <CURRENT_CR_ID>

Deletes only an actor-owned comment on the exact JIRA issue. The final TL;DR
and the current CR evidence must be passed as protected IDs; pass the same ID
twice when the final TL;DR is the current CR comment.
EOF
}

if [[ "$#" -ne 4 ]]; then
  usage
  exit 1
fi

INPUT="$1"
COMMENT_ID="$2"
FINAL_TLDR_ID="$3"
CURRENT_CR_ID="$4"

for id in "$COMMENT_ID" "$FINAL_TLDR_ID" "$CURRENT_CR_ID"; do
  if [[ ! "$id" =~ ^[1-9][0-9]*$ ]]; then
    printf '%s\n' "$PROG: every comment id must be a positive integer" >&2
    exit 1
  fi
done

if [[ "$COMMENT_ID" == "$FINAL_TLDR_ID" || "$COMMENT_ID" == "$CURRENT_CR_ID" ]]; then
  printf '%s\n' "$PROG: refusing to delete a protected final comment or current merge-evidence comment" >&2
  exit 4
fi

KEY=""
if [[ "$INPUT" =~ ^[A-Z][A-Z0-9_]+-[0-9]+$ ]]; then
  KEY="$INPUT"
elif [[ "$INPUT" == *"/browse/"* ]]; then
  KEY="$(printf '%s' "$INPUT" | sed -nE 's#.*/browse/([A-Z][A-Z0-9_]+-[0-9]+).*#\1#p')"
elif [[ "$INPUT" == *"selectedIssue="* ]]; then
  KEY="$(printf '%s' "$INPUT" | sed -nE 's#.*selectedIssue=([A-Z][A-Z0-9_]+-[0-9]+).*#\1#p')"
fi

if [[ -z "$KEY" ]]; then
  printf '%s\n' "$PROG: could not extract a JIRA key from input: $INPUT" >&2
  exit 1
fi

for bin in acli jq php; do
  if ! command -v "$bin" >/dev/null 2>&1; then
    printf '%s\n' "$PROG: required tool not found: $bin" >&2
    exit 2
  fi
done

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=jira-actor.sh
source "$SCRIPT_DIR/jira-actor.sh"

EMAIL="$(jira_auth_status_field "$(acli jira auth status 2>/dev/null || true)" email)"
DIGEST="$(jira_actor_digest "$EMAIL")"
if [[ -z "$DIGEST" ]]; then
  printf '%s\n' "$PROG: could not resolve the acli account identity; ownership cannot be proven" >&2
  exit 3
fi
MARKER="cr-comment:actor=${DIGEST}"

read_comments() {
  local raw=""
  if ! raw="$(acli jira workitem view "$KEY" --fields comment --json 2>/dev/null)"; then
    return 1
  fi

  printf '%s' "$raw" | jq -c -s 'map(
      if type == "array" then .
      elif type == "object" then (.fields.comment.comments // .comments // [])
      else [] end
    ) | add // []' 2>/dev/null
}

# Print `<accountId>\t<emailAddress>` of a comment that exists on the issue and,
# when a marker is given, carries it; print nothing otherwise.
owned_identity() {
  printf '%s' "$COMMENTS" | jq -r --arg id "$1" --arg marker "$2" '
    map(select(((.id // "") | tostring) == $id)) | first
    | select(. != null)
    | select($marker == "" or ((.body | tojson) | contains($marker)))
    | [ (.author.accountId? // ""), (.author.emailAddress? // "") ] | @tsv' 2>/dev/null || true
}

# Refuse unless the comment is on the issue, carries the required marker,
# belongs to the anchor account, and shows no conflicting e-mail.
require_owned() {
  local id="$1" what="$2" marker="$3" identity account email
  identity="$(owned_identity "$id" "$marker")"
  account="${identity%%$'\t'*}"
  email="${identity#*$'\t'}"

  if [[ -z "$identity" || -z "$account" ]]; then
    if [[ -n "$marker" ]]; then
      printf '%s\n' "$PROG: $what $id is not on $KEY or does not carry this actor's cr-comment marker" >&2
    else
      printf '%s\n' "$PROG: $what $id is not on $KEY or has no resolvable author account" >&2
    fi
    exit 4
  fi

  if [[ -n "$email" && "$email" != "$EMAIL" ]]; then
    printf '%s\n' "$PROG: $what $id is authored by another account" >&2
    exit 4
  fi

  if [[ -n "${ANCHOR_ACCOUNT:-}" && "$account" != "$ANCHOR_ACCOUNT" ]]; then
    printf '%s\n' "$PROG: $what $id is not owned by the authenticated actor" >&2
    exit 4
  fi

  ANCHOR_ACCOUNT="$account"
}

if ! COMMENTS="$(read_comments)" || [[ -z "$COMMENTS" ]]; then
  printf '%s\n' "$PROG: failed to read the comments of $KEY" >&2
  exit 3
fi

ANCHOR_ACCOUNT=""
require_owned "$FINAL_TLDR_ID" "protected comment" ""
require_owned "$CURRENT_CR_ID" "protected comment" ""
require_owned "$COMMENT_ID" "comment" "$MARKER"

if ! acli jira workitem comment delete --key "$KEY" --id "$COMMENT_ID" >/dev/null 2>&1; then
  printf '%s\n' "$PROG: acli comment delete failed on $KEY comment $COMMENT_ID" >&2
  exit 3
fi

if ! COMMENTS="$(read_comments)" || [[ -z "$COMMENTS" ]]; then
  printf '%s\n' "$PROG: deletion could not be verified; the comments of $KEY are unreadable" >&2
  exit 3
fi

for protected_id in "$FINAL_TLDR_ID" "$CURRENT_CR_ID"; do
  if ! printf '%s' "$COMMENTS" | jq -e --arg id "$protected_id" 'any(.[]; ((.id // "") | tostring) == $id)' >/dev/null; then
    printf '%s\n' "$PROG: deletion could not be verified; the re-read of $KEY lacks protected comment $protected_id" >&2
    exit 3
  fi
done

if printf '%s' "$COMMENTS" | jq -e --arg id "$COMMENT_ID" 'any(.[]; ((.id // "") | tostring) == $id)' >/dev/null; then
  printf '%s\n' "$PROG: deletion verification failed; comment $COMMENT_ID is still on $KEY" >&2
  exit 3
fi

printf 'deleted id=%s key=%s\n' "$COMMENT_ID" "$KEY"
