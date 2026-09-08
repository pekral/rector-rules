---
name: pr-summary
description: "Use when summarizing current PR changes for the development and product team. Analyzes all commits in the current branch, explains what broke and what the fix changes, and produces a human-readable report that can be posted as a GitHub PR comment (Markdown), a JIRA comment (ADF), or a Bugsnag comment (plain text)."
license: MIT
metadata:
  author: "Petr Král (pekral.cz)"
---

## TL;DR

Read the branch's commits and its linked tracker. Write one non-technical comment. Publish it.

- **Every target renders the same two sections** → `What changed`, then `How to test`.
- **`What changed`** → `Problem`, `Cause`, `Result`, `What I fixed`, plus two conditional fields.
- **`How to test`** → a scenario a human follows: every step names a concrete input and a must-hold outcome.
- **A closing line** links the PR and the source issue.
- Only the delivery format differs per target: GitHub Markdown, JIRA ADF, Bugsnag plain text.
- Prose is terse. Business "why" first, enough technical context to locate the change, nothing more.
- No code snippets, file paths, line numbers, diff fragments.
- Length follows the facts the report carries. There is no word budget.
- Publish through `upsert-comment.sh` — a fresh comment per run, never an edit of a previous one.

---

## Constraints

### Rules to apply

Each line states what the rule actually decides here, so its relevance is clear without opening it.

- Apply @rules/php/core-standards.md — the package-wide prose and code standards every skill is held to.
- Apply @rules/git/general.md — how the base branch is resolved and what the commit history this skill reads is expected to look like.
- Apply @rules/writing/general.md — the sentence shape of every line this skill authors, and the rule that decides how long the report is: one idea per sentence, active voice, one term per concept, no marketing register.
- Apply @rules/jira/general.md when the target is a JIRA issue. The template uses a constrained Wiki Markup source format. The canonical helper converts that source to ADF and publishes it through `--body-adf`.
- Apply @rules/reports/general.md — the published comment is written in the language of the source assignment (Czech assignment → Czech comment; English assignment → English comment). Code identifiers stay verbatim per the rule's *Scope clarifications*.
- If the current project uses Laravel, also apply `@rules/laravel/laravel.md`, `@rules/laravel/architecture.md`, `@rules/laravel/filament.md`, and `@rules/laravel/livewire.md` — they tell the summary what a change to an Action, a Livewire component, or a Filament resource means in business terms.

### What renders where

The three targets carry the **same** structure. Only the markup and the template differ — no target gets a reduced shape, because the report carries nothing a tracker would need to omit.

| Element | GitHub PR comment | JIRA comment | Bugsnag comment |
|---|---|---|---|
| `What changed` | yes | yes | yes |
| `How to test` | yes | yes | yes |
| `{embedded_blocks}` | conditional — exactly as the wrapper passed them | conditional — same rule | conditional — same rule |
| Closing links line | yes | yes | yes |
| Markup | GitHub Markdown | ADF at the API boundary; the template's Wiki Markup is intermediate input only | plain text; no markup at all |
| Template | `templates/pr-summary-github.md` | `templates/pr-summary-jira.md` | `templates/pr-summary-bugsnag.md` |

### The section names are translated, the concepts are not

The headings and field labels above are this skill's canonical **concepts**, written in English because the skill itself is. The rendered comment follows the assignment language per `@rules/reports/general.md`, headings and field labels included — a Czech assignment renders `Co se změnilo` / `Problém` / `Příčina` / `Výsledek` / `Co jsem opravil` / `Vedlejší přínos` / `Na jiný ticket` / `Jak otestovat`. Never publish an English heading above assignment-language prose; that is the bilingual mixing the rule bans.

### What changed — four required fields, two conditional ones

Required, always rendered, in this order:

- **Problem** — what the reader's own world looked like when it was broken: who hit it, on what, what they saw instead. Name the scale when it is known (how many attempts, over how long, how many accounts).
- **Cause** — why it happened. One mechanism, stated so a non-developer follows it. This is where a missing or partially met acceptance criterion is named in prose, never as a verdict field.
- **Result** — what the cause actually cost: the number, the runtime, the silent failure it produced. When a failure was silent, say why it was silent.
- **What I fixed** — a bullet list, one bullet per change the reader can observe. Each bullet states the new behaviour and, where a number exists, the before-and-after.

Conditional — render only when it has content, never as an empty field:

