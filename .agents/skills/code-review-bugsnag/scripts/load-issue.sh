#!/usr/bin/env bash
# load-issue.sh — single deterministic entry point for loading Bugsnag error context.
#
# Usage:
#   load-issue.sh <URL|ORG_SLUG/PROJECT_SLUG/ERROR_ID>
#   load-issue.sh --self-test
#
# Accepts:
#   - a Bugsnag dashboard URL, e.g.
#     https://app.bugsnag.com/<org-slug>/<project-slug>/errors/<error-id>?filters[...]
#     (the optional `www.` host prefix is tolerated)
#   - a slash triple, e.g. your-org/your-project/0123456789abcdef01234567
#
# Auth:
#   Reads a personal Data Access API token from the BUGSNAG_TOKEN env var
#   (BUGSNAG_AUTH_TOKEN is accepted as an alias). This is the organization
#   data-access token, NOT the per-project notifier API key. The token is never
#   read from a file and never written anywhere by this script.
#
# Emits one JSON document on stdout with the following stable shape:
#
#   {
#     "kind": "bugsnag-error",
#     "id": <string>,
#     "url": <string>,                # app.bugsnag.com dashboard URL
#     "apiUrl": <string>,             # api.bugsnag.com error URL
#     "organization": { "id", "slug", "name" },
#     "project":      { "id", "slug", "name", "type", "language" },
#     "title":      <string>,         # error class (parity with GitHub/JIRA "title")
#     "errorClass": <string>,
#     "message":    <string>,
#     "context":    <string|null>,    # e.g. "PUT /lists/4/update-subscriber"
#     "status":     <string>,         # open | fixed | ignored | snoozed
#     "severity":   <string>,
#     "events":     <int>,            # occurrence count
#     "users":      <int>,
#     "firstSeen", "lastSeen", "createdAt": <string|null>,
#     "assignedCollaboratorId", "assignedTeamId": <string|null>,
#     "releaseStages": [ <string> ],
#     "linkedIssues":  [ { "type", "number", "url" } ],   # e.g. github-issues #25280
#     "commentCount": <int>,
#     "comments":      [ { "author", "email", "body", "createdAt", "updatedAt" } ],
#     "groupingFields": { "errorClass", "file" },
#     "latestEvent": {
#       "id", "receivedAt", "context", "unhandled", "severity",
#       "errorClass", "message",
#       "app":    { "id", "version", "releaseStage", "type" },
#       "device": { "osName", "osVersion", "runtimeVersions" },
#       "request":{ "httpMethod", "url", "clientIp" },
#       "user":   { "id", "name", "email" },
#       "stacktrace":  [ { "file", "line", "method", "inProject" } ],
#       "breadcrumbs": [ { "timestamp", "name", "type" } ]
#     } | null
#   }
#
# Notes:
#   - The script is the single deterministic source of Bugsnag context. Skills must
#     never call api.bugsnag.com directly: changes to the JSON shape happen here,
#     in one place — mirroring code-review-github/scripts/load-issue.sh. The shared
#     parse / HTTP / slug-resolution helpers live in _lib.sh alongside this script.
#   - Bugsnag's Data Access API keys resources by numeric id, not by the slugs that
#     appear in dashboard URLs, so the script resolves org slug -> org id ->
#     project slug -> project id before fetching the error.
#   - `linkedIssues` surfaces issues linked to the error (e.g. the mirrored GitHub
#     issue), so downstream skills can route the technical report to the linked PR.
#   - `latestEvent.stacktrace` carries the full frame list (slimmed); `inProject`
#     flags application frames, which is the entry point for a TDD reproduction.
#
# Known limitations (intentionally out of scope, fall back to Bugsnag MCP):
#   - Comment threads longer than 3000 comments (30 pages of 100). The loader
#     reads every page up to that cap and reports the truncation on stderr, so a
#     short read is never returned as if it were the whole thread.
#   - Per-event pivots / custom event fields beyond the latest event
#   - Trend / stability time series
#   - Attachment binary contents
#
# Exit codes:
#   1  usage error (missing or unparseable argument), or a failing self-test
#   2  missing required tool (curl, jq) or missing BUGSNAG_TOKEN
#   3  Bugsnag fetch failed (auth, not found, or API error)
set -euo pipefail

