#!/usr/bin/env bash
# Delete one top-level GitHub issue/PR comment after proving that it belongs to
# the current actor and exact target. Protected IDs make publication-before-
# deletion and preservation of current merge evidence enforceable.
set -euo pipefail

PROG="${0##*/}"

usage() {
  cat >&2 <<EOF
Usage: $PROG <GitHub issue-or-PR URL> <comment-id> <final-tldr-id> <current-cr-id>

Deletes only an authenticated actor-owned top-level issue/PR comment. The final
TL;DR and current CR evidence must be passed as protected IDs.
EOF
}

if [[ "$#" -ne 4 ]]; then
  usage
  exit 1
fi

TARGET_URL="$1"
COMMENT_ID="$2"
shift 2
PROTECTED_IDS=("$@")
PROTECTED_MARKERS=("merge-readiness" "cr-comment")

if [[ ! "$COMMENT_ID" =~ ^[1-9][0-9]*$ ]]; then
  printf '%s\n' "$PROG: comment id must be a positive integer" >&2
  exit 1
fi

for protected_id in "${PROTECTED_IDS[@]}"; do
  if [[ ! "$protected_id" =~ ^[1-9][0-9]*$ ]]; then
    printf '%s\n' "$PROG: every protected id must be a positive integer" >&2
    exit 1
  fi

  if [[ "$COMMENT_ID" == "$protected_id" ]]; then
    printf '%s\n' "$PROG: refusing to delete a protected final comment or current merge-evidence comment" >&2
    exit 4
  fi
done

if [[ "$TARGET_URL" =~ ^https://github\.com/([A-Za-z0-9_.-]+)/([A-Za-z0-9_.-]+)/(issues|pull)/([1-9][0-9]*)/?$ ]]; then
  OWNER="${BASH_REMATCH[1]}"
  REPOSITORY="${BASH_REMATCH[2]}"
  NUMBER="${BASH_REMATCH[4]}"
else
  printf '%s\n' "$PROG: target must be one full GitHub issue or pull-request URL" >&2
  exit 1
fi

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
NAME_WITH_OWNER="$("$SCRIPT_DIR"/assert-current-repo.sh "$TARGET_URL")"
EXPECTED_NAME="$(printf '%s/%s' "$OWNER" "$REPOSITORY" | tr '[:upper:]' '[:lower:]')"
ACTUAL_NAME="$(printf '%s' "$NAME_WITH_OWNER" | tr '[:upper:]' '[:lower:]')"

if [[ "$ACTUAL_NAME" != "$EXPECTED_NAME" ]]; then
  printf '%s\n' "$PROG: ownership guard returned a different repository" >&2
  exit 4
fi

ACTOR="$(gh api user --jq .login)"
EXPECTED_REPOSITORY_URL="https://api.github.com/repos/$OWNER/$REPOSITORY"

for index in "${!PROTECTED_IDS[@]}"; do
  protected_id="${PROTECTED_IDS[$index]}"
  protected_json="$(gh api "repos/$OWNER/$REPOSITORY/issues/comments/$protected_id")"
  protected_actor="$(printf '%s' "$protected_json" | jq -r '.user.login // empty')"
  protected_repository_url="$(printf '%s' "$protected_json" | jq -r '.repository_url // empty')"
  protected_body="$(printf '%s' "$protected_json" | jq -r '.body // empty')"
  expected_marker="<!-- ${PROTECTED_MARKERS[$index]}:actor=$ACTOR -->"

  if [[ "$protected_actor" != "$ACTOR" ]]; then
    printf '%s\n' "$PROG: protected comment $protected_id is not owned by the authenticated actor" >&2
    exit 4
  fi

  if [[ "$(printf '%s' "$protected_repository_url" | tr '[:upper:]' '[:lower:]')" != "$(printf '%s' "$EXPECTED_REPOSITORY_URL" | tr '[:upper:]' '[:lower:]')" ]]; then
    printf '%s\n' "$PROG: protected comment $protected_id belongs to a different repository" >&2
    exit 4
  fi

  if [[ "$protected_body" != *"$expected_marker"* ]]; then
    printf '%s\n' "$PROG: protected comment $protected_id does not carry the required ${PROTECTED_MARKERS[$index]} marker" >&2
    exit 4
  fi
done

COMMENT_JSON="$(gh api "repos/$OWNER/$REPOSITORY/issues/comments/$COMMENT_ID")"
COMMENT_ACTOR="$(printf '%s' "$COMMENT_JSON" | jq -r '.user.login // empty')"
COMMENT_ISSUE_URL="$(printf '%s' "$COMMENT_JSON" | jq -r '.issue_url // empty')"
EXPECTED_ISSUE_URL="https://api.github.com/repos/$OWNER/$REPOSITORY/issues/$NUMBER"

if [[ "$COMMENT_ACTOR" != "$ACTOR" ]]; then
  printf '%s\n' "$PROG: refusing to delete a comment not owned by the authenticated actor" >&2
  exit 4
fi

if [[ "$(printf '%s' "$COMMENT_ISSUE_URL" | tr '[:upper:]' '[:lower:]')" != "$(printf '%s' "$EXPECTED_ISSUE_URL" | tr '[:upper:]' '[:lower:]')" ]]; then
  printf '%s\n' "$PROG: refusing to delete a comment outside the exact target" >&2
  exit 4
fi

gh api --method DELETE "repos/$OWNER/$REPOSITORY/issues/comments/$COMMENT_ID" >/dev/null

VERIFY_OUTPUT=""
if VERIFY_OUTPUT="$(gh api --include "repos/$OWNER/$REPOSITORY/issues/comments/$COMMENT_ID" 2>&1)"; then
  printf '%s\n' "$PROG: deletion verification failed; the comment is still readable" >&2
  exit 3
fi

if ! printf '%s\n' "$VERIFY_OUTPUT" | grep -Eq '^HTTP/[^ ]+ 404([[:space:]]|$)'; then
  printf '%s\n' "$PROG: deletion could not be verified as HTTP 404" >&2
  exit 3
fi

printf 'deleted id=%s target=%s\n' "$COMMENT_ID" "$TARGET_URL"
