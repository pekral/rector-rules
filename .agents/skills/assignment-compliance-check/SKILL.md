---
name: assignment-compliance-check
description: "Use when checking that the pull request implementation actually fulfills the business requirements stated in the linked issue or task. Returns a plain-language Assignment Compliance markdown block on every run that has a linked tracker, always carrying one of three verdicts: every acceptance criterion is met, a named criterion is not met and what is missing, or the assignment states no explicit criteria plus the basis the state was judged on. Only a run with no linked tracker returns a skip status. The block carries no file paths, line numbers, or code snippets, and it is embedded in the consolidated tracker comment, never in the GitHub PR comment. No local file is created."
license: MIT
metadata:
  author: "Petr Král (pekral.cz)"
---

## Constraints
- Apply `@rules/php/core-standards.md`
- Apply `@rules/git/general.md`
- Apply `@rules/jira/general.md`
- Apply `@rules/reports/general.md` — the **Assignment Compliance** markdown block this skill returns to the caller must be written in the language of the linked assignment (Czech issue / JIRA description → Czech block; English → English). Linked-task / PR URLs, author handles, and severity labels follow the rule's *Scope clarifications*.
- The skill **must not** write any output to disk. It also **must not** publish anywhere itself — no `gh issue comment`, no `acli`, no JIRA / GitHub MCP write call. The skill returns the assembled markdown block to the calling CR wrapper on every run that has a linked tracker, and the status `no linked issue — assignment compliance skipped` only when no linked tracker is detected. The wrapper embeds the block into the **single consolidated linked-tracker comment** authored by `@skills/pr-summary/SKILL.md` (one comment per linked issue / JIRA ticket per CR run — see issue #498); on the skip status there is no tracker comment to embed into and the wrapper surfaces the status only on the PR comment summary line.
- The block **must not** be embedded into the GitHub PR comment produced by `@skills/code-review/SKILL.md`, `@skills/code-review-github/SKILL.md`, or `@skills/code-review-jira/SKILL.md`. The PR comment carries technical findings; the linked-tracker comment carries assignment compliance as part of the consolidated `pr-summary` output.
- The published block must be plain language understandable by a non-technical reader. Include a short example for every Critical gap. **Do not list satisfied requirements one by one, do not add a "what is working" list, and do not ask the reviewer open questions** — a met assignment is reported as the single verdict sentence of case 1 below, never as a checklist.
- **The block always carries a verdict, including the affirmative one** (`@rules/code-review/general.md` *Two-Part CR Output* → *The tracker comment carries the same verdict — in all three cases*). The tracker is the surface the person who owns the ticket reads; a silent comment makes "every criterion is met" and "nobody checked" look identical to them. The three verdicts are defined in **Output Format** below and exactly one of them renders per run.
- The returned block carries **no `Authors` line and no `Available behind` line**. Both lines were dropped from `@skills/pr-summary/SKILL.md` when that skill narrowed to `What changed` + `How to test`; it resolves no authorship now and renders neither line. This skill does not take either over: no other source resolves them for the block, and the block needs neither — it carries a verdict and, when the verdict is case 2, the gaps behind it.
- Report **only Critical** functional / business-logic gaps under the verdict. Do not report architecture, code style, test coverage, refactoring opportunities, or any other concern — those are owned by the other review skills.
- Never modify code. This skill is read-only with respect to the codebase.
- Do not expose secrets, internal infrastructure paths, or PII in the comment.

## Use when
- A code review is being prepared for a PR linked to an issue or task (GitHub issue, JIRA ticket, Bugsnag report).
- A reviewer wants a focused "did the implementation do what the assignment asked for" check, separate from architecture / security / refactoring lenses.
- This skill is **invoked from every CR run** by `@skills/code-review/SKILL.md`, `@skills/code-review-github/SKILL.md`, and `@skills/code-review-jira/SKILL.md`.

## Required approach

### 1. Load the assignment
- Detect the originating tracker from the PR description / linked issue.
- **GitHub-originated:** run `skills/code-review-github/scripts/load-issue.sh <URL>` against the linked issue — always the full GitHub URL, never a bare number (the loader rejects it). Read the full `body`, every entry in `comments[]` (including replies), and every referenced attachment URL.
- **JIRA-originated:** run `skills/code-review-jira/scripts/load-issue.sh <KEY|URL>`. Read `descriptionText`, `comments[]`, and any attachment metadata.
- **Bugsnag-originated:** run `skills/code-review-bugsnag/scripts/load-issue.sh <URL|TRIPLE>` (requires `BUGSNAG_TOKEN`) to read the error class, `message`, `context`, and `latestEvent.stacktrace` as the assignment. The error is also mirrored to GitHub via `linkedIssues[]`; load that linked GitHub issue as well to pick up any human-authored acceptance criteria and apply the GitHub branch on top.
- Never call `gh`, `acli`, `api.bugsnag.com`, or REST endpoints directly — always use the deterministic loaders.
- Group comments by thread. Discard outdated or superseded requirements (per the comment-analysis rules in `@skills/resolve-issue/SKILL.md`). Keep only the **current** requirements as the source of truth.

### 2. Extract verifiable requirements
For the assignment + current comments, enumerate:
- **Acceptance criteria** the implementation must satisfy (explicit "must" / "should" / numbered lists / Given-When-Then blocks).
- **Expected behavior** described in plain language (what the user should see / experience / receive).
- **Edge cases** named by the reporter or in comments.
- **Examples** the reporter provided (sample inputs, payloads, screenshots, expected outputs).

Skip generic developer hygiene wishes ("clean code", "tests please"). The check is strictly about business behavior described by the reporter.

### 3. Load the implementation
- Run `skills/code-review-github/scripts/load-issue.sh <PR-URL>` for the PR and read `files[]`, `body`, and `commits[]`.
- For each extracted requirement from step 2, locate the matching change in the diff: the function, controller action, Livewire method, job, command, view, or test that should realize the requirement.
- If a requirement has no corresponding change in the diff, that is itself a Critical gap candidate (see step 4).

### 4. Cross-check requirement vs implementation
For every requirement from step 2, decide one of:
- **Satisfied** — the diff implements the behavior the assignment describes. Not reported individually; it feeds the verdict. When *every* requirement lands here, the run's verdict is case 1.
- **Partially satisfied** — the diff covers part of the requirement (e.g. handles the happy path but ignores an explicitly stated edge case). Report as Critical.
- **Missing** — no code in the diff implements the requirement. Report as Critical.
- **Divergent** — the diff implements behavior that contradicts the requirement (wrong field, wrong status, opposite condition). Report as Critical.

When step 2 produced **no** requirement at all — the assignment names no acceptance criterion, no expected behaviour, no edge case, and no example — the run's verdict is case 3. Do not treat that as a clean result: record which sources were read (description, comments, reproduction steps, attachments) and what the implementation was judged against instead, because that basis is what case 3 must state.

Do **not** report stylistic / architectural / test-coverage concerns even if you notice them — those belong in `@skills/code-review/SKILL.md` and `@skills/security-review/SKILL.md`.

### Real-Code Grounding for Every Finding (issue #97)
Apply the contract in `@rules/code-review/general.md` *Real-Code Grounding for Every Finding (issue #97)* to every gap this skill reports — it reports only Critical gaps, and every one of them, no exception. Run it **before** classifying a requirement as Partially satisfied, Missing, or Divergent above: open the real file the diff hunk belongs to and confirm against its current, full content that the requirement genuinely is not satisfied — the required behavior may live elsewhere in the file or in a helper the diff hunk does not show.

This gate matters most here: this skill is invoked directly by every CR wrapper (`code-review-github`, `code-review-jira`, `code-review-bugsnag`), reads only the diff in step 3, and never passes through `@skills/code-review/SKILL.md`'s own aggregation or Critical Findings Verification (issue #537) — its Critical gaps publish straight to a non-technical tracker audience with no verification layer behind this skill.

### 5. Return the report to the caller

> **Quiet mode (loop iterations from `@skills/process-code-review/SKILL.md`):** the loop iterations call this skill with "do not publish; return findings as in-memory markdown for this loop iteration only" — which is now the **only** mode this skill ever operates in. The skill never publishes anywhere itself; every caller (loop iteration or final consolidating publish) receives the same in-memory return. The loop convergence math still counts Critical gaps from the returned block.

- Build the **Assignment Compliance** markdown block using the template in **Output Format** below on **every** run that has a linked tracker, and render exactly one of its three verdicts. Use GitHub-flavoured Markdown by default; convert to the supported **JIRA intermediate source** per `@rules/jira/general.md` when the calling CR wrapper signals a JIRA tracker target (`h2.` / `h3.` headings, `*bold*`, `_italic_`, `{{inline}}`, `{code:php}…{code}`, `* / # bullets`, `[label|url]`, `{quote}`), and to plain text when it signals a Bugsnag target. The canonical JIRA helper converts that source to ADF before publication.
- **Do not call `gh issue comment`, `acli`, the GitHub MCP server's `add_issue_comment`, or any JIRA write endpoint.** The skill is a pure markdown producer; the calling CR wrapper (`@skills/code-review-github/SKILL.md` / `@skills/code-review-jira/SKILL.md` / `@skills/code-review-bugsnag/SKILL.md`) embeds the returned block into the single consolidated linked-tracker comment authored by `@skills/pr-summary/SKILL.md` (see issue #498 — one comment per linked issue per CR run).
- **When every requirement is satisfied, still return a block** — verdict 1, the single affirmative sentence. This is the case the tracker used to lose entirely, and returning a skip status here is the defect this contract exists to prevent. Do not append a list of satisfied requirements behind that sentence.
- **When the assignment states no explicit acceptance criteria, still return a block** — verdict 3, naming the basis the implementation was judged against instead (step 4). An absent criterion set is a fact the reader needs, not a clean result.
- If no linked tracker exists (`closingIssues[]` empty for GitHub PRs, or no JIRA ticket detected for JIRA-originated), return the status `no linked issue — assignment compliance skipped` instead of a block. That is the only skip status this skill returns: there is no tracker comment to carry a verdict, so the CR wrapper includes the status in its PR comment summary line only.
- The CR wrapper skills (`code-review`, `code-review-github`, `code-review-jira`, `code-review-bugsnag`) **must not** embed the Assignment Compliance content into the **GitHub PR** comment — it belongs in the consolidated linked-tracker comment, never on the PR comment, which carries technical findings only.

## Output Format

> **Render this block on every run that has a linked tracker**, carrying exactly one of the three verdicts below (`@rules/code-review/general.md` *Two-Part CR Output* → *The tracker comment carries the same verdict — in all three cases*). Never return a bare skip status because the result was clean, and never emit a "What is satisfied" list or an "Open questions" list — satisfied requirements and reviewer questions stay out of the block by design.

Assignment Compliance block, embedded in the consolidated tracker comment (Markdown shown; convert to the JIRA intermediate source per `@rules/jira/general.md`, and to plain text for Bugsnag). The header two lines are identical in all three cases:

```markdown
## Assignment Compliance

- **Linked task:** <issue / JIRA / Bugsnag URL>
- **Pull request:** <PR URL>
```

**Verdict 1 — every acceptance criterion is met.** One sentence, nothing behind it:

```markdown
- **Verdict:** All stated acceptance criteria are met.
```

**Verdict 2 — a criterion is not met.** The gap list, one entry per Critical gap:

```markdown
- **Verdict:** Critical gaps found: N

### Critical gaps

#### 1. <short title in everyday language>
- **What the task asked for:** <one sentence quoting or paraphrasing the requirement, with the source comment URL or "issue description">
- **What the pull request does instead:** <one sentence describing the actual behavior implied by the diff>
- **Example a tester would see:** <concrete input → expected output vs actual output, ideally taken from the example the reporter provided; when the change is reachable only behind a test parameter, the example must start by enabling the gating toggle>

(Repeat for every Critical gap.)
```

**Verdict 3 — the assignment states no explicit acceptance criteria.** Say so, then name the basis:

```markdown
- **Verdict:** The assignment states no explicit acceptance criteria.
- **Judged against:** <what the check used instead — the described expected behaviour, the reporter's reproduction steps, the attached example — and the sources read (description, comments, attachments)>
- **Result:** <one sentence: the implementation matches that basis, or the one place where it does not>
```

Translate the verdict sentences and the field labels into the assignment language per `@rules/reports/general.md`; never publish an English verdict above assignment-language prose.

The block carries no file paths, line numbers, or code snippets — the linked-tracker audience is non-technical reviewers and product owners. Technical details belong on the PR.

## Done when
- One of the following was returned to the calling CR wrapper:
  - an **Assignment Compliance** markdown block carrying exactly one of the three verdicts (every run that has a linked tracker, clean result included);
  - the status `no linked issue — assignment compliance skipped` (only when no linked tracker exists).
- The skill itself did **not** publish anywhere — no `gh issue comment`, no `acli`, no GitHub / JIRA MCP write call. Publishing is exclusively the responsibility of the CR wrapper through `@skills/pr-summary/SKILL.md` as the single consolidated linked-tracker comment.
- The GitHub PR comment produced by the calling CR skill does **not** contain an Assignment Compliance section.
- No files were created on disk — neither in the repository nor in any external directory.
- The returned block is plain language, states its verdict explicitly, and includes a short example for every Critical gap under verdict 2.
- Only Critical functional / business-logic gaps are listed under the verdict — no architecture / style / coverage findings, no "what is satisfied" lists, and no "open questions" lists.

## Output Humanization
- Use [blader/humanizer](https://github.com/blader/humanizer) for all skill outputs to keep the text natural and human-friendly.
