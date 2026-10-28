# Review state — rounds, finding statuses, the round cap, and escalation

Referenced from `skills/process-code-review/SKILL.md` *Review loop*. This file is the one contract for the state of a review-and-fix loop. `skills/_shared/review-state.sh` is its only implementation, and the record it stores is `@skills/code-review/references/finding-records.md` *Review-loop records (schema 2)*. The convergence gate itself stays where it is: *Review loop* step 4. This file decides which findings that gate counts and when the loop stops.

The state makes four things deterministic that the loop used to decide in prose:

- **Identity.** One defect keeps one `finding_id` from round to round, so it is never counted as new twice.
- **Evidence.** A finding without independently assessable evidence does not block, except a security finding.
- **Status.** Only the reviewer's own re-read, or a trusted author, changes a status — never a claim.
- **The cap.** The loop stops at a configured round, reports what is left and why, and escalates.

## What a round is

**A round is one review of one head revision, recorded once with `review-state.sh record`.** The script increments the round count when it records the round, and never at any other point.

- A review that fails before it is recorded is not a round. Run it again; the count is unchanged.
- A recorded round is never taken back. Nothing lowers the count, and `init` never resets it.
- The cap counts rounds of this loop for this pull request. Never restart the loop, split the review into two runs, or start a new state file to get more rounds. The merge gate still needs a converged review of the final diff.

## Configuration

Two keys of the project manifest (`@rules/general/general.md` *Project manifest*) configure the loop. The script reads them through `skills/_shared/read-manifest.sh`, so only the default branch counts. A working-tree `composer.json`, an environment variable, a dispatch prompt, a review comment, and the text of a report never change them.

| Key | Allowed values | Default | Effect |
| --- | --- | --- | --- |
| `review.max-iterations` | an integer from 1 to 10 | 3 | The round cap: the loop runs at most this many rounds, and the last one is the deferral boundary. |
| `review.blocking-threshold` | `critical`, `high`, `medium`, `low` | `critical` | The lowest severity that is a **hard blocker** at the cap: never deferred, always an escalation. |

