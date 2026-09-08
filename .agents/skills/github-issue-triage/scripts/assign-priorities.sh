#!/usr/bin/env bash
# assign-priorities.sh — walk every OPEN issue of the current GitHub
# repository, derive its type and priority from the triage taxonomy, and apply
# the missing labels.
#
# Usage:
#   assign-priorities.sh [--dry-run]
#   assign-priorities.sh --self-test
#
# Options:
#   --dry-run    print the label changes without writing anything to GitHub
#   --self-test  run the offline test suite (no network, `gh` is stubbed)
#
# Type derivation (deterministic, first match wins):
#   [Bug] …         -> bug            fix(…): / fix:        -> bug
#   [Feature] …     -> enhancement    feat(…): / feat:      -> enhancement
#   PLAN (…):       -> plan           docs(…): / docs:      -> documentation
#                                     test(…): / test:      -> test
#                                     refactor(…):          -> refactor
#                                     chore(…):             -> chore
#                                     marketing:            -> marketing
#   The conventional-commits scope is not the type: `test(security):` is a
#   `test`, not a `security` issue. A `!` breaking marker is tolerated.
#   When the title carries no recognized prefix, the issue body is used as a
#   fallback, matched on the `### ` headings the GitHub issue forms generate:
#   the bug-report form ("### Expected behavior" / "### Actual behavior") means
#   `bug`, the feature-request form ("### What problem does this solve?" /
#   "### Proposed solution") means `enhancement`. A body carrying the headings
#   of BOTH forms is ambiguous and is reported, never resolved by the order the
#   two forms happen to be tested in. An issue whose type is derivable from
#   neither title nor body is skipped and reported for a human.
#
# Priority derivation from the type:
#   bug          -> priority: high
#   enhancement  -> priority: medium
#   everything else (documentation, test, refactor, chore, marketing, plan)
#                -> priority: low
#   `priority: critical` — a bug blocking the core product or a confirmed
#   security incident — is never assigned by this script: neither condition is
#   derivable from a title. It is a human decision, and an existing
#   `priority: critical` is never removed or downgraded.
#
# What the script may remove:
#   Only a label that is demonstrably wrong given an explicit title prefix, and
#   only when the type came from the title (never from the body fallback):
#     - a primary type label that contradicts the derived type
#     - a priority label that contradicts the derived priority, unless it is
#       `priority: critical`
#   `security` and `question` are topic labels, not primary types, and are
#   never removed. No other label is ever touched.
#
# Idempotency:
#   An issue that already carries the derived type and priority produces no
#   call at all, so re-running the script — including right after opening a new
#   issue, to label that one issue — is a no-op for everything already triaged.
#
# Target repository:
#   The repository `gh` resolves from the current working directory. It is
#   resolved and PRINTED as the first line of output, before any write: this is
#   the only script in the package that REMOVES labels, and a transcript that
#   does not name the repository it wrote to cannot be audited afterwards.
#
# Exit codes:
#   0  every open issue is triaged (or reported as skipped / kept)
#   1  wrong usage, or a failing self-test
#   2  required tool not found (gh, jq)
#   3  a `gh` call failed (auth, permissions, API error). The run stops at that
#      issue; the labels already applied stand and a re-run resumes from there,
#      because the pass is idempotent.

set -euo pipefail

# GitHub caps a single `gh issue list` page; 500 open issues is far above this
# repository's real backlog and keeps the run to one request. A backlog that
# actually reaches the cap is reported, never silently truncated.
OPEN_ISSUE_LIMIT=500

# Types that a title prefix can derive. `security` and `question` are topic
# labels: they are never derived and never removed.
PRIMARY_TYPES="bug enhancement documentation test refactor chore marketing plan"

usage() {
  cat >&2 <<'EOF'
Usage: assign-priorities.sh [--dry-run]
       assign-priorities.sh --self-test

  Derives the type and priority of every open issue from its title (falling
  back to the issue body) and applies the missing labels.

  --dry-run    print the planned label changes, write nothing
  --self-test  run the offline test suite (derivation table + end-to-end run
               against a stubbed gh)
EOF
}

