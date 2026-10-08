#!/usr/bin/env bash
# upsert-comment.sh — update-in-place GitHub issue / PR comment publisher used
# by CR-track skills. Each invocation looks for a comment already carrying this
# actor's hidden marker on the target and PATCHes the newest match; only when
# no match exists does it POST a new one. One destination therefore keeps one
# permanent comment per actor + namespace instead of a growing chain.
#
# This reverses the append-only behaviour a previous explicit request
# introduced (see CHANGELOG). The lookup-and-PATCH branch is restored on a
# newer explicit request from the same owner; the older CHANGELOG entry stays
# as history.
#
# Usage:
#   upsert-comment.sh [--create] <NUMBER|URL> <BODY_FILE> [<MARKER_KEY>]
#   <body-producer> | upsert-comment.sh [--create] <NUMBER|URL> - [<MARKER_KEY>]
#
# Inputs:
#   --create    Optional. Always POST a new comment in the given namespace and
#               never look up or PATCH an existing one. A review-only run
#               (`/report-code-review`) passes it, so every invocation leaves
#               its own comment. Unlike `agent-note`, the marker namespace stays
#               unchanged, so a later run without the flag updates the newest
#               comment as usual.
#   NUMBER|URL  Bare GitHub issue / PR number (resolved against the current
#               git remote) or a full github.com URL containing /issues/<N> or
#               /pull/<N>. The optional `www.` host prefix is tolerated.
#   BODY_FILE   Path to a file holding the comment body, or `-` to read from
#               stdin. The body must already be in the target tracker markup
#               (GitHub Markdown).
#   MARKER_KEY  Optional. Marker namespace, defaults to `cr-comment`. Three other
#               namespaces this package writes: `merge-readiness` and
#               `test-report` (upserted, same as `cr-comment`) and `agent-note` — the one namespace that
#               is create-only (see step 3 below). A project skill may pass its own
#               namespace; `@rules/code-review/general.md` *Authorship trust*
#               reads every `<namespace>:actor=` marker as agent output.
#
# Behavior:
#   1. Detect the actor login via `gh api user --jq .login`.
#   2. Append a hidden marker `<!-- <MARKER_KEY>:actor=<login> -->` to the body
#      (only when the body does not already carry the marker).
#   3. `agent-note` skips this step entirely and always POSTs (see below). Every
#      other namespace lists the target's comments and picks the newest one
#      this actor authored whose body carries that marker. The author filter is
#      load-bearing: a marker is visible text anyone can copy into their own
#      comment, so a lookup matching on the marker alone could PATCH a
#      stranger's comment.
#   4. Carry every line the operator added to the matched comment into the new
#      body verbatim (`skills/_shared/carry-operator-lines.php`). The operator
#      posts under the same account, so a line counts as the operator's when the
#      previous version's hidden `<!-- <MARKER_KEY>:lines=... -->` fingerprint of
#      agent-written lines does not know it. Every published body records that
#      fingerprint. `agent-note` is never rewritten, so it skips this step.
#   5. When a match exists, PATCH it via
#      `gh api repos/<nwo>/issues/comments/<id>`; otherwise POST a new comment
#      via `gh api repos/<nwo>/issues/<N>/comments`.
#
# One result is one comment, for every namespace except `agent-note`. A failing
# lookup publishes nothing and exits 3: without it, a POST could duplicate the
# comment this actor already owns, and a rerun once the API answers again
# updates that comment in place. `agent-note` is the deliberate exception:
# every call POSTs a fresh comment, by design — never a lookup, never a PATCH.
# It is for a separate agent comment (a runbook, a note) that must never be
# picked up and overwritten by a later `cr-comment` / `merge-readiness` publish.
#
# The marker stays at the bottom of the comment so it survives manual edits
# at the top. It is rendered by GitHub as an invisible HTML comment, and it is
# what the lookup in step 3 matches on, together with the comment's author.
#
# Output:
#   The published comment URL on stdout. `action=updated id=<id>` (an existing
#   comment was PATCHed) or `action=created id=<id>` (a new one was POSTed) on
#   stderr, for the calling skill to log in its summary line. On an update,
#   stderr also carries `carried_lines=<n>` and one `carried: <line>` per carried
#   operator line; the calling skill states every carried line in its report.
#
# Exit codes:
#   1  usage / argument error
#   2  missing required tool (gh, jq)
#   3  GitHub API call failed
set -euo pipefail