PROG="${0##*/}"
# shellcheck source=_lib.sh
source "$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)/_lib.sh"

usage() {
  cat >&2 <<'EOF'
Usage: load-issue.sh <URL|ORG_SLUG/PROJECT_SLUG/ERROR_ID>
       load-issue.sh --self-test

  URL     an app.bugsnag.com URL of the form
          https://app.bugsnag.com/<org>/<project>/errors/<error-id>
  TRIPLE  <org-slug>/<project-slug>/<error-id>

  --self-test  run the offline test suite (no network, `curl` is stubbed)

Auth: export BUGSNAG_TOKEN with a Data Access API token.
EOF
}

# --- self-test --------------------------------------------------------------

# Removed on exit by cleanup_self_test. Global, not local: the EXIT trap fires
# after the function's locals are gone.
SELF_TEST_TMP=""

cleanup_self_test() {
  if [[ -n "$SELF_TEST_TMP" ]]; then
    rm -rf "$SELF_TEST_TMP"
  fi
  return 0
}

# Writes the stand-in for every curl call the loader makes. It answers from the
# routing table in $BSNAG_STUB_ROUTES -- one `<url>|<status>|<body-file>|<next>`
# line per request -- and writes the `Link: rel="next"` header back through
# curl's own -D file. The LAST matching line wins, so a case overrides one route
# by appending it after the base set. An unrouted URL exits 7 rather than 404:
# it means the run made a request the case did not expect, which is a failure.
write_curl_stub() {
  cat >"$1/curl" <<'STUB'
#!/usr/bin/env bash
set -euo pipefail

headers=''
url=''
want_headers=false

for arg in "$@"; do
  if [[ "$want_headers" == true ]]; then
    headers="$arg"
    want_headers=false
    continue
  fi
  case "$arg" in
    -D) want_headers=true ;;
    http*) url="$arg" ;;
  esac
done

route="$(awk -F'|' -v u="$url" '$1 == u { found = $0 } END { print found }' "$BSNAG_STUB_ROUTES")"
if [[ -z "$route" ]]; then
  echo "curl stub: no route for $url" >&2
  exit 7
fi

status="${route#*|}"
status="${status%%|*}"
rest="${route#*|*|}"
body_file="${rest%%|*}"
next="${rest#*|}"

if [[ -n "$headers" ]]; then
  {
    printf 'HTTP/2 %s\r\n' "$status"
    if [[ -n "$next" ]]; then
      printf 'Link: <%s>; rel="next"\r\n' "$next"
    fi
    printf '\r\n'
  } >"$headers"
fi

printf '%s\n%s' "$(cat "$body_file")" "$status"
STUB
  chmod +x "$1/curl"
}

# The fixture bodies the routes point at. Kept minimal: every field one of the
# assertions below reads, and nothing else.
write_fixtures() {
  local dir="$1"

  cat >"$dir/organizations.json" <<'JSON'
[{"id":"org-1","slug":"stub-org","name":"Stub Org"}]
JSON

  cat >"$dir/organizations-none.json" <<'JSON'
[]
JSON

  cat >"$dir/projects-page-1.json" <<'JSON'
[{"id":"proj-9","slug":"other-project","name":"Other","type":"laravel","language":"php"}]
JSON

  cat >"$dir/projects-page-2.json" <<'JSON'
[{"id":"proj-1","slug":"stub-project","name":"Stub","type":"laravel","language":"php"}]
JSON

  cat >"$dir/error.json" <<'JSON'
{
  "id": "0123456789abcdef01234567",
  "error_class": "RuntimeException",
  "message": "Undefined index",
  "context": "PUT /lists/4",
  "status": "open",
  "severity": "error",
  "events": 12,
  "users": 3,
  "release_stages": ["production"],
  "first_seen": "2026-01-01T00:00:00Z",
  "last_seen": "2026-01-02T00:00:00Z",
  "linked_issues": []
}
JSON

  cat >"$dir/latest-event.json" <<'JSON'
{
  "id": "ev-1",
  "received_at": "2026-01-02T00:00:00Z",
  "unhandled": true,
  "exceptions": [{
    "error_class": "RuntimeException",
    "message": "Undefined index",
    "stacktrace": [{"file": "app/Foo.php", "line_number": 42, "method": "run", "in_project": true}]
  }],
  "breadcrumbs": []
}
JSON

  cat >"$dir/unauthorized.json" <<'JSON'
{"errors":["Unauthorized"]}
JSON

  write_comment_fixtures "$dir"
}

