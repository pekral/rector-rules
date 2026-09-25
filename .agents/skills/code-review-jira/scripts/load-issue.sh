#!/usr/bin/env bash
# load-issue.sh — single deterministic entry point for loading JIRA issue context.
#
# Usage:
#   load-issue.sh <KEY|URL>
#
# Accepts:
#   - a bare issue key, e.g. ACME-1234
#   - a /browse/<KEY> URL, e.g. https://your-company.atlassian.net/browse/ACME-1234
#   - any JIRA URL containing ?selectedIssue=<KEY> (atlOrigin and other query
#     params are tolerated and ignored)
#
# Emits one JSON document on stdout with the following stable shape:
#
#   {
#     "key", "url", "summary", "status", "issueType", "priority",
#     "assignee", "reporter", "creator", "created", "updated",
#     "resolution", "resolutionDate", "dueDate", "environment",
#     "labels", "components", "fixVersions",
#     "parent":  { "key", "summary", "status" } | null,
#     "project": { "key", "name", "typeKey" }   | null,
#     "watchCount": <int>,
#     "timeTracking": { "originalEstimate", "remainingEstimate", "timeSpent", "ratio" },
#     "descriptionAdf":  <raw ADF or null>,
#     "descriptionText": "<flattened plain text>",
#     "descriptionMediaRefs": [ { "adfId", "altText" } ],
#     "issueLinks":  [ { "id", "type", "direction", "verb", "linkedKey", "linkedSummary", "linkedStatus", "linkedType" } ],
#     "subtasks":    [ { "key", "summary", "status", "type",
#                        "descriptionText", "descriptionAdf",
#                        "comments":    [ { "id", "author", "body", "created", "visibility" } ],
#                        "attachments": [ { "id", "name", "size", "mimeType", "contentUrl", "author", "created" } ] } ],
#     "comments":    [ { "id", "author", "body", "created", "visibility" } ],
#     "attachments": [ { "id", "name", "size", "mimeType", "contentUrl", "author", "created" } ],
#     "customFields":  { "customfield_XXXXX": <parsed value>, … },
#     "devSummary":    { "pullRequestCount", "branchCount", "commitCount", "state", "isStale", "byInstance" } | null,
#     "pullRequests":  [ { "number", "title", "url", "state", "headRefName", "baseRefName", "isDraft", "mergedAt", "author" } ]
#   }
#
# Notes:
#   - A comment `body` is rendered from the ADF document `workitem view` embeds under
#     `.fields.comment.comments[]`, paired to the `comment list` entry by comment `id`. The list
#     body is flattened by acli itself and drops mentions, emoji, links, and the text of every list
#     item, so a decision written as a bullet is missing from it entirely. The flattened list text is
#     only the fallback for a comment the view did not embed. JIRA may embed fewer comments than
#     the issue carries (`.fields.comment.total` above the embedded count); the loader says so on
#     stderr, and the comments past the embedded page keep the flattened text. `id` is the comment
#     ID, which `delete-owned-comment.sh` and `comment update --id` take.
#   - The ADF renderer keeps every node a reader needs: a mention as its `@Name`, an emoji as its
#     text (the character, or the `:shortcode:` when JIRA stores no character), a smart link as its URL, a linked text as `text (url)`, a status or a date as
#     its value, a list item as `- ` / `1. ` indented two spaces per nesting level, a task as
#     `- [ ]` / `- [x]`, a rule as `---`, a table as `| cell | cell |` rows, and an expand as its
#     title followed by its content. The same renderer produces `descriptionText`.
#   - `customFields` runs every customfield_* value through a universal Java/Groovy
#     toString unwrap: any string that starts with `{` and contains `json={…}` is
#     parsed back into JSON. The leading-`{` anchor keeps the unwrap from firing
#     on free-text fields that happen to mention `json={…}` in prose. Primitives,
#     arrays, and already-structured objects pass through unchanged. No
#     site-specific field IDs are hardcoded.
#   - `descriptionMediaRefs[]` carries only `adfId` + `altText`. Correlating ADF
#     media nodes back to entries in `attachments[]` requires an additional
#     Atlassian Cloud Media API call, which is out of scope for this script;
#     consumers should join on `attachments[]` themselves when needed.
#   - `devSummary` is a convenience projection derived from
#     customFields[$JIRA_DEV_SUMMARY_FIELD] (default `customfield_10000`,
#     overridable via the JIRA_DEV_SUMMARY_FIELD env var). The shape stays
#     identical across JIRA sites because it's computed, not field-id-bound.
#   - `subtasks[]` carries the full sub-issue context (description, comments,
#     attachments), not just the shallow reference the parent issue embeds. Each
#     subtask is fetched individually (one `acli ... workitem view` plus one
#     `acli ... comment list` per subtask), so a parent with many subtasks costs
#     proportionally more API calls. A subtask whose individual fetch fails
#     degrades to its shallow reference (key/summary/status/type) with empty
#     description / comments / attachments rather than breaking the whole load.
#   - The Atlassian CLI `--paginate` flag emits a JSON stream (one document per
#     page) instead of a single document. We slurp with `jq -s` to merge pages.
#   - `pullRequests` are resolved via `gh search prs <KEY>` and may include PRs
#     across any GitHub repo the current `gh` auth can see.
#
# Known limitations (intentionally out of scope, fall back to JIRA MCP):
#   - issue changelog (`expand=changelog`)
#   - available next transitions
#   - friendly custom-field names (`expand=names`)
#
# Exit codes:
#   1  usage error (missing or unparseable argument)
#   2  missing required tool (acli, jq)
#   3  JIRA fetch failed
set -euo pipefail

