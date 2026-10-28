#!/usr/bin/env bash
# review-state.sh — the state of one review-and-fix loop: its rounds, the status of every finding, the round
# cap, and the convergence verdict.
#
# Why this exists
#   The review loop of skills/process-code-review/SKILL.md counted findings in prose, round by round. The same
#   finding came back as new, a finding without evidence blocked like a proven defect, a resolved finding was
#   reported again, and nothing outside the loop could tell why it stopped. This script keeps that state as
#   data, under the git-ignored run directory, and computes the verdict the same way every time.
#
#   The loop contract (what a round is, the statuses, who may change them, the cap, and the escalation) is
#   written once, in skills/process-code-review/references/review-state.md. The record schema it stores is
#   written in skills/code-review/references/finding-records.md *Review-loop records (schema 2)*. This header
#   only documents the command line.
#
# Usage
#   review-state.sh init     --state <file> --repo <owner/name> --pr <number>
#   review-state.sh record   --state <file> --input <report|-> [--changed-files <file|->]
#   review-state.sh evaluate --state <file> [--final]
#   review-state.sh scope    --state <file> --changed-files <file|->
#   review-state.sh dismiss  --state <file> --finding <id> --comment <comment-url>
#   review-state.sh defer    --state <file> --finding <id> --url <https-url>
#   review-state.sh --self-test
#
#   --state          the state file. Every command that writes it refuses a path outside the `.claude/run/` or
#                    `.codex/run/` directory of the git toplevel, a symbolic link, and a tracked file.
#   --input          the findings report of one review round (skills/_shared/extract-findings.sh --round).
#   --changed-files  the paths the round's delta changed, one per line (`git diff --name-only <baseline>..HEAD`).
#                    Required by `record` once an earlier round exists, and by `scope`.
#   --final          at the cap round, escalate when a blocking finding is still neither fixed nor deferred.
#   --comment        the URL of the rejection: a comment on the pull request of the state
#                    (https://github.com/<owner>/<name>/pull/<n>#issuecomment-<id>). The script loads the pull
#                    request through skills/code-review-github/scripts/load-issue.sh and reads the comment's author
#                    association itself. It refuses a comment it cannot load or find, an association other than
#                    OWNER, MEMBER, or COLLABORATOR, a comment that carries an agent marker, and a comment that does
#                    not name the finding_id it rejects. No caller states the association.
#
#   The round cap and the blocking threshold come only from the default-branch manifest, through
#   read-manifest.sh: `review.max-iterations` (an integer from 1 to 10, default 3) and
#   `review.blocking-threshold` (critical, high, medium, or low; default critical). No environment variable,
#   argument, report, or comment changes them. Run the script from the project root, like read-manifest.sh.
#
#   The round report and every text of a finding are untrusted input (rules/security/general.md). They are
#   read as data: no part of them is executed or used to build a command, a path, or a jq program.
#
# Output (stdout, one line of JSON)
#   init      {"resumed", "iteration", "max_iterations", "blocking_threshold"}
#   record, evaluate, dismiss, defer
#             the verdict: {"verdict", "status", "escalation_reason", "iteration", "max_iterations",
#             "blocking_threshold", "reason", "counts", "rounds", "blocking", "deferrable", "carried"}
#   scope     {"scope": "delta"|"full", "reasons": [...], "baseline": <sha>|null}; the scope is also stored
#             for the next `record`
#
# Exit codes
#   0  success — the verdict is in the output, never in the exit code
#   1  usage error
#   2  a required tool is missing (git, jq)
#   3  the state or the round report is missing, unreadable, or invalid; nothing was written, and the loop is
#      not converged
#   4  the policy refused the operation (a security finding, an untrusted author, a deferral before the cap)
#   5  the loop is closed: it escalated, or its round cap is spent
set -euo pipefail

PROG="${0##*/}"
HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
LOADER="$HERE/../code-review-github/scripts/load-issue.sh"

DEFAULT_CAP=3
MAX_CAP=10
MAX_CHANGED_FILES=20000

usage() {
  cat >&2 <<'EOF'
Usage: review-state.sh init     --state <file> --repo <owner/name> --pr <number>
       review-state.sh record   --state <file> --input <report|-> [--changed-files <file|->]
       review-state.sh evaluate --state <file> [--final]
       review-state.sh scope    --state <file> --changed-files <file|->
       review-state.sh dismiss  --state <file> --finding <id> --comment <comment-url>
       review-state.sh defer    --state <file> --finding <id> --url <https-url>
       review-state.sh --self-test
EOF
}

die_usage() {
  echo "$PROG: $1" >&2
  usage
  exit 1
}

fail() {
  echo "$PROG: $2" >&2
  exit "$1"
}

safe_display() {
  printf '%s' "$1" | LC_ALL=C tr -cd '[:print:]' | cut -c1-160
}

require_tools() {
  local tool
  for tool in git jq; do
    command -v "$tool" >/dev/null 2>&1 || fail 2 "required tool not found: $tool"
  done
}

# The jq definitions every command shares. They are program text this script ships; no input contributes to them.
# finding-defs.jq holds the ones extract-findings.sh shares.
JQ_STATE=''
IFS= read -r -d '' JQ_STATE <<'EOF' || true
include "finding-defs";

def isint($v; $min): ($v | type) == "number" and ($v | floor) == $v and $v >= $min;
def is_open: .status == "new" or .status == "confirmed" or .status == "needs-verification";
# A finding blocks when it carries evidence, or when it is security-relevant even without evidence (the S1-S3 floor).
def is_blocking: .status == "new" or .status == "confirmed" or (.status == "needs-verification" and .security);
# A hard blocker is never deferred: a security finding, or a severity at or above the blocking threshold.
def is_hard($threshold): .security or ((.severity | severity_rank) >= ($threshold | severity_rank));
# A blocking finding in a file the delta did not change: a delta review cannot show whether it is gone. A finding
# whose location names no file (".") is outside every delta.
def outside_delta($changed): . as $f | ($f | is_blocking) and ($changed | index([$f.file])) == null;