- **Side benefit** — an improvement the fix produces that the assignment never asked for (load removed from a shared system, a class of failure that can no longer happen).
- **Filed separately** — a genuinely unrelated defect found during the work and filed on its own ticket. Name the ticket and state that it is linked.

### How to test — a scenario, not a checklist of tests

`How to test` is what a human does, in the application's own domain. It is never a list of automated tests and never a code-level instruction.

- Every step names **concrete inputs**: the account, the URL, the entity name, the value typed in.
- Every step states an explicit **must-hold outcome** — what the tester must see for the step to pass.
- Order the steps by what matters. When one step is the important one, say so in that step.
- When the change is reachable only behind a test parameter — a feature flag, an ENV switch, a query-string parameter, a request header, an A/B variant, a beta toggle, or an allow-listed account — the **first** step enables it, naming the exact toggle and the value required. There is no separate metadata line for it on any target; the toggle lives inside the step that enables it.
- Cover the regression too: name the neighbouring flows the tester should exercise to confirm nothing else moved.
- **Caller-supplied steps win.** When the caller (for example `hermes` in post-convergence reporting mode) passes pre-authored steps derived from designed test scenarios, use those steps as passed — never compressed, never rewritten. The caller's scenarios are the source of truth for this section.

### Closing line — the PR and the source issue

The comment ends with one line linking the pull request and the source tracker item, separated by ` · ` — a `PR #123` link, then an `ECOMAIL-6974` link, each written in the target's own link syntax (see the three templates). Render whichever of the two links exists; when neither exists, omit the line. It is a navigation aid, never prose, and it is never compressed or translated.

### Length follows the facts

There is no word budget and no "fits on one screen" rule. The report is as long as the facts it carries, and no longer. `@rules/writing/general.md` decides the shape of every sentence in it.

- **Never pad.** Do not restate the process, do not narrate what the run did, do not add a closing summary of what was already said.
- **Never truncate a fact** to hit a length. A dropped number, boundary, or must-hold outcome costs the reader the decision the report exists to support.
- A one-line fix produces a short report. A change with a measured cause, a measured result, and four things to retest produces a long one. Both are correct.

### What the comment carries

- Focus on the "why" and business impact, not on implementation details — but keep enough technical context (which integration, payload, table, endpoint, etc.) that a developer can still follow what changed.
- Do not include code snippets, file paths, line numbers, or diff fragments. The summary is for humans, not for static analysis.
- Do not restate the acceptance criteria as a checklist and do not publish a coverage verdict. `@skills/assignment-compliance-check/SKILL.md` owns the assignment verdict, and it reaches this comment through the `{embedded_blocks}` slot. On a CR run that slot always carries it — met, not met, or no criteria stated (`@rules/code-review/general.md` *Two-Part CR Output* → *The tracker comment carries the same verdict — in all three cases*). This skill still authors no verdict sentence of its own: it renders the block it was passed.

### Terse output style (issue #51)

Every sentence this skill authors into the rendered comment — the `What changed` fields and the `How to test` steps — carries a fact and nothing else.

- **Drop** filler words (just / really / basically / actually / simply and their assignment-language equivalents), pleasantries, hedging, and self-congratulation.
- **Keep** all technical substance — only fluff goes. Prefer short synonyms ("fix", not "implement a solution for").
- **Sentence shape is `@rules/writing/general.md`'s, not this section's.** Terseness removes ideas per sentence and removes filler; it never removes a word the sentence needs. Keep articles, prepositions, and relative pronouns — telegraphic fragments are not terse, only shorter.
- **Abbreviations:** standard well-known acronyms are fine (DB, API, HTTP); never invent new abbreviations (cfg / impl / req) — they save nothing and cost clarity.
- **No decoration:** no decorative tables, no decorative emoji, no causal arrows (→) in authored prose.
- **Verbatim always:** technical terms, code identifiers, toggle names, values, URLs, and commands.
- **Compress the style, never the language** — the assignment-language rule above (`@rules/reports/general.md`) is unchanged.
- **Never name or announce the style** in the rendered comment — no "terse mode". The JIRA template's generator-attribution footer is traceability, not a style announcement, and stays.
- **Auto-clarity carve-outs** — write normal, fully explicit sentences for: the `Cause` and `Result` fields (a reader who misreads the mechanism draws the wrong conclusion), security warnings and destructive or irreversible actions inside `How to test` steps, and every must-hold outcome. Never drop a word whose absence changes or blurs a tester's action.
- **Never compressed at all:** the `{embedded_blocks}` slot (rendered verbatim per the consolidation contract below), pre-authored test steps passed by the caller (used as passed), the closing links line, and the templates' fixed footers.

