#!/usr/bin/env bash
# The globals this library sets are read by the script that sources it.
# shellcheck disable=SC2034
# proposal-identity.sh — shared library for the identity of a prevention proposal.
#
# Sourced, not executed, by `propose-prevention.sh` (renders a proposal and finds the issue that holds it) and
# `promote-learning.sh` (reads a decision and a promotion on that issue). Both must agree on what a dedupe key is
# and on which issue is the proposal of a key, so that logic exists here once. The contract is
# skills/code-review/references/prevention-proposal.md *Dedupe* and learning-promotion.md *Approval and rejection*.

# The three parts of a defect class. The class check, the dedupe key, and the issue check all read them.
REPO_RE='[A-Za-z0-9_.-]+/[A-Za-z0-9_.-]+'
CATEGORY_RE='[a-z0-9_./-]+'
CAUSE_RE='[a-z0-9-]+'
KEY_PATTERN="^${REPO_RE}:${CATEGORY_RE}:${CAUSE_RE}\$"

# proposal_marker($key) is the last line of every proposal. proposal_of($key) reads {url, association, body} and is
# true for the proposal of the key: an issue of the key's repository, filed by an author with write access, whose
# body carries the marker of the key on a line of its own. A copy of the marker anywhere else is text.
JQ_PROPOSAL=''
IFS= read -r -d '' JQ_PROPOSAL <<'EOF' || true
def proposal_marker($key): "<!-- prevention-proposal:key=\($key) -->";
def proposal_of($key):
  (.association | IN("OWNER", "MEMBER", "COLLABORATOR"))
  and (.url | type == "string" and test("^https://github\\.com/" + proposal_repo_re + "/issues/[0-9]+$"))
  and (.url | ascii_downcase | startswith("https://github.com/" + ($key | split(":")[0] | ascii_downcase) + "/issues/"))
  and ((.body // "") | split("\n") | any(sub("[ \t\r]+$"; "") == proposal_marker($key)));
EOF
JQ_PROPOSAL="def proposal_repo_re: \"${REPO_RE}\";"$'\n'"$JQ_PROPOSAL"