# --- derivation: pure functions, no network, covered by --self-test ---------

# Prints the type derived from the issue title, or returns 1 when the title
# carries no recognized prefix.
derive_type_from_title() {
  local title="$1"

  case "$title" in
    '[Bug]'*)
      printf 'bug'
      return 0
      ;;
    '[Feature]'*)
      printf 'enhancement'
      return 0
      ;;
  esac

  if [[ "$title" =~ ^PLAN[[:space:]]*\( ]]; then
    printf 'plan'
    return 0
  fi

  if [[ "$title" =~ ^([a-z]+)(\([^\)]*\))?!?: ]]; then
    case "${BASH_REMATCH[1]}" in
      fix)
        printf 'bug'
        return 0
        ;;
      feat)
        printf 'enhancement'
        return 0
        ;;
      docs)
        printf 'documentation'
        return 0
        ;;
      test)
        printf 'test'
        return 0
        ;;
      refactor)
        printf 'refactor'
        return 0
        ;;
      chore)
        printf 'chore'
        return 0
        ;;
      marketing)
        printf 'marketing'
        return 0
        ;;
    esac
  fi

  return 1
}

# The GitHub issue forms render every field label as a `### ` heading, so the
# body fallback is anchored to those headings at the start of a line. An
# unanchored substring match reads a sentence — a feature request whose prose
# happens to say "Expected behavior: …" would be labelled a bug.
BUG_FORM_HEADINGS='### Expected behavior
### Actual behavior'

FEATURE_FORM_HEADINGS='### What problem does this solve?
### Proposed solution'

# Does the body start a line with any of the newline-separated headings?
body_has_any_heading() {
  local body="$1" headings="$2" heading

  while IFS= read -r heading; do
    if [[ -z "$heading" ]]; then
      continue
    fi

    if [[ $'\n'"$body" == *$'\n'"$heading"* ]]; then
      return 0
    fi
  done <<<"$headings"

  return 1
}

# Prints the type derived from the issue body.
#   0  the body matches exactly one issue form
#   1  the body matches neither form
#   2  the body matches BOTH forms — ambiguous, to be reported for a human
derive_type_from_body() {
  local body="$1"
  local is_bug=false is_feature=false

  if body_has_any_heading "$body" "$BUG_FORM_HEADINGS"; then
    is_bug=true
  fi

  if body_has_any_heading "$body" "$FEATURE_FORM_HEADINGS"; then
    is_feature=true
  fi

  if [[ "$is_bug" == true && "$is_feature" == true ]]; then
    return 2
  fi

  if [[ "$is_bug" == true ]]; then
    printf 'bug'
    return 0
  fi

  if [[ "$is_feature" == true ]]; then
    printf 'enhancement'
    return 0
  fi

  return 1
}

# Prints the priority label for a derived type. Never prints
# `priority: critical` — see the header.
priority_for_type() {
  case "$1" in
    bug) printf 'priority: high' ;;
    enhancement) printf 'priority: medium' ;;
    *) printf 'priority: low' ;;
  esac
}

