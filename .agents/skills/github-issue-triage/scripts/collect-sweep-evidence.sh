#!/usr/bin/env bash
# collect-sweep-evidence.sh — READ-ONLY evidence for a backlog sweep: every
# OPEN issue of the current GitHub repository with its epic, its parent, the
# same-repository pull requests that reference it, and the structural defects
# of the epic tree.
#
# Usage:
#   collect-sweep-evidence.sh
#   collect-sweep-evidence.sh --self-test
#
# Options:
#   --self-test  run the offline test suite (no network, `gh` is stubbed)
#
# What it prints, one line per open issue, sorted by number:
#   #10  EPIC   parent: -  open sub-issues: #11 #12  — <title>
#   #11  issue  epic: #10  parent: #10  labels: enhancement  prs: #20 merged->master  evidence: merged  — <title>
# followed by one `structure:` line per defect and a closing `summary:` line.
#
# Epic:
#   An issue carrying the `EPIC` label. An issue sits under an epic when the
#   epic is its parent, grandparent, or great-grandparent — three levels of
#   native sub-issues, which covers an umbrella issue between the epic and its
#   parts.
#
# Structural defects reported (never repaired — this script writes nothing):
#   - an open epic whose ancestor chain holds another epic
#     (`structure: epic #A contains epic #C`, with `(via #P)` when an
#     intermediate issue sits between them)
#   - a closed epic listed as a sub-issue of an open epic, or of an open
#     issue under an epic (`structure: epic #A contains epic #C (closed)`,
#     with `, via #P` for the intermediate issue). A closed intermediate issue
#     is not listed, so what sits under it stays out of view.
#   - an open non-epic issue with no epic in its ancestor chain
#     (`structure: #N has no epic`)
#   - an epic whose sub-issue list is longer than one page
#     (`(+N not listed)` on the epic's own line)
#   - an issue with more referencing events than one page holds
#     (`(more references not listed)` after its pull requests)
#
# Evidence, per open non-epic issue — a pointer for the reader, never a
# verdict that the issue is resolved:
#   open-pr   at least one referencing pull request is still open
#   merged    no open pull request, and at least one merged into the default
#             branch
#   unmerged  pull requests exist, but none is open and none merged into the
#             default branch (closed unmerged, or merged into another branch)
#   no-pr     no same-repository pull request references the issue
#   A pull request counts when it closes the issue (`closes` in the line) or
#   merely cross-references it (`Part of #N`, `Refs #N`). A pull request of
#   another repository is ignored: it cannot merge into this default branch.
#
# Target repository:
#   The repository `gh` resolves from the current working directory. It is
#   resolved and PRINTED as the first line of output, so a transcript always
#   names the backlog it describes.
#
# Exit codes:
#   0  the evidence was collected
#   1  wrong usage, or a failing self-test
#   2  required tool not found (gh, jq)
#   3  a `gh` call failed (auth, permissions, API error)

set -euo pipefail

EPIC_LABEL='EPIC'

# One page of open issues. `gh api graphql --paginate` walks every page through
# `$endCursor`, so no backlog is truncated; the nested lists are capped (100
# sub-issues, 20 closing and 100 cross-referencing pull requests per issue).
# shellcheck disable=SC2016 # GraphQL variables, not shell expansions
QUERY='query($owner: String!, $name: String!, $endCursor: String) {
  repository(owner: $owner, name: $name) {
    defaultBranchRef { name }
    issues(states: OPEN, first: 50, after: $endCursor, orderBy: {field: CREATED_AT, direction: ASC}) {
      pageInfo { hasNextPage endCursor }
      nodes {
        number
        title
        labels(first: 30) { nodes { name } }
        parent {
          number
          labels(first: 30) { nodes { name } }
          parent {
            number
            labels(first: 30) { nodes { name } }
            parent { number labels(first: 30) { nodes { name } } }
          }
        }
        subIssues(first: 100) { totalCount nodes { number state labels(first: 30) { nodes { name } } } }
        closedByPullRequestsReferences(first: 20, includeClosedPrs: true) {
          totalCount
          nodes { number state merged baseRefName repository { nameWithOwner } }
        }
        timelineItems(first: 100, itemTypes: [CROSS_REFERENCED_EVENT]) {
          totalCount
          nodes {
            ... on CrossReferencedEvent {
              source { ... on PullRequest { number state merged baseRefName repository { nameWithOwner } } }
            }
          }
        }
      }
    }
  }
}'

