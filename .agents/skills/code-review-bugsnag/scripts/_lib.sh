#!/usr/bin/env bash
# _lib.sh — shared helpers for the Bugsnag Data Access API entry points
# (load-issue.sh, upsert-comment.sh). Sourced, not executed. Keeps the URL/triple
# parse grammar, the status-checked HTTP helper, and the slug→id resolution in one
# place so a fix lands once instead of in every entry script.
#
# Contract for sourcing scripts:
#   - set PROG (used in error messages) before sourcing, or it defaults to $0's basename
#   - call bsnag_require_tools and bsnag_require_token once at startup
#   - TOKEN is exported into the caller's scope by bsnag_require_token
#
# All helpers honor the deterministic exit-code contract: 2 = missing tool/token,
# 3 = Bugsnag API/network failure. They never print the token.

API="https://api.bugsnag.com"
: "${PROG:=${0##*/}}"

# The shape of every paged read: 100 items per request, and at most 30 requests.
# The cap exists so a runaway `Link: rel="next"` chain terminates; hitting it is
# reported, never returned as a short answer that reads like a complete one.
BSNAG_PAGE_SIZE=100
BSNAG_MAX_PAGES=30

bsnag_require_tools() {
  local bin
  for bin in curl jq; do
    if ! command -v "$bin" >/dev/null 2>&1; then
      echo "${PROG}: required tool not found: $bin" >&2
      exit 2
    fi
  done
}

bsnag_require_token() {
  TOKEN="${BUGSNAG_TOKEN:-${BUGSNAG_AUTH_TOKEN:-}}"
  if [[ -z "$TOKEN" ]]; then
    echo "${PROG}: BUGSNAG_TOKEN is not set (export a Data Access API token)" >&2
    exit 2
  fi
}