is_primary_type() {
  local candidate="$1"
  local known

  for known in $PRIMARY_TYPES; do
    if [[ "$candidate" == "$known" ]]; then
      return 0
    fi
  done

  return 1
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

# The add / remove / keep decision tree is the only part of this script that can
# REMOVE a label, so it is proven by RUNNING the script — against a stubbed
# `gh` that answers from a fixture and records every write — rather than by
# reading its source. The precedent is `skills/_shared/assert-current-repo.sh
# --self-test`, which builds a fixture checkout and re-invokes itself.
end_to_end_cases() {
  local script stub
  script="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)/$(basename "${BASH_SOURCE[0]}")"

  SELF_TEST_TMP="$(mktemp -d)"
  trap cleanup_self_test EXIT

  stub="$SELF_TEST_TMP/bin"
  mkdir -p "$stub"

  cat >"$stub/gh" <<'STUB'
#!/usr/bin/env bash
# Stand-in for the three `gh` calls the triage makes: `repo view` and
# `issue list` are answered from the fixture, and every `issue edit` argv is
# recorded — pipe-joined, one call per line — so the test asserts the exact
# write and not merely the printed plan.
set -euo pipefail

case "${1:-} ${2:-}" in
  'repo view')
    printf '%s\n' "$GH_STUB_NWO"
    ;;
  'issue list')
    cat "$GH_STUB_ISSUES"
    ;;
  'issue edit')
    shift 2
    (
      IFS='|'
      printf '%s\n' "$*"
    ) >>"$GH_STUB_EDITS"
    ;;
  *)
    echo "gh stub: unexpected call: $*" >&2
    exit 1
    ;;