# One comment per page, so a case that pages twice can assert on the bodies it
# got back rather than only on a count.
write_comment_fixtures() {
  local dir="$1"

  cat >"$dir/comments-page-1.json" <<'JSON'
[{
  "collaborator": {"name": "Alice", "email": "alice@example.com"},
  "message": "first comment",
  "created_at": "2026-01-01T00:00:00Z",
  "updated_at": null
}]
JSON

  cat >"$dir/comments-page-2.json" <<'JSON'
[
  {
    "collaborator": {"name": "Bob", "email": "bob@example.com"},
    "message": "second comment",
    "created_at": "2026-01-02T00:00:00Z",
    "updated_at": null
  },
  {
    "collaborator": {"name": "Bob", "email": "bob@example.com"},
    "message": "third comment",
    "created_at": "2026-01-03T00:00:00Z",
    "updated_at": null
  }
]
JSON
}

# What this loader does across more than one HTTP response -- following a
# `Link: rel="next"` header, stopping at the first project that matches, keeping
# a pruned event from aborting the document -- is invisible in the source of any
# single line, so the proof RUNS the script against the stubbed curl above. The
# precedent is `skills/github-issue-triage/scripts/assign-priorities.sh
# --self-test`.
self_test() {
  local script stub routes fixtures err_file
  local failures=0 checks=0
  script="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)/$(basename "${BASH_SOURCE[0]}")"

  SELF_TEST_TMP="$(mktemp -d)"
  trap cleanup_self_test EXIT

  stub="$SELF_TEST_TMP/bin"
  routes="$SELF_TEST_TMP/routes"
  fixtures="$SELF_TEST_TMP/fixtures"
  err_file="$SELF_TEST_TMP/stderr"
  mkdir -p "$stub" "$fixtures"

  write_curl_stub "$stub"
  write_fixtures "$fixtures"

  local triple='stub-org/stub-project/0123456789abcdef01234567'
  local error_id='0123456789abcdef01234567'
  local projects_1="${API}/organizations/org-1/projects?per_page=100&sort=created_at&direction=asc"
  local projects_2="${API}/organizations/org-1/projects?per_page=100&page=2"
  local unrouted="${API}/organizations/org-1/projects?per_page=100&page=unrouted"
  local comments="${API}/projects/proj-1/errors/${error_id}/comments"
  local comments_1="${comments}?per_page=${BSNAG_PAGE_SIZE}"
  local comments_2="${comments}?per_page=${BSNAG_PAGE_SIZE}&page=2"
  local page

  # Appends one route. The last line matching a URL is the one the stub serves.
  route() {
    printf '%s|%s|%s|%s\n' "$1" "$2" "$fixtures/$3" "${4:-}" >>"$routes"
  }

  # Routes every request the happy path makes, with the wanted project on the
  # second page of projects. A case appends the one route it is about.
  base_routes() {
    : >"$routes"
    route "${API}/user/organizations" 200 organizations.json
    route "$projects_1" 200 projects-page-1.json "$projects_2"
    route "$projects_2" 200 projects-page-2.json
    route "${API}/projects/proj-1/errors/${error_id}" 200 error.json
    route "$comments_1" 200 comments-page-1.json
    route "${API}/projects/proj-1/errors/${error_id}/latest_event" 200 latest-event.json
  }

  # Runs the real loader over the routes written so far and compares three
  # things: the exit code, a jq projection of the emitted document, and the
  # WHOLE of stderr. An empty filter or stderr expectation skips that
  # comparison. Stderr is compared exactly rather than by substring because the
  # interesting failure is a run that prints the real cause and then carries on
  # to a second, misleading message -- a substring match reads both as a pass.
  run_load() {
    local label="$1" expect_rc="$2" filter="$3" expect_json="$4" expect_err="$5"
    local out rc err actual

    set +e
    out="$(PATH="$stub:$PATH" BUGSNAG_TOKEN='stub-token' BSNAG_STUB_ROUTES="$routes" \
      "$script" "$triple" 2>"$err_file")"
    rc=$?
    set -e
    err="$(cat "$err_file")"

    checks=$((checks + 1))

    if [[ "$rc" -ne "$expect_rc" ]]; then
      echo "self-test FAIL: $label -> exit $rc (expected $expect_rc)" >&2
      echo "$err" >&2
      failures=$((failures + 1))
      return 0
    fi

    if [[ -n "$filter" ]]; then
      actual="$(printf '%s' "$out" | jq -c "$filter" 2>/dev/null || true)"
      if [[ "$actual" != "$expect_json" ]]; then
        echo "self-test FAIL: $label -> $filter was '$actual', expected '$expect_json'" >&2
        failures=$((failures + 1))
        return 0
      fi
    fi

    if [[ -n "$expect_err" && "$err" != "$expect_err" ]]; then
      echo "self-test FAIL: $label -> stderr was '$err', expected '$expect_err'" >&2
      failures=$((failures + 1))
    fi
  }

  # The document carries the error, the project resolved off the second page of
  # projects, and the comments.
  base_routes
  run_load 'loads the error, its project and its comments' 0 \
    '[.title, .project.slug, (.comments | length), .comments[0].body]' \
    '["RuntimeException","stub-project",1,"first comment"]' ''

  # Project paging stops at the first page carrying the slug: the next link on
  # that page points at a URL no route answers, so paging past it exits 7.
  base_routes
  route "$projects_1" 200 projects-page-2.json "$unrouted"
  run_load 'stops paging projects at the first match' 0 \
    '.project.slug' '"stub-project"' ''

  # A pruned latest event degrades to null instead of aborting the whole load.
  base_routes
  route "${API}/projects/proj-1/errors/${error_id}/latest_event" 404 unauthorized.json
  run_load 'degrades a pruned latest event to null' 0 \
    '.latestEvent' 'null' ''

  # A failed comments request aborts. An empty comments list must never stand in
  # for a fetch that did not happen.
  base_routes
  route "$comments_1" 401 unauthorized.json
  run_load 'aborts when the comments request fails' 3 '' '' \
    "${PROG}: Bugsnag API returned HTTP 401 listing comments"

  # An organization the token cannot see is named, not silently resolved.
  base_routes
  route "${API}/user/organizations" 200 organizations-none.json
  run_load 'reports an unknown organization slug' 3 '' '' \
    "${PROG}: organization slug not found or not accessible: stub-org"

  # A project slug on no page is reported as not found, distinctly from a page
  # cap being hit.
  base_routes
  route "$projects_2" 200 projects-page-1.json
  run_load 'reports a project slug that is on no page' 3 '' '' \
    "${PROG}: project slug not found in organization: stub-project"

  # A failing projects page names the HTTP cause. Reporting "slug not found"
  # over a 500 would send the reader looking for a slug that is in fact there.
  base_routes
  route "$projects_1" 500 unauthorized.json
  run_load 'reports the HTTP cause when a projects page fails' 3 '' '' \
    "${PROG}: Bugsnag API returned HTTP 500 listing projects"

  # The defect this loader shipped with: the comments were fetched in one
  # request, so a thread longer than one API page came back silently short.
  base_routes
  route "$comments_1" 200 comments-page-1.json "$comments_2"
  route "$comments_2" 200 comments-page-2.json
  run_load 'follows comment pagination to the last page' 0 \
    '[.comments[].body]' \
    '["first comment","second comment","third comment"]' ''

  # A thread longer than the page cap is named on stderr. Coming back short in
  # silence is exactly what the cap must not reintroduce.
  base_routes
  route "$comments_1" 200 comments-page-1.json "${comments}?per_page=${BSNAG_PAGE_SIZE}&page=2"
  for ((page = 2; page <= BSNAG_MAX_PAGES + 1; page++)); do
    route "${comments}?per_page=${BSNAG_PAGE_SIZE}&page=${page}" 200 comments-page-1.json \
      "${comments}?per_page=${BSNAG_PAGE_SIZE}&page=$((page + 1))"
  done
  run_load 'discloses a comment thread that hits the page cap' 0 \
    '(.comments | length)' '30' \
    "${PROG}: stopped after 30 pages (3000 items) while listing comments — the result is truncated"

  # The next page is the one destination the response picks, and every request
  # carries the token, so a link off the API host stops the walk instead of
  # following it.
  base_routes
  route "$comments_1" 200 comments-page-1.json 'https://evil.example.com/comments'
  run_load 'refuses a pagination link that leaves the API host' 0 \
    '[.comments[].body]' '["first comment"]' \
    "${PROG}: refused a pagination link outside ${API}, so the read stops here: https://evil.example.com/comments"

  if [[ "$failures" -gt 0 ]]; then
    echo "${PROG}: self-test failed ($failures of $checks checks)" >&2
    return 1
  fi

  echo "${PROG}: self-test passed ($checks checks)"
}

