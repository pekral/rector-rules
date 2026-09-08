---
name: code-review-jira
description: Use when run code review for JIRA issues and publish results to
  GitHub PR and JIRA
license: MIT
metadata:
  author: Petr Král (pekral.cz)
---

## Constraints
- Apply the shared CR tracker-wrapper contract in `@skills/code-review-github/references/cr-wrapper-contract.md` — Constraints, Load Context gates, Run Reviews, Publish Results, and Output Rules all live there and are not restated here. This file carries only what a JIRA-sourced review decides for itself.
- Apply @rules/jira/general.md
- Publishing is limited to PR / linked-issue comments via `gh` and to JIRA ticket comments via `acli`.
- The JIRA comment carries **only how to test the change**, plus — when they exist — clarifying questions, assignment discrepancies, and Critical items. Nothing else. The publisher converts the constrained template source to ADF and applies it through `--body-adf`.

---

## Scope
Perform code review for JIRA issues by analyzing related pull requests and publishing results to:
- GitHub (technical findings)
- JIRA (human-readable summary)

---

## Execution

### 1. Load Context
- Load JIRA context by running `skills/code-review-jira/scripts/load-issue.sh <KEY|URL>`. The script accepts a bare key (`ACME-1234`), a `/browse/<KEY>` URL, or any URL containing `?selectedIssue=<KEY>`. Read issue header, description, comments, attachments, subtasks, issue links, custom fields, `devSummary`, and `pullRequests` off the resulting JSON document.
- The context-brief and comment-array helpers are `skills/code-review-jira/scripts/gather-issue-context.sh <KEY|URL>` and `skills/code-review-jira/scripts/parse-comments.sh <KEY|URL>`. The brief renders the issue plus its comments, attachments, recursively-loaded linked issues, and an inventory of external URLs. `acli` cannot download attachments, so their content is read with your own tools.
- Prefer the JIRA MCP fallback for the data the scripts cannot cover: changelog (`expand=changelog`), available next transitions, and friendly custom-field names (`expand=names`).
- Identify all open PRs linked to the issue from the script's `pullRequests` array.
- **Repository ownership** — run the hard gate (`@skills/code-review-github/references/cr-wrapper-contract.md` *Repository ownership*) **per linked PR, after the `pullRequests` array is known and before that PR is checked out**. A JIRA project can carry links to PRs across several repositories, so this is where a cross-repo review silently starts — and it is why this wrapper skips a mismatching PR and continues with the rest instead of stopping the run.

#### Issue Context Analysis
The assignment is the **JIRA issue**. Fetch it complete — description, all comments, and all attachments (screenshots, files, embedded data) — and run the four analysis steps in `@skills/code-review-github/references/cr-wrapper-contract.md` *Issue Context Analysis* against it.

#### Incremental review scope — where the round history lives
The baseline still resolves from the **GitHub PR's** CR comments (`@skills/code-review-github/references/cr-wrapper-contract.md` *Incremental review scope*) — JIRA carries no reviewed revision. The round markers this wrapper reads as a pointer to that history are the `kolo N` / `round N` markers in the **JIRA description and comments**, and they are resolved **per linked PR**: each PR keeps its own baseline, so a ticket linking several PRs never crosses one PR's revision into another's delta.

### 2. Pre-checks
- `statusCheckRollup[]` for the CI check map comes off the GitHub PR JSON, loaded via `skills/code-review-github/scripts/load-issue.sh <PR-URL>` if it is not already loaded.

### 3. Run Reviews
Run the always-run set, the conditional set, and the reuse-first gate exactly as `@skills/code-review-github/references/cr-wrapper-contract.md` *3. Run Reviews* defines them, for **each** linked PR. Two JIRA-specific riders apply:

- Convert the `## Assignment Compliance` block `@skills/assignment-compliance-check/SKILL.md` returns to the supported JIRA intermediate source before passing it to `pr-summary`, and keep the GitHub-Markdown original for the linked-GitHub-issue mirror. The JIRA helper converts that source to ADF. The block travels on every run with a linked ticket, its affirmative verdict included — a JIRA comment that stays silent when every criterion is met tells the ticket owner nothing (`@rules/code-review/general.md` *Two-Part CR Output* → *The tracker comment carries the same verdict — in all three cases*).
- Every blocking documentation request from the Third-Party API & Service Analysis also becomes a plain-language one-liner in the JIRA *Clarifying questions* block below, so whichever tracker the answerer reads carries the ask.

### 4. Publish Results

