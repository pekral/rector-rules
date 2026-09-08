#!/usr/bin/env bash
# upsert-comment.sh — always-new JIRA issue comment per CR run. Used by
# CR-track skills so each CR run posts a fresh comment (visible at the bottom
# of the JIRA thread) instead of editing a prior comment in place. No hidden
# anchor marker is added to the body.
#
# Usage:
#   upsert-comment.sh <KEY|URL> <BODY_FILE> [<MARKER_KEY>]
#   <body-producer> | upsert-comment.sh <KEY|URL> - [<MARKER_KEY>]
#
# Inputs:
#   KEY|URL     Bare JIRA issue key (e.g. ACME-1234), a /browse/<KEY> URL,
#               or any URL containing ?selectedIssue=<KEY>.
#   BODY_FILE   Path to a file holding the JIRA Wiki Markup source, or `-` to
#               read from stdin. The helper converts it to ADF before publish.
#   MARKER_KEY  Optional. Accepted for backward compatibility but ignored —
#               no anchor marker is appended to the body.
#
# Behavior:
#   1. Detect the site from `acli jira auth status` to build the output URL.
#   2. Convert the Wiki Markup source to Atlassian Document Format (ADF).
#   3. Create a fresh comment from the ADF file and immediately update that same
#      new comment via `acli jira workitem comment update --body-adf`. Passing
#      ADF to both calls ensures a failed update never leaves Wiki Markup behind.
#
# Output:
#   The published comment URL on stdout. `action=created` on stderr
#   for the calling skill to log in its summary line.
#
# Exit codes:
#   1  usage / argument error
#   2  missing required tool (acli, jq, php)
#   3  JIRA API call failed
set -euo pipefail

usage() {
  cat >&2 <<'EOF'
Usage: upsert-comment.sh <KEY|URL> <BODY_FILE|-> [<MARKER_KEY>]

  KEY         JIRA issue key (e.g. ACME-1234)
  URL         /browse/<KEY> URL or any URL containing ?selectedIssue=<KEY>
  BODY_FILE   path to a file containing the comment body, or `-` for stdin
  MARKER_KEY  optional, accepted for backward compatibility but ignored
EOF
}

if [[ $# -lt 2 || $# -gt 3 || -z "${1:-}" || -z "${2:-}" ]]; then
  usage
  exit 1
fi

INPUT="$1"
BODY_SRC="$2"
# $3 (MARKER_KEY) accepted for backward compatibility but not used.

for bin in acli jq php; do
  if ! command -v "$bin" >/dev/null 2>&1; then
    echo "upsert-comment.sh: required tool not found: $bin" >&2
    exit 2
  fi
done

KEY=""
if [[ "$INPUT" =~ ^[A-Z][A-Z0-9_]+-[0-9]+$ ]]; then
  KEY="$INPUT"
elif [[ "$INPUT" == *"/browse/"* ]]; then
  KEY="$(printf '%s' "$INPUT" | sed -nE 's#.*/browse/([A-Z][A-Z0-9_]+-[0-9]+).*#\1#p')"
elif [[ "$INPUT" == *"selectedIssue="* ]]; then
  KEY="$(printf '%s' "$INPUT" | sed -nE 's#.*selectedIssue=([A-Z][A-Z0-9_]+-[0-9]+).*#\1#p')"
fi

if [[ -z "$KEY" ]]; then
  echo "upsert-comment.sh: could not extract JIRA key from input: $INPUT" >&2
  exit 1
fi

if [[ "$BODY_SRC" == "-" ]]; then
  BODY="$(cat)"
else
  if [[ ! -r "$BODY_SRC" ]]; then
    echo "upsert-comment.sh: cannot read body file: $BODY_SRC" >&2
    exit 1
  fi
  BODY="$(cat "$BODY_SRC")"
fi

if [[ -z "$BODY" ]]; then
  echo "upsert-comment.sh: refusing to publish an empty comment" >&2
  exit 1
fi

# Resolve the site from `acli jira auth status` to build the output URL.
# The installed acli build prints them as human-readable lines:
#   ✓ Authenticated
#     Site: your-org.atlassian.net
#     Email: someone@example.com
AUTH_STATUS="$(acli jira auth status 2>/dev/null || true)"
SITE="$(printf '%s' "$AUTH_STATUS" | awk -F': *' 'tolower($0) ~ /site:/ { gsub(/[[:space:]]+$/, "", $2); print $2; exit }')"
if [[ -z "$SITE" ]]; then
  echo "upsert-comment.sh: failed to resolve JIRA site — is acli authenticated? (run: acli jira auth status)" >&2
  exit 3
fi

# Build valid ADF before the external write. The create call has no dedicated
# `--body-adf` flag, but `--body-file` accepts an ADF document. The update call
# then applies the same payload to that exact new comment ID through the
# explicitly requested `--body-adf` path.
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
ADF_FILE_TMP="$(mktemp)"
CREATE_STDERR="$(mktemp)"
trap 'rm -f "$ADF_FILE_TMP" "$CREATE_STDERR"' EXIT

if ! printf '%s' "$BODY" | php "$SCRIPT_DIR/wiki-markup-to-adf.php" > "$ADF_FILE_TMP"; then
  echo "upsert-comment.sh: failed to convert the JIRA comment to ADF" >&2
  exit 3
fi

if ! jq -e '.version == 1 and .type == "doc" and (.content | type == "array")' "$ADF_FILE_TMP" >/dev/null; then
  echo "upsert-comment.sh: converter produced invalid ADF" >&2
  exit 3
fi

if ! CREATE_JSON="$(acli jira workitem comment create --key "$KEY" --body-file "$ADF_FILE_TMP" --json 2>"$CREATE_STDERR")"; then
  echo "upsert-comment.sh: acli comment create failed on $KEY: $(<"$CREATE_STDERR")" >&2
  exit 3
fi

NEW_ID="$(printf '%s' "$CREATE_JSON" | jq -r '(.id // .comment.id // .comments[0].id // empty) | tostring' 2>/dev/null || true)"

if [[ -z "$NEW_ID" ]]; then
  echo "upsert-comment.sh: created a comment on $KEY but its ID is missing; ADF update aborted" >&2
  exit 3
fi

if ! acli jira workitem comment update --key "$KEY" --id "$NEW_ID" --body-adf "$ADF_FILE_TMP" >/dev/null 2>&1; then
  echo "upsert-comment.sh: created comment $NEW_ID on $KEY but the ADF update failed" >&2
  exit 3
fi

echo "https://${SITE}/browse/${KEY}?focusedCommentId=${NEW_ID}"
echo "action=created id=${NEW_ID}" >&2