### Output shape per target

- Every target outputs the **two sections plus the closing line**: `What changed` (four required fields, two conditional), `How to test`, then the PR / issue links.
- No target renders an `Authors` line, an `Available behind` line, a `Summary of changes` section, a categories list, a breaking-changes section, or a testing-notes section. This skill resolves no authorship — a caller that needs an author set resolves it itself.
- The only per-target difference is markup and template. When the caller passes embedded blocks, they render on every target under the same rule.

### No leaked markup on JIRA

When the target is JIRA, the template body uses only the helper's supported Wiki Markup subset. It is never sent to JIRA directly. Before publishing, scan the source and convert or reject each leaked Markdown construct per `@rules/jira/general.md`:

| Markdown | JIRA Wiki Markup |
|---|---|
| `**bold**` / `__bold__` | `*bold*` |
| `#` / `##` / `###` headings | `h1.` / `h2.` / `h3.` |
| `` `code` `` | `{{code}}` |
| fenced ```` ``` ```` blocks | `{code}…{code}` |
| `- ` / `+ ` bullets | `*` |
| `[label]` + `(url)` | `[label\|url]` |

The reader must never see a raw `**` or `#`.

### No markup at all on Bugsnag

Bugsnag renders a comment as plain text, so every markup character reaches the reader literally. Write the body with no headings, no bold, no inline code, no links in bracket form: section names on their own line, field labels followed by a colon, list items opened with a plain `-`, and URLs written out in full. There is no per-actor marker either — the API token identifies the author.

### Embedded blocks (consolidation contract — issue #498)

When the calling CR wrapper passes extra markdown blocks (the `Clarifying questions` block and/or the `Assignment Compliance` block returned by `@skills/assignment-compliance-check/SKILL.md`), append them **verbatim** after `How to test` and **before** the closing links line.

- Each embedded block must already use the target tracker's source format (GitHub Markdown for GitHub, the supported intermediate Wiki Markup subset for JIRA, plain text for Bugsnag).
- The resulting comment is published once per linked tracker target — that single consolidated comment is the only non-technical artifact a CR run posts on each linked issue, JIRA ticket, or Bugsnag error.
- When no embedded blocks are passed, the template renders without that slot exactly as before. This is the shape of a non-CR invocation (for example `hermes` in post-convergence reporting mode), never of a clean CR result.
- This slot is how the assignment verdict reaches the reader, and on a CR run it carries that verdict on **every** run with a linked tracker — the affirmative one included. Silence is no longer the clean signal: a tracker comment in which "every criterion is met" and "nobody checked" look identical is the defect `@rules/code-review/general.md` *Two-Part CR Output* → *The tracker comment carries the same verdict — in all three cases* removes. This skill authors no verdict, no banner, and no "satisfies the assignment" sentence of its own — it renders the passed block verbatim, and the block is the verdict.

---

## Steps

Eight numbered steps, three independent jobs. The headings below are the jobs; the numbering runs continuously so a step can still be cited by number.

### Load context (1–4)

