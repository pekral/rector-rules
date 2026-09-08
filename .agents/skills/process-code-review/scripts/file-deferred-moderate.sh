#!/usr/bin/env bash
# file-deferred-moderate.sh — file one round-3 deferred Moderate finding as a
# SUB-ISSUE of the source tracker item, and nothing else.
#
# Called by skills/process-code-review/SKILL.md *Review loop* step 6 (the
# deferral boundary), once per finding that (a) is not Critical, (b) does not
# meet the S1-S3 security carve-out, and (c) passes the filing bar in
# rules/compound-engineering/general.md *File deferred points as follow-up
# tracker issues*. The caller makes all three judgments; this script only
# performs the write and proves it landed.
#
# Usage:
#   file-deferred-moderate.sh <PARENT> <TITLE> <BODY-FILE|-> [<LABEL>]
#
# Inputs:
#   PARENT     GitHub issue URL (https://github.com/<owner>/<repo>/issues/<n>),
#              a bare JIRA key (ACME-1234), or a /browse/<KEY> URL.
#   TITLE      Sub-issue title / summary.
#   BODY-FILE  File holding the sub-issue body, or "-" to read stdin.
#   LABEL      Optional content label per rules/compound-engineering/general.md
#              *Label newly created tracker issues*. Selecting it is a semantic
#              judgment the caller makes; this script only applies what it is
#              given. Omitted means no label, which that rule permits.
#
# Environment:
#   DRY_RUN=1  Perform every read and every validation, print the exact write
#              commands to stderr, and make no write. Used to exercise the
#              script safely.
#
# Tracker support:
#   GitHub  Native sub-issue relation via the GraphQL `addSubIssue` mutation.
#           The parent needs no EPIC label: `AddSubIssueInput` takes only
#           `issueId` + `subIssueId`, and a probe against a parent labelled
#           `bug` resolved the parent and failed only on the child id. The EPIC
#           label in skills/create-issues-from-text/SKILL.md is that skill's own
#           breakdown convention, never a GitHub requirement.
#   JIRA    Native subtask via `acli jira workitem create --parent <KEY>`
#           (`--parent  Parent work item ID`, confirmed against acli's own
#           --help). The subtask type name is project-configurable, so it is
#           resolved from $JIRA_SUBTASK_TYPE and defaults to "Subtask".
#   Bugsnag Has no sub-issue concept at all. Refused with exit 1 and a pointer
#           at the error's linked GitHub issue, which is the parent to pass
#           instead — the same precedent *File deferred points as follow-up
#           tracker issues* already sets for a Bugsnag-originated deferral.
#
# Output:
#   The created sub-issue URL (or, under DRY_RUN, the resolved parent) on
#   stdout. `action=created|dry-run` plus the parent on stderr.
#
# Exit codes:
#   1  usage / argument error, or an unsupported tracker (Bugsnag)
#   2  missing required tool (gh / acli / jq)
#   3  tracker API call failed
#   4  the sub-issue was created but the parent relation could not be verified
set -euo pipefail

usage() {
  cat >&2 <<'EOF'
Usage: file-deferred-moderate.sh <PARENT> <TITLE> <BODY-FILE|-> [<LABEL>]

  PARENT     GitHub issue URL, bare JIRA key (ACME-1234), or /browse/<KEY> URL
  TITLE      sub-issue title / summary
  BODY-FILE  file holding the body, or "-" for stdin
  LABEL      optional existing content label to apply

  DRY_RUN=1  validate and print the write commands without writing
EOF
}