#### JIRA (consolidated non-technical comment — fresh comment per CR run)
- Delegate the JIRA comment to `@skills/pr-summary/SKILL.md`: invoke it with the **JIRA** tracker target so it renders `@skills/pr-summary/templates/pr-summary-jira.md` as the intermediate source and publishes real ADF via `skills/code-review-jira/scripts/upsert-comment.sh` (JIRA MCP server fallback on exit code 2/3). No direct JIRA comment write may bypass the helper.
- The JIRA comment carries the **same structure `pr-summary` renders on every target** — `What changed` (Problem / Cause / Result / What I fixed, plus the two conditional fields), then `How to test`, then the closing links line — as rendered ADF. There is **no reduced JIRA shape**: the report carries no `Authors` line and no `Available behind` line on any target, so JIRA has nothing left to omit. State this rather than assuming it, because JIRA did receive a reduced shape until this contract changed.
- On top of that structure, the embedded blocks are passed together in one invocation — *Clarifying questions* first (conditional: only when a question survives the gate below), then *Assignment Compliance* (always, on every run with a linked ticket). Still no severity counts and no file paths: the JIRA comment stays non-technical. Test-parameter gating lives inside the **first `How to test` step**, which enables the toggle before the tester proceeds.
- **Clarifying questions block (conditional).** While running the sub-reviews, collect every **genuine open question** the reviewer needs answered before the work can be accepted — an ambiguity in the assignment that the issue description, comments, and code could not resolve (a missing acceptance criterion, an undefined edge case, a value the assignment never specified, a contradiction between the ticket and a comment). Then put every candidate through the **severity gate** and the **already-answered walk** below, in that order, and assemble the block only from what survives both. When at least one question survives, assemble a `h2.
Clarifying questions` block in the supported JIRA intermediate source (one `*` bullet per question, each a single plain-language sentence) and pass it as an embedded block to `pr-summary` so it renders after `How to test`. When none survives, pass nothing — never emit an empty "no questions" block, and never a "previously answered" note. Do not invent questions to fill the section; ask only what genuinely blocks acceptance. **Every blocking documentation request** produced by the Third-Party API & Service Analysis step 7 is such a question and must appear here as one bullet, phrased so a non-developer can forward it:
the vendor / service name, the version in use (or that it could not be determined), and the ask for a documentation link covering the reviewed operations. Keep the endpoint / SDK-method list itself on the GitHub PR comment — JIRA carries no technical detail per the constraint above.
- **Severity gate and already-answered walk (issue #208).** Emit only **Critical** questions (without the answer the change cannot be accepted) and **Moderate** ones (the change ships either way, but the answer decides whether the implemented behaviour is the intended one); **Minor** questions are dropped, never asked. Then walk every comment step 1 already loaded and drop each question the tracker has already answered **and** the diff already implements. Severity is never rendered — the block carries plain sentences in Critical-before-Moderate order. The full gate, the sources walked, the answered-but-not-implemented case, and the ambiguous-answer rule live in `references/clarifying-questions.md`.
- **ADF source conversion.** Convert an embedded Markdown block to the supported source per @rules/jira/general.md (`## ` → `h2. `, `**bold**` → `*bold*`, `` `code` `` → `{{code}}`, `- ` → `* `, Markdown link `[label]` + `(url)` → `[label|url]`) before passing it. Verify the source contains no leaked Markdown. The canonical helper performs the only conversion to ADF and the only `acli` write; never post the source directly.

#### Linked GitHub issues (consolidated mirror — always-new comment per CR run)
- The JIRA-side summary is the **primary** tracker comment; the linked-GitHub-issue comment is a courtesy mirror so reviewers reading the GitHub issue see the same *"What changed + How to test + Assignment Compliance"* output without opening JIRA. Both come from `pr-summary`, so they are guaranteed to match. Publish it per `@skills/code-review-github/references/cr-wrapper-contract.md` *Linked GitHub issues*, passing the GitHub-Markdown version of any embedded block.
- If `closingIssues[]` is empty, note `no linked GitHub issue — mirror skipped` in the PR comment summary line.

---

## Output Rules

### GitHub (technical report — only here)

Apply `@skills/code-review-github/references/cr-wrapper-contract.md` *Output Rules — GitHub PR comment*, and use the template defined in `templates/github-output.md`. The JIRA-specific slots it leaves open:

- The header block's tracker-mirror field is `Linked-tracker mirror`.
- The summary line's tracker-mirror status is `posted JIRA summary on <KEY> (+ mirrored to GitHub issue #N)`, `JIRA only — no linked GitHub issue`, or `failed: <reason>`.

### JIRA (non-technical summary — only here)
- The non-technical JIRA comment is **produced and posted by `@skills/pr-summary/SKILL.md`**, not by this skill. Do not author or embed a custom template here.
- It carries no severity counts, no file paths, no line numbers, no code snippets — plain language understandable by non-developers. Its two sections are `What changed` and `How to test`; `pr-summary` owns both, and this skill neither authors nor reduces them.
- The intermediate source constructs (`h2.` / `h3.` headings, `*bold*`, `_italic_`, `{{inline}}`, `{code:php} ... {code}`, `*` / `#` bullets, `[label|url]`, `{quote}`) come from `@skills/pr-summary/templates/pr-summary-jira.md`. The helper converts them to ADF nodes and marks per @rules/jira/general.md.

## References

- @skills/code-review-github/references/cr-wrapper-contract.md
- references/clarifying-questions.md

## Output Humanization
- Use [blader/humanizer](https://github.com/blader/humanizer) for all skill outputs to keep the text natural and human-friendly.