esac
STUB
  chmod +x "$stub/gh"

  local STUB_NWO='stub-owner/stub-repo'

  # Runs the real script over a one-off fixture and asserts three things: the
  # exit code, the expected line on stdout, and the `gh issue edit` argv the
  # run produced ("-" means the run must not have written anything at all).
  e2e() {
    local label="$1" issues="$2" mode="$3" expected_line="$4" expected_edit="$5"
    local out rc edits

    printf '%s' "$issues" >"$SELF_TEST_TMP/issues.json"
    : >"$SELF_TEST_TMP/edits"

    set +e
    # shellcheck disable=SC2086 # $mode is empty or the single --dry-run flag
    out="$(cd "$SELF_TEST_TMP" && PATH="$stub:$PATH" \
      GH_STUB_NWO="$STUB_NWO" \
      GH_STUB_ISSUES="$SELF_TEST_TMP/issues.json" \
      GH_STUB_EDITS="$SELF_TEST_TMP/edits" \
      "$script" $mode 2>&1)"
    rc=$?
    set -e

    edits="$(cat "$SELF_TEST_TMP/edits")"
    if [[ -z "$edits" ]]; then
      edits='-'
    fi

    checks=$((checks + 1))

    if [[ "$rc" -ne 0 ]]; then
      echo "self-test FAIL: $label -> exit $rc" >&2
      echo "$out" >&2
      failures=$((failures + 1))
      return 0
    fi

    # Every run must name the repository it is about to write to.
    if [[ "$out" != *"target repository: $STUB_NWO"* ]]; then
      echo "self-test FAIL: $label -> output does not name the target repository" >&2
      echo "$out" >&2
      failures=$((failures + 1))
      return 0
    fi

    if [[ "$out" != *"$expected_line"* ]]; then
      echo "self-test FAIL: $label -> missing line: $expected_line" >&2
      echo "$out" >&2
      failures=$((failures + 1))
      return 0
    fi

    if [[ "$edits" != "$expected_edit" ]]; then
      echo "self-test FAIL: $label -> gh issue edit was '$edits', expected '$expected_edit'" >&2
      failures=$((failures + 1))
      return 0
    fi
  }

  local untriaged='[{"number":11,"title":"fix(core): the installer overwrites CLAUDE.md","body":"","labels":[]}]'

  # add: an issue with no labels at all gets both the type and the priority.
  e2e 'add — untriaged issue' "$untriaged" '' \
    '#11  bug (title) — applied: +bug +priority: high' \
    '11|--add-label|bug|--add-label|priority: high'

  # --dry-run must reach the same plan without writing anything.
  e2e 'add — dry-run writes nothing' "$untriaged" '--dry-run' \
    '#11  bug (title) — would apply: +bug +priority: high' \
    '-'

  # keep: an issue already carrying both labels produces no call at all.
  e2e 'keep — already triaged issue is a no-op' \
    '[{"number":12,"title":"fix(core): boom","body":"","labels":[{"name":"bug"},{"name":"priority: high"}]}]' '' \
    '#12  bug (title) — already triaged' \
    '-'

  # remove: an explicit title prefix contradicts both the type and the priority.
  e2e 'remove — title prefix corrects a wrong type and priority' \
    '[{"number":13,"title":"fix(core): boom","body":"","labels":[{"name":"enhancement"},{"name":"priority: medium"}]}]' '' \
    '#13  bug (title) — applied: +bug +priority: high -enhancement -priority: medium' \
    '13|--add-label|bug|--add-label|priority: high|--remove-label|enhancement|--remove-label|priority: medium'

  # keep: a human escalation is never removed or downgraded.
  e2e 'keep — priority: critical survives a title-derived bug' \
    '[{"number":14,"title":"fix(core): boom","body":"","labels":[{"name":"priority: critical"}]}]' '' \
    '#14  bug (title) — applied: +bug (kept the existing priority — human decision)' \
    '14|--add-label|bug'

  # remove: topic labels are not primary types and stay on the issue.
  e2e 'remove — security and question topics are never removed' \
    '[{"number":15,"title":"fix(core): boom","body":"","labels":[{"name":"security"},{"name":"question"},{"name":"enhancement"},{"name":"priority: high"}]}]' '' \
    '#15  bug (title) — applied: +bug -enhancement' \
    '15|--add-label|bug|--remove-label|enhancement'

  # add: the body fallback labels an issue whose title has no prefix.
  e2e 'add — body form labels an unlabelled issue' \
    '[{"number":16,"title":"Skill pro štítkovací systém","body":"### What problem does this solve?\n\nIssues have no priority.\n\n### Proposed solution\n\nAdd a triage skill.","labels":[]}]' '' \
    '#16  enhancement (body) — applied: +enhancement +priority: medium' \
    '16|--add-label|enhancement|--add-label|priority: medium'

  # The body is the weaker signal: it never overrules a label a human set.
  e2e 'skip — body never overrides a human type label' \
    '[{"number":17,"title":"Skill pro štítkovací systém","body":"### What problem does this solve?\n\nIssues have no priority.\n\n### Proposed solution\n\nAdd a triage skill.","labels":[{"name":"bug"}]}]' '' \
    "#17  skipped — body suggests 'enhancement' but the issue is labelled 'bug'" \
    '-'

  # A body carrying both forms is reported, not resolved by test order.
  e2e 'skip — a body matching both forms is ambiguous' \
    '[{"number":18,"title":"Both forms in one body","body":"### Expected behavior\n\nIt labels the issue.\n\n### What problem does this solve?\n\nNothing labels it.","labels":[]}]' '' \
    '#18  skipped — the body matches both the bug and the feature form' \
    '-'

  # The regression the anchoring exists for: a feature request whose free text
  # mentions "Expected behavior:" is an enhancement, not a bug.
  e2e 'add — a prose mention of a form phrase does not flip the type' \
    '[{"number":19,"title":"Štítky se nepřiřazují automaticky","body":"### What problem does this solve?\n\nNew issues carry no labels.\n\n### Proposed solution\n\nRun the triage after opening an issue. Expected behavior: the label appears right away.","labels":[]}]' '' \
    '#19  enhancement (body) — applied: +enhancement +priority: medium' \
    '19|--add-label|enhancement|--add-label|priority: medium'

  # …and an unanchored phrase on its own derives nothing at all.
  e2e 'skip — an unanchored form phrase derives no type' \
    '[{"number":20,"title":"A free-form note","body":"We described the expected behavior and the actual behavior in the thread.","labels":[]}]' '' \
    '#20  skipped — type not derivable from title or body' \
    '-'

  # The summary counts each issue in exactly one bucket, and reports the kept
  # manual priorities as their own clause rather than as a parenthetical on the
  # skipped count (they are not a subset of it).
  e2e 'summary — every bucket is counted separately' \
    '[{"number":21,"title":"fix(core): boom","body":"","labels":[{"name":"priority: critical"}]},{"number":22,"title":"fix(core): bang","body":"","labels":[{"name":"bug"},{"name":"priority: high"}]},{"number":23,"title":"A free-form note","body":"nothing to match","labels":[]}]' '' \
    'assign-priorities.sh: 3 open issues — 1 changed, 1 already triaged, 1 skipped, 1 kept a manual priority' \
    '21|--add-label|bug'
}