usage() {
  cat >&2 <<'EOF'
Usage: load-issue.sh <KEY|URL>

  KEY    bare JIRA work-item key (e.g. ACME-1234)
  URL    /browse/<KEY> URL or any URL with ?selectedIssue=<KEY>

Env:
  JIRA_SITE                  override the JIRA host (e.g. your-company.atlassian.net)
  JIRA_DEV_SUMMARY_FIELD     customfield id feeding devSummary (default: customfield_10000)
EOF
}

if [[ $# -ne 1 || -z "${1:-}" ]]; then
  usage
  exit 1
fi

INPUT="$1"

for bin in acli jq; do
  if ! command -v "$bin" >/dev/null 2>&1; then
    echo "load-issue.sh: required tool not found: $bin" >&2
    exit 2
  fi
done

extract_key_from_url() {
  local url="$1"
  local key
  key="$(printf '%s' "$url" | grep -oE '[?&]selectedIssue=[A-Z][A-Z0-9_]+-[0-9]+' | head -n1 | sed -E 's/^[?&]selectedIssue=//')"
  if [[ -n "$key" ]]; then
    printf '%s' "$key"
    return 0
  fi
  key="$(printf '%s' "$url" | grep -oE '/browse/[A-Z][A-Z0-9_]+-[0-9]+' | head -n1 | sed -E 's#^/browse/##')"
  if [[ -n "$key" ]]; then
    printf '%s' "$key"
    return 0
  fi
  return 1
}

extract_host_from_url() {
  local url="$1"
  printf '%s' "$url" | sed -nE 's#^https?://([^/]+)/.*#\1#p'
}

KEY=""
HOST_FROM_URL=""

if [[ "$INPUT" =~ ^[A-Z][A-Z0-9_]+-[0-9]+$ ]]; then
  KEY="$INPUT"
elif [[ "$INPUT" =~ ^https?:// ]]; then
  if ! KEY="$(extract_key_from_url "$INPUT")"; then
    echo "load-issue.sh: could not extract a JIRA key from URL: $INPUT" >&2
    exit 1
  fi
  HOST_FROM_URL="$(extract_host_from_url "$INPUT")"
else
  echo "load-issue.sh: argument must be a bare key or a URL: $INPUT" >&2
  exit 1
fi

resolve_host() {
  if [[ -n "$HOST_FROM_URL" ]]; then
    printf '%s' "$HOST_FROM_URL"
    return 0
  fi
  if [[ -n "${JIRA_SITE:-}" ]]; then
    printf '%s' "$JIRA_SITE"
    return 0
  fi
  local config="${HOME}/.config/acli/jira_config.yaml"
  if [[ -f "$config" ]]; then
    awk '/^current_profile:/ { cp=$2 } /^[[:space:]]*-[[:space:]]*site:/ { site=$3 } /^[[:space:]]*cloud_id:/ { if ($2 ":" account_id == cp) { print site; exit } cid=$2 } /^[[:space:]]*account_id:/ { account_id=$2; if (cid ":" account_id == cp) { print site; exit } }' "$config" | head -n1
  fi
}

HOST="$(resolve_host || true)"
DEV_FIELD="${JIRA_DEV_SUMMARY_FIELD:-customfield_10000}"

VIEW_JSON="$(acli jira workitem view "$KEY" --fields '*all' --json 2>/dev/null || true)"
if [[ -z "$VIEW_JSON" ]] || ! printf '%s' "$VIEW_JSON" | jq -e . >/dev/null 2>&1; then
  echo "load-issue.sh: failed to fetch JIRA issue $KEY" >&2
  exit 3
fi

# The issue view can embed fewer comments than the issue carries. Disclose it rather than let a
# flattened fallback body pass for the full ADF one.
VIEW_COMMENT_GAP="$(printf '%s' "$VIEW_JSON" | jq -r '((.fields.comment.total // 0) | tonumber? // 0) - ((.fields.comment.comments // []) | length)' 2>/dev/null || true)"
if [[ "$VIEW_COMMENT_GAP" =~ ^[1-9][0-9]*$ ]]; then
  echo "load-issue.sh: the issue view embedded $VIEW_COMMENT_GAP fewer comments than $KEY carries; those comments keep the flattened comment-list text" >&2
fi

# `|| printf` would append the fallback to whatever jq had already written, leaving two JSON
# documents in one variable and failing `--argjson` below with exit 2 — the load died where it was
# documented to degrade. Take whatever the pipeline produced, then validate it.
COMMENTS_JSON="$(acli jira workitem comment list --key "$KEY" --json --paginate 2>/dev/null | jq -s '{ comments: ([ .[].comments // [] ] | add // []) }' 2>/dev/null || true)"
if [[ -z "$COMMENTS_JSON" ]] || ! printf '%s' "$COMMENTS_JSON" | jq -e . >/dev/null 2>&1; then
  COMMENTS_JSON='{"comments": []}'
fi

# Fetch the full context of every subtask (description, comments, attachments).
# The parent issue only embeds a shallow subtask reference, so each subtask is
# loaded individually and accumulated into an object keyed by subtask key. A
# failed individual fetch is skipped, leaving that subtask with its shallow
# reference only.
SUBTASK_DETAILS='{}'
SUBTASK_KEYS="$(printf '%s' "$VIEW_JSON" | jq -r '(.fields.subtasks // [])[] | .key // empty' 2>/dev/null || true)"
if [[ -n "$SUBTASK_KEYS" ]]; then
  while IFS= read -r SUBTASK_KEY; do
    [[ -z "$SUBTASK_KEY" ]] && continue
    SUBTASK_VIEW="$(acli jira workitem view "$SUBTASK_KEY" --fields '*all' --json 2>/dev/null || true)"
    if [[ -z "$SUBTASK_VIEW" ]] || ! printf '%s' "$SUBTASK_VIEW" | jq -e . >/dev/null 2>&1; then
      continue
    fi
    SUBTASK_COMMENTS="$(acli jira workitem comment list --key "$SUBTASK_KEY" --json --paginate 2>/dev/null | jq -s '{ comments: ([ .[].comments // [] ] | add // []) }' 2>/dev/null || true)"
    if [[ -z "$SUBTASK_COMMENTS" ]] || ! printf '%s' "$SUBTASK_COMMENTS" | jq -e . >/dev/null 2>&1; then
      SUBTASK_COMMENTS='{"comments": []}'
    fi
    SUBTASK_DETAILS="$(jq -c -n \
      --arg key "$SUBTASK_KEY" \
      --argjson acc "$SUBTASK_DETAILS" \
      --argjson view "$SUBTASK_VIEW" \
      --argjson commentsResp "$SUBTASK_COMMENTS" \
      '$acc + { ($key): { view: $view, comments: ($commentsResp.comments // []) } }' 2>/dev/null || printf '%s' "$SUBTASK_DETAILS")"
  done <<< "$SUBTASK_KEYS"
fi

PRS_JSON='[]'
if command -v gh >/dev/null 2>&1; then
  PRS_JSON="$(gh search prs "$KEY" \
      --json number,title,url,state,headRefName,baseRefName,isDraft,mergedAt,author \
      --limit 50 2>/dev/null || printf '[]')"
  if ! printf '%s' "$PRS_JSON" | jq -e . >/dev/null 2>&1; then
    PRS_JSON='[]'
  fi
fi

jq -n \
  --arg key "$KEY" \
  --arg host "$HOST" \
  --arg devField "$DEV_FIELD" \
  --argjson view "$VIEW_JSON" \
  --argjson commentsResp "$COMMENTS_JSON" \
  --argjson subtaskDetails "$SUBTASK_DETAILS" \
  --argjson prs "$PRS_JSON" '
def tryParseTrimEnd:
  . as $s
  | { s: $s, parsed: null }
  | until(.parsed != null or (.s | length) == 0;
      .s |= .[0:length-1]
      | .parsed = (.s | fromjson? // null))
  | .parsed;

def unwrapJavaToString:
  if type == "string" and test("^\\{.*json=\\{") then
    (capture("json=(?<j>\\{.*\\})") | .j) as $candidate
    | (($candidate | fromjson?) // ($candidate | tryParseTrimEnd) // .)
  else .
  end;

# `adfInline` renders one inline node. Nothing a reader needs is dropped: a mention keeps its
# `@Name`, an emoji its text or `:shortcode:`, a smart link its URL, a linked text its target, and a status
# lozenge or a date its value — the flattened `comment list` text loses exactly these nodes.
def adfInline:
  if type != "object" then ""
  elif .type == "text" then
    (.text // "") as $t
    | ([(.marks // [])[] | select(.type == "link") | .attrs.href // empty] | first) as $href
    | if $href != null and $href != $t then $t + " (" + $href + ")" else $t end
  elif .type == "hardBreak" then "\n"
  elif .type == "mention" then (.attrs.text // "")
  elif .type == "emoji" then (.attrs.text // .attrs.shortName // "")
  elif (.type // "") | IN("inlineCard","blockCard","embedCard") then (.attrs.url // "")
  elif .type == "status" then (.attrs.text // "")
  elif .type == "date" then
    ((.attrs.timestamp // "") | tostring) as $raw
    | ($raw | tonumber? // null) as $ms
    | if $ms == null then $raw
      else (try ($ms / 1000 | floor | strftime("%Y-%m-%d")) catch $raw) end
  else ((.content // []) | map(adfInline) | join(""))
  end;

# `adfBlock($indent)` renders one block node as lines. A list item carries its `- ` / `1. ` marker,
# and a nested list is indented by two spaces per level, so a decision written as a bullet survives.
def adfBlock($indent):
  if type != "object" then ""
  elif (.type // "") | IN("bulletList","orderedList","taskList","decisionList") then
    .type as $listType
    | ((.attrs.order // 1) | tonumber? // 1) as $start
    | (.content // []) | to_entries
    | map(
        (if $listType == "orderedList" then (($start + .key) | tostring) + ". "
         elif $listType == "taskList" then (if .value.attrs.state == "DONE" then "- [x] " else "- [ ] " end)
         else "- " end) as $marker
        | .value as $item
        | ($item.content // []) as $children
        | if ($item.type // "") | IN("taskItem","decisionItem") then
            $indent + $marker + ($item | adfInline) + "\n"
          elif ($children | length) > 0 and ($children[0].type // "") == "paragraph" then
            $indent + $marker + ($children[0] | adfInline) + "\n"
            + ($children[1:] | map(adfBlock($indent + "  ")) | join(""))
          else
            $indent + $marker + "\n" + ($children | map(adfBlock($indent + "  ")) | join(""))
          end)
    | join("")
  elif .type == "listItem" then ({ type: "bulletList", content: [.] } | adfBlock($indent))
  elif (.type // "") | IN("paragraph","heading","codeBlock") then $indent + adfInline + "\n"
  elif .type == "rule" then $indent + "---\n"
  elif (.type // "") | IN("blockCard","embedCard") then $indent + adfInline + "\n"
  elif .type == "table" then
    (.content // [])
    | map($indent + "| "
          + ((.content // [])
             | map((.content // []) | map(adfBlock("")) | join(" ")
                   | gsub("\\s*\n\\s*"; " ") | sub("^\\s+"; "") | sub("\\s+$"; ""))
             | join(" | "))
          + " |\n")
    | join("")
  elif (.type // "") | IN("expand","nestedExpand") then
    (if (.attrs.title // "") != "" then $indent + .attrs.title + "\n" else "" end)
    + ((.content // []) | map(adfBlock($indent)) | join(""))
  elif (.type // "") | IN("text","hardBreak","mention","emoji","inlineCard","status","date") then adfInline
  else ((.content // []) | map(adfBlock($indent)) | join(""))
  end;

def adfText: adfBlock("");

def adfPlain: adfText | gsub("\n\n+"; "\n\n") | sub("\n+$"; "");

# The comment body prefers the ADF document `workitem view` embeds for the same comment `id`. The
# `comment list` body is the flattening acli does itself, which drops mentions, emoji, and every list item —
# a decision written as a bullet disappears from it entirely. The flattened text stays the fallback
# for a comment the view did not embed.
def commentOut($viewIdx):
  . as $c
  | (($c.id // "") | tostring) as $id
  | ($viewIdx[$id] // {}) as $v
  | {
      id: (if $id == "" then null else $id end),
      author: (if ($c.author | type) == "object" then ($c.author.displayName // null) else $c.author end),
      body: (if ($v.body | type) == "object" then ($v.body | adfPlain)
             elif ($c.body | type) == "object" then ($c.body | adfPlain)
             else $c.body end),
      created: ($c.created // $v.created // null),
      visibility: (if ($c.visibility | type) == "object" then $c.visibility.value else ($c.visibility // $v.visibility // null) end)
    };

def viewCommentIdx:
  ((.comment.comments // []) | map({ key: ((.id // "") | tostring), value: { body: .body, created: .created, visibility: (.visibility.value // null) } }) | from_entries);

def adfMedia:
  if type != "object" then []
  elif .type == "media" then
    [ { adfId: (.attrs.id // null),
        altText: (.attrs.alt // null) } ]
  else
    ((.content // []) | map(adfMedia) | add // [])
  end;

($view.fields // {}) as $f
| ($f.attachment // []) as $att
| ($f.subtasks // []) as $sub
| ($f.issuelinks // []) as $links
| ($f | viewCommentIdx) as $viewCommentIdx
| ($f | to_entries
       | map(select(.key | startswith("customfield_")))
       | map({ key: .key, value: (.value | unwrapJavaToString) })
       | from_entries) as $cf
| ($cf[$devField] // null) as $devRaw
| (if ($devRaw | type) == "object" and ($devRaw.cachedValue.summary // null) != null
    then $devRaw.cachedValue.summary
    else null
   end) as $devCached
| ($f.description // null) as $desc
| (if $desc == null then "" else ($desc | adfText) end) as $descText
| (if $desc == null then [] else ($desc | adfMedia) end) as $descMedia
| {
    key: $key,
    url: (if $host != "" then "https://" + $host + "/browse/" + $key else null end),
    summary: ($f.summary // null),
    status: ($f.status.name // null),
    issueType: ($f.issuetype.name // null),
    priority: ($f.priority.name // null),
    assignee: ($f.assignee.displayName // null),
    reporter: ($f.reporter.displayName // null),
    creator: ($f.creator.displayName // null),
    created: ($f.created // null),
    updated: ($f.updated // null),
    resolution: ($f.resolution.name // null),
    resolutionDate: ($f.resolutiondate // null),
    dueDate: ($f.duedate // null),
    environment: ($f.environment // null),
    labels: ($f.labels // []),
    components: ($f.components // [] | map(.name)),
    fixVersions: ($f.fixVersions // [] | map(.name)),
    parent: (if $f.parent then { key: $f.parent.key, summary: ($f.parent.fields.summary // null), status: ($f.parent.fields.status.name // null) } else null end),
    project: (if $f.project then { key: $f.project.key, name: $f.project.name, typeKey: ($f.project.projectTypeKey // null) } else null end),
    watchCount: ($f.watches.watchCount // 0),
    timeTracking: {
      originalEstimate: ($f.timetracking.originalEstimate // null),
      remainingEstimate: ($f.timetracking.remainingEstimate // null),
      timeSpent: ($f.timetracking.timeSpent // null),
      ratio: ($f.workratio // null)
    },
    descriptionAdf: $desc,
    descriptionText: ($descText | gsub("\n\n+"; "\n\n") | sub("\n+$"; "")),
    descriptionMediaRefs: $descMedia,
    issueLinks: ($links | map(
      if .outwardIssue then
        { id: .id, type: (.type.name // null), direction: "outward",
          verb: (.type.outward // null),
          linkedKey: .outwardIssue.key,
          linkedSummary: (.outwardIssue.fields.summary // null),
          linkedStatus: (.outwardIssue.fields.status.name // null),
          linkedType: (.outwardIssue.fields.issuetype.name // null) }
      else
        { id: .id, type: (.type.name // null), direction: "inward",
          verb: (.type.inward // null),
          linkedKey: (.inwardIssue.key // null),
          linkedSummary: (.inwardIssue.fields.summary // null),
          linkedStatus: (.inwardIssue.fields.status.name // null),
          linkedType: (.inwardIssue.fields.issuetype.name // null) }
      end)),
    subtasks: ($sub | map(. as $st
      | ($subtaskDetails[$st.key] // null) as $d
      | ($d.view.fields // null) as $sf
      | ($sf.description // null) as $sdesc
      | {
          key: $st.key,
          summary: ($st.fields.summary // null),
          status: ($st.fields.status.name // null),
          type: ($st.fields.issuetype.name // null),
          descriptionAdf: $sdesc,
          descriptionText: (if $sdesc == null then "" else ($sdesc | adfPlain) end),
          comments: (if $d == null then [] else (($sf | viewCommentIdx) as $subIdx | ($d.comments // []) | map(commentOut($subIdx))) end),
          attachments: (if $sf == null then [] else (($sf.attachment // []) | map({
            id: (.id // null),
            name: (.filename // null),
            size: (.size // null),
            mimeType: (.mimeType // null),
            contentUrl: (.content // null),
            author: (if (.author | type) == "object" then (.author.displayName // null) else .author end),
            created: (.created // null)
          })) end)
        })),
    comments: ($commentsResp.comments // [] | map(commentOut($viewCommentIdx))),
    attachments: ($att | map({
      id: (.id // null),
      name: (.filename // null),
      size: (.size // null),
      mimeType: (.mimeType // null),
      contentUrl: (.content // null),
      author: (if (.author | type) == "object" then (.author.displayName // null) else .author end),
      created: (.created // null)
    })),
    customFields: $cf,
    devSummary: (if $devCached == null then null else {
      pullRequestCount: ($devCached.pullrequest.overall.count // 0),
      branchCount: ($devCached.branch.overall.count // 0),
      commitCount: ($devCached.repository.overall.count // 0),
      state: ($devCached.pullrequest.overall.state // null),
      isStale: (($devCached.pullrequest.overall.stateCount // 0) == 0),
      byInstance: ($devCached.pullrequest.byInstanceType // null)
    } end),
    pullRequests: ($prs | map({
      number: .number,
      title: .title,
      url: .url,
      state: .state,
      headRefName: .headRefName,
      baseRefName: .baseRefName,
      isDraft: .isDraft,
      mergedAt: .mergedAt,
      author: (.author.login // null)
    }))
  }
'