# bsnag_parse_ref <input> -> echoes "<org-slug> <project-slug> <error-id>" or returns 1.
# Accepts an app.bugsnag.com error URL or an <org>/<project>/<error-id> triple.
bsnag_parse_ref() {
  local input="$1" parsed
  if [[ "$input" =~ ^https?://(www\.)?app\.bugsnag\.com/ ]]; then
    parsed="$(printf '%s' "$input" | sed -nE 's#^https?://(www\.)?app\.bugsnag\.com/([^/]+)/([^/]+)/errors/([0-9a-fA-F]+).*#\2 \3 \4#p')"
  elif [[ "$input" =~ ^[^/]+/[^/]+/[0-9a-fA-F]+$ ]]; then
    parsed="$(printf '%s' "$input" | awk -F/ '{print $1, $2, $3}')"
  else
    echo "${PROG}: argument must be an app.bugsnag.com URL or <org>/<project>/<error-id>: $input" >&2
    return 1
  fi
  if [[ -z "$parsed" ]]; then
    echo "${PROG}: could not extract org/project/error from input: $input" >&2
    return 1
  fi
  printf '%s' "$parsed"
}

# bsnag_get <url> -> echoes the response body; aborts with exit 3 on any non-2xx.
bsnag_get() {
  local url="$1" body http
  body="$(curl -sS -w $'\n%{http_code}' \
    -H "Authorization: token ${TOKEN}" \
    -H "X-Version: 2" \
    -H "Content-Type: application/json" \
    "$url")" || { echo "${PROG}: network error calling $url" >&2; exit 3; }
  http="${body##*$'\n'}"
  body="${body%$'\n'*}"
  if [[ "$http" -lt 200 || "$http" -ge 300 ]]; then
    echo "${PROG}: Bugsnag API returned HTTP $http for $url" >&2
    exit 3
  fi
  printf '%s' "$body"
}

# bsnag_resolve_org_id <org-slug> -> echoes the numeric org id; aborts on failure.
bsnag_resolve_org_id() {
  local org_slug="$1" id
  id="$(bsnag_get "${API}/user/organizations" | jq -r --arg s "$org_slug" 'map(select(.slug == $s)) | .[0].id // empty')"
  if [[ -z "$id" ]]; then
    echo "${PROG}: organization slug not found or not accessible: $org_slug" >&2
    exit 3
  fi
  printf '%s' "$id"
}

# bsnag_get_page <url> <headers-file> <what> -> echoes the response body and
# leaves the response headers in <headers-file> for bsnag_next_page_url; fails
# with status 3 on a network error or any non-2xx, naming <what> so each caller's
# message reads as its own. The failing paths remove <headers-file> themselves,
# because they never return to the caller that would otherwise clean it up.
#
# Every caller tests the call rather than leaning on `set -e`: this helper runs
# inside a command substitution that is itself inside one, and bash carries an
# `exit` out of the inner substitution only as a status, so an unchecked call
# leaves the caller running on an empty body.
bsnag_get_page() {
  local url="$1" headers="$2" what="$3" body http
  body="$(curl -sS -w $'\n%{http_code}' -D "$headers" \
    -H "Authorization: token ${TOKEN}" -H "X-Version: 2" "$url")" \
    || { rm -f "$headers"; echo "${PROG}: network error $what" >&2; exit 3; }
  http="${body##*$'\n'}"
  body="${body%$'\n'*}"
  if [[ "$http" -lt 200 || "$http" -ge 300 ]]; then
    rm -f "$headers"
    echo "${PROG}: Bugsnag API returned HTTP $http $what" >&2
    exit 3
  fi
  printf '%s' "$body"
}

# bsnag_next_page_url <headers-file> -> echoes the URL the response's
# `Link: rel="next"` header points at, or nothing when this was the last page.
#
# The next page is the one request whose destination the response chooses rather
# than this script, and every paged request carries the Data Access token in an
# Authorization header. A link pointing off ${API} is therefore refused: the
# walk stops there and says so, instead of handing the token to whatever host
# the header named.
bsnag_next_page_url() {
  local next
  next="$(grep -i '^link:' "$1" | sed -nE 's/.*<([^>]+)>; *rel="next".*/\1/p' || true)"
  if [[ -n "$next" && "$next" != "${API}/"* ]]; then
    echo "${PROG}: refused a pagination link outside ${API}, so the read stops here: $next" >&2
    return 0
  fi
  printf '%s' "$next"
}

# bsnag_get_all_pages <url> <what> -> echoes one JSON array carrying the items of
# every page, following `Link: rel="next"` from the first page onwards. A
# collection that outgrows the page cap is named on stderr and the pages already
# read are still returned: a short answer nobody was told about reads exactly like
# a complete one, which is the failure this helper exists to prevent.
bsnag_get_all_pages() {
  local url="$1" what="$2"
  local next="$url" pages=0 headers page items='[]'
  while [[ -n "$next" && "$pages" -lt "$BSNAG_MAX_PAGES" ]]; do
    pages=$((pages + 1))
    headers="$(mktemp)"
    if ! page="$(bsnag_get_page "$next" "$headers" "$what")"; then
      rm -f "$headers"
      exit 3
    fi
    items="$(jq -c -n --argjson acc "$items" --argjson page "$page" '$acc + $page')"
    next="$(bsnag_next_page_url "$headers")"
    rm -f "$headers"
  done
  if [[ -n "$next" ]]; then
    echo "${PROG}: stopped after ${BSNAG_MAX_PAGES} pages ($((BSNAG_MAX_PAGES * BSNAG_PAGE_SIZE)) items) while ${what} — the result is truncated" >&2
  fi
  printf '%s' "$items"
}

# bsnag_resolve_project_json <org-id> <project-slug> -> echoes the matching project
# JSON object; aborts on failure. The walk stops at the first page carrying the
# slug, so a large organization costs one request in the common case, and a hit on
# the page cap is reported distinctly rather than silently collapsing into
# "not found".
bsnag_resolve_project_json() {
  local org_id="$1" proj_slug="$2"
  local next="${API}/organizations/${org_id}/projects?per_page=${BSNAG_PAGE_SIZE}&sort=created_at&direction=asc"
  local pages=0 headers page match
  while [[ -n "$next" && "$pages" -lt "$BSNAG_MAX_PAGES" ]]; do
    pages=$((pages + 1))
    headers="$(mktemp)"
    if ! page="$(bsnag_get_page "$next" "$headers" 'listing projects')"; then
      rm -f "$headers"
      exit 3
    fi
    match="$(printf '%s' "$page" | jq -c --arg s "$proj_slug" 'map(select(.slug == $s)) | .[0] // empty' 2>/dev/null || true)"
    if [[ -n "$match" ]]; then
      rm -f "$headers"
      printf '%s' "$match"
      return 0
    fi
    next="$(bsnag_next_page_url "$headers")"
    rm -f "$headers"
  done
  if [[ "$pages" -ge "$BSNAG_MAX_PAGES" && -n "$next" ]]; then
    echo "${PROG}: stopped after ${BSNAG_MAX_PAGES} pages ($((BSNAG_MAX_PAGES * BSNAG_PAGE_SIZE)) projects) without finding slug: $proj_slug" >&2
  else
    echo "${PROG}: project slug not found in organization: $proj_slug" >&2
  fi
  exit 3
}