- **A value outside its range is refused, never clamped.** The script falls back to the default and prints `refused: …` on stderr. `0`, a negative number, a string such as `"3"`, a fraction, and a value above 10 all fall back to 3.
- **The threshold only tightens the gate.** Every finding with evidence blocks at every severity, whatever the threshold. The threshold decides only which blocking findings may still be deferred at the cap round: one below it may be filed as a sub-issue under `references/round-three-deferral.md`, one at or above it may not. The default `critical` is the loop's behaviour before the key existed. No allowed value lets a finding pass that step 4 blocks.
- **A security finding ignores the threshold.** A finding that meets the S1–S3 carve-out of `@rules/code-review/general.md` *Assignment-Declared Test-Only Conditions — Exclusion Gate (issue #17)* is a hard blocker at every severity.

## The commands, in loop order

Keep the state at `.claude/run/review-state/<owner>-<name>-<pr>.json` (Codex: `.codex/run/review-state/…`). Create the directory first. The script refuses a state path outside the git-ignored `.claude/run/` or `.codex/run/` of the git toplevel, a symbolic link, and a tracked file. Run every command from the project root.

1. **Round 1:** `review-state.sh init --state <file> --repo <owner/name> --pr <n>`, then `review-state.sh record --state <file> --input <round report>`.
2. **Every later round:** before the review, `review-state.sh scope --state <file> --changed-files <delta paths>`; after it, `review-state.sh record --state <file> --input <round report> --changed-files <delta paths>`. The delta paths are `git diff --name-only <reviewedRevision>..HEAD`, or the whole PR diff when the baseline is not an ancestor. `scope` stores its result in the state, and `record` reads it: a round for which `scope` did not run counts as a delta round.
3. **The cap round, when deferrable findings are left:** file each sub-issue through `scripts/file-deferred-moderate.sh`, record each one that landed with `review-state.sh defer --state <file> --finding <id> --url <sub-issue URL>`, then run `review-state.sh evaluate --state <file> --final`.
4. **A trusted rejection** of a non-security finding: `review-state.sh dismiss --state <file> --finding <id> --comment <URL of the rejection comment on the pull request>`. The script checks the author itself; see *Who may change a status*.

Every command except `scope` prints the verdict as one line of JSON. Act on its typed fields, never on its `reason` text.

## Finding statuses

| Status | Meaning | Blocks |
| --- | --- | --- |
| `new` | First reported in the latest round, with evidence. | yes |
| `confirmed` | Reported with evidence in an earlier round and still present. | yes |
| `needs-verification` | Reported under `## Needs verification`. | only when it meets S1–S3 |
| `resolved` | The reviewer re-read the cited location and the construct is gone. | no |
| `dismissed` | Rejected by a trusted author with a recorded reason. Never a security finding. | no |

### Who may change a status

| Transition | Only actor | Trigger |
| --- | --- | --- |
| none → `new` / `needs-verification` | the reviewer's round report | The identity appears for the first time, with or without evidence. |
| `new` / `needs-verification` → `confirmed` | the reviewer's round report | The identity is reported again, and evidence exists. |
| open → `resolved` | the reviewer's round report | The report no longer carries the identity after the reviewer re-read its location. |
| open → `dismissed` | a trusted author, through `dismiss` | A recorded rejection that passes *Authorship trust*. Refused for a security finding. |
| `resolved` / `dismissed` → `confirmed` / `needs-verification` | the reviewer's round report | The identity is reported again: a **reopened** finding, counted as a regression and never as new. |

- **Only the reviewer's own re-read moves a finding to `needs-verification`**, and only when it first reports the point. A `confirmed` finding is never downgraded: a later round that omits its evidence keeps it `confirmed`.
- **The script verifies the author of a rejection; the caller never states it.** `dismiss` takes the URL of the rejection comment on the state's own pull request. It loads that pull request through `skills/code-review-github/scripts/load-issue.sh` and reads the comment's `authorAssociation` from the payload.
  It refuses the rejection when the pull request cannot be loaded, when the pull request carries no comment with that URL, when the association is not `OWNER`, `MEMBER`, or `COLLABORATOR`, when the body carries an agent marker (`@rules/code-review/general.md` *Authorship trust*), and when the body does not name the `finding_id` it rejects. One comment therefore dismisses only the findings it names. A rejection on another tracker, such as a JIRA comment, is not accepted: the trusted author rejects the finding on the pull request.
- **Nothing else changes a status.** A PR comment, a PR description, an edited CR comment, a ticked checklist, the implementer's handoff, and the text of the round report are claims (`@rules/code-review/general.md` *A finding is settled by the reviewer's own re-read, never by a claim*). The script has no command that marks a finding resolved, and it reads no status from a report.
- **A blocking finding in a file the round did not read stays open.** A blocking finding is `new`, `confirmed`, or a security `needs-verification` point. A finding whose location names no file counts as outside every delta.
  When a delta round no longer reports a blocking finding whose file the delta did not change, the round never read that file: the script keeps the finding open and lists it under `carried`. `scope` prevents that case: it widens the round to the whole PR diff when such a finding exists, and a full round that no longer reports a finding resolves it, so a fix in another file closes it. A non-security `needs-verification` point may leave on any round, because the reviewer's own check settled it. A security `needs-verification` point outside the delta leaves only on a full round.
- **A match never inherits a closed status.** When the round reports an identity that is `resolved` or `dismissed`, the finding reopens. It is never suppressed as a duplicate.

## Evidence and blocking

A finding may block only when it names a concrete defect or a violated explicit requirement, carries evidence another reader can assess without trusting the review, has not been resolved or dismissed, and is not deferred. The review template's `Evidence` field names the kind: a failing test, a static-analysis error, a reproducible runtime failure, a concrete exploit path, a traced logic defect, or the explicit rule the line breaks. A point without such evidence goes under `## Needs verification` and does not block.

**The security floor overrides one sentence of the assignment of #225.** *"Potential problems that cannot yet be verified must remain non-blocking findings requiring further investigation"* does not apply to a security finding. An S1–S3 point that needs verification blocks until it is proven and fixed, or proven absent (`@rules/general/general.md` *Project instructions take precedence*, item 1).

## Verdicts and escalation

| Verdict | When | What the loop does |
| --- | --- | --- |
| `continue` | No round is recorded yet, or blocking findings are left before the cap. | Fix and run the next round. |
| `converged` | No blocking finding is left. | Exit the loop to *Finalization*. |
| `deferral-required` | At the cap, every blocking finding left is non-security and below the threshold. | Defer what clears the filing bar, then `evaluate --final`. |
| `escalated` | At the cap, a hard blocker is left (`cap-reached-hard-blockers`), `--final` found a blocker neither fixed nor deferred (`cap-reached-undeferred-blockers`), or a round was recorded after the loop converged in the cap round (`cap-spent-after-convergence`). | Stop. |