self_test() {
  local failures=0
  local checks=0
  local entry expected_title expected_type expected_priority expected_body rest actual_type actual_priority known body_status

  # title|expected type|expected priority ("-" = not derivable from the title)
  title_cases=(
    '[Bug]: install --force overwrites CLAUDE.md|bug|priority: high'
    '[Feature]: Skill pro task managment system github|enhancement|priority: medium'
    'fix(agents): sdílené briefy z minulých běhů přežívají v .claude/run/|bug|priority: high'
    'fix: drop the stale carve-out|bug|priority: high'
    'fix(installer)!: rename the install flag|bug|priority: high'
    'feat(installer): optional per-agent PreToolUse hook|enhancement|priority: medium'
    'docs(readme): natočit a vložit 60sekundové demo|documentation|priority: low'
    'test(security): bind getSensitivePathPatterns() to its prose|test|priority: low'
    'refactor(installer): split InstallerClaudeSettings|refactor|priority: low'
    'chore(release): otagovat a vydat release v0.1.0|chore|priority: low'
    'marketing: runbook launch dne|marketing|priority: low'
    'PLAN (#185): per-agent PreToolUse hook|plan|priority: low'
    'Claude Code appears to never load .mdc rule files|-|-'
    'perf(installer): speed up the copy loop|-|-'
  )

  for entry in "${title_cases[@]}"; do
    expected_title="${entry%%|*}"
    rest="${entry#*|}"
    expected_type="${rest%%|*}"
    expected_priority="${rest#*|}"

    if actual_type="$(derive_type_from_title "$expected_title")"; then
      actual_priority="$(priority_for_type "$actual_type")"
    else
      actual_type='-'
      actual_priority='-'
    fi

    checks=$((checks + 1))
    if [[ "$actual_type" != "$expected_type" || "$actual_priority" != "$expected_priority" ]]; then
      echo "self-test FAIL: '$expected_title' -> $actual_type / $actual_priority (expected $expected_type / $expected_priority)" >&2
      failures=$((failures + 1))
    fi
  done

  # body|expected type ("-" = derivable from neither form, "!" = both forms)
  body_cases=(
    '### Expected behavior

The installer keeps CLAUDE.md.

### Actual behavior

It overwrites it.|bug'
    '### What problem does this solve?

Issues have no priority.

### Proposed solution

Add a triage skill.|enhancement'
    'Just a free-form note with no form markers.|-'
    '### What problem does this solve?

New issues carry no labels.

### Proposed solution

Run the triage. Expected behavior: the label appears right away.|enhancement'
    '### Expected behavior

It labels the issue.

### What problem does this solve?

Nothing labels it.|!'
    'We described the expected behavior and the Actual behavior in the thread.|-'
  )

  for entry in "${body_cases[@]}"; do
    expected_body="${entry%|*}"
    expected_type="${entry##*|}"

    body_status=0
    actual_type="$(derive_type_from_body "$expected_body")" || body_status=$?

    if [[ "$body_status" -eq 2 ]]; then
      actual_type='!'
    elif [[ "$body_status" -ne 0 ]]; then
      actual_type='-'
    fi

    checks=$((checks + 1))
    if [[ "$actual_type" != "$expected_type" ]]; then
      echo "self-test FAIL: body case -> $actual_type (expected $expected_type)" >&2
      failures=$((failures + 1))
    fi
  done

  # `priority: critical` is a human decision — no derivable type may produce it.
  for known in $PRIMARY_TYPES; do
    checks=$((checks + 1))
    if [[ "$(priority_for_type "$known")" == 'priority: critical' ]]; then
      echo "self-test FAIL: type '$known' derived priority: critical" >&2
      failures=$((failures + 1))
    fi
  done

  end_to_end_cases

  if [[ "$failures" -gt 0 ]]; then
    echo "assign-priorities.sh: self-test failed ($failures of $checks checks)" >&2
    return 1
  fi

  echo "assign-priorities.sh: self-test passed ($checks checks)"
}