usage() {
  cat >&2 <<'EOF'
Usage: upsert-comment.sh [--create] <NUMBER|URL> <BODY_FILE|-> [<MARKER_KEY>]

  --create    always POST a new comment; never look up or PATCH an existing one
  NUMBER      bare GitHub issue or PR number (resolved against current git remote)
  URL         any github.com URL containing /issues/<N> or /pull/<N>
  BODY_FILE   path to a file containing the comment body, or `-` for stdin
  MARKER_KEY  optional marker namespace (default: cr-comment, the only
              namespace this package publishes into — one comment per
              review run, per destination).
EOF
}

CREATE_ONLY=0
if [[ "${1:-}" == "--create" ]]; then
  CREATE_ONLY=1
  shift
fi

if [[ $# -lt 2 || $# -gt 3 || -z "${1:-}" || -z "${2:-}" ]]; then
  usage
  exit 1
fi

INPUT="$1"
BODY_SRC="$2"
MARKER_KEY="${3:-cr-comment}"

if [[ ! "$MARKER_KEY" =~ ^[a-z][a-z0-9-]*$ ]]; then
  echo "upsert-comment.sh: MARKER_KEY must match [a-z][a-z0-9-]* — got: $MARKER_KEY" >&2
  exit 1
fi

for bin in gh jq php; do
  if ! command -v "$bin" >/dev/null 2>&1; then
    echo "upsert-comment.sh: required tool not found: $bin" >&2
    exit 2
  fi
done

resolve_repo_from_git() {
  local remote
  remote="$(git config --get remote.origin.url 2>/dev/null || true)"
  if [[ -z "$remote" ]]; then
    return 1
  fi
  printf '%s' "$remote" \
    | sed -E -e 's#^git@github\.com:#https://github.com/#' -e 's#\.git$##' \
    | sed -nE 's#^https?://github\.com/([^/]+)/([^/]+).*#\1 \2#p'
}

OWNER=""
REPO=""
NUMBER=""

if [[ "$INPUT" =~ ^https?://(www\.)?github\.com/ ]]; then
  parsed="$(printf '%s' "$INPUT" | sed -nE 's#^https?://(www\.)?github\.com/([^/]+)/([^/]+)/(issues|pull)/([0-9]+).*#\2 \3 \5#p' || true)"
  if [[ -z "$parsed" ]]; then
    echo "upsert-comment.sh: could not extract issue/PR from URL: $INPUT" >&2
    exit 1
  fi
  OWNER="$(printf '%s' "$parsed" | awk '{print $1}')"
  REPO="$(printf '%s' "$parsed"  | awk '{print $2}')"
  NUMBER="$(printf '%s' "$parsed" | awk '{print $3}')"
elif [[ "$INPUT" =~ ^[0-9]+$ ]]; then
  NUMBER="$INPUT"
  parsed="$(resolve_repo_from_git || true)"
  if [[ -z "$parsed" ]]; then
    echo "upsert-comment.sh: cannot resolve repo from git remote — pass a full URL instead" >&2
    exit 1
  fi
  OWNER="$(printf '%s' "$parsed" | awk '{print $1}')"
  REPO="$(printf '%s' "$parsed"  | awk '{print $2}')"
else
  echo "upsert-comment.sh: argument must be a bare number or a github.com URL: $INPUT" >&2
  exit 1
fi

NWO="${OWNER}/${REPO}"

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

# Resolve the current GitHub actor through `gh api user`. Earlier revisions
# discarded both stderr and the exit code, which collapsed every failure mode
# (expired token, rate limit, network blip) into the same misleading
# "is gh authenticated?" message. Capture stderr to surface the actual cause
# and retry up to three times so a single transient API hiccup does not abort
# the whole CR comment publish — see issue #519.
ACTOR_STDERR="$(mktemp)"
LOOKUP_STDERR="$(mktemp)"
NEW_BODY_FILE="$(mktemp)"
PREVIOUS_BODY_FILE="$(mktemp)"
trap 'rm -f "$ACTOR_STDERR" "$LOOKUP_STDERR" "$NEW_BODY_FILE" "$PREVIOUS_BODY_FILE"' EXIT
ACTOR=""
ACTOR_ERR=""
for attempt in 1 2 3; do
  : > "$ACTOR_STDERR"
  if ACTOR="$(gh api user --jq .login 2>"$ACTOR_STDERR")" && [[ -n "$ACTOR" ]]; then
    break
  fi
  ACTOR=""
  ACTOR_ERR="$(cat "$ACTOR_STDERR")"
  [[ $attempt -lt 3 ]] && sleep 1
done

if [[ -z "$ACTOR" ]]; then
  if [[ -n "$ACTOR_ERR" ]]; then
    echo "upsert-comment.sh: failed to resolve current GitHub actor after 3 attempts: ${ACTOR_ERR}" >&2
  else
    echo "upsert-comment.sh: failed to resolve current GitHub actor — is gh authenticated? (run: gh auth status)" >&2
  fi
  exit 3
fi

MARKER="<!-- ${MARKER_KEY}:actor=${ACTOR} -->"

# Look for a comment this actor already published under the same marker. A
# failed lookup publishes nothing: a POST without it could duplicate the
# comment this actor already owns. `--paginate` emits one JSON array per page,
# so `jq -s 'add // []'` flattens them into a single array before the marker
# match runs. `agent-note` is the one namespace this skips entirely — it is
# create-only, so an existing agent-note comment (a runbook, a note the
# operator asked an agent to leave as its own comment) is never picked up or
# overwritten. `--create` skips it for the same reason, in any namespace.
EXISTING_ID=""
if [[ "$MARKER_KEY" != "agent-note" && "$CREATE_ONLY" -eq 0 ]]; then
  ALL_COMMENTS=""
  if ! ALL_COMMENTS="$(gh api "repos/${NWO}/issues/${NUMBER}/comments" --paginate 2>"$LOOKUP_STDERR")"; then
    echo "upsert-comment.sh: comment lookup failed on ${NWO}#${NUMBER}, nothing was published: $(cat "$LOOKUP_STDERR")" >&2
    echo "upsert-comment.sh: a POST without the lookup could duplicate a comment this actor already owns; rerun once the API answers" >&2
    exit 3
  fi

  if [[ -n "$ALL_COMMENTS" ]]; then
    EXISTING_ID="$(printf '%s' "$ALL_COMMENTS" \
      | jq -s 'add // []' \
      | jq -r --arg marker "$MARKER" --arg actor "$ACTOR" \
          '[.[] | select((.user.login // "") == $actor) | select(.body // "" | contains($marker))] | sort_by(.created_at) | last | .id // empty' \
          2>/dev/null || true)"
  fi
fi

if [[ "$MARKER_KEY" != "agent-note" ]]; then
  CARRY_ARGS=(markdown "$MARKER_KEY" "$NEW_BODY_FILE")
  if [[ "$EXISTING_ID" =~ ^[0-9]+$ ]]; then
    printf '%s' "$ALL_COMMENTS" \
      | jq -s 'add // []' \
      | jq -r --argjson id "$EXISTING_ID" '.[] | select(.id == $id) | .body // ""' > "$PREVIOUS_BODY_FILE"
    CARRY_ARGS+=("$PREVIOUS_BODY_FILE")
  fi
  printf '%s' "$BODY" > "$NEW_BODY_FILE"
  if ! BODY="$(php "$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)/../../_shared/carry-operator-lines.php" "${CARRY_ARGS[@]}")"; then
    echo "upsert-comment.sh: carrying the operator lines failed on ${NWO}#${NUMBER}, nothing was published" >&2
    exit 3
  fi
fi

if ! grep -Fq "$MARKER" <<<"$BODY"; then
  BODY="${BODY}

${MARKER}"
fi

# `gh api` body payloads are built via jq and fed through `--input -` so the
# body stays a string regardless of its content (a body that happens to be
# `true` or an integer would otherwise be coerced by `-F` type inference).
if [[ "$EXISTING_ID" =~ ^[0-9]+$ ]]; then
  ACTION="updated"
  RESPONSE="$(jq -n --arg body "$BODY" '{body:$body}' | gh api \
    "repos/${NWO}/issues/comments/${EXISTING_ID}" \
    -X PATCH \
    --input - \
    || true)"
else
  ACTION="created"
  RESPONSE="$(jq -n --arg body "$BODY" '{body:$body}' | gh api \
    "repos/${NWO}/issues/${NUMBER}/comments" \
    -X POST \
    --input - \
    || true)"
fi

# A failed request is not always an empty response: `gh api` prints the API's own
# error JSON on stdout, so emptiness alone would let a 403 or a 422 report
# `action=updated id=null` and exit 0. The published URL is the evidence the
# write landed, so it is what the success check reads.
NEW_URL="$(printf '%s' "$RESPONSE" | jq -r '.html_url // empty' 2>/dev/null || true)"
if [[ -z "$NEW_URL" ]]; then
  echo "upsert-comment.sh: ${ACTION} request failed on ${NWO}#${NUMBER}: $(printf '%s' "$RESPONSE" | jq -r '.message // "unknown error"' 2>/dev/null || echo 'unknown error')" >&2
  exit 3
fi
printf '%s\n' "$NEW_URL"
NEW_ID="$(printf '%s' "$RESPONSE" | jq -r '.id')"
echo "action=${ACTION} id=${NEW_ID}" >&2