1. Identify the current branch and its base branch (usually `master` or `main`).
2. Load all commits in the current branch since it diverged from the base branch (`git log base..HEAD`).
3. For each commit, read the commit message and the diff to understand what changed and why.
4. If a PR already exists for this branch, load the PR description and linked issue(s) for additional context (business motivation, acceptance criteria, reporter's expectations):
   - **GitHub:** `skills/code-review-github/scripts/load-issue.sh <URL>` — always the full GitHub URL, never a bare number (the loader rejects it); read `body`, `comments[]`, and `closingIssues[]` off the resulting JSON document.
   - **JIRA:** `skills/code-review-jira/scripts/load-issue.sh <KEY|URL>` — read `descriptionText`, `comments[]`, and linked PRs.
   - **Bugsnag:** `skills/code-review-bugsnag/scripts/load-issue.sh <URL|TRIPLE>` — read the error context, its `comments[]`, and its linked issues / PRs.
   - Never call `gh pr view`, `gh issue view`, or `acli` directly; fall back to the GitHub / JIRA / Bugsnag MCP server only when the loader is unavailable (exit code 2/3).

### Decide the target (5)

5. Detect the **target tracker** for the comment by following the table in `@skills/resolve-issue/references/source-detection.md` (branch name / PR description / linked issue trail):
   - **JIRA** — the branch or PR description matches a JIRA issue-key regex (e.g. `^[A-Z][A-Z0-9_]+-\d+$`), or the JIRA loader from step 4 returns a non-empty document. Use `templates/pr-summary-jira.md` as intermediate source for the ADF publisher.
   - **Bugsnag** — the caller named a Bugsnag error URL or `organization/project/error` triple, or the Bugsnag loader from step 4 returns a non-empty document. Use `templates/pr-summary-bugsnag.md` (plain text).
   - **GitHub** — otherwise, or when the user explicitly asks for a PR comment. Use `templates/pr-summary-github.md` (GitHub Markdown).
   - If several signals match (a cross-tracker PR), prefer the tracker named in the user's invocation. Absent that, prefer the tracker the assignment itself came from, so the reporter reads the answer where they asked the question.

### Write and publish (6–8)

6. **Write `What changed`** — the four required fields in order (`Problem`, `Cause`, `Result`, `What I fixed`), then the two conditional ones (`Side benefit`, `Filed separately`) only when each has content. Derive every field from the commits, the diff, and the tracker context loaded in steps 1–4. State numbers where the run measured them; never invent one.
7. **Write `How to test`** — an ordered scenario per *How to test* above: concrete inputs, an explicit must-hold outcome per step, the gating toggle enabled in step 1 when the change is gated, and the regression flows named at the end. Use caller-supplied steps as passed when the caller provided them.
8. **Assemble and render.** Place the embedded blocks, when the caller passed any, between `How to test` and the closing links line, separated by a single blank line — each rendered exactly as received, with no re-formatting, no language conversion, and no re-ordering. Close with the PR / issue links line. Translate the headings and field labels into the assignment language, then convert the whole body to the target's markup and verify nothing leaked.

---

## Output format

- **GitHub PR comments** — `templates/pr-summary-github.md`, in GitHub Markdown.
- **JIRA issue comments** — `templates/pr-summary-jira.md`, converted to ADF by the JIRA helper. Never pass the intermediate Wiki Markup directly to `acli` or the JIRA MCP server.
- **Bugsnag error comments** — `templates/pr-summary-bugsnag.md`, in plain text.

All three carry the same two sections and the same closing line; they differ only in markup.

---

## Publishing

Post the summary as a comment to the related PR or issue if available, using the template that matches the target tracker. Publish through the shared helpers so each tracker receives its tracker-native markup — never via raw `gh issue comment` / `gh pr comment` / `acli jira workitem comment add` calls.

- **GitHub target** (PR comment or linked-GitHub-issue mirror): pipe the rendered body into `skills/code-review-github/scripts/upsert-comment.sh <NUMBER|URL> -`. The helper detects the current GitHub actor (`gh api user --jq .login`), appends the marker `<!-- cr-comment:actor=<gh-login> -->` for traceability, and **POSTs a fresh comment on every run** (it never PATCHes a prior comment in place). Fall back to the GitHub MCP server's `addIssueComment` only when the helper exits with code 2 (missing tool) or 3 (API failure) — also as a fresh post; never call `updateIssueComment` to edit a previous CR / pr-summary comment.
- **JIRA target**: pipe the rendered source into `skills/code-review-jira/scripts/upsert-comment.sh <KEY|URL> -`. The helper converts it to ADF, creates a new comment, and updates only that newly created comment through `--body-adf`. It never edits a comment from a prior run. Fall back to the JIRA MCP server's `addCommentToJiraIssue` only when the helper exits with code 2 (missing tool) or 3 (API failure), passing an ADF document rather than Wiki Markup.
- **Bugsnag target**: pipe the rendered body into `skills/code-review-bugsnag/scripts/upsert-comment.sh <URL|TRIPLE> -`. The helper POSTs a new comment on every run. Fall back to the Bugsnag MCP server only when the helper exits with code 2 (missing tool) or 3 (API failure) — also as a fresh post.
- Pre-existing comments published before these conventions were introduced are left untouched.
- Log the action (`created`) plus the resulting comment URL in the CR wrapper's summary line.

---

## Principles

- Explain what broke, why it broke, and what the reader can now observe instead
- Focus on business impact, not technical detail — but keep enough "what" that a developer can locate the change without reading the diff
- Every sentence carries a fact; the report is as long as its facts and no longer
- Make the test scenario reproducible by a non-developer tester, with concrete inputs and explicit must-hold outcomes
- Match the formatting to the target tracker (Markdown for GitHub, ADF for JIRA, plain text for Bugsnag)

## Output Humanization
- Use [blader/humanizer](https://github.com/blader/humanizer) for all skill outputs to keep the text natural and human-friendly.
