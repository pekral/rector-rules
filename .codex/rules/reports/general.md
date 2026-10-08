---
description: Language rule for reports published to issue trackers (GitHub, JIRA, Bugsnag)
paths:
  - ".claude/rules/reports/**"
---

## Tracker-Published Reports — Language

Every report a skill publishes to an issue tracker **must be written in the same language as the source assignment**, and **must never mix that language with another natural language inside the same comment**. When the GitHub issue / JIRA ticket / Bugsnag-linked issue description is in Czech, the published report is fully in Czech; when it is in English, the report is fully in English. Pick the assignment language and stay in it for every prose sentence of the comment — no parenthetical bilingual hints, no half-translated headings, no English boilerplate dropped into a Czech body.

The rule applies to every tracker target and every tracker output:

- non-technical PR / issue / JIRA summaries (`pr-summary`, `assignment-compliance-check`, `tester-cookbook`)
- security-review and security-threat-analysis reports surfaced on the linked issue or non-technical channel
- analyze-problem / resolve-issue reports surfaced on the tracker
- process-code-review mirrored issue summaries
- any other comment posted on a tracker by a skill

### Exception — technical CR findings on the GitHub PR

One narrowly scoped exception: **the technical code-review comment posted on a GitHub pull request stays in canonical English**, regardless of the assignment language. Specifically:

- `@skills/code-review-github/SKILL.md` PR comments (full CR template — Status, Counts, Findings, Coverage, Summary line)
- `@skills/code-review-jira/SKILL.md` GitHub-side PR comments (the technical findings half of its split publish)
- `@skills/code-review/SKILL.md` review markdown — produced for the wrappers above and never published directly, but the output is shaped for the exception channel and therefore stays English at source
- `@skills/process-code-review/SKILL.md` reply comments on the PR (resolved-items follow-up)
- `@skills/security-review/SKILL.md` audit findings when they are folded into the GitHub PR comment
- `@skills/security-threat-analysis/SKILL.md` remediation reports when posted as a PR comment
- `@skills/resolve-issue/SKILL.md` final technical report posted on the PR (code-review / security-review summary block) — same channel as the CR wrappers above

These seven stay in English because they (a) are machine-parsed by `@skills/process-code-review/SKILL.md` for reproducer extraction; (b) carry severity labels (*Critical / Moderate*), structured field labels (*Location*, *Rule*, *Impact*, *Faulty Example*, *Expected Behavior*, *Test Hint*, *Suggested Fix*), and rule references that already exist in English elsewhere in the codebase; (c) live next to code identifiers, error messages, and discussion threads from non-Czech contributors. Translating them creates parsing breakage and cross-language drift without helping the reader.

The exception does **not** extend to the reports below. On GitHub, the manifest override in *Project override — `language.github` in the manifest* below still fixes their language when it is set:

- the non-technical mirror published on the linked GitHub issue (`closingIssues[]`) — that follows the assignment language
- the JIRA-side comment from `code-review-jira` (delegated to `pr-summary`) — that follows the assignment language
- the assignment-compliance comment from `assignment-compliance-check` — that follows the assignment language
- the `pr-summary` comment, regardless of where it is posted — that follows the assignment language. GitHub and Bugsnag carry the same shape: *What changed* (Problem / Cause / Result / What I fixed, plus the conditional *Side benefit* / *Filed separately* fields), then *How to test*, then a closing line linking the PR and the source issue, plus any conditional *Clarifying questions* / *Assignment Compliance* blocks.
JIRA carries its own shape on every run — a status line, *Acceptance criteria*, *Review findings*, *What changed*, *Impact after deployment*, then the same closing line and a footer, with each open question inside the bullet it concerns — and no *How to test*, for the reason *A JIRA comment is written for a non-technical reader* below states (`@skills/pr-summary/SKILL.md` *The JIRA shape*). The section headings and the field labels are part of the report's prose, so they are translated too — a Czech assignment renders *Co se změnilo*, *Jak otestovat*, and *Co může změna ovlivnit po nasazení*, never an English heading above Czech prose.
On GitHub and Bugsnag one exception replaces *How to test*: a review-only run (`/report-code-review`) passes `review-only`, and `pr-summary` renders *Review findings* in its place — a plain-language retelling of the GitHub review that invites the reader's feedback (`@skills/pr-summary/SKILL.md` *Review-only run*).

### Project override — `language.github` in the manifest

A project can fix the language of everything it publishes to GitHub. It sets `language.github` in its manifest (`@rules/general/general.md` *Project manifest*). A run reads the manifest from the default branch through `skills/_shared/read-manifest.sh`, never from the working tree. When the key is set, every report published to GitHub is written in that language, whatever the assignment language is:

- the technical code-review comment on the pull request — the exception above,
- the non-technical mirror on a linked GitHub issue,
- the `pr-summary` comment on GitHub,
- every other comment or description a skill publishes on a GitHub pull request or issue.

Reports on JIRA and Bugsnag keep the assignment language. The key never lets one artifact mix two languages: a GitHub comment is written wholly in the `language.github` language, and a JIRA or Bugsnag comment wholly in the assignment language. The machine-read tokens of the technical CR comment — the header-line keys (`Status:`, `Counts:`, `Reviewed revision:`), the severity labels, and the reproducer field labels — stay as the template writes them. They are identifiers, like code, so keeping them is not mixing. When the key is absent, the rules above apply unchanged.

### How to detect the assignment language
1. Read the issue description and the most recent author-written comment off the deterministic loader (`skills/code-review-github/scripts/load-issue.sh` for GitHub, `skills/code-review-jira/scripts/load-issue.sh` for JIRA). The wording the reporter used there is the canonical signal.
2. When the issue body is empty or contains only a screenshot, fall back to the language of the linked JIRA ticket, the parent epic, or the PR description written by the same reporter.
3. When no signal is available, default to English and state the assumption in the published report's footer.