# Renders the report from the slurped GraphQL pages (a JSON array, one element
# per page). A pure function of its input: covered by --self-test.
# shellcheck disable=SC2016 # jq variables, not shell expansions
REPORT_JQ='
def names: [.labels.nodes[].name];
def is_epic: (names | index($epic)) != null;
def ancestors: [.parent | select(. != null) | recurse(.parent; . != null)];
def nearest_epic: (ancestors | map(select(is_epic)) | first);
def refs:
  ([.closedByPullRequestsReferences.nodes[] | select(.repository.nameWithOwner == $repo) | . + {closes: true}]
   + [.timelineItems.nodes[] | .source | select(. != null and .number != null and .repository.nameWithOwner == $repo) | . + {closes: false}])
  | group_by(.number)
  | map(.[0] + {closes: (map(.closes) | any)});
def pr_text:
  "#\(.number) \(if .state == "OPEN" then "open" elif .merged then "merged" else "closed" end)->\(.baseRefName)\(if .closes then " closes" else "" end)";
def evidence($default):
  if length == 0 then "no-pr"
  elif any(.[]; .state == "OPEN") then "open-pr"
  elif any(.[]; .merged and .baseRefName == $default) then "merged"
  else "unmerged" end;
def ref_or_dash: if . == null then "-" else "#\(.number)" end;
def refs_truncated:
  (.closedByPullRequestsReferences.totalCount // 0) > (.closedByPullRequestsReferences.nodes | length)
  or (.timelineItems.totalCount // 0) > (.timelineItems.nodes | length);

(.[0].data.repository.defaultBranchRef.name) as $default
| ([.[].data.repository.issues.nodes[]] | sort_by(.number)) as $issues
| ($issues | map(select(is_epic))) as $epics
| ($issues | map(select(is_epic | not)) | map(. + {refs: refs, epic: nearest_epic})) as $others
| ($epics | map(select(nearest_epic != null) | {
    epic: nearest_epic.number,
    child: .number,
    via: (if .parent.number == nearest_epic.number then null else .parent.number end)
  })) as $open_nested
| (($epics | map(. as $e | .subIssues.nodes[] | select(.state == "CLOSED" and is_epic) | {epic: $e.number, child: .number, via: null}))
   + ($others | map(select(.epic != null) | . as $o | .subIssues.nodes[] | select(.state == "CLOSED" and is_epic) | {epic: $o.epic.number, child: .number, via: $o.number}))) as $closed_nested
| ($others | map(select(.epic == null))) as $orphans
| (
    ($issues[] | if is_epic then
      "#\(.number)  EPIC   parent: \(.parent | ref_or_dash)  open sub-issues: \([.subIssues.nodes[] | select(.state == "OPEN") | "#\(.number)"] | if length == 0 then "-" else join(" ") end)\(if .subIssues.totalCount > (.subIssues.nodes | length) then " (+\(.subIssues.totalCount - (.subIssues.nodes | length)) not listed)" else "" end)  — \(.title)"
    else
      (.number) as $n | ($others[] | select(.number == $n)) |
      "#\(.number)  issue  epic: \(.epic | ref_or_dash)  parent: \(.parent | ref_or_dash)  labels: \(names | if length == 0 then "-" else join(", ") end)  prs: \(.refs | if length == 0 then "-" else map(pr_text) | join(", ") end)\(if refs_truncated then " (more references not listed)" else "" end)  evidence: \(.refs | evidence($default))  — \(.title)"
    end),
    ($open_nested[] | "structure: epic #\(.epic) contains epic #\(.child)\(if .via == null then "" else " (via #\(.via))" end)"),
    ($closed_nested[] | "structure: epic #\(.epic) contains epic #\(.child) (closed\(if .via == null then "" else ", via #\(.via)" end))"),
    ($orphans[] | "structure: #\(.number) has no epic"),
    "summary: \($issues | length) open issues — \($epics | length) epics, \($others | length) other; \(($open_nested | length) + ($closed_nested | length)) nesting violations, \($orphans | length) without an epic; evidence: \([$others[] | select((.refs | evidence($default)) == "merged")] | length) merged, \([$others[] | select((.refs | evidence($default)) == "open-pr")] | length) open-pr, \([$others[] | select((.refs | evidence($default)) == "unmerged")] | length) unmerged, \([$others[] | select((.refs | evidence($default)) == "no-pr")] | length) no-pr"
  )
'

usage() {
  cat >&2 <<'EOF'
Usage: collect-sweep-evidence.sh
       collect-sweep-evidence.sh --self-test

  Prints, for every open issue of the current repository, its epic, its
  parent, and the pull requests that reference it, then the defects of the
  epic tree. Read-only: it never writes to GitHub.

  --self-test  run the offline test suite against a stubbed gh
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

# The report is proven by RUNNING the script against a stubbed `gh` that
# answers from a two-page fixture and records every call. The stub refuses any
# call other than the two reads, so a passing run is also the proof that the
# script writes nothing. The precedent is `assign-priorities.sh --self-test`.
self_test() {
  local failures=0
  local checks=0
  local script stub out rc calls expected

  script="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)/$(basename "${BASH_SOURCE[0]}")"

  SELF_TEST_TMP="$(mktemp -d)"
  trap cleanup_self_test EXIT

  stub="$SELF_TEST_TMP/bin"
  mkdir -p "$stub"

  cat >"$stub/gh" <<'STUB'
#!/usr/bin/env bash
# Stand-in for the two reads the sweep evidence makes. Every call is recorded
# (the multi-line GraphQL document is left out); any other call fails the run.
set -euo pipefail

recorded=()
for arg in "$@"; do
  if [[ "$arg" == query=* ]]; then
    recorded+=('query=<document>')
  else
    recorded+=("$arg")
  fi
done
(
  IFS='|'
  printf '%s\n' "${recorded[*]}"
) >>"$GH_STUB_CALLS"

case "${1:-} ${2:-}" in
  'repo view')
    printf '%s\n' "$GH_STUB_NWO"
    ;;
  'api graphql')
    if [[ "${GH_STUB_FAIL:-}" == '1' ]]; then
      echo 'HTTP 502: Bad Gateway' >&2
      exit 1
    fi
    cat "$GH_STUB_PAGES"
    ;;
  *)
    echo "gh stub: unexpected call: $*" >&2
    exit 1
    ;;
esac
STUB
  chmod +x "$stub/gh"

  local STUB_NWO='stub-owner/stub-repo'

  # Two pages, concatenated exactly as `gh api graphql --paginate` prints them.
  cat >"$SELF_TEST_TMP/pages.json" <<'PAGES'
{"data":{"repository":{"defaultBranchRef":{"name":"master"},"issues":{"pageInfo":{"hasNextPage":true,"endCursor":"c1"},"nodes":[
{"number":10,"title":"EPIC | Orders","labels":{"nodes":[{"name":"EPIC"}]},"parent":null,
 "subIssues":{"totalCount":4,"nodes":[
   {"number":11,"state":"OPEN","labels":{"nodes":[{"name":"enhancement"}]}},
   {"number":12,"state":"OPEN","labels":{"nodes":[{"name":"EPIC"}]}},
   {"number":13,"state":"CLOSED","labels":{"nodes":[{"name":"EPIC"}]}}]},
 "closedByPullRequestsReferences":{"nodes":[]},"timelineItems":{"nodes":[]}},
{"number":11,"title":"feat: umbrella","labels":{"nodes":[{"name":"enhancement"}]},
 "parent":{"number":10,"labels":{"nodes":[{"name":"EPIC"}]},"parent":null},
 "subIssues":{"totalCount":2,"nodes":[{"number":14,"state":"OPEN","labels":{"nodes":[]}},{"number":18,"state":"CLOSED","labels":{"nodes":[{"name":"EPIC"}]}}]},
 "closedByPullRequestsReferences":{"nodes":[]},
 "timelineItems":{"nodes":[{"source":{"number":20,"state":"MERGED","merged":true,"baseRefName":"master","repository":{"nameWithOwner":"stub-owner/stub-repo"}}},{}]}},
{"number":12,"title":"EPIC | Nested","labels":{"nodes":[{"name":"EPIC"}]},
 "parent":{"number":10,"labels":{"nodes":[{"name":"EPIC"}]},"parent":null},
 "subIssues":{"totalCount":0,"nodes":[]},
 "closedByPullRequestsReferences":{"nodes":[]},"timelineItems":{"nodes":[]}}
]}}}}
{"data":{"repository":{"defaultBranchRef":{"name":"master"},"issues":{"pageInfo":{"hasNextPage":false,"endCursor":"c2"},"nodes":[
{"number":14,"title":"fix: child of the umbrella","labels":{"nodes":[{"name":"bug"},{"name":"priority: high"}]},
 "parent":{"number":11,"labels":{"nodes":[{"name":"enhancement"}]},"parent":{"number":10,"labels":{"nodes":[{"name":"EPIC"}]},"parent":null}},
 "subIssues":{"totalCount":0,"nodes":[]},
 "closedByPullRequestsReferences":{"nodes":[{"number":21,"state":"OPEN","merged":false,"baseRefName":"master","repository":{"nameWithOwner":"stub-owner/stub-repo"}}]},
 "timelineItems":{"nodes":[
   {"source":{"number":21,"state":"OPEN","merged":false,"baseRefName":"master","repository":{"nameWithOwner":"stub-owner/stub-repo"}}},
   {"source":{"number":22,"state":"MERGED","merged":true,"baseRefName":"master","repository":{"nameWithOwner":"stub-owner/stub-repo"}}},
   {"source":{"number":99,"state":"MERGED","merged":true,"baseRefName":"master","repository":{"nameWithOwner":"other-owner/fork"}}}]}},
{"number":15,"title":"docs: orphan","labels":{"nodes":[{"name":"documentation"}]},"parent":null,
 "subIssues":{"totalCount":0,"nodes":[]},
 "closedByPullRequestsReferences":{"nodes":[]},"timelineItems":{"nodes":[]}},
{"number":16,"title":"EPIC | Deep","labels":{"nodes":[{"name":"EPIC"}]},
 "parent":{"number":11,"labels":{"nodes":[{"name":"enhancement"}]},"parent":{"number":10,"labels":{"nodes":[{"name":"EPIC"}]},"parent":null}},
 "subIssues":{"totalCount":0,"nodes":[]},
 "closedByPullRequestsReferences":{"nodes":[]},"timelineItems":{"nodes":[]}},
{"number":17,"title":"chore: merged elsewhere","labels":{"nodes":[{"name":"chore"}]},
 "parent":{"number":10,"labels":{"nodes":[{"name":"EPIC"}]},"parent":null},
 "subIssues":{"totalCount":0,"nodes":[]},
 "closedByPullRequestsReferences":{"nodes":[{"number":23,"state":"MERGED","merged":true,"baseRefName":"release","repository":{"nameWithOwner":"stub-owner/stub-repo"}}]},
 "timelineItems":{"totalCount":150,"nodes":[{"source":{"number":24,"state":"CLOSED","merged":false,"baseRefName":"master","repository":{"nameWithOwner":"stub-owner/stub-repo"}}}]}}
]}}}}
PAGES

  run_script() {
    : >"$SELF_TEST_TMP/calls"
    set +e
    out="$(cd "$SELF_TEST_TMP" && PATH="$stub:$PATH" \
      GH_STUB_NWO="$STUB_NWO" \
      GH_STUB_PAGES="$SELF_TEST_TMP/pages.json" \
      GH_STUB_CALLS="$SELF_TEST_TMP/calls" \
      GH_STUB_FAIL="${1:-}" \
      "$script" 2>&1)"
    rc=$?
    set -e
    calls="$(cat "$SELF_TEST_TMP/calls")"
  }

  expect_line() {
    local label="$1" line="$2"

    checks=$((checks + 1))
    if [[ "$out" != *"$line"* ]]; then
      echo "self-test FAIL: $label -> missing line: $line" >&2
      failures=$((failures + 1))
    fi
  }

  run_script ''

  checks=$((checks + 1))
  if [[ "$rc" -ne 0 ]]; then
    echo "self-test FAIL: run over the fixture -> exit $rc" >&2
    echo "$out" >&2
    failures=$((failures + 1))
  fi

  expect_line 'target — the run names the repository it read' \
    "target repository: $STUB_NWO"
  expect_line 'target — the run names the default branch the evidence is measured against' \
    'default branch: master'
  expect_line 'epic — open sub-issues listed, a truncated list is reported' \
    '#10  EPIC   parent: -  open sub-issues: #11 #12 (+1 not listed)  — EPIC | Orders'
  expect_line 'epic — a nested epic names its parent' \
    '#12  EPIC   parent: #10  open sub-issues: -  — EPIC | Nested'
  expect_line 'evidence — a merged pull request into the default branch' \
    '#11  issue  epic: #10  parent: #10  labels: enhancement  prs: #20 merged->master  evidence: merged  — feat: umbrella'
  expect_line 'evidence — an open pull request wins, one pull request is listed once, a foreign one is ignored' \
    '#14  issue  epic: #10  parent: #11  labels: bug, priority: high  prs: #21 open->master closes, #22 merged->master  evidence: open-pr  — fix: child of the umbrella'
  expect_line 'evidence — no pull request at all' \
    '#15  issue  epic: -  parent: -  labels: documentation  prs: -  evidence: no-pr  — docs: orphan'
  expect_line 'evidence — merged into another branch is not merged, a truncated timeline is reported' \
    '#17  issue  epic: #10  parent: #10  labels: chore  prs: #23 merged->release closes, #24 closed->master (more references not listed)  evidence: unmerged  — chore: merged elsewhere'
  expect_line 'structure — a direct epic in an epic' \
    'structure: epic #10 contains epic #12'
  expect_line 'structure — an epic in an epic through an umbrella issue' \
    'structure: epic #10 contains epic #16 (via #11)'
  expect_line 'structure — a closed epic in an open epic' \
    'structure: epic #10 contains epic #13 (closed)'
  expect_line 'structure — a closed epic under an umbrella issue in an open epic' \
    'structure: epic #10 contains epic #18 (closed, via #11)'
  expect_line 'structure — an issue with no epic' \
    'structure: #15 has no epic'
  expect_line 'summary — every bucket is counted separately' \
    'summary: 7 open issues — 3 epics, 4 other; 4 nesting violations, 1 without an epic; evidence: 1 merged, 1 open-pr, 1 unmerged, 1 no-pr'

  checks=$((checks + 1))
  if [[ "$out" == *'structure: #11 has no epic'* || "$out" == *'structure: #14 has no epic'* ]]; then
    echo "self-test FAIL: structure — an issue under an umbrella under an epic was reported without an epic" >&2
    failures=$((failures + 1))
  fi

  # Read-only: exactly the two reads, and the GraphQL read walks every page.
  expected="repo|view|--json|nameWithOwner|--jq|.nameWithOwner
api|graphql|--paginate|-f|owner=stub-owner|-f|name=stub-repo|-f|query=<document>"
  checks=$((checks + 1))
  if [[ "$calls" != "$expected" ]]; then
    echo "self-test FAIL: read-only — gh calls were:" >&2
    echo "$calls" >&2
    failures=$((failures + 1))
  fi

  # A failing read stops the run with exit 3 and names the gh error.
  run_script '1'
  checks=$((checks + 1))
  if [[ "$rc" -ne 3 || "$out" != *"target repository: $STUB_NWO"* || "$out" != *'failed to load the open issues: HTTP 502: Bad Gateway'* ]]; then
    echo "self-test FAIL: gh failure -> exit $rc" >&2
    echo "$out" >&2
    failures=$((failures + 1))
  fi

  if [[ "$failures" -gt 0 ]]; then
    echo "collect-sweep-evidence.sh: self-test failed ($failures of $checks checks)" >&2
    return 1
  fi

  echo "collect-sweep-evidence.sh: self-test passed ($checks checks)"
}

# --- arguments --------------------------------------------------------------

if [[ $# -gt 1 ]]; then
  echo "collect-sweep-evidence.sh: too many arguments" >&2
  usage
  exit 1
fi

if [[ $# -eq 1 ]]; then
  case "$1" in
    --self-test)
      # The self-test runs this script for real, so it needs `jq` — only `gh`
      # is stubbed.
      if ! command -v jq >/dev/null 2>&1; then
        echo "collect-sweep-evidence.sh: the self-test requires jq" >&2
        exit 2
      fi
      self_test || exit $?
      exit 0
      ;;
    -h | --help)
      usage
      exit 0
      ;;
    *)
      echo "collect-sweep-evidence.sh: unknown argument: $1" >&2
      usage
      exit 1
      ;;
  esac
fi

for bin in gh jq; do
  if ! command -v "$bin" >/dev/null 2>&1; then
    echo "collect-sweep-evidence.sh: required tool not found: $bin" >&2
    exit 2
  fi
done

# --- collect ----------------------------------------------------------------

if ! repo_nwo="$(gh repo view --json nameWithOwner --jq '.nameWithOwner' 2>&1)"; then
  echo "collect-sweep-evidence.sh: failed to resolve the target repository: $repo_nwo" >&2
  exit 3
fi

echo "collect-sweep-evidence.sh: target repository: $repo_nwo"

PAGES_JSON="$(mktemp)"
trap 'rm -f "$PAGES_JSON"' EXIT

if ! gh_error="$(gh api graphql --paginate -f owner="${repo_nwo%%/*}" -f name="${repo_nwo#*/}" -f query="$QUERY" 2>&1 >"$PAGES_JSON")"; then
  echo "collect-sweep-evidence.sh: failed to load the open issues: $gh_error" >&2
  exit 3
fi

if ! default_branch="$(jq -r -s '.[0].data.repository.defaultBranchRef.name' "$PAGES_JSON")"; then
  echo "collect-sweep-evidence.sh: unexpected non-JSON response from gh" >&2
  exit 3
fi

echo "collect-sweep-evidence.sh: default branch: $default_branch"

jq -r -s --arg epic "$EPIC_LABEL" --arg repo "$repo_nwo" "$REPORT_JQ" "$PAGES_JSON"