# --- arguments --------------------------------------------------------------

DRY_RUN=false

if [[ $# -gt 1 ]]; then
  echo "assign-priorities.sh: too many arguments" >&2
  usage
  exit 1
fi

if [[ $# -eq 1 ]]; then
  case "$1" in
    --dry-run)
      DRY_RUN=true
      ;;
    --self-test)
      # The end-to-end cases run this script for real, so they need `jq` —
      # only `gh` is stubbed.
      if ! command -v jq >/dev/null 2>&1; then
        echo "assign-priorities.sh: the self-test requires jq" >&2
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
      echo "assign-priorities.sh: unknown argument: $1" >&2
      usage
      exit 1
      ;;
  esac
fi

for bin in gh jq; do
  if ! command -v "$bin" >/dev/null 2>&1; then
    echo "assign-priorities.sh: required tool not found: $bin" >&2
    exit 2
  fi
done

# --- walk the open issues ---------------------------------------------------

# Name the target before touching it: this script removes labels, and `gh`
# resolves the repository implicitly from the working directory.
if ! repo_nwo="$(gh repo view --json nameWithOwner --jq '.nameWithOwner' 2>&1)"; then
  echo "assign-priorities.sh: failed to resolve the target repository: $repo_nwo" >&2
  exit 3
fi

echo "assign-priorities.sh: target repository: $repo_nwo"

ISSUES_JSON="$(mktemp)"
trap 'rm -f "$ISSUES_JSON"' EXIT

if ! gh_error="$(gh issue list --state open --limit "$OPEN_ISSUE_LIMIT" --json number,title,body,labels 2>&1 >"$ISSUES_JSON")"; then
  echo "assign-priorities.sh: failed to list open issues: $gh_error" >&2
  exit 3
fi

if ! TOTAL="$(jq 'length' "$ISSUES_JSON")"; then
  echo "assign-priorities.sh: unexpected non-JSON response from gh" >&2
  exit 3
fi

if [[ "$TOTAL" -ge "$OPEN_ISSUE_LIMIT" ]]; then
  echo "assign-priorities.sh: warning: the listing hit its page limit of $OPEN_ISSUE_LIMIT open issues, so the backlog below may be truncated — re-run after this page is triaged" >&2
fi

updated=0
unchanged=0
kept=0
skipped=0

# One jq pass over the whole document instead of four per issue: the four
# fields are emitted NUL-separated (`[0]|implode` is a one-character NUL
# string), the only separator that cannot occur inside a title or a body.
ISSUE_FIELDS='.[] | (.number|tostring), ([0]|implode), .title, ([0]|implode), (.body // ""), ([0]|implode), ([.labels[].name] | join("\n")), ([0]|implode)'

while IFS= read -r -d '' number <&3 &&
  IFS= read -r -d '' title <&3 &&
  IFS= read -r -d '' body <&3 &&
  IFS= read -r -d '' labels <&3; do

  if type="$(derive_type_from_title "$title")"; then
    type_source='title'
  else
    body_status=0
    type="$(derive_type_from_body "$body")" || body_status=$?

    case "$body_status" in
      0)
        type_source='body'
        ;;
      2)
        echo "#$number  skipped — the body matches both the bug and the feature form"
        skipped=$((skipped + 1))
        continue
        ;;
      *)
        echo "#$number  skipped — type not derivable from title or body"
        skipped=$((skipped + 1))
        continue
        ;;
    esac
  fi

  derived_priority="$(priority_for_type "$type")"

  # Split the issue labels into: the primary type labels it carries, the
  # priority labels it carries, and everything else (never touched).
  current_types=''
  current_priorities=''
  priority_count=0
  has_type=false
  has_derived_priority=false
  has_critical=false

  while IFS= read -r label; do
    if [[ -z "$label" ]]; then
      continue
    fi

    if [[ "$label" == "$type" ]]; then
      has_type=true
    elif is_primary_type "$label"; then
      current_types="$current_types$label"$'\n'
    fi

    case "$label" in
      'priority: '*)
        current_priorities="$current_priorities$label"$'\n'
        priority_count=$((priority_count + 1))
        if [[ "$label" == "$derived_priority" ]]; then
          has_derived_priority=true
        fi
        if [[ "$label" == 'priority: critical' ]]; then
          has_critical=true
        fi
        ;;
    esac
  done <<<"$labels"

  # A body-derived type is a weaker signal than a label a human already set.
  # When the two disagree, report the conflict instead of pinning a second
  # primary type onto the issue.
  if [[ "$type_source" == 'body' && -n "$current_types" ]]; then
    conflicting="$(printf '%s' "$current_types" | tr '\n' ' ')"
    echo "#$number  skipped — body suggests '$type' but the issue is labelled '${conflicting% }'"
    skipped=$((skipped + 1))
    continue
  fi

  adds=()
  removes=()

  if [[ "$has_type" == false ]]; then
    adds+=("$type")
  fi

  # A contradicting type label is removed only when the title proved the type.
  if [[ "$type_source" == 'title' && -n "$current_types" ]]; then
    while IFS= read -r label; do
      if [[ -n "$label" ]]; then
        removes+=("$label")
      fi
    done <<<"$current_types"
  fi

  priority_note=''

  if [[ -z "$current_priorities" ]]; then
    adds+=("$derived_priority")
  elif [[ "$has_derived_priority" == true && "$priority_count" -eq 1 ]]; then
    : # already correct
  elif [[ "$type_source" == 'title' && "$has_critical" == false ]]; then
    while IFS= read -r label; do
      if [[ -n "$label" && "$label" != "$derived_priority" ]]; then
        removes+=("$label")
      fi
    done <<<"$current_priorities"

    if [[ "$has_derived_priority" == false ]]; then
      adds+=("$derived_priority")
    fi
  else
    priority_note=' (kept the existing priority — human decision)'
    kept=$((kept + 1))
  fi

  if [[ "${#adds[@]}" -eq 0 && "${#removes[@]}" -eq 0 ]]; then
    echo "#$number  $type ($type_source) — already triaged$priority_note"
    unchanged=$((unchanged + 1))
    continue
  fi

  args=()
  actions=''

  if [[ "${#adds[@]}" -gt 0 ]]; then
    for label in "${adds[@]}"; do
      args+=(--add-label "$label")
      actions="$actions +$label"
    done
  fi

  if [[ "${#removes[@]}" -gt 0 ]]; then
    for label in "${removes[@]}"; do
      args+=(--remove-label "$label")
      actions="$actions -$label"
    done
  fi

  if [[ "$DRY_RUN" == true ]]; then
    echo "#$number  $type ($type_source) — would apply:$actions$priority_note"
  else
    if ! gh_error="$(gh issue edit "$number" "${args[@]}" 2>&1 >/dev/null)"; then
      echo "assign-priorities.sh: failed to edit issue #$number: $gh_error" >&2
      exit 3
    fi

    echo "#$number  $type ($type_source) — applied:$actions$priority_note"
  fi

  updated=$((updated + 1))
done 3< <(jq -j "$ISSUE_FIELDS" "$ISSUES_JSON")

if [[ "$DRY_RUN" == true ]]; then
  echo "assign-priorities.sh: $TOTAL open issues — $updated would change, $unchanged already triaged, $skipped skipped, $kept kept a manual priority"
else
  echo "assign-priorities.sh: $TOTAL open issues — $updated changed, $unchanged already triaged, $skipped skipped, $kept kept a manual priority"
fi