# Every problem the state has; an empty array means the state is valid.
def state_errors:
  . as $s
  | if ($s | type) != "object" then ["the state is not a JSON object"] else
    ["schema", "repo", "pr", "iteration", "max_iterations", "blocking_threshold", "status", "escalation_reason",
     "revision", "scope", "findings", "deferrals", "transitions", "rounds"] as $keys
    | (($s.findings // []) | if type == "array" then map(.finding_id) else [] end) as $ids
    | [
        (($s | keys) - $keys | .[] | "unknown key \(.)"),
        ($keys - ($s | keys) | .[] | "missing key \(.)"),
        (if $s.schema == 1 then empty else "schema must be 1" end),
        (if isstr($s.repo; "^[A-Za-z0-9_.-]+/[A-Za-z0-9_.-]+$") then empty else "repo must be owner/name" end),
        (if isint($s.pr; 1) then empty else "pr must be a positive integer" end),
        (if isint($s.iteration; 0) then empty else "iteration must be a non-negative integer" end),
        (if ($s.rounds | type) == "array" and ($s.rounds | length) == $s.iteration
            and ([range(0; $s.rounds | length)] | all(. as $i | $s.rounds[$i].iteration == $i + 1))
         then empty else "rounds must list every iteration once, in order, up to the iteration count" end),
        (if ($s.rounds | type) == "array" and all($s.rounds[];
              type == "object" and (keys == (["confirmed", "dismissed", "iteration", "needs_verification", "new", "remaining_blocking",
                "reopened", "resolved", "revision", "verdict"]))
              and all(.new, .confirmed, .resolved, .dismissed, .reopened, .needs_verification, .remaining_blocking; isint(.; 0))
              and isstr(.revision; "^[0-9a-f]{7,64}$")
              and (.verdict as $v | ["continue", "converged", "deferral-required", "escalated"] | index([$v])) != null)
         then empty else "a round entry is malformed" end),
        (if isint($s.max_iterations; 1) and $s.max_iterations <= 10 then empty else "max_iterations must be an integer from 1 to 10" end),
        (if (["critical", "high", "medium", "low"] | index([$s.blocking_threshold])) != null then empty
         else "blocking_threshold must be critical, high, medium, or low" end),
        (if (["open", "converged", "escalated"] | index([$s.status])) != null then empty else "status must be open, converged, or escalated" end),
        (if ($s.status == "escalated") == ($s.escalation_reason != null) then empty
         else "escalation_reason must be set exactly when the status is escalated" end),
        (if $s.escalation_reason == null
            or (["cap-reached-hard-blockers", "cap-reached-undeferred-blockers", "cap-spent-after-convergence"]
                | index([$s.escalation_reason])) != null
         then empty else "escalation_reason is not a known reason" end),
        (if $s.status == "converged" and $s.iteration == 0 then "a state without a review round is never converged" else empty end),
        (if $s.revision == null or isstr($s.revision; "^[0-9a-f]{7,64}$") then empty else "revision must be null or a commit SHA" end),
        (if $s.scope == null or $s.scope == "delta" or $s.scope == "full" then empty else "scope must be null, delta, or full" end),
        (if ($s.findings | type) == "array" and all($s.findings[]; type == "object" and .repo == $s.repo and .pr == $s.pr)
         then empty else "every finding must belong to the pull request of the state" end),
        (if ($s.deferrals | type) == "array" and all($s.deferrals[];
              type == "object" and keys == ["finding_id", "url"] and (.finding_id as $id | $ids | index([$id])) != null
              and isstr(.url; "^https://\\S+$") and (.url | length) <= 500)
         then empty else "a deferral is malformed or names an unknown finding" end),
        (if ($s.transitions | type) == "array" and all($s.transitions[];
              type == "object" and keys == ["actor", "finding_id", "from", "iteration", "to"]
              and (.finding_id as $id | $ids | index([$id])) != null and isint(.iteration; 1) and .iteration <= $s.iteration
              and (.from == null or (.from | status_rank) > 0) and (.to | status_rank) > 0
              and (if .to == "dismissed" then isstr(.actor; "^trusted:(OWNER|MEMBER|COLLABORATOR)$")
                   else .actor == "reviewer" end))
         then empty else "a transition is malformed" end),
        # Every status is the end of the finding's own history: no status changes without a recorded transition.
        (if ($s.findings | type) == "array" and ($s.transitions | type) == "array" and all($s.findings[];
              . as $f | ([$s.transitions[] | select(.finding_id == $f.finding_id)] | last | .to?) == $f.status)
         then empty else "a finding status has no matching transition" end)
      ]
    end;

# The verdict of the state under the effective configuration. A state without a review round never converges.
def verdict($cap; $threshold):
  . as $s
  | ($s.deferrals | map(.finding_id)) as $deferred
  | [ $s.findings[] | select(is_blocking)
      | select(is_hard($threshold) or (.finding_id as $id | $deferred | index([$id])) == null) ] as $open
  | ($open | map(select(is_hard($threshold)))) as $hard
  | (if $s.status == "escalated" then "escalated"
     elif $s.iteration == 0 then "continue"
     elif ($open | length) == 0 then "converged"
     elif $s.iteration < $cap then "continue"
     elif ($hard | length) > 0 then "escalated"
     else "deferral-required" end) as $v
  | {
      verdict: $v,
      escalation_reason: (if $s.status == "escalated" then $s.escalation_reason
                          elif $v == "escalated" then "cap-reached-hard-blockers" else null end),
      open: $open,
      deferrable: ($open | map(select(is_hard($threshold) | not)))
    };

def brief: {finding_id, severity, security, status, file, line};

def output($cap; $threshold; $carried):
  . as $s
  | verdict($cap; $threshold) as $v
  | {
      verdict: $v.verdict,
      status: $s.status,
      escalation_reason: $s.escalation_reason,
      iteration: $s.iteration,
      max_iterations: $cap,
      blocking_threshold: $threshold,
      reason: (if $v.verdict == "converged" then "no blocking finding is left"
               elif $v.verdict == "continue" and $s.iteration == 0 then "no review round is recorded yet"
               elif $v.verdict == "continue" then "\($v.open | length) blocking finding(s) are left after round \($s.iteration) of \($cap)"
               elif $v.verdict == "deferral-required" then "the round cap of \($cap) is reached; \($v.deferrable | length) blocking finding(s) are left that are neither security-relevant nor at or above the blocking threshold: fix or defer each one, or escalate"
               elif $s.escalation_reason == "cap-spent-after-convergence" then "the loop converged in the cap round of \($cap), and a later change needs a review round the cap no longer allows"
               elif $s.escalation_reason == "cap-reached-undeferred-blockers" then "the round cap of \($cap) is reached and \($v.open | length) blocking finding(s) were neither fixed nor deferred"
               else "the round cap of \($cap) is reached and \($v.open | length) blocking finding(s) are left, at least one of them security-relevant or at or above the blocking threshold" end),
      counts: {
        new: ($s.rounds | map(.new) | add // 0),
        confirmed: ($s.findings | map(select(.status == "confirmed")) | length),
        resolved: ($s.findings | map(select(.status == "resolved")) | length),
        dismissed: ($s.findings | map(select(.status == "dismissed")) | length),
        reopened: ($s.rounds | map(.reopened) | add // 0),
        needs_verification: ($s.findings | map(select(.status == "needs-verification")) | length),
        deferred: ($s.deferrals | length),
        remaining_blocking: ($v.open | length)
      },
      rounds: ($s.rounds | map({iteration, new, resolved, reopened, remaining_blocking, verdict})),
      blocking: ($v.open | map(brief)),
      deferrable: ($v.deferrable | map(brief)),
      carried: $carried
    };

# Apply a verdict to the state's own status. Escalation is terminal; nothing reopens an escalated loop.
def settle($cap; $threshold; $final):
  verdict($cap; $threshold) as $v
  | if .status == "escalated" then .
    elif $v.verdict == "converged" then .status = "converged" | .escalation_reason = null
    elif $v.verdict == "escalated" then .status = "escalated" | .escalation_reason = $v.escalation_reason
    elif $v.verdict == "deferral-required" and $final then .status = "escalated" | .escalation_reason = "cap-reached-undeferred-blockers"
    else .status = "open" | .escalation_reason = null end;
EOF

# Merge one round into the state. Reads the state; $cur is the round's records, $changed the delta's paths or
# null. A finding the round carries keeps its identity; one it no longer carries is resolved by the reviewer's
# re-read. The one exception is a delta round and a blocking finding whose file is outside the delta: that round
# never read the file, so the finding stays open. A round counts as a delta round unless `scope` recorded
# `full` for it, and round 1 is always full. A non-security point that only needed verification may leave on any
# round: the reviewer's own check settled it.
JQ_RECORD=''
IFS= read -r -d '' JQ_RECORD <<'EOF' || true
. as $s
| ($s.iteration + 1) as $n
| ($s.findings | map({key: .finding_id, value: .}) | from_entries) as $prev
| ($cur | map({key: .finding_id, value: .}) | from_entries) as $now
| (if $s.iteration == 0 then "full" else ($s.scope // "delta") end) as $scope
| def lift: if . == "new" then "confirmed" else . end;
  [ $cur[] | . as $c | $prev[$c.finding_id] as $p
    | if $p == null then {rec: $c, from: null, carried: false}
      elif ($p.status == "resolved" or $p.status == "dismissed") then
        {rec: ($c | .status = (.status | lift)), from: $p.status, carried: false}
      else
        ([($c.status | lift), ($p.status | lift)] | max_by(status_rank)) as $st
        | {rec: ($c
            | .status = $st
            | .severity = ([$c.severity, $p.severity] | max_by(severity_rank))
            | .security = ($c.security or $p.security)
            | .evidence = (if $st == "confirmed" then ($c.evidence // $p.evidence) else $c.evidence end)),
           from: $p.status, carried: false}
      end ]
  + [ $s.findings[] | select($now[.finding_id] == null) | . as $f
      | if ($f | is_open | not) then {rec: $f, from: $f.status, carried: false}
        elif $scope == "delta" and $changed != null and ($f | outside_delta($changed)) then {rec: $f, from: $f.status, carried: true}
        else {rec: ($f | .status = "resolved" | .revision = $rev | .time = $time), from: $f.status, carried: false} end ]
  | . as $merged
  | [ $merged[] | select(.from != .rec.status)
      | {iteration: $n, finding_id: .rec.finding_id, from, to: .rec.status, actor: "reviewer"} ] as $moves
  | $s
  | .iteration = $n
  | .revision = $rev
  | .scope = null
  | .findings = ($merged | map(.rec) | sort_by(.finding_id))
  | .transitions += $moves
  | . as $next
  | verdict($cap; $threshold) as $v
  | .rounds += [{
      iteration: $n, revision: $rev,
      new: ($moves | map(select(.from == null)) | length),
      confirmed: ($next.findings | map(select(.status == "confirmed")) | length),
      resolved: ($moves | map(select(.to == "resolved")) | length),
      dismissed: ($next.findings | map(select(.status == "dismissed")) | length),
      reopened: ($moves | map(select((.from == "resolved" or .from == "dismissed") and (.to | . == "confirmed" or . == "needs-verification"))) | length),
      needs_verification: ($next.findings | map(select(.status == "needs-verification")) | length),
      remaining_blocking: ($v.open | length),
      verdict: $v.verdict
    }]
  | settle($cap; $threshold; false)
  | {state: ., carried: ($merged | map(select(.carried) | .rec.finding_id))}
EOF

# effective_config — the round cap and the blocking threshold of the default-branch manifest, as
# `<cap> <threshold>`. A value outside its range falls back to the default and is named on stderr.
effective_config() {
  local config
  config="$(manifest_config)"
  [[ "$config" =~ ^[0-9]+\ (critical|high|medium|low)$ ]] || config="$DEFAULT_CAP critical"
  printf '%s\n' "$config"
}

manifest_config() {
  local manifest
  manifest="$("$HERE/read-manifest.sh" 2>/dev/null)" || manifest='{}'
  printf '%s' "$manifest" | jq -r --argjson def "$DEFAULT_CAP" --argjson max "$MAX_CAP" '
    (if type == "object" and (.review | type) == "object" then .review else {} end) as $r
    | $r["max-iterations"] as $c
    | $r["blocking-threshold"] as $t
    | ($c | type == "number" and floor == . and . >= 1 and . <= $max) as $cok
    | ($t | type == "string" and (. as $x | ["critical", "high", "medium", "low"] | index([$x])) != null) as $tok
    | (if $c != null and ($cok | not) then "refused: review.max-iterations must be an integer from 1 to \($max); using \($def)" else empty end),
      (if $t != null and ($tok | not) then "refused: review.blocking-threshold must be critical, high, medium, or low; using critical" else empty end),
      "config \(if $cok then $c else $def end) \(if $tok then $t else "critical" end)"' 2>/dev/null \
    | while IFS= read -r line; do
      case "$line" in
      config\ *) printf '%s\n' "${line#config }" ;;
      *) echo "$PROG: $line" >&2 ;;
      esac
    done
}

# check_writable <file> — refuse a state path outside the git-ignored run directory of the git toplevel.
check_writable() {
  local file="$1" dir real top
  [[ ! -L "$file" ]] || fail 3 "the state file is a symbolic link: $(safe_display "$file")"
  dir="$(dirname -- "$file")"
  [[ -d "$dir" ]] || fail 3 "the state directory does not exist: $(safe_display "$dir")"
  real="$(cd -- "$dir" && pwd -P)"
  top="$(cd -- "$dir" && git rev-parse --show-toplevel 2>/dev/null)" || fail 3 "the state file is not inside a git checkout"
  top="$(cd -- "$top" && pwd -P)"
  case "$real/" in
  "$top/.claude/run/"* | "$top/.codex/run/"*) ;;
  *) fail 3 "the state must live under .claude/run/ or .codex/run/ of the git toplevel, got: $(safe_display "$file")" ;;
  esac
  if git -C "$top" ls-files --error-unmatch -- "$real/$(basename -- "$file")" >/dev/null 2>&1; then
    fail 3 "the state file is tracked by git: $(safe_display "$file")"
  fi
}

# load_state <file> <out> — validate the state and copy it to <out>. Exit 3 on a missing or invalid state.
load_state() {
  local file="$1" out="$2" problems
  [[ -f "$file" && -r "$file" ]] || fail 3 "the review state is missing or unreadable; the loop is not converged: $(safe_display "$file")"
  if ! jq -e -s 'length == 1' "$file" >/dev/null 2>&1; then
    fail 3 "the review state is not one JSON document; the loop is not converged"
  fi
  problems="$(jq -r -L "$HERE" "$JQ_STATE"' state_errors[]' "$file" 2>&1 || true)"
  if [[ -z "$problems" ]]; then
    jq -c '.findings[]' "$file" >"$out.findings"
    if [[ -s "$out.findings" ]]; then
      problems="$("$HERE/extract-findings.sh" --validate "$out.findings" 2>&1 >/dev/null || true)"
    fi
  fi
  if [[ -n "$problems" ]]; then
    while IFS= read -r line; do
      echo "$PROG: invalid review state: $(safe_display "$line")" >&2
    done <<<"$problems"
    fail 3 "the review state is invalid; the loop is not converged"
  fi
  jq -c . "$file" >"$out"
}

# write_state <json-file> <file> — replace the state atomically.
write_state() {
  local json="$1" file="$2" out
  check_writable "$file"
  out="$(mktemp "$file.XXXXXX")"
  jq -c . "$json" >"$out"
  mv -f "$out" "$file"
}

# read_paths <file|-> <out> — the changed paths as a JSON array of strings. Paths are data only.
read_paths() {
  local input="$1" out="$2"
  if [[ "$input" == '-' ]]; then
    head -n "$MAX_CHANGED_FILES" >"$out.raw"
  else
    [[ -f "$input" ]] || fail 3 "changed-files list not found: $(safe_display "$input")"
    head -n "$MAX_CHANGED_FILES" <"$input" >"$out.raw"
  fi
  jq -R -s -c 'split("\n") | map(gsub("[\\x00-\\x1f\\x7f]"; "") | sub("^(\\./)+"; "") | .[0:300]) | map(select(. != "" and . != ".")) | unique' "$out.raw" >"$out"
}

new_tmp() {
  TMP="$(mktemp -d)"
  # shellcheck disable=SC2064
  trap "rm -rf '$TMP'" EXIT
}

cmd_init() {
  local state='' repo='' pr=''
  while [[ $# -gt 0 ]]; do
    case "$1" in
    --state) [[ $# -ge 2 ]] || die_usage '--state needs a value'; state="$2"; shift 2 ;;
    --repo) [[ $# -ge 2 ]] || die_usage '--repo needs a value'; repo="$2"; shift 2 ;;
    --pr) [[ $# -ge 2 ]] || die_usage '--pr needs a value'; pr="$2"; shift 2 ;;
    *) die_usage "unknown argument: $(safe_display "$1")" ;;
    esac
  done
  [[ -n "$state" ]] || die_usage '--state is required'
  [[ "$repo" =~ ^[A-Za-z0-9_.-]+/[A-Za-z0-9_.-]+$ ]] || die_usage "--repo must be owner/name, got: $(safe_display "$repo")"
  [[ "$pr" =~ ^[1-9][0-9]{0,8}$ ]] || die_usage "--pr must be a positive integer, got: $(safe_display "$pr")"
  check_writable "$state"

  local config cap threshold
  config="$(effective_config)"
  cap="${config%% *}"
  threshold="${config#* }"
  new_tmp

  # An existing state is resumed, never replaced: a fresh state would reset the round count. An invalid one
  # stops the loop instead of being overwritten.
  if [[ -e "$state" ]]; then
    load_state "$state" "$TMP/state.json"
    jq -e --arg repo "$repo" --argjson pr "$pr" '.repo == $repo and .pr == $pr' "$TMP/state.json" >/dev/null \
      || fail 3 "the review state belongs to another pull request; refusing to replace it"
    jq -c --argjson cap "$cap" --arg t "$threshold" \
      '{resumed: true, iteration, status, max_iterations: $cap, blocking_threshold: $t}' "$TMP/state.json"
    return 0
  fi

  jq -n -c --arg repo "$repo" --argjson pr "$pr" --argjson cap "$cap" --arg t "$threshold" \
    '{schema: 1, repo: $repo, pr: $pr, iteration: 0, max_iterations: $cap, blocking_threshold: $t, status: "open",
      escalation_reason: null, revision: null, scope: null, findings: [], deferrals: [], transitions: [], rounds: []}' >"$TMP/new.json"
  write_state "$TMP/new.json" "$state"
  jq -c '{resumed: false, iteration, status, max_iterations, blocking_threshold}' "$TMP/new.json"
}

cmd_record() {
  local state='' input='' changed=''
  while [[ $# -gt 0 ]]; do
    case "$1" in
    --state) [[ $# -ge 2 ]] || die_usage '--state needs a value'; state="$2"; shift 2 ;;
    --input) [[ $# -ge 2 ]] || die_usage '--input needs a value'; input="$2"; shift 2 ;;
    --changed-files) [[ $# -ge 2 ]] || die_usage '--changed-files needs a value'; changed="$2"; shift 2 ;;
    *) die_usage "unknown argument: $(safe_display "$1")" ;;
    esac
  done
  [[ -n "$state" ]] || die_usage '--state is required'
  [[ -n "$input" ]] || die_usage '--input is required'
  [[ "$input" != '-' || "$changed" != '-' ]] || die_usage '--input and --changed-files cannot both read standard input'
  check_writable "$state"
  new_tmp
  load_state "$state" "$TMP/state.json"

  local config cap threshold iteration status
  config="$(effective_config)"
  cap="${config%% *}"
  threshold="${config#* }"
  iteration="$(jq -r '.iteration' "$TMP/state.json")"
  status="$(jq -r '.status' "$TMP/state.json")"
  [[ "$status" != 'escalated' ]] || fail 5 "the loop escalated; no further automatic review round starts"
  # A change after a convergence in the cap round needs a review round the cap no longer allows. The loop
  # escalates instead of letting the converged verdict stand for a diff nobody reviewed.
  if [[ "$status" == 'converged' && "$iteration" -ge "$cap" ]]; then
    jq -c '.status = "escalated" | .escalation_reason = "cap-spent-after-convergence"' "$TMP/state.json" >"$TMP/next.json"
    write_state "$TMP/next.json" "$state"
    jq -c -L "$HERE" --argjson cap "$cap" --arg threshold "$threshold" "$JQ_STATE"' output($cap; $threshold; [])' "$TMP/next.json"
    fail 5 "the loop converged in the cap round of $cap; a later change needs a review round the cap no longer allows: escalated (cap-spent-after-convergence)"
  fi
  [[ "$iteration" -lt "$cap" ]] || fail 5 "the round cap of $cap is spent; no further automatic review round starts"
  if [[ "$iteration" -gt 0 && -z "$changed" ]]; then
    die_usage '--changed-files is required once an earlier round exists'
  fi

  local repo pr
  repo="$(jq -r '.repo' "$TMP/state.json")"
  pr="$(jq -r '.pr' "$TMP/state.json")"
  if [[ "$input" == '-' ]]; then
    cat >"$TMP/report.md"
    input="$TMP/report.md"
  fi
  "$HERE/extract-findings.sh" --header --input "$input" >"$TMP/header.json" \
    || fail 3 "the round report could not be read; nothing was recorded"
  "$HERE/extract-findings.sh" --round --repo "$repo" --pr "$pr" --input "$input" >"$TMP/round.jsonl" \
    || fail 3 "the round report could not be read; nothing was recorded"

  local paths='null'
  if [[ -n "$changed" ]]; then
    read_paths "$changed" "$TMP/changed.json"
    paths="$(cat "$TMP/changed.json")"
  fi

  jq -c -s -L "$HERE" --slurpfile s "$TMP/state.json" --argjson changed "$paths" \
    --arg rev "$(jq -r '.revision' "$TMP/header.json")" --arg time "$(jq -r '.time' "$TMP/header.json")" \
    --argjson cap "$cap" --arg threshold "$threshold" \
    "$JQ_STATE"$'\n'". as \$cur | \$s[0] | $JQ_RECORD" "$TMP/round.jsonl" >"$TMP/merged.json"
  jq -c --argjson cap "$cap" '.state | .max_iterations = $cap' "$TMP/merged.json" \
    | jq -c --arg t "$threshold" '.blocking_threshold = $t' >"$TMP/next.json"
  write_state "$TMP/next.json" "$state"
  jq -c -L "$HERE" --argjson cap "$cap" --arg threshold "$threshold" --argjson carried "$(jq -c '.carried' "$TMP/merged.json")" \
    "$JQ_STATE"' output($cap; $threshold; $carried)' "$TMP/next.json"
}

cmd_evaluate() {
  local state='' final=false
  while [[ $# -gt 0 ]]; do
    case "$1" in
    --state) [[ $# -ge 2 ]] || die_usage '--state needs a value'; state="$2"; shift 2 ;;
    --final) final=true; shift ;;
    *) die_usage "unknown argument: $(safe_display "$1")" ;;
    esac
  done
  [[ -n "$state" ]] || die_usage '--state is required'
  new_tmp
  load_state "$state" "$TMP/state.json"

  local config cap threshold
  config="$(effective_config)"
  cap="${config%% *}"
  threshold="${config#* }"
  if [[ "$final" == true ]]; then
    check_writable "$state"
    jq -c -L "$HERE" --argjson cap "$cap" --arg threshold "$threshold" "$JQ_STATE"' settle($cap; $threshold; true)' \
      "$TMP/state.json" >"$TMP/next.json"
    if ! cmp -s <(jq -c . "$TMP/state.json") "$TMP/next.json"; then
      write_state "$TMP/next.json" "$state"
    fi
    cp "$TMP/next.json" "$TMP/state.json"
  fi
  jq -c -L "$HERE" --argjson cap "$cap" --arg threshold "$threshold" "$JQ_STATE"' output($cap; $threshold; [])' "$TMP/state.json"
}

cmd_scope() {
  local state='' changed=''
  while [[ $# -gt 0 ]]; do
    case "$1" in
    --state) [[ $# -ge 2 ]] || die_usage '--state needs a value'; state="$2"; shift 2 ;;
    --changed-files) [[ $# -ge 2 ]] || die_usage '--changed-files needs a value'; changed="$2"; shift 2 ;;
    *) die_usage "unknown argument: $(safe_display "$1")" ;;
    esac
  done
  [[ -n "$state" ]] || die_usage '--state is required'
  [[ -n "$changed" ]] || die_usage '--changed-files is required'
  check_writable "$state"
  new_tmp
  load_state "$state" "$TMP/state.json"
  read_paths "$changed" "$TMP/changed.json"

  # A narrow delta is not enough when it touches a surface whose regressions sit outside the changed lines.
  # The surfaces are the risk classifier's own, so the two never disagree on what is sensitive.
  local signals=''
  if [[ "$(jq 'length' "$TMP/changed.json")" -gt 0 ]]; then
    jq -r '.[]' "$TMP/changed.json" >"$TMP/changed.txt"
    signals="$("$HERE/classify-risk.sh" --files "$TMP/changed.txt" 2>/dev/null | sed -n 's/^signal=[^|]*|\([a-z-]*\)|.*/\1/p' || true)"
  fi
  # The next `record` reads the scope stored here: a blocking finding outside a delta round stays open.
  jq -c -L "$HERE" --arg signals "$signals" --slurpfile changed "$TMP/changed.json" "$JQ_STATE"'
    ($signals | split("\n") | map(select(. != ""))) as $sig
    | [ (if .iteration == 0 then "first-round" else empty end),
        (if (.rounds | last | .reopened? // 0) > 0 then "regression" else empty end),
        (if ($sig | any(. == "auth-security-secrets" or . == "payments-billing" or . == "migrations-data-loss" or . == "project-critical-path"))
         then "security-surface" else empty end),
        (if ($sig | any(. == "shared-core-architecture" or . == "public-api")) then "shared-surface" else empty end),
        (if any(.findings[]; outside_delta($changed[0])) then "open-finding-outside-delta" else empty end) ] as $reasons
    | .scope = (if ($reasons | length) > 0 then "full" else "delta" end)
    | {state: ., verdict: {scope, reasons: $reasons, baseline: .revision}}' "$TMP/state.json" >"$TMP/scoped.json"
  jq -c '.state' "$TMP/scoped.json" >"$TMP/next.json"
  write_state "$TMP/next.json" "$state"
  jq -c '.verdict' "$TMP/scoped.json"
}

# rejection_association <comment-url> <finding-id> — the author association of the rejection comment, read from
# the GitHub loader's payload of the state's own pull request, never from the caller. Exit 4 when the comment cannot
# be verified as a trusted author's own comment that names the finding (rules/code-review/general.md *Authorship trust*).
rejection_association() {
  local url="$1" id="$2" repo pr rc=0 verdict
  repo="$(jq -r '.repo' "$TMP/state.json")"
  pr="$(jq -r '.pr' "$TMP/state.json")"
  set +e
  "$LOADER" "https://github.com/$repo/pull/$pr" >"$TMP/pr.json" 2>"$TMP/pr.err"
  rc=$?
  set -e
  [[ "$rc" -eq 0 ]] || fail 4 "the rejection cannot be verified: the pull request cannot be loaded ($(safe_display "$(head -n 1 "$TMP/pr.err")")); the status is unchanged"
  verdict="$(jq -r --arg url "$url" --arg id "$id" --arg repo "$repo" --argjson pr "$pr" '
    if type != "object" or .kind != "pr" or .number != $pr
       or ((.repo.nameWithOwner // "") | ascii_downcase) != ($repo | ascii_downcase)
    then "refused:the loader returned another item than the pull request of the state"
    else [ (.comments // [])[] | select(.url == $url) ] as $m
    | if ($m | length) != 1 then "refused:the pull request of the state has no comment with this URL"
      elif ($m[0].body | type) != "string" or ($m[0].body | test("[a-z][a-z0-9-]*:actor=")) then
        "refused:the comment carries an agent marker; agent output is never a trusted rejection"
      elif ($m[0].body | contains($id) | not) then "refused:the comment does not name finding \($id)"
      elif (["OWNER", "MEMBER", "COLLABORATOR"] | index([$m[0].authorAssociation])) == null then
        "refused:the author association \($m[0].authorAssociation // "null") is not trusted"
      else "trusted:\($m[0].authorAssociation)" end
    end' "$TMP/pr.json" 2>/dev/null)" || verdict='refused:the loader payload is not JSON'
  case "$verdict" in
  trusted:OWNER | trusted:MEMBER | trusted:COLLABORATOR) printf '%s\n' "${verdict#trusted:}" ;;
  *) fail 4 "only a trusted author dismisses a finding: $(safe_display "${verdict#refused:}"); the status is unchanged" ;;
  esac
}

cmd_dismiss() {
  local state='' id='' comment=''
  while [[ $# -gt 0 ]]; do
    case "$1" in
    --state) [[ $# -ge 2 ]] || die_usage '--state needs a value'; state="$2"; shift 2 ;;
    --finding) [[ $# -ge 2 ]] || die_usage '--finding needs a value'; id="$2"; shift 2 ;;
    --comment) [[ $# -ge 2 ]] || die_usage '--comment needs a value'; comment="$2"; shift 2 ;;
    *) die_usage "unknown argument: $(safe_display "$1")" ;;
    esac
  done
  [[ -n "$state" ]] || die_usage '--state is required'
  [[ "$id" =~ ^r-[0-9a-f]{16}$ ]] || die_usage "--finding must be a finding_id, got: $(safe_display "$id")"
  [[ "$comment" =~ ^https://github\.com/[A-Za-z0-9_.-]+/[A-Za-z0-9_.-]+/pull/[1-9][0-9]{0,8}#issuecomment-[1-9][0-9]{0,19}$ ]] \
    || die_usage '--comment must be the URL of a comment on the pull request (https://github.com/<owner>/<name>/pull/<n>#issuecomment-<id>)'
  check_writable "$state"
  new_tmp
  load_state "$state" "$TMP/state.json"
  [[ "$(jq -r '.status' "$TMP/state.json")" != 'escalated' ]] || fail 5 "the loop escalated; the state is closed"

  local finding
  finding="$(jq -c --arg id "$id" '.findings[] | select(.finding_id == $id)' "$TMP/state.json")"
  [[ -n "$finding" ]] || fail 4 "no finding $id in the review state"
  jq -e '.security | not' <<<"$finding" >/dev/null || fail 4 "a security finding (S1-S3) is never dismissed; it leaves the loop only by being fixed"
  jq -e '.status == "new" or .status == "confirmed" or .status == "needs-verification"' <<<"$finding" >/dev/null \
    || fail 4 "finding $id is not open; the status is unchanged"
  local association
  association="$(rejection_association "$comment" "$id")"

  local config cap threshold
  config="$(effective_config)"
  cap="${config%% *}"
  threshold="${config#* }"
  jq -c -L "$HERE" --arg id "$id" --arg actor "trusted:$association" --argjson cap "$cap" --arg threshold "$threshold" "$JQ_STATE"'
    (.findings[] | select(.finding_id == $id)) as $f
    | .transitions += [{iteration: .iteration, finding_id: $id, from: $f.status, to: "dismissed", actor: $actor}]
    | .findings = (.findings | map(if .finding_id == $id then .status = "dismissed" else . end))
    | settle($cap; $threshold; false)' "$TMP/state.json" >"$TMP/next.json"
  write_state "$TMP/next.json" "$state"
  jq -c -L "$HERE" --argjson cap "$cap" --arg threshold "$threshold" "$JQ_STATE"' output($cap; $threshold; [])' "$TMP/next.json"
}

cmd_defer() {
  local state='' id='' url=''
  while [[ $# -gt 0 ]]; do
    case "$1" in
    --state) [[ $# -ge 2 ]] || die_usage '--state needs a value'; state="$2"; shift 2 ;;
    --finding) [[ $# -ge 2 ]] || die_usage '--finding needs a value'; id="$2"; shift 2 ;;
    --url) [[ $# -ge 2 ]] || die_usage '--url needs a value'; url="$2"; shift 2 ;;
    *) die_usage "unknown argument: $(safe_display "$1")" ;;
    esac
  done
  [[ -n "$state" ]] || die_usage '--state is required'
  [[ "$id" =~ ^r-[0-9a-f]{16}$ ]] || die_usage "--finding must be a finding_id, got: $(safe_display "$id")"
  [[ "$url" =~ ^https://[^[:space:]]+$ && ${#url} -le 500 ]] || die_usage '--url must be the https URL of the filed sub-issue'
  check_writable "$state"
  new_tmp
  load_state "$state" "$TMP/state.json"
  [[ "$(jq -r '.status' "$TMP/state.json")" != 'escalated' ]] || fail 5 "the loop escalated; the state is closed"

  local config cap threshold
  config="$(effective_config)"
  cap="${config%% *}"
  threshold="${config#* }"
  [[ "$(jq -r '.iteration' "$TMP/state.json")" -ge "$cap" ]] || fail 4 "a finding is deferred only at the cap round ($cap)"
  jq -e -L "$HERE" --arg id "$id" --argjson cap "$cap" --arg threshold "$threshold" "$JQ_STATE"'
    verdict($cap; $threshold).deferrable | any(.finding_id == $id)' "$TMP/state.json" >/dev/null \
    || fail 4 "finding $id is not deferrable: it is not blocking, or it is security-relevant or at or above the blocking threshold"
  jq -c -L "$HERE" --arg id "$id" --arg url "$url" --argjson cap "$cap" --arg threshold "$threshold" "$JQ_STATE"'
    .deferrals += [{finding_id: $id, url: $url}] | settle($cap; $threshold; false)' "$TMP/state.json" >"$TMP/next.json"
  write_state "$TMP/next.json" "$state"
  jq -c -L "$HERE" --argjson cap "$cap" --arg threshold "$threshold" "$JQ_STATE"' output($cap; $threshold; [])' "$TMP/next.json"
}

# The fixtures below are Markdown that carries backticks and dollar signs; none of it is meant to expand.
# shellcheck disable=SC2016
self_test() {
  local failures=0 script tmp
  tmp="$(mktemp -d)"
  # shellcheck disable=SC2064
  trap "rm -rf '$tmp'" EXIT

  # The scripts are copied into a temporary tree, so the GitHub loader is a fixture and not the network.
  mkdir -p "$tmp/pkg/skills/_shared" "$tmp/pkg/skills/code-review-github/scripts"
  cp "$HERE"/{review-state,extract-findings,cr-header,read-manifest,classify-risk,domain-vocabulary}.sh "$HERE/finding-defs.jq" "$tmp/pkg/skills/_shared/"
  script="$tmp/pkg/skills/_shared/$PROG"
  cat >"$tmp/pkg/skills/code-review-github/scripts/load-issue.sh" <<EOF
#!/usr/bin/env bash
printf '%s\n' "\$1" >>"$tmp/loader-calls"
[[ "\$1" == 'https://github.com/acme/shop/pull/7' && -f "$tmp/pr.json" ]] || { echo 'no such pull request' >&2; exit 4; }
cat "$tmp/pr.json"
EOF
  chmod +x "$tmp/pkg/skills/code-review-github/scripts/load-issue.sh"
  # pr_comments <comment-json>... — the loader payload of pull request acme/shop#7 with these comments.
  pr_comments() {
    jq -n -c '{kind: "pr", number: 7, url: "https://github.com/acme/shop/pull/7",
      repo: {owner: "acme", name: "shop", nameWithOwner: "acme/shop"}, comments: $ARGS.positional}' --jsonargs "$@" >"$tmp/pr.json"
  }
  # comment <id> <association> <body> — one loader comment object.
  comment() {
    jq -n -c --arg id "$1" --arg a "$2" --arg b "$3" \
      '{author: "someone", authorAssociation: $a, body: $b, createdAt: "2026-10-01T10:00:00Z", updatedAt: null,
        url: "https://github.com/acme/shop/pull/7#issuecomment-\($id)"}'
  }

  check() {
    if [[ "$2" == 0 ]]; then
      printf 'ok    %s\n' "$1"
    else
      printf 'FAIL  %s\n' "$1" >&2
      failures=$((failures + 1))
    fi
  }

  # run_case <label> <expected-exit> -- <args...>   (runs in the project repository; output in $tmp/out, $tmp/err)
  run_case() {
    local label="$1" expected="$2" rc=0
    shift 3
    set +e
    (cd "$repo" && "$script" "$@") >"$tmp/out" 2>"$tmp/err"
    rc=$?
    set -e
    if [[ "$rc" -eq "$expected" ]]; then
      printf 'ok    %s\n' "$label"
    else
      printf 'FAIL  %s (expected exit %s, got %s: %s)\n' "$label" "$expected" "$rc" "$(head -n 1 "$tmp/err")" >&2
      failures=$((failures + 1))
    fi
  }
  # q <jq-program> — the exit of `jq -e` over the last output, as 0 or 1.
  q() { jq -e "$1" "$tmp/out" >/dev/null 2>&1 && echo 0 || echo 1; }

  # manifest <json> — commit a manifest and make it the default branch.
  manifest() {
    printf '{ "name": "acme/shop", "extra": { "ai-olympus": %s } }\n' "$1" >"$repo/composer.json"
    git -C "$repo" add composer.json
    git -C "$repo" -c user.name=t -c user.email=t@t commit -q -m manifest
    git -C "$repo" update-ref refs/remotes/origin/master HEAD
  }

  # finding <severity> <title> <location> <rule> <evidence|-> [level]
  finding() {
    printf '### 🔴 %s 1. %s\n\n- **Location:** `%s`\n- **Rule:** `%s`\n' "$1" "$2" "$3" "$4"
    [[ -n "${6:-}" ]] && printf -- '- **Level:** %s\n' "$6"
    printf -- '- **Provenance:** `regression — introduced in this revision`\n- **Impact:** %s impact.\n' "$2"
    [[ "$5" != '-' ]] && printf -- '- **Evidence:** %s\n' "$5"
    printf -- '- **Faulty Example:** x\n- **Expected behavior:** y\n- **Test hint:** z\n- **Suggested fix:** n/a — w\n\n'
  }
  # report <file> <round> [finding-block]... — a round report; the round number picks the revision and the time.
  report() {
    local file="$1" n="$2"
    shift 2
    {
      printf '# Code Review\n\n**Status:** needs-fix\n**Counts:** Critical 0 · Moderate 0\n'
      printf '**Reviewed revision:** %s\n' "$(printf '%040d' "$n" | tr '0' 'a')"
      printf '**Last updated:** 2026-10-0%sT10:00:00Z\n\n## Findings\n\n' "$n"
      [[ $# -eq 0 ]] || printf '%s\n\n' "$@"
    } >"$file"
  }

  local repo="$tmp/repo"
  mkdir -p "$repo/.claude/run" "$repo/.codex/run"
  git -C "$repo" init -q
  manifest '{}'
  local S=".claude/run/review-state.json"
  local SQL="@rules/security/backend.md#database" STRUCT="@rules/php/core-standards.md#structure"
  local F_SQL F_SQL2 F_STRUCT F_NOEV F_SEC_NOEV F_LOW_SEC F_MED
  F_SQL="$(finding Critical 'Raw query' 'app/Http/Orders.php:42' "$SQL" 'exploit-path — sort=1;DROP reaches DB::raw')"
  F_SQL2="$(finding Critical 'Raw query again' 'app/Http/Invoices.php:7' "$SQL" 'exploit-path — the same path in invoices')"
  F_STRUCT="$(finding Moderate 'Copied step' 'src/Foo/Bar.php:10' "$STRUCT" 'rule-violation — the step is copied')"
  # A point without evidence goes under `## Needs verification`; a report puts it after every proven finding.
  F_NOEV="$(printf '## Needs verification\n\n'; finding Moderate 'Maybe a copied step' 'src/Foo/Baz.php:3' "$STRUCT" '-')"
  F_SEC_NOEV="$(printf '## Needs verification\n\n'; finding Moderate 'Token may be logged' 'src/Foo/Log.php:3' "$STRUCT" '-')"
  F_LOW_SEC="$(finding Moderate 'Weak escaping' 'src/View/Render.php:3' "$SQL" 'exploit-path — <b> reaches the page' Low)"
  F_MED="$(finding Moderate 'Copied step' 'src/Foo/Bar.php:10' "$STRUCT" 'rule-violation — the step is copied' Medium)"
  printf 'src/Foo/Bar.php\napp/Http/Orders.php\n' >"$tmp/changed-both"
  printf 'docs/readme.md\n' >"$tmp/changed-none"

  # --- the state lives only under the git-ignored run directory --------------------------------------------
  run_case 'a state outside the run directory is refused' 3 -- init --state review.json --repo acme/shop --pr 7
  check 'the refused state is not written' "$([[ ! -e "$repo/review.json" ]] && echo 0 || echo 1)"
  ln -s "$repo/.claude/run/elsewhere.json" "$repo/.claude/run/link.json"
  run_case 'a state that is a symbolic link is refused' 3 -- init --state .claude/run/link.json --repo acme/shop --pr 7
  run_case 'a state under .codex/run is accepted' 0 -- init --state .codex/run/review-state.json --repo acme/shop --pr 7
  run_case 'init writes a fresh state under .claude/run' 0 -- init --state "$S" --repo acme/shop --pr 7
  check 'a fresh state starts at round 0 with the default cap 3 and threshold critical' "$(q '.resumed == false and .iteration == 0 and .max_iterations == 3 and .blocking_threshold == "critical"')"
  run_case 'a state without a review round is evaluated' 0 -- evaluate --state "$S"
  check 'a state without a review round is never converged' "$(q '.verdict == "continue" and .reason == "no review round is recorded yet"')"

  # --- scenarios 1, 2, 3: identity -------------------------------------------------------------------------
  report "$tmp/r1.md" 1 "$F_SQL" "$F_SQL2" "$F_STRUCT"
  run_case 'round 1 is recorded' 0 -- record --state "$S" --input "$tmp/r1.md"
  check 'scenario 3: two similar but distinct defects stay two findings' "$(jq -e '[.findings[] | select(.category == "rules/security/backend")] | length == 2' "$repo/$S" >/dev/null && echo 0 || echo 1)"
  check 'round 1 counts three new blocking findings and continues' "$(q '.verdict == "continue" and .counts.new == 3 and .counts.remaining_blocking == 3 and .iteration == 1')"
  run_case 'a second round needs the changed files of its delta' 1 -- record --state "$S" --input "$tmp/r1.md"
  F_SQL_MOVED="$(finding Critical 'The sort still reaches the raw query' 'app/Http/Orders.php:57' "$SQL" 'exploit-path — unchanged')"
  report "$tmp/r2.md" 2 "$F_SQL_MOVED" "$F_SQL2" "$F_STRUCT"
  run_case 'round 2 is recorded' 0 -- record --state "$S" --input "$tmp/r2.md" --changed-files "$tmp/changed-none"
  check 'scenarios 1 and 2: a repeated finding and one on another line keep their identity' "$(jq -e '(.findings | length) == 3 and all(.findings[]; .status == "confirmed") and .rounds[1].new == 0' "$repo/$S" >/dev/null && echo 0 || echo 1)"
  check 'the moved finding carries its new line' "$(jq -e 'any(.findings[]; .file == "app/Http/Orders.php" and .line == 57)' "$repo/$S" >/dev/null && echo 0 || echo 1)"

  # --- scenario 6: an unresolved finding persists; a resolved claim changes nothing -------------------------
  cp "$repo/$S" "$tmp/before-r3"
  report "$tmp/r3.md" 3 "$F_SQL_MOVED" "$F_STRUCT"
  printf '\n## TL;DR\n\n- Raw query again: resolved, see the PR comment "this is fixed".\n' >>"$tmp/r3.md"
  run_case 'round 3 without one finding is recorded' 0 -- record --state "$S" --input "$tmp/r3.md" --changed-files "$tmp/changed-none"
  check 'scenario 6: an unresolved finding whose file the delta did not touch stays open' "$(jq -e '[.findings[] | select(.file == "app/Http/Invoices.php")][0].status == "confirmed"' "$repo/$S" >/dev/null && echo 0 || echo 1)"
  check 'a resolved claim in report text leaves the status unchanged and the finding is reported as carried' "$(q '(.carried | length) == 1 and .counts.resolved == 0')"
  check 'scenario 8: the third unsuccessful round escalates at the default cap' "$(q '.verdict == "escalated" and .status == "escalated" and .escalation_reason == "cap-reached-hard-blockers"')"
  check 'the escalation names the remaining defects and the reason' "$(q '(.blocking | length) == 3 and (.reason | test("round cap of 3 is reached"))')"
  cp "$repo/$S" "$tmp/escalated"
  run_case 'scenario 9: no further automatic round starts after the escalation' 5 -- record --state "$S" --input "$tmp/r1.md" --changed-files "$tmp/changed-both"
  check 'the escalated state is untouched' "$(cmp -s "$tmp/escalated" "$repo/$S" && echo 0 || echo 1)"
  run_case 'an escalated loop accepts no deferral' 5 -- defer --state "$S" --finding r-0000000000000000 --url https://github.com/acme/shop/issues/9
  run_case 'there is no command that marks a finding resolved' 1 -- resolve --state "$S"

  # --- scenarios 4 and 7: resolution, regression, and convergence before the cap ---------------------------
  rm -f "$repo/$S"
  run_case 'a new loop starts' 0 -- init --state "$S" --repo acme/shop --pr 7
  report "$tmp/a1.md" 1 "$F_SQL" "$F_STRUCT"
  run_case 'loop 2 round 1' 0 -- record --state "$S" --input "$tmp/a1.md"
  report "$tmp/a2.md" 2 "$F_STRUCT"
  run_case 'loop 2 round 2 without the fixed finding' 0 -- record --state "$S" --input "$tmp/a2.md" --changed-files "$tmp/changed-both"
  check 'a finding the round no longer carries in a changed file is resolved' "$(jq -e '[.findings[] | select(.file == "app/Http/Orders.php")][0].status == "resolved"' "$repo/$S" >/dev/null && echo 0 || echo 1)"
  report "$tmp/a3.md" 3 "$F_SQL_MOVED"
  run_case 'loop 2 round 3 brings the defect back' 0 -- record --state "$S" --input "$tmp/a3.md" --changed-files "$tmp/changed-both"
  check 'scenario 4: a resolved finding that reappears is reopened, not new' "$(q '.counts.reopened == 1 and .rounds[2].new == 0 and .rounds[2].reopened == 1')"
  check 'the reopened finding blocks again and keeps its history' "$(jq -e '([.findings[] | select(.file == "app/Http/Orders.php")][0].status == "confirmed")
      and ([.transitions[] | select(.from == "resolved" and .to == "confirmed")] | length == 1)' "$repo/$S" >/dev/null && echo 0 || echo 1)"

  rm -f "$repo/$S"
  (cd "$repo" && "$script" init --state "$S" --repo acme/shop --pr 7 >/dev/null)
  report "$tmp/b1.md" 1 "$F_STRUCT"
  run_case 'loop 3 round 1' 0 -- record --state "$S" --input "$tmp/b1.md"
  report "$tmp/b2.md" 2
  run_case 'loop 3 round 2 is clean' 0 -- record --state "$S" --input "$tmp/b2.md" --changed-files "$tmp/changed-both"
  check 'scenario 7: the review passes before reaching the round cap' "$(q '.verdict == "converged" and .status == "converged" and .iteration == 2 and .counts.resolved == 1')"

  # --- scenarios 5 and 10: evidence and non-blocking findings ----------------------------------------------
  rm -f "$repo/$S"
  (cd "$repo" && "$script" init --state "$S" --repo acme/shop --pr 7 >/dev/null)
  report "$tmp/c1.md" 1 "$F_NOEV"
  run_case 'a round with only a finding without evidence' 0 -- record --state "$S" --input "$tmp/c1.md"
  check 'scenarios 5 and 10: a finding without evidence cannot block, and only non-blocking findings converge' "$(q '.verdict == "converged" and .counts.needs_verification == 1 and .counts.remaining_blocking == 0')"
  rm -f "$repo/$S"
  (cd "$repo" && "$script" init --state "$S" --repo acme/shop --pr 7 >/dev/null)
  report "$tmp/c2.md" 1 "$F_SEC_NOEV"
  run_case 'a round with a security finding without evidence' 0 -- record --state "$S" --input "$tmp/c2.md"
  check 'a security (S1-S3) finding that needs verification still blocks' "$(q '.verdict == "continue" and .blocking[0].status == "needs-verification" and .blocking[0].security == true')"
  report "$tmp/c3.md" 2 "$(finding Moderate 'Token may be logged' 'src/Foo/Log.php:3' "$STRUCT" 'logic-trace — the token reaches Log::info')"
  run_case 'the finding gains evidence in round 2' 0 -- record --state "$S" --input "$tmp/c3.md" --changed-files "$tmp/changed-none"
  report "$tmp/c4.md" 3 "$F_SEC_NOEV"
  run_case 'round 3 reports it without evidence again' 0 -- record --state "$S" --input "$tmp/c4.md" --changed-files "$tmp/changed-none"
  check 'a confirmed finding is never downgraded to needs-verification by a later round' "$(jq -e '.findings[0].status == "confirmed" and (.findings[0].evidence | test("Log::info"))' "$repo/$S" >/dev/null && echo 0 || echo 1)"
  rm -f "$repo/$S"
  (cd "$repo" && "$script" init --state "$S" --repo acme/shop --pr 7 >/dev/null)
  (cd "$repo" && "$script" record --state "$S" --input "$tmp/c2.md" >/dev/null)
  run_case 'a delta that leaves a security point needing verification untouched is scoped' 0 -- scope --state "$S" --changed-files "$tmp/changed-none"
  check 'a security point needing verification outside the delta widens the next round to the whole PR' "$(q '.scope == "full" and .reasons == ["open-finding-outside-delta"]')"
  report "$tmp/c5.md" 2
  run_case 'the broad round verifies the security point as absent without a code change' 0 -- record --state "$S" --input "$tmp/c5.md" --changed-files "$tmp/changed-none"
  check 'a full round that omits a security point needing verification resolves it' "$(q '.verdict == "converged" and .counts.resolved == 1 and (.carried | length) == 0')"
  rm -f "$repo/$S"
  (cd "$repo" && "$script" init --state "$S" --repo acme/shop --pr 7 >/dev/null)
  (cd "$repo" && "$script" record --state "$S" --input "$tmp/c2.md" >/dev/null)
  run_case 'a delta round without scope omits the security point' 0 -- record --state "$S" --input "$tmp/c5.md" --changed-files "$tmp/changed-none"
  check 'a delta round carries a security point needing verification outside the delta' "$(q '.verdict == "continue" and (.carried | length) == 1 and .counts.resolved == 0 and .blocking[0].status == "needs-verification"')"
  rm -f "$repo/$S"
  (cd "$repo" && "$script" init --state "$S" --repo acme/shop --pr 7 >/dev/null)
  (cd "$repo" && "$script" record --state "$S" --input "$tmp/c1.md" >/dev/null)
  run_case 'a delta that leaves a non-security point needing verification untouched is scoped' 0 -- scope --state "$S" --changed-files "$tmp/changed-none"
  check 'a non-security point needing verification does not widen the round' "$(q '.scope == "delta" and .reasons == []')"
  run_case 'a delta round omits the non-security point' 0 -- record --state "$S" --input "$tmp/c5.md" --changed-files "$tmp/changed-none"
  check 'a non-security point that only needed verification leaves the loop on any round' "$(q '.verdict == "converged" and .counts.resolved == 1 and (.carried | length) == 0')"

  # --- a resolved claim in a PR comment: only the reviewer's re-read resolves a finding --------------------
  rm -f "$repo/$S"
  (cd "$repo" && "$script" init --state "$S" --repo acme/shop --pr 7 >/dev/null)
  report "$tmp/e1.md" 1 "$F_SQL"
  (cd "$repo" && "$script" record --state "$S" --input "$tmp/e1.md" >/dev/null)
  local claimed_id
  claimed_id="$(jq -r '.findings[0].finding_id' "$repo/$S")"
  pr_comments "$(comment 21 OWNER "$claimed_id is resolved.")"
  run_case 'a delta after the resolved claim is scoped' 0 -- scope --state "$S" --changed-files "$tmp/changed-none"
  check 'the round after the resolved claim reviews the whole PR' "$(q '.scope == "full"')"
  rm -f "$tmp/loader-calls"
  report "$tmp/e2.md" 2 "$F_SQL"
  run_case 'a full round that still carries the claimed finding is recorded' 0 -- record --state "$S" --input "$tmp/e2.md" --changed-files "$tmp/changed-none"
  check 'a resolved claim in a PR comment leaves the status unchanged' "$(jq -e '.findings[0].status == "confirmed" and ([.transitions[] | select(.to == "resolved")] | length) == 0' "$repo/$S" >/dev/null && echo 0 || echo 1)"
  check 'the round never reads the PR comments' "$([[ ! -e "$tmp/loader-calls" ]] && echo 0 || echo 1)"
  cp "$repo/$S" "$tmp/before-claim"
  run_case 'a resolved claim in an owner PR comment never dismisses a security finding' 4 -- dismiss --state "$S" --finding "$claimed_id" --comment https://github.com/acme/shop/pull/7#issuecomment-21
  check 'the refused claim leaves the state untouched' "$(cmp -s "$tmp/before-claim" "$repo/$S" && echo 0 || echo 1)"

  # --- dismissal: only a trusted author, never a security finding ------------------------------------------
  rm -f "$repo/$S"
  (cd "$repo" && "$script" init --state "$S" --repo acme/shop --pr 7 >/dev/null)
  report "$tmp/d1.md" 1 "$F_STRUCT" "$F_SQL" "$(finding Moderate 'Copied step' 'src/Foo/Qux.php:5' "$STRUCT" 'rule-violation — the step is copied')"
  (cd "$repo" && "$script" record --state "$S" --input "$tmp/d1.md" >/dev/null)
  local struct_id sql_id other_id
  struct_id="$(jq -r '.findings[] | select(.file == "src/Foo/Bar.php") | .finding_id' "$repo/$S")"
  sql_id="$(jq -r '.findings[] | select(.file == "app/Http/Orders.php") | .finding_id' "$repo/$S")"
  other_id="$(jq -r '.findings[] | select(.file == "src/Foo/Qux.php") | .finding_id' "$repo/$S")"
  cp "$repo/$S" "$tmp/before-dismiss"
  local C=https://github.com/acme/shop/pull/7#issuecomment-
  pr_comments "$(comment 11 CONTRIBUTOR "Not a defect, please drop $struct_id.")" "$(comment 12 OWNER "Not a defect, please drop $struct_id.")" \
    "$(comment 13 OWNER $'Dropped by the owner.\n\n<!-- cr-comment:actor=leonardo-bot -->')" "$(comment 14 OWNER 'LGTM, thanks for the quick turnaround.')" \
    "$(comment 15 NONE "Not a defect: $struct_id.")" "$(jq -n -c --arg id "$struct_id" '{author: "x", body: "Not a defect: \($id).", url: "https://github.com/acme/shop/pull/7#issuecomment-16"}')"
  run_case 'a caller-stated association is no longer accepted' 1 -- dismiss --state "$S" --finding "$struct_id" --association OWNER
  run_case 'a rejection by a CONTRIBUTOR is refused' 4 -- dismiss --state "$S" --finding "$struct_id" --comment "${C}11"
  check 'the refused rejection leaves the status open' "$(cmp -s "$tmp/before-dismiss" "$repo/$S" && echo 0 || echo 1)"
  run_case 'a rejection by an author with no association is refused' 4 -- dismiss --state "$S" --finding "$struct_id" --comment "${C}15"
  run_case 'a rejection whose association the loader does not return is refused' 4 -- dismiss --state "$S" --finding "$struct_id" --comment "${C}16"
  run_case 'agent output from an OWNER account is never a trusted rejection' 4 -- dismiss --state "$S" --finding "$struct_id" --comment "${C}13"
  check 'the refused agent output names the agent marker' "$(grep -q 'carries an agent marker' "$tmp/err" && echo 0 || echo 1)"
  run_case 'a trusted comment that does not name the finding is refused' 4 -- dismiss --state "$S" --finding "$struct_id" --comment "${C}14"
  check 'the refused rejection names the finding it does not mention' "$(grep -q "the comment does not name finding $struct_id" "$tmp/err" && echo 0 || echo 1)"
  run_case 'a comment the pull request does not carry is refused' 4 -- dismiss --state "$S" --finding "$struct_id" --comment "${C}99"
  run_case 'a comment on another pull request is refused' 4 -- dismiss --state "$S" --finding "$struct_id" --comment https://github.com/acme/shop/pull/8#issuecomment-12
  run_case 'a rejection URL that is not a pull-request comment is a usage error' 1 -- dismiss --state "$S" --finding "$struct_id" --comment https://evil.example/acme/shop/pull/7#issuecomment-12
  mv "$tmp/pr.json" "$tmp/pr.saved"
  run_case 'a rejection the loader cannot load is refused' 4 -- dismiss --state "$S" --finding "$struct_id" --comment "${C}12"
  mv "$tmp/pr.saved" "$tmp/pr.json"
  check 'every refused rejection leaves the state untouched' "$(cmp -s "$tmp/before-dismiss" "$repo/$S" && echo 0 || echo 1)"
  rm -f "$tmp/loader-calls"
  run_case 'a security finding is never dismissed, even by the owner' 4 -- dismiss --state "$S" --finding "$sql_id" --comment "${C}12"
  check 'a security finding is refused before the loader runs' "$([[ ! -e "$tmp/loader-calls" ]] && echo 0 || echo 1)"
  run_case 'the owner dismisses a non-security finding' 0 -- dismiss --state "$S" --finding "$struct_id" --comment "${C}12"
  check 'the dismissal reads the association from the loaded pull request' "$(grep -qx 'https://github.com/acme/shop/pull/7' "$tmp/loader-calls" && echo 0 || echo 1)"
  check 'the dismissal is recorded with its trusted actor' "$(jq -e --arg id "$struct_id" '(.findings[] | select(.finding_id == $id) | .status) == "dismissed"
      and any(.transitions[]; .finding_id == $id and .to == "dismissed" and .actor == "trusted:OWNER")' "$repo/$S" >/dev/null && echo 0 || echo 1)"
  run_case 'one comment dismisses only the finding it names' 4 -- dismiss --state "$S" --finding "$other_id" --comment "${C}12"
  check 'the finding the comment does not name stays open' "$(jq -e --arg id "$other_id" '(.findings[] | select(.finding_id == $id) | .status) == "new"' "$repo/$S" >/dev/null && echo 0 || echo 1)"
  report "$tmp/d2.md" 2 "$F_STRUCT" "$F_SQL"
  run_case 'the reviewer reports the dismissed finding again' 0 -- record --state "$S" --input "$tmp/d2.md" --changed-files "$tmp/changed-both"
  check 'a dismissed finding the code still carries reopens instead of being suppressed' "$(jq -e --arg id "$struct_id" '(.findings[] | select(.finding_id == $id) | .status) == "confirmed"' "$repo/$S" >/dev/null && echo 0 || echo 1)"
  run_case 'a deferral before the cap round is refused' 4 -- defer --state "$S" --finding "$struct_id" --url https://github.com/acme/shop/issues/9

  # --- the cap and the threshold: default branch only, range-checked ---------------------------------------
  manifest '{ "review": { "max-iterations": 2, "blocking-threshold": "medium" } }'
  printf '{ "extra": { "ai-olympus": { "review": { "max-iterations": 9, "blocking-threshold": "low" } } } }\n' >"$repo/composer.json"
  run_case 'the configuration is read' 0 -- evaluate --state "$S"
  check 'a working-tree composer.json changes neither the cap nor the threshold' "$(q '.max_iterations == 2 and .blocking_threshold == "medium"')"
  (cd "$repo" && AI_OLYMPUS_REVIEW_MAX_ITERATIONS=9 REVIEW_MAX_ITERATIONS=9 MAX_ITERATIONS=9 maxIterations=9 "$script" evaluate --state "$S") >"$tmp/out" 2>/dev/null
  check 'an environment variable does not change the cap' "$(q '.max_iterations == 2')"
  git -C "$repo" checkout -q -- composer.json
  local bad
  for bad in 0 -1 '"3"' 2.5 11 null; do
    manifest "{ \"review\": { \"max-iterations\": $bad } }"
    run_case "a cap of $bad is evaluated" 0 -- evaluate --state "$S"
    check "a cap of $bad falls back to 3" "$(q '.max_iterations == 3')"
  done
  check 'a refused cap is named on stderr' "$(manifest '{ "review": { "max-iterations": 0 } }'; (cd "$repo" && "$script" evaluate --state "$S" 2>&1 >/dev/null) | grep -q 'refused: review.max-iterations' && echo 0 || echo 1)"
  manifest '{ "review": { "blocking-threshold": "none" } }'
  run_case 'an unknown threshold is evaluated' 0 -- evaluate --state "$S"
  check 'an unknown threshold falls back to critical' "$(q '.blocking_threshold == "critical"')"

  # The most permissive threshold still blocks every Moderate with evidence; a security low blocks too.
  manifest '{ "review": { "blocking-threshold": "critical" } }'
  rm -f "$repo/$S"
  (cd "$repo" && "$script" init --state "$S" --repo acme/shop --pr 7 >/dev/null)
  report "$tmp/t1.md" 1 "$F_MED"
  run_case 'a Moderate under the most permissive threshold' 0 -- record --state "$S" --input "$tmp/t1.md"
  check 'the most permissive threshold leaves a Moderate blocking' "$(q '.verdict == "continue" and .counts.remaining_blocking == 1 and .blocking[0].severity == "medium"')"
  for level in High Medium Low; do
    rm -f "$repo/$S"
    (cd "$repo" && "$script" init --state "$S" --repo acme/shop --pr 7 >/dev/null)
    report "$tmp/t2.md" 1 "$(finding Moderate 'Weak escaping' 'src/View/Render.php:3' "$SQL" 'exploit-path — <b> reaches the page' "$level")"
    run_case "a security-lens $level finding is recorded" 0 -- record --state "$S" --input "$tmp/t2.md"
    check "a security-lens $level finding maps to a blocking severity" "$(q ".blocking[0].severity == \"$(printf '%s' "$level" | tr '[:upper:]' '[:lower:]')\" and .counts.remaining_blocking == 1")"
  done

  # --- cap 1: an open security finding is a hard stop, never a deferral ------------------------------------
  manifest '{ "review": { "max-iterations": 1 } }'
  rm -f "$repo/$S"
  (cd "$repo" && "$script" init --state "$S" --repo acme/shop --pr 7 >/dev/null)
  report "$tmp/k1.md" 1 "$F_LOW_SEC"
  run_case 'cap 1 with a security low finding' 0 -- record --state "$S" --input "$tmp/k1.md"
  check 'at cap 1 an open security low finding is a hard stop, never a deferral and never convergence' "$(q '.verdict == "escalated" and .escalation_reason == "cap-reached-hard-blockers" and (.deferrable | length) == 0')"

  rm -f "$repo/$S"
  (cd "$repo" && "$script" init --state "$S" --repo acme/shop --pr 7 >/dev/null)
  report "$tmp/k2.md" 1 "$F_STRUCT" "$F_NOEV"
  run_case 'cap 1 with a non-security Moderate' 0 -- record --state "$S" --input "$tmp/k2.md"
  check 'at the cap a non-security Moderate below the threshold requires a deferral' "$(q '.verdict == "deferral-required" and (.deferrable | length) == 1')"
  run_case 'a deferral without an https URL is a usage error' 1 -- defer --state "$S" --finding "$struct_id" --url 'http://x'
  run_case 'the filed sub-issue defers the finding' 0 -- defer --state "$S" --finding "$struct_id" --url https://github.com/acme/shop/issues/9
  check 'scenario 10: a loop left with only deferred and unverified findings converges' "$(q '.verdict == "converged" and .counts.deferred == 1 and .counts.needs_verification == 1')"

  rm -f "$repo/$S"
  (cd "$repo" && "$script" init --state "$S" --repo acme/shop --pr 7 >/dev/null)
  (cd "$repo" && "$script" record --state "$S" --input "$tmp/k2.md" >/dev/null)
  run_case 'the final evaluation of an undeferred Moderate' 0 -- evaluate --state "$S" --final
  check 'a Moderate neither fixed nor deferred at the cap escalates on the final evaluation' "$(q '.verdict == "escalated" and .escalation_reason == "cap-reached-undeferred-blockers"')"

  rm -f "$repo/$S"
  (cd "$repo" && "$script" init --state "$S" --repo acme/shop --pr 7 >/dev/null)
  report "$tmp/m1.md" 1
  run_case 'cap 1 with a clean round' 0 -- record --state "$S" --input "$tmp/m1.md"
  check 'the loop converges in the cap round' "$(q '.verdict == "converged" and .iteration == 1')"
  report "$tmp/m2.md" 2 "$F_STRUCT"
  run_case 'a round after a convergence in the cap round is refused' 5 -- record --state "$S" --input "$tmp/m2.md" --changed-files "$tmp/changed-both"
  check 'a change after a convergence in the cap round escalates with cap-spent-after-convergence' "$(q '.verdict == "escalated" and .status == "escalated" and .escalation_reason == "cap-spent-after-convergence" and (.reason | test("converged in the cap round of 1"))')"
  check 'the escalation is stored and the refused round is not recorded' "$(jq -e '.status == "escalated" and .escalation_reason == "cap-spent-after-convergence" and .iteration == 1 and (.findings | length) == 0' "$repo/$S" >/dev/null && echo 0 || echo 1)"
  run_case 'the escalated loop is evaluated' 0 -- evaluate --state "$S"
  check 'the evaluation after the refused round is escalated, never converged' "$(q '.verdict == "escalated" and .escalation_reason == "cap-spent-after-convergence"')"
  manifest '{ "review": { "max-iterations": 1, "blocking-threshold": "medium" } }'
  rm -f "$repo/$S"
  (cd "$repo" && "$script" init --state "$S" --repo acme/shop --pr 7 >/dev/null)
  run_case 'a tighter threshold makes a medium Moderate a hard blocker' 0 -- record --state "$S" --input "$tmp/k2.md"
  check 'a medium finding at or above the threshold is never deferrable' "$(q '.verdict == "escalated" and (.deferrable | length) == 0')"

  # --- scenario 11: recovery after an interrupted workflow -------------------------------------------------
  manifest '{}'
  rm -f "$repo/$S"
  (cd "$repo" && "$script" init --state "$S" --repo acme/shop --pr 7 >/dev/null)
  (cd "$repo" && "$script" record --state "$S" --input "$tmp/r1.md" >/dev/null)
  (cd "$repo" && "$script" record --state "$S" --input "$tmp/r2.md" --changed-files "$tmp/changed-none" >/dev/null)
  run_case 'scenario 11: init after an interruption resumes the existing state' 0 -- init --state "$S" --repo acme/shop --pr 7
  check 'the resumed state keeps its round count' "$(q '.resumed == true and .iteration == 2')"
  run_case 'the next round continues the count' 0 -- record --state "$S" --input "$tmp/r3.md" --changed-files "$tmp/changed-none"
  check 'the recovered loop counts the round as round 3' "$(q '.iteration == 3')"
  run_case 'init for another pull request refuses to replace the state' 3 -- init --state "$S" --repo acme/shop --pr 8

  jq -c '.iteration = 0' "$repo/$S" >"$tmp/lowered" && cp "$tmp/lowered" "$repo/$S"
  run_case 'a state whose round count was lowered is invalid' 3 -- evaluate --state "$S"
  printf '{ broken' >"$repo/$S"
  cp "$repo/$S" "$tmp/corrupt"
  run_case 'a corrupted state is never converged' 3 -- evaluate --state "$S"
  check 'the corrupted state prints no verdict' "$([[ ! -s "$tmp/out" ]] && echo 0 || echo 1)"
  run_case 'init never overwrites a corrupted state' 3 -- init --state "$S" --repo acme/shop --pr 7
  check 'the corrupted state is left for inspection' "$(cmp -s "$tmp/corrupt" "$repo/$S" && echo 0 || echo 1)"
  run_case 'a missing state is never converged' 3 -- evaluate --state .claude/run/none.json
  run_case 'record without a state is refused' 3 -- record --state .claude/run/none.json --input "$tmp/r1.md"

  rm -f "$repo/$S"
  (cd "$repo" && "$script" init --state "$S" --repo acme/shop --pr 7 >/dev/null)
  (cd "$repo" && "$script" record --state "$S" --input "$tmp/b1.md" >/dev/null)
  jq -c '.findings[0].status = "resolved"' "$repo/$S" >"$tmp/edited" && cp "$tmp/edited" "$repo/$S"
  run_case 'a status edited without a transition is invalid' 3 -- evaluate --state "$S"
  (cd "$repo" && "$script" init --state "$S" --repo acme/shop --pr 7 >/dev/null 2>&1) || true
  jq -c '.findings[0].status = "dismissed" | .findings[0].security = true
      | .transitions += [{iteration: 1, finding_id: .findings[0].finding_id, from: "new", to: "dismissed", actor: "trusted:OWNER"}]' "$tmp/edited" >"$repo/$S"
  run_case 'a dismissed security finding in a recovered state is invalid' 3 -- evaluate --state "$S"
  jq -c '.status = "converged" | .rounds = [] | .iteration = 0 | .transitions = [] | .findings = []' "$tmp/edited" >"$repo/$S"
  run_case 'a state that claims convergence without a round is invalid' 3 -- evaluate --state "$S"

  # --- scenario 12: the broad review -----------------------------------------------------------------------
  rm -f "$repo/$S"
  (cd "$repo" && "$script" init --state "$S" --repo acme/shop --pr 7 >/dev/null)
  run_case 'the first round is scoped' 0 -- scope --state "$S" --changed-files "$tmp/changed-none"
  check 'the first round reviews the full change set' "$(q '.scope == "full" and .reasons == ["first-round"]')"
  (cd "$repo" && "$script" record --state "$S" --input "$tmp/b1.md" >/dev/null)
  printf 'src/Foo/Bar.php\n' >"$tmp/changed-plain"
  run_case 'a plain delta is scoped' 0 -- scope --state "$S" --changed-files "$tmp/changed-plain"
  check 'a delta that touches no sensitive surface stays incremental' "$(q '.scope == "delta" and .reasons == [] and (.baseline | test("^a{39}1$"))')"
  printf 'src/Foo/Bar.php\napp/Http/Middleware/Authenticate.php\n' >"$tmp/changed-auth"
  run_case 'a delta that touches authentication is scoped' 0 -- scope --state "$S" --changed-files "$tmp/changed-auth"
  check 'scenario 12: a delta on a security surface triggers the broad review' "$(q '.scope == "full" and (.reasons | index("security-surface"))')"
  printf 'config/app.php\n' >"$tmp/changed-config"
  run_case 'a delta that touches shared configuration is scoped' 0 -- scope --state "$S" --changed-files "$tmp/changed-config"
  check 'a delta on a shared surface triggers the broad review' "$(q '.scope == "full" and (.reasons | index("shared-surface"))')"
  (cd "$repo" && "$script" record --state "$S" --input "$tmp/b2.md" --changed-files "$tmp/changed-both" >/dev/null)
  (cd "$repo" && "$script" record --state "$S" --input "$tmp/b1.md" --changed-files "$tmp/changed-both" >/dev/null 2>&1) || true
  run_case 'a delta after a regression is scoped' 0 -- scope --state "$S" --changed-files "$tmp/changed-plain"
  check 'a regression of a resolved finding triggers the broad review' "$(q '.scope == "full" and (.reasons | index("regression"))')"

  # A fix can land in another file than the finding it fixes. The next round then reads the whole PR diff.
  rm -f "$repo/$S"
  (cd "$repo" && "$script" init --state "$S" --repo acme/shop --pr 7 >/dev/null)
  report "$tmp/f1.md" 1 "$F_SQL"
  (cd "$repo" && "$script" record --state "$S" --input "$tmp/f1.md" >/dev/null)
  printf 'app/Support/SortColumns.php\n' >"$tmp/changed-elsewhere"
  run_case 'a delta that leaves a proven finding untouched is scoped' 0 -- scope --state "$S" --changed-files "$tmp/changed-elsewhere"
  check 'a proven finding outside the delta widens the next round to the whole PR' "$(q '.scope == "full" and .reasons == ["open-finding-outside-delta"]')"
  check 'the computed scope is stored for the next record' "$(jq -e '.scope == "full"' "$repo/$S" >/dev/null && echo 0 || echo 1)"
  report "$tmp/f2.md" 2
  run_case 'the broad round no longer reports the finding' 0 -- record --state "$S" --input "$tmp/f2.md" --changed-files "$tmp/changed-elsewhere"
  check 'a finding fixed in another file is resolved by the broad round and the loop converges' "$(q '.verdict == "converged" and .counts.resolved == 1 and (.carried | length) == 0')"
  check 'the record consumes the stored scope' "$(jq -e '.scope == null' "$repo/$S" >/dev/null && echo 0 || echo 1)"

  # A blocking finding whose location names no file sits outside every delta: no delta round reads it.
  rm -f "$repo/$S"
  (cd "$repo" && "$script" init --state "$S" --repo acme/shop --pr 7 >/dev/null)
  report "$tmp/g1.md" 1 "$(finding Critical 'The policy is never checked' 'the pull request as a whole' "$SQL" 'exploit-path — no route calls the policy')"
  (cd "$repo" && "$script" record --state "$S" --input "$tmp/g1.md" >/dev/null)
  check 'a finding whose location names no file is stored with the file "."' "$(jq -e '.findings[0].file == "." and .findings[0].status == "new"' "$repo/$S" >/dev/null && echo 0 || echo 1)"
  run_case 'a delta that leaves a path-less blocking finding is scoped' 0 -- scope --state "$S" --changed-files "$tmp/changed-plain"
  check 'a path-less blocking finding widens the next round to the whole PR' "$(q '.scope == "full" and .reasons == ["open-finding-outside-delta"]')"
  report "$tmp/g2.md" 2
  run_case 'the broad round no longer reports the path-less finding' 0 -- record --state "$S" --input "$tmp/g2.md" --changed-files "$tmp/changed-plain"
  check 'a full round that omits a path-less blocking finding resolves it' "$(q '.verdict == "converged" and .counts.resolved == 1 and (.carried | length) == 0')"
  rm -f "$repo/$S"
  (cd "$repo" && "$script" init --state "$S" --repo acme/shop --pr 7 >/dev/null)
  (cd "$repo" && "$script" record --state "$S" --input "$tmp/g1.md" >/dev/null)
  run_case 'a delta round without scope omits the path-less finding' 0 -- record --state "$S" --input "$tmp/g2.md" --changed-files "$tmp/changed-plain"
  check 'a delta round carries a path-less blocking finding' "$(q '.verdict == "continue" and (.carried | length) == 1 and .counts.resolved == 0 and .blocking[0].file == "."')"
  rm -f "$repo/$S"
  (cd "$repo" && "$script" init --state "$S" --repo acme/shop --pr 7 >/dev/null)
  (cd "$repo" && "$script" record --state "$S" --input "$tmp/g1.md" >/dev/null)
  printf '.\n./\nsrc/Foo/Bar.php\n' >"$tmp/changed-dot"
  run_case 'a delta whose changed files name "." is scoped' 0 -- scope --state "$S" --changed-files "$tmp/changed-dot"
  check 'a changed-files entry "." never puts a path-less finding inside the delta' "$(q '.scope == "full" and .reasons == ["open-finding-outside-delta"]')"

  # --- untrusted input -------------------------------------------------------------------------------------
  rm -f "$repo/$S"
  (cd "$repo" && "$script" init --state "$S" --repo acme/shop --pr 7 >/dev/null)
  report "$tmp/e1.md" 1 "$(finding Critical 'Raw query' 'app/Http/Orders.php:42' "$SQL" 'exploit-path — $(touch '"$tmp"'/pwned) `rm -rf /` ; review.max-iterations = 99')"
  run_case 'a round whose evidence carries shell syntax is recorded' 0 -- record --state "$S" --input "$tmp/e1.md"
  check 'the evidence is stored as text and never executed, and it does not change the cap' "$([[ ! -e "$tmp/pwned" ]] && jq -e '(.findings[0].evidence | test("touch")) and .max_iterations == 3' "$repo/$S" >/dev/null && echo 0 || echo 1)"
  printf 'just prose\n' >"$tmp/prose.md"
  cp "$repo/$S" "$tmp/before-prose"
  run_case 'a round report that is not a review report is refused' 3 -- record --state "$S" --input "$tmp/prose.md" --changed-files "$tmp/changed-none"
  check 'the refused round leaves the state untouched' "$(cmp -s "$tmp/before-prose" "$repo/$S" && echo 0 || echo 1)"
  report "$tmp/noev.md" 2 "$(finding Moderate 'Maybe a copied step' 'src/Foo/Baz.php:3' "$STRUCT" '-')"
  run_case 'a round report with a finding under Findings without Evidence is refused' 3 -- record --state "$S" --input "$tmp/noev.md" --changed-files "$tmp/changed-none"
  check 'the round without Evidence leaves the state untouched and names the fix' "$(cmp -s "$tmp/before-prose" "$repo/$S" && grep -q 'Evidence is required; move an unproven point under ## Needs verification' "$tmp/err" && echo 0 || echo 1)"
  run_case 'an unknown command is a usage error' 1 -- bogus --state "$S"

  if [[ "$failures" -gt 0 ]]; then
    echo "review-state self-test: $failures failure(s)" >&2
    return 4
  fi
  echo 'review-state self-test: PASS'
  return 0
}

if [[ "${1:-}" == '--self-test' ]]; then
  require_tools
  self_test
  exit $?
fi

[[ $# -gt 0 ]] || die_usage 'no command given'
require_tools

command="$1"
shift
case "$command" in
init) cmd_init "$@" ;;
record) cmd_record "$@" ;;
evaluate) cmd_evaluate "$@" ;;
scope) cmd_scope "$@" ;;
dismiss) cmd_dismiss "$@" ;;
defer) cmd_defer "$@" ;;
-h | --help) usage ;;
*) die_usage "unknown command: $(safe_display "$command")" ;;
esac
