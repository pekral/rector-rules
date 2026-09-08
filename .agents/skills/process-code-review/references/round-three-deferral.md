# Round-3 deferral boundary

Referenced from `skills/process-code-review/SKILL.md` *Review loop* step 6. Extracted to keep the skill body under the skill-check token limit; the procedure is the skill's, stated once here.

Round 3 is the loop's last review. It is a **deferral boundary**, not a failure line: what remains is triaged into one of three outcomes rather than iterating a fourth time. The point is a review that converges in a bounded number of rounds without lowering the bar of anything that merges — every outcome below is either a fix, a recorded tracker item, or a hard stop.

## Resolution table — every remaining finding lands in exactly one row

| Remaining finding at round 3 | Outcome | Effect on the convergence gate |
|---|---|---|
| **Critical** (including every not-fulfilled reviewer instruction, which the fulfillment gate already raises as Critical) | **Hard stop.** Surface the findings, escalate to the user. Never filed as a sub-issue. | Blocks. The run does not converge, the PR stays a Draft, and nothing is published. |
| **Moderate meeting the S1–S3 security carve-out** (`@rules/code-review/general.md` *Assignment-Declared Test-Only Conditions — Exclusion Gate (issue #17)*: produced by a security lens, citing a rule in `@rules/security/**`, or landing on a security surface) | **Hard stop**, identical to a Critical. Never deferred, never filed as a sub-issue. | Blocks. |
| **Moderate, non-security, passing the filing bar** | **Deferred** — filed as a sub-issue of the source tracker item and recorded in the published report. | Does not block. The finding is resolved for this PR by being scheduled, not by being forgotten. |
| **Moderate, non-security, already recorded in an open tracker issue** | **Deferred by linking** that existing issue instead of creating a duplicate, per *Deduplicate before filing* in the filing-bar rule. | Does not block. |
| **Moderate, non-security, failing the filing bar** | **Blocking.** | Blocks. See *A Moderate that satisfies neither criterion* below. |
| **Minor** | Not detected and not reported at all (`@rules/code-review/general.md` *Minor findings are not detected*). | Never reaches this table. |

## The filing bar is cross-referenced, never restated

Whether a non-security Moderate may be deferred is decided by the bar that already exists: `@rules/compound-engineering/general.md` *File deferred points as follow-up tracker issues* → *The filing bar*. It states the three conditions that make an item worth filing and the list that is never filed (cosmetic or wording-only proposals, naming preferences, a refactoring idea with no named consequence, nice-to-have work, an observation carrying no concrete step, a mirror issue). Read the bar there and apply it verbatim.

The user's own framing of this change — *"do not file issues for refactorings and things that do not block further business growth"* — **is** that bar. A second copy of it here would be a second source of truth to drift from.

## A Moderate that satisfies neither criterion still blocks

A round-3 Moderate can fail the filing bar while also not being security-relevant — a genuine architectural debt item with a named consequence that the bar nonetheless routes elsewhere, or an item whose deferral would only produce backlog noise. **It blocks.** The run does not converge, and the finding is surfaced to the user exactly like a Critical.

This is deliberate. The filing bar exists to keep noise out of the backlog, never to create a silent bypass: an item that is not important enough to file and not fixed in the loop would otherwise vanish between the two criteria, and the PR would merge carrying a Moderate nobody ever sees again. Exactly one of *deferred* or *blocking* always applies to every non-security Moderate, and a run that cannot decide which treats the finding as blocking.

## Filing mechanics per tracker

Use `scripts/file-deferred-moderate.sh <PARENT> <TITLE> <BODY-FILE|-> [<LABEL>]`, once per deferred finding. It resolves the tracker from the parent reference, performs the write, and re-reads the result to prove it landed — an external write can be silently blocked in auto-mode, so a zero exit code is not evidence. `DRY_RUN=1` runs every read and validation and prints the write commands without writing.

- **The sub-issue body carries the finding verbatim** — `file:line`, severity, Impact, Faulty Example, Expected Behavior, Test Hint, and Suggested Fix — plus a link back to the PR and the source issue. Do not rewrite or shrink the finding (`@skills/create-issue/SKILL.md` owns the create-without-rewriting convention); the next agent must be able to act on it without re-deriving context.
- **Apply one content label** per `@rules/compound-engineering/general.md` *Label newly created tracker issues*. Selecting it is a semantic judgment the caller makes from the repository's existing labels; the script only applies the label it is given, and no label is a permitted outcome.
- **GitHub — the native sub-issue relation, under any parent.** The script creates the issue and attaches it with the GraphQL `addSubIssue` mutation. **The parent needs no `EPIC` label.** `AddSubIssueInput` takes only `issueId` and `subIssueId` (plus optional `subIssueUrl` / `replaceParent`), and a probe against a parent carrying the label `bug` resolved that parent and failed only on the child id. The `EPIC` label in `@skills/create-issues-from-text/SKILL.md` *EPIC parent & sub-issues* is that skill's own breakdown convention, not a GitHub requirement, and this path does not adopt it — a source issue is not an epic just because one finding was deferred out of it.
- **JIRA — the native subtask.** `acli jira workitem create --parent <KEY>` (`--parent  Parent work item ID`, confirmed against `acli`'s own `--help`). The subtask type name is project-configurable, so it is read from `$JIRA_SUBTASK_TYPE` and defaults to `Subtask`; a project that names it differently re-runs with that name. Creating a work item is not a status transition, so `@rules/jira/general.md`'s human-only rule is untouched.
- **Bugsnag — no sub-issue concept, stated as a limitation.** A Bugsnag error has no child relation of any kind. The equivalent is a GitHub issue filed in the repository of the error's linked issue (`linkedIssues[]`), which is exactly the precedent *File deferred points as follow-up tracker issues* already sets for a Bugsnag-originated deferral. The script refuses a Bugsnag URL with exit 1 and names that linked issue as the parent to pass instead. When the error has no linked issue, there is no parent and therefore no sub-issue: the finding stays **blocking**, because deferral without a tracker record is the silent bypass this whole section exists to prevent.

## Reporting the deferral

- Every deferred finding appears in the published review and in the `cr-status` comment as a **deferred** entry carrying the created sub-issue URL — never as a resolved finding and never silently dropped. A reader must be able to tell a fix from a deferral at a glance.
- The `Counts:` line keeps the **real** detected numbers, per `@rules/code-review/review-process.md` *Output Rules — Truthful reporting (issue #74)*. A deferred Moderate was detected; the report says so and says where it went.
- **A deferral that did not land is not a deferral.** When the script exits non-zero — creation blocked, the relation unverified, no parent available — the finding reverts to **blocking** and the run does not converge. Report the failed write rather than assuming it.
