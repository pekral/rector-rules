# Ready-to-merge phase signal (phase 3)

Referenced from `skills/process-code-review/SKILL.md` *Promote the PR out of Draft and signal ready to merge*. Extracted to keep the skill body under the skill-check token limit; the procedure is unchanged.

This is phase 3 of `@rules/compound-engineering/general.md` *Tracker status tracks the phase of work*. It runs at exactly one moment: the Review loop converged (`skills/process-code-review/SKILL.md` *Review loop* step 4 — zero Critical, zero unfulfilled reviewer comments, no undeferred Moderate), and the merge has not happened yet. The implementing agent never observes convergence, so this write belongs here, beside the Draft → ready promotion, and never to the resolving run.

The write is unconditional, idempotent, and verified — the same apply-then-verify discipline the phase-1 and phase-2 writes use. A zero exit code is not evidence: an external write can be silently blocked in auto-mode.

### GitHub-specific write
1. **Create the label when the repository lacks it**, then ignore the "already exists" outcome on every later run: `gh label create "ready to merge" --description "The code review for this issue converged; the PR is waiting to be merged" --color 1d76db`. This mirrors the `ready for review` label creation in `@skills/resolve-issue/references/tracker-follow-up.md`.
2. **Apply it to the source issue:** `gh issue edit <N> --add-label "ready to merge"`.
3. **Re-read and verify the label landed** via `skills/code-review-github/scripts/load-issue.sh <URL>`. When it did not land, report the failed phase write in the completion report; the PR stays promoted and is not rolled back.
4. **Leave the `ready for review` label in place.** It is no longer the active signal, and the revert below falls back to it.

### JIRA-specific write
- Run `skills/code-review-jira/scripts/transition-to-ready-to-merge.sh <KEY|URL>`. This is the third sanctioned status transition (`@rules/jira/general.md`); the helper refuses any non-merge target, refuses every resolution name (`Merged`, `Done - merged`) even when it is listed as a synonym, and reports success only after confirming the issue actually reached the column.
- On exit 5 the project names that column differently and it could not be auto-resolved: discover the real name via the JIRA MCP server's available-transitions and re-run with it as the `STATUS` argument, or ask a human. A discovered name that turns out to be a resolution column is refused with exit 1 — that board has no ready-to-merge column, so leave the status alone and say so in the completion report. Perform no other status transition; all others remain human-only.

### Bugsnag-specific write
- There is none. Bugsnag's `status` field is a resolution enum (`open` / `fixed` / `ignored` / `snoozed`) carrying no ready-to-merge value, so no status write exists to make — the same documented limitation the phase-1 and phase-2 writes already carry. The substitute signal is the comment on the error and its mirror on the linked GitHub issue in `linkedIssues[]`.

### No source tracker item — explicit no-op
- A branch that resolves no tracker issue (a task the user described directly) has nothing to write a status on. Skip the issue-side write, state the skip in the completion report, and promote the PR exactly as above. This is not a failure and not a partial success; the PR's own half of the signal is unaffected.

### Revert when the review re-opens
A commit landing after the promotion can re-open the review (*Finalization* — **A behaviour-changing gate fix re-opens the review**). Phase 3 then states something untrue, so withdraw it symmetrically with how it was written, and only for the halves that were actually written:

1. `gh pr ready --undo <PR-NUMBER|URL>` returns the PR to Draft when it had already been promoted.
2. `gh issue edit <N> --remove-label "ready to merge"` removes the GitHub signal. The still-present `ready for review` label is again the active phase-2 signal, which is what is true — the work waits on a reviewer.
3. `skills/code-review-jira/scripts/transition-to-code-review.sh <KEY|URL>` moves JIRA back to the review column. That is the **existing** second sanctioned transition, so the revert direction needs no new capability.
4. Verify each withdrawal by re-reading through the deterministic loader, exactly as the write was verified. When a withdrawal does not land — a write silently blocked in auto-mode, or exit 5 because the review column is not reachable from the ready-to-merge column — report the stale phase-3 signal in the completion report and never report convergence. The tracker then still claims *ready to merge* over a re-opened review, so a human has to reset it. The PR stays in Draft either way.

A fix commit carrying only the verbatim output of the project's fixers re-opens nothing, so it never triggers this revert — the converged verdict stands and the signal stays.

**The detector is not always the owner.** The role that notices that the effective PR diff fingerprint changed may sit outside this skill (typically the implementing agent, during the pre-merge quality gate). It reports the staleness; it does not write or withdraw the phase-3 signal itself. A content-identical history rewrite preserves the signal and starts no CR round. A genuinely changed diff runs review again, and that fresh run either re-writes the signal idempotently or leaves it withdrawn.