### Scope clarifications
- **This rule picks the language; `@rules/writing/general.md` shapes the sentences.** Once the language is settled here, the report is written in the simplified technical style that rule mandates — one idea per sentence, active voice, one term per concept — in that language, never only in English. The two rules never override each other: raise one finding per violation, and never a second finding on the same line for the sibling rule.
- **Code identifiers stay verbatim.** Class names, file paths, function names, error codes, enum cases, configuration keys, route paths, and similar machine-readable tokens keep their original form regardless of the surrounding prose language. Do not translate `App\Actions\ProcessPayment` into the assignment language. Quoting a code identifier inside an assignment-language sentence is not "mixing" — code is not a natural language.
- **PR titles and commit messages follow `@rules/git/general.md`** — English, or the manifest's `language.github` when it is set. Branch names are always English. The language-matching rule applies to report bodies posted as comments / descriptions, not to git metadata.
- **In-conversation status, terminal output, and debug logs may stay in English.** Only tracker-facing reports follow the assignment language.
- **No bilingual parentheses.** Do not write *Kritické (Critical)* or *Závažné (Moderate)*. Either the whole comment is the English exception (so use *Critical / Moderate* directly), or the whole comment is in the assignment language (so use the assignment-language equivalent without an English gloss).

### Failure modes to avoid
- Posting a bilingual comment with the assignment language for prose and English in inline parentheses for severity labels or structural keywords.
- Translating the technical CR PR comment to Czech — the exception above keeps it English, unless the manifest sets `language.github` to Czech.
- Translating the non-technical issue / JIRA summary to English when the assignment is in Czech — the exception is narrow and does **not** cover those. Only `language.github` changes the language of the GitHub issue mirror, and nothing changes the JIRA one.
- Posting in the language of the agent's chat session instead of the language of the assignment.
- Switching mid-comment between Czech and English when quoting requirements verbatim — quote the requirement verbatim, then continue in the assignment language without a parenthetical translation.

## A JIRA comment is written for a non-technical reader

The person who reads a JIRA ticket is the person who asked for the work — a product manager, not a developer. A run once published a 10 964 B comment to such a ticket. It carried method names, test file names, the head SHA, the diff fingerprint, the quality-gate result, three CI check statuses, test and assertion counts, and per-line coverage. Rewriting it by hand into what that reader actually needs produced 3 063 B, so 72 % of the published comment was noise for its only audience. This section states what a JIRA comment never carries, what it may always carry, and how long it is.

The section is binding on **every** comment a skill or an agent publishes to a JIRA issue — the `pr-summary` report, the assignment verdict rendered inside it, the merge-readiness TL;DR, and any other. It governs content, never language: *Tracker-Published Reports — Language* above still picks the language, and `@rules/writing/general.md` still shapes the sentences.

### Never in a JIRA comment

- class, method, function, variable, enum, and file names
- file paths and line numbers
- commit SHAs, diff fingerprints, branch names
- quality-gate results, CI status, test / assertion counts, coverage figures
- severity labels, finding counts, rule references
- code blocks, and the names of internal layers (Action, Repository, Data Builder)

An item on this list is **removed, never annotated**. A comment that says *"the head SHA is omitted here"* has still spent the reader's attention on the head SHA.

### Three exceptions, and there is no fourth

1. **A string the end user sees is quoted verbatim.** A button label, a menu item, an error message the tester has to match, a toggle name, a value typed into a field. The tester matches it character by character in the application, so a translation or a paraphrase destroys its purpose. Quoting it is not a technical note; it is the input the step needs.
2. **One pull-request link at the end.** That is navigation, not a technical note, and the tracker must point at the work it describes.
3. **Links to related tracker items and to the product documentation.** A link to a tracker item the reader acts on — the known issue, the duplicate, the follow-up — and a link to an article of the project's customer-facing product documentation (the help centre; the manifest key `product-docs` names it when set). They are navigation, like the pull-request link: the reader opens them to act, never to read code. A link to code, a commit, a CI run, or a log stays banned.

### The technical evidence moves to the pull request; it does not disappear

Nothing on the banned list is lost. Every one of those facts belongs on the **pull-request comment**, which is where `@skills/merge-github-pr/SKILL.md` reads it: the head SHA, the effective diff fingerprint, the quality-gate command and its verdict, the CI statuses, the coverage figures, the finding counts, and the severity labels. That comment is the merge gate's evidence and the reviewer's report. This section moves that content to the surface that consumes it. It never deletes it, and it is never a reason to stop producing it. Read this section as a loss of information and the next agent works around it in good faith.

### Length — 3 000 characters

A JIRA comment fits within **3 000 characters**, counted over the published body. When it overflows, shorten *What changed* first, then merge *Impact after deployment* bullets. **Never drop an *Acceptance criteria* bullet or a *Review findings* bullet**: those are what the reader decides on. A JIRA comment carries no *How to test*; the steps a tester follows live on the GitHub pull request, whose description carries them and has no length cap.

### Boundary — this section and the GitHub-PR English exception never fire on the same comment

*Exception — technical CR findings on the GitHub PR* above keeps the technical code-review comment in canonical English. That exception is scoped to a comment published **on a GitHub pull request**. This section is scoped to a comment published **on a JIRA issue**. The two destinations are disjoint, so no comment is ever governed by both — and the technical content the exception protects is exactly the content this section redirects to that same GitHub PR comment. A JIRA-sourced code review already splits along that line: `@skills/code-review-jira/SKILL.md` publishes technical findings to the GitHub PR and the non-technical summary to the JIRA ticket.