if [[ $# -ne 1 || -z "${1:-}" ]]; then
  usage
  exit 1
fi

if [[ "$1" == '--self-test' ]]; then
  bsnag_require_tools
  self_test || exit $?
  exit 0
fi

bsnag_require_tools
bsnag_require_token

parsed="$(bsnag_parse_ref "$1")" || exit 1
ORG_SLUG="$(printf '%s' "$parsed" | awk '{print $1}')"
PROJ_SLUG="$(printf '%s' "$parsed" | awk '{print $2}')"
ERROR_ID="$(printf '%s' "$parsed" | awk '{print $3}')"

# --- resolve org id + project id (slugs are not API keys) -------------------
ORGS_JSON="$(bsnag_get "${API}/user/organizations")"
ORG_ID="$(printf '%s' "$ORGS_JSON" | jq -r --arg s "$ORG_SLUG" 'map(select(.slug == $s)) | .[0].id // empty')"
if [[ -z "$ORG_ID" ]]; then
  echo "${PROG}: organization slug not found or not accessible: $ORG_SLUG" >&2
  exit 3
fi
PROJ_JSON="$(bsnag_resolve_project_json "$ORG_ID" "$PROJ_SLUG")"
PROJ_ID="$(printf '%s' "$PROJ_JSON" | jq -r '.id')"

# --- fetch error, comments, latest event -----------------------------------
ERROR_JSON="$(bsnag_get "${API}/projects/${PROJ_ID}/errors/${ERROR_ID}")"
COMMENTS_JSON="$(bsnag_get_all_pages \
  "${API}/projects/${PROJ_ID}/errors/${ERROR_ID}/comments?per_page=${BSNAG_PAGE_SIZE}" \
  'listing comments')"

# latest_event may legitimately 404 (event pruned); degrade to null rather than abort.
EVENT_JSON='null'
if ev="$(curl -sS -w $'\n%{http_code}' \
      -H "Authorization: token ${TOKEN}" -H "X-Version: 2" \
      "${API}/projects/${PROJ_ID}/errors/${ERROR_ID}/latest_event" 2>/dev/null)"; then
  ev_http="${ev##*$'\n'}"
  ev_body="${ev%$'\n'*}"
  if [[ "$ev_http" -ge 200 && "$ev_http" -lt 300 ]]; then
    EVENT_JSON="$ev_body"
  fi
fi

DASH_URL="https://app.bugsnag.com/${ORG_SLUG}/${PROJ_SLUG}/errors/${ERROR_ID}"

# --- assemble stable JSON ---------------------------------------------------
jq -n \
  --arg dashUrl "$DASH_URL" \
  --arg orgSlug "$ORG_SLUG" \
  --arg orgId "$ORG_ID" \
  --argjson org "$ORGS_JSON" \
  --argjson project "$PROJ_JSON" \
  --argjson error "$ERROR_JSON" \
  --argjson comments "$COMMENTS_JSON" \
  --argjson event "$EVENT_JSON" '
def map_comments:
  [ (. // [])[] | {
      author:    (.collaborator.name // null),
      email:     (.collaborator.email // null),
      body:      (.message // ""),
      createdAt: (.created_at // null),
      updatedAt: (.updated_at // null)
  } ];

def map_linked:
  [ (. // [])[] | {
      type:   (.type // null),
      number: (.number // null),
      url:    (.url // null)
  } ];

def map_event:
  if . == null then null else
  (.exceptions[0] // {}) as $exc
  | {
      id:         (.id // null),
      receivedAt: (.received_at // null),
      context:    (.context // null),
      unhandled:  (.unhandled // null),
      severity:   (.severity // null),
      errorClass: ($exc.error_class // null),
      message:    ($exc.message // null),
      app: {
        id:           (.app.id // null),
        version:      (.app.version // null),
        releaseStage: (.app.release_stage // null),
        type:         (.app.type // null)
      },
      device: {
        osName:          (.device.os_name // null),
        osVersion:       (.device.os_version // null),
        runtimeVersions: (.device.runtime_versions // null)
      },
      request: {
        httpMethod: (.request.http_method // null),
        url:        (.request.url // null),
        clientIp:   (.request.client_ip // null)
      },
      user: {
        id:    (.user.id // null),
        name:  (.user.name // null),
        email: (.user.email // null)
      },
      stacktrace: [ ($exc.stacktrace // [])[] | {
        file:      (.file // null),
        line:      (.line_number // null),
        method:    (.method // null),
        inProject: (.in_project // false)
      } ],
      breadcrumbs: [ (.breadcrumbs // [])[] | {
        timestamp: (.timestamp // null),
        name:      (.name // null),
        type:      (.type // null)
      } ]
  } end;

$error as $e
| {
    kind: "bugsnag-error",
    id: ($e.id // null),
    url: $dashUrl,
    apiUrl: ($e.url // null),
    organization: {
      id: $orgId,
      slug: $orgSlug,
      name: ($org | map(select(.slug == $orgSlug)) | .[0].name // null)
    },
    project: {
      id: ($project.id // null),
      slug: ($project.slug // null),
      name: ($project.name // null),
      type: ($project.type // null),
      language: ($project.language // null)
    },
    title: ($e.error_class // null),
    errorClass: ($e.error_class // null),
    message: ($e.message // ""),
    context: ($e.context // null),
    status: ($e.status // null),
    severity: ($e.severity // null),
    events: ($e.events // 0),
    users: ($e.users // 0),
    firstSeen: ($e.first_seen // null),
    lastSeen: ($e.last_seen // null),
    createdAt: ($e.first_seen // null),
    assignedCollaboratorId: ($e.assigned_collaborator_id // null),
    assignedTeamId: ($e.assigned_team_id // null),
    releaseStages: ($e.release_stages // []),
    linkedIssues: ($e.linked_issues | map_linked),
    commentCount: ($e.comment_count // ($comments | length)),
    comments: ($comments | map_comments),
    groupingFields: {
      errorClass: ($e.grouping_fields.errorClass // null),
      file: ($e.grouping_fields.file // null)
    },
    latestEvent: ($event | map_event)
  }
'