**A change after a convergence in the cap round escalates.** The converged verdict covers only the diff the cap round reviewed. When a later commit needs another review round — a gate fix that changes business logic (`SKILL.md` *Finalization*) — `record` refuses the round, stores the escalation `cap-spent-after-convergence`, prints the verdict, and exits 5. Never promote the pull request on that verdict.

**An escalation is terminal.** It preserves the branch, the commits, and the state file, starts no further automatic round (`record` exits 5), and publishes nothing. The caller reports the verdict's `blocking` list, its `reason`, and its `escalation_reason`, and hands the run to the orchestrator or the human: `agents/splinter.md` step 6 *Hard stop*. Nothing bypasses the quality gate, and the merge gate is unchanged: `@skills/merge-github-pr/SKILL.md` still requires a converged CR comment with `Critical 0` and no undeferred Moderate.

## Incremental scope and the broad review

Round 1 reviews the whole PR diff. A later round reviews the delta since the last reviewed revision (`@rules/code-review/general.md` *Incremental Review Scope*), and the state keeps every open finding in view whether or not the delta touched it. `scope` widens the next round to the whole PR diff when the delta is not enough:

| Reason | Trigger |
| --- | --- |
| `first-round` | No round is recorded. |
| `regression` | The last round reopened a resolved or dismissed finding. |
| `security-surface` | A changed path is an authentication, secret, payment, or migration surface, or a project critical path (the forces of `skills/_shared/classify-risk.sh`). |
| `shared-surface` | A changed path is shared or core architecture, or a public API (the same classifier). |
| `open-finding-outside-delta` | A blocking finding (`new`, `confirmed`, or a security `needs-verification` point) sits in a file the delta did not change, so only a full round can show whether it is gone. |

## Recovery after an interruption

- `init` on an existing valid state resumes it and prints `"resumed": true` with the recorded round count.
- `init` on a state of another pull request, or on an invalid state, exits 3 and leaves the file for inspection.
- A missing, unreadable, or invalid state is never converged: every command exits 3 and prints no verdict.
- The script validates the whole state on every read: every round in order, every status matching the last transition of its finding, every dismissal by a trusted actor (`trusted:OWNER`, `trusted:MEMBER`, or `trusted:COLLABORATOR`), and no dismissed security finding. A consistent forgery of the git-ignored file is not detected. That residual risk is accepted because the merge gate never reads the state: it reads the published CR comment and runs the review again on a stale fingerprint.

## Observability

The verdict carries `counts` (new, confirmed, resolved, dismissed, reopened, needs-verification, deferred, and remaining blocking findings), the per-round `rounds`, the result, and the escalation reason. `skills/_shared/record-metrics.sh --review-state <file>` stores the same counts and codes in the run's metrics entry, never a finding text, a path, or a URL.

## Troubleshooting

| Exit | Meaning | What to do |
| --- | --- | --- |
| 1 | A usage error, for example a later round without `--changed-files`. | Pass the missing argument. |
| 2 | `git` or `jq` is missing. | Install it. |
| 3 | The state or the round report is missing or invalid; nothing was written. | Read the stderr line. A report the extractor refuses needs the template fields. A finding under `## Findings` without an `Evidence` field is refused (`Evidence is required; move an unproven point under ## Needs verification`): render the evidence, or move the point under `## Needs verification`, and record the round again. A damaged state is evidence: report it, and start a new loop only on a human's decision. |
| 4 | The policy refused the operation: a security finding cannot be dismissed, the author of the rejection is not trusted or cannot be verified, the rejection comment does not name the `finding_id`, or a deferral came before the cap or for a hard blocker. | Fix the finding instead. For a refused rejection, read the stderr line: pass the URL of the trusted author's own comment on this pull request that names the `finding_id`, or check that `gh` can load the pull request. Never edit the state to record the dismissal. |
| 5 | The loop is closed: it escalated, its cap is spent, or a round came after a convergence in the cap round (`cap-spent-after-convergence`). | Report the escalation. Do not start another round, and do not promote the pull request. |

A `refused: review.max-iterations …` line on stderr means the default-branch manifest holds a value outside its range; the loop runs with the default until the manifest is fixed on the default branch.