if [[ $# -lt 3 || $# -gt 4 || -z "${1:-}" || -z "${2:-}" || -z "${3:-}" ]]; then
  usage
  exit 1
fi

PARENT="$1"
TITLE="$2"
BODY_SRC="$3"
LABEL="${4:-}"
DRY_RUN="${DRY_RUN:-0}"

if [[ "$BODY_SRC" == "-" ]]; then
  BODY="$(cat)"
elif [[ -f "$BODY_SRC" ]]; then
  BODY="$(cat "$BODY_SRC")"
else
  echo "file-deferred-moderate.sh: body file not found: $BODY_SRC" >&2
  exit 1
fi

if [[ -z "${BODY//[[:space:]]/}" ]]; then
  echo "file-deferred-moderate.sh: refused — the sub-issue body is empty. A deferred finding is filed verbatim, never as a title alone." >&2
  exit 1
fi

need() {
  if ! command -v "$1" >/dev/null 2>&1; then
    echo "file-deferred-moderate.sh: required tool not found: $1" >&2
    exit 2
  fi
}

# Bugsnag carries no sub-issue relation, so it is refused before anything else.
if [[ "$PARENT" == *bugsnag.com* ]]; then
  echo "file-deferred-moderate.sh: refused — Bugsnag has no sub-issue concept. File against the GitHub issue in the error's linkedIssues[] instead and pass that URL as PARENT." >&2
  exit 1
fi

if [[ "$PARENT" =~ ^https://github\.com/([^/]+)/([^/]+)/issues/([0-9]+) ]]; then
  TRACKER="github"
  OWNER="${BASH_REMATCH[1]}"
  REPO="${BASH_REMATCH[2]}"
  NUMBER="${BASH_REMATCH[3]}"
elif [[ "$PARENT" =~ ^[A-Z][A-Z0-9_]+-[0-9]+$ ]]; then
  TRACKER="jira"
  KEY="$PARENT"
elif [[ "$PARENT" == *"/browse/"* ]]; then
  TRACKER="jira"
  KEY="$(printf '%s' "$PARENT" | sed -nE 's#.*/browse/([A-Z][A-Z0-9_]+-[0-9]+).*#\1#p')"
  [[ -n "$KEY" ]] || { echo "file-deferred-moderate.sh: could not extract JIRA key from: $PARENT" >&2; exit 1; }
else
  echo "file-deferred-moderate.sh: unsupported PARENT: $PARENT (expected a GitHub issue URL or a JIRA key)" >&2
  exit 1
fi

if [[ "$TRACKER" == "github" ]]; then
  need gh
  need jq

  # The `$owner` / `$repo` / `$n` / `$parent` / `$child` tokens below are GraphQL variables bound
  # by the `-f` / `-F` flags, never shell ones. A quoted heredoc keeps the shell out of them
  # without a linter suppression.
  #
  # Every `String!` / `ID!` variable is passed with `-f` and only the `Int!` `$n` with `-F`. `-F`
  # sends a *typed* value, so it coerces an all-digit owner or repository name to an integer that
  # GitHub rejects against `String!`, and it reads a leading `@` as "take this value from that
  # file" — which would send a local file's contents to api.github.com for a `PARENT` an attacker
  # influenced. `-f` sends the raw string and closes both.
  ISSUE_ID_QUERY="$(cat <<'GRAPHQL'
query($owner:String!,$repo:String!,$n:Int!){repository(owner:$owner,name:$repo){issue(number:$n){id title url}}}
GRAPHQL
)"
  SUBISSUES_QUERY="$(cat <<'GRAPHQL'
query($owner:String!,$repo:String!,$n:Int!){repository(owner:$owner,name:$repo){issue(number:$n){subIssues(first:100){nodes{number}}}}}
GRAPHQL
)"
  ADD_SUBISSUE_MUTATION="$(cat <<'GRAPHQL'
mutation($parent:ID!,$child:ID!){addSubIssue(input:{issueId:$parent,subIssueId:$child}){issue{number}}}
GRAPHQL
)"

  # A pull request is never a sub-issue parent; only issues carry the relation.
  PARENT_JSON="$(gh api graphql -f query="$ISSUE_ID_QUERY" \
    -f owner="$OWNER" -f repo="$REPO" -F n="$NUMBER" 2>&1)" || {
    echo "file-deferred-moderate.sh: failed to read parent issue $PARENT: $PARENT_JSON" >&2
    exit 3
  }
  PARENT_ID="$(printf '%s' "$PARENT_JSON" | jq -r '.data.repository.issue.id // empty' 2>/dev/null || true)"
  if [[ -z "$PARENT_ID" ]]; then
    echo "file-deferred-moderate.sh: $PARENT does not resolve to an issue (a pull request cannot be a sub-issue parent)" >&2
    exit 3
  fi

  if [[ "$DRY_RUN" == "1" ]]; then
    {
      echo "would run: gh issue create --repo $OWNER/$REPO --title <TITLE> --body-file - ${LABEL:+--label \"$LABEL\"}"
      echo "would run: gh api graphql -f query=<addSubIssue mutation> -f parent=$PARENT_ID -f child=<CHILD_ID>"
      echo "would run: skills/code-review-github/scripts/load-issue.sh $PARENT   # verify the relation landed"
      echo "action=dry-run parent=$PARENT parent_id=$PARENT_ID title=$TITLE label=${LABEL:-<none>}"
    } >&2
    printf '%s\n' "$PARENT"
    exit 0
  fi

  CREATE_ARGS=(issue create --repo "$OWNER/$REPO" --title "$TITLE" --body-file -)
  [[ -n "$LABEL" ]] && CREATE_ARGS+=(--label "$LABEL")
  CHILD_URL="$(printf '%s' "$BODY" | gh "${CREATE_ARGS[@]}")" || {
    echo "file-deferred-moderate.sh: gh issue create failed for $OWNER/$REPO" >&2
    exit 3
  }
  CHILD_NUMBER="$(printf '%s' "$CHILD_URL" | sed -nE 's#.*/issues/([0-9]+).*#\1#p')"

  # The child issue already exists at this point, so every failure below must still name its URL
  # and exit 4. Without the `|| { ... }` handler `set -e` would end the run at exit 1 — documented
  # as a usage error — with the discarded stderr taking the new issue's URL down with it.
  CHILD_JSON="$(gh api graphql -f query="$ISSUE_ID_QUERY" \
    -f owner="$OWNER" -f repo="$REPO" -F n="$CHILD_NUMBER" 2>&1)" || {
    echo "file-deferred-moderate.sh: created $CHILD_URL but the node-id lookup failed: $CHILD_JSON" >&2
    exit 4
  }
  CHILD_ID="$(printf '%s' "$CHILD_JSON" | jq -r '.data.repository.issue.id // empty' 2>/dev/null || true)"
  if [[ -z "$CHILD_ID" ]]; then
    echo "file-deferred-moderate.sh: created $CHILD_URL but could not resolve its node id to attach it to $PARENT" >&2
    exit 4
  fi

  ADD_OUT="$(gh api graphql -f query="$ADD_SUBISSUE_MUTATION" \
    -f parent="$PARENT_ID" -f child="$CHILD_ID" 2>&1)" || {
    echo "file-deferred-moderate.sh: created $CHILD_URL but addSubIssue failed against $PARENT: $ADD_OUT" >&2
    exit 4
  }

  # An external write can be silently blocked in auto-mode, so a zero exit is
  # not evidence: re-read the parent and confirm the child is actually attached.
  ATTACHED_JSON="$(gh api graphql -f query="$SUBISSUES_QUERY" \
    -f owner="$OWNER" -f repo="$REPO" -F n="$NUMBER" 2>&1)" || {
    echo "file-deferred-moderate.sh: created $CHILD_URL but the parent re-read failed, so the relation is unverified: $ATTACHED_JSON" >&2
    exit 4
  }
  ATTACHED="$(printf '%s' "$ATTACHED_JSON" | jq -r --arg c "$CHILD_NUMBER" '[.data.repository.issue.subIssues.nodes[]?.number|tostring]|index($c)//empty' 2>/dev/null || true)"
  if [[ -z "$ATTACHED" ]]; then
    echo "file-deferred-moderate.sh: created $CHILD_URL but $PARENT does not list it as a sub-issue" >&2
    exit 4
  fi

  printf '%s\n' "$CHILD_URL"
  echo "action=created parent=$PARENT child=$CHILD_URL" >&2
  exit 0
fi

# JIRA
need acli
need jq

PROJECT="${KEY%%-*}"
SUBTASK_TYPE="${JIRA_SUBTASK_TYPE:-Subtask}"

if [[ "$DRY_RUN" == "1" ]]; then
  {
    echo "would run: acli jira workitem create --project $PROJECT --parent $KEY --type \"$SUBTASK_TYPE\" --summary <TITLE> --description-file <BODY> ${LABEL:+--label \"$LABEL\"} --json"
    echo "would run: skills/code-review-jira/scripts/load-issue.sh <CREATED-KEY>   # verify the subtask landed"
    echo "action=dry-run parent=$KEY project=$PROJECT type=$SUBTASK_TYPE title=$TITLE label=${LABEL:-<none>}"
  } >&2
  printf '%s\n' "$KEY"
  exit 0
fi

BODY_FILE="$(mktemp)"
trap 'rm -f "$BODY_FILE"' EXIT
printf '%s' "$BODY" >"$BODY_FILE"

CREATE_ARGS=(jira workitem create --project "$PROJECT" --parent "$KEY" --type "$SUBTASK_TYPE"
  --summary "$TITLE" --description-file "$BODY_FILE" --json)
[[ -n "$LABEL" ]] && CREATE_ARGS+=(--label "$LABEL")

CREATED="$(acli "${CREATE_ARGS[@]}" 2>&1)" || {
  echo "file-deferred-moderate.sh: acli workitem create failed for parent $KEY: $CREATED" >&2
  echo "file-deferred-moderate.sh: when the project names its subtask type differently, re-run with JIRA_SUBTASK_TYPE=<name>." >&2
  exit 3
}

CHILD_KEY="$(printf '%s' "$CREATED" | jq -r '.key // .issueKey // empty' 2>/dev/null || true)"
if [[ -z "$CHILD_KEY" ]]; then
  CHILD_KEY="$(printf '%s' "$CREATED" | grep -oE '[A-Z][A-Z0-9_]+-[0-9]+' | head -n1 || true)"
fi
if [[ -z "$CHILD_KEY" ]]; then
  echo "file-deferred-moderate.sh: acli reported success but no subtask key could be read from its output: $CREATED" >&2
  exit 4
fi

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
LOADER="$SCRIPT_DIR/../../code-review-jira/scripts/load-issue.sh"
if [[ -x "$LOADER" ]] && ! "$LOADER" "$CHILD_KEY" >/dev/null 2>&1; then
  echo "file-deferred-moderate.sh: created $CHILD_KEY but it could not be read back through the deterministic loader" >&2
  exit 4
fi

printf '%s\n' "$CHILD_KEY"
echo "action=created parent=$KEY child=$CHILD_KEY" >&2
