---
description: JIRA CLI (acli) usage and fallback rules
paths:
  - ".claude/rules/jira/**"
---

## JIRA Rules

- Never change JIRA issue status, with three exceptions:
  1. A transition to the project's In Progress status, performed only via `skills/code-review-jira/scripts/transition-to-in-progress.sh` — either an early transition at the start of work, or the owner's return from a Code Review status when work on the code resumes.
  2. A transition to the project's Code Review status when the PR opens, performed only via `skills/code-review-jira/scripts/transition-to-code-review.sh`.
  3. A transition to the project's Ready to Merge status when the code review converges (`@skills/process-code-review/SKILL.md` *Review loop* step 4 — zero Critical, zero unfulfilled reviewer comments, no undeferred Moderate; this rule cites that one definition rather than restating it), before the merge itself, performed only via `skills/code-review-jira/scripts/transition-to-ready-to-merge.sh`.

  Every other transition (To Do, Done, Closed, …) stays human-only (L3, per `@rules/compound-engineering/orchestration.md` *Externally-visible actions & consent levels*). All three helpers refuse any out-of-scope target, re-read the status to confirm the issue actually reached the column before reporting success, and are idempotent (no-op when already in the target status).
  Reverting exception (3) — a later commit re-opens the review, so the issue moves back to the review column — needs no fourth helper: that move is exception (2)'s own transition, run again. Undoing the owner's return — moving the issue back to the review column once the resumed change is pushed and green — needs no fourth helper either: that move is exception (2)'s own transition, run again. Each project may name these columns differently, so the target is resolved and validated by each helper, never hardcoded.
- The In Progress helper accepts the Czech status name `Rozpracováno` as a built-in safe progress target.
Before changing an issue that is already in progress or in review (matched the same synonym-aware way `transition-to-code-review.sh` matches its own target), it verifies that `assignee = currentUser()`; otherwise it aborts instead of stealing another run's claim. The same check lets the owner return an issue from review to In Progress when work on the code resumes.
An issue in Ready to Merge (matched the same synonym-aware way `transition-to-ready-to-merge.sh` matches its own target) is never returned, whoever owns it — Ready to Merge already means an approved code review sits behind the issue and it is ready to merge into the main branch. The way back from Ready to Merge is `transition-to-code-review.sh`, which reverts exception (3).
A finished issue (Done, Closed, Resolved, Cancelled, Canceled, Merged, Hotovo, a status containing "deploy", Testování/testovani) is never returned. For a new claim it assigns the issue to the account currently authenticated in `acli` by running `acli jira workitem assign --key <KEY> --assignee "@me" --yes`, then verifies the same JQL predicate. A failed or unverified assignment blocks implementation even when the status transition succeeded.

## Tooling
- Use `acli` as the primary tool for all JIRA operations (read, comment, attachments).
- Read comments through `skills/code-review-jira/scripts/load-issue.sh` or `parse-comments.sh`, never from the `acli jira workitem comment list` body alone. That body is flattened by acli and drops mentions, emoji, links, and the text of every list item, so a decision written as a bullet disappears. The loaders render each body from the ADF the issue view embeds and expose the comment `id`.
- If `acli` is unavailable, use a JIRA MCP server.
- If no JIRA tool is available, stop and report that JIRA access is not available.

## Comments Format
- Every JIRA comment must reach the API as an Atlassian Document Format (ADF) document. JIRA Cloud stores comments as ADF. `acli comment create --body-file` stores Wiki Markup such as `h2.` and `*bold*` as flat text instead of rendering it.
- Publish only through `skills/code-review-jira/scripts/upsert-comment.sh`. The helper accepts the Wiki Markup subset below as an intermediate authoring format, appends the marker line `_cr-comment:actor=<actor-digest>_` — a digest of the account e-mail, never the address, since every reader of the issue sees that line — converts the source to real ADF, and applies that ADF with `acli jira workitem comment update --body-adf <file>` — to the existing marker-carrying comment when one exists, otherwise to a comment it creates first. Never send Wiki Markup directly to `acli` or the JIRA MCP server.
- Do not use Markdown syntax:
    - no fenced code blocks
    - no `#` headings
    - no markdown tables
- Intermediate Wiki Markup cheatsheet (the helper converts these constructs to ADF nodes and marks):
    - Heading: `## Heading` → `h2. Heading` (`### Heading` → `h3. Heading`)
    - Bold: `**bold**` → `*bold*`
    - Italic: `*italic*` or `_italic_` → `_italic_`
    - Inline code: `` `code` `` → `{{code}}`
    - Code block: ` ```php ... ``` ` → `{code:php} ... {code}`
    - Bullet list: `- item` → `* item`
    - Numbered list: `1. item` → `# item`
    - Link: `[label](https://example.com)` → `[label|https://example.com]`
    - Quote: `> text` → `{quote}text{quote}`
- **A helper that fails is never a licence to improvise.** When `upsert-comment.sh` exits 2 or 3, the only sanctioned fallback is the JIRA MCP server with an **ADF** payload carrying the same `_cr-comment:actor=<actor-digest>_` marker line the helper would have appended — an agent marker per `@rules/code-review/general.md` *Authorship trust*. When the session carries no JIRA MCP tool, the run stops as blocked: it quotes the helper's stderr verbatim, keeps the Wiki Markup source for a human to publish, and says whether a comment may already exist on the issue. Never retry with a raw `acli` write, and never hand the Wiki Markup source to any other command — that is how a ticket ends up carrying `h2.`, `{{code}}`, and `[label|url]` as literal text.
  When the helper exits 3 because `acli jira auth status` carries no account e-mail, the MCP fallback cannot compute the digest either, so the run stops as blocked.
- **One issue carries one comment per actor, and it holds the final result.** Publish once, when the result is final; a later publish updates that comment in place and never adds a second one. A retry goes through `upsert-comment.sh` again: it updates the comment an earlier attempt created, or exits 3 without creating anything. When the fallback runs through the JIRA MCP server and the issue already carries this actor's marked comment, update that comment; never create a new one next to it.
  The one exception is a review-only run (`/report-code-review`): it passes `--create`, so each run creates its own comment, on the MCP fallback too.
- **Delete a comment only through `skills/code-review-jira/scripts/delete-owned-comment.sh`.** Never run a raw `acli jira workitem comment delete`. The helper deletes only a comment on the exact issue that carries this account's `_cr-comment:actor=<actor-digest>_` marker and shares the author account ID of the protected final comment, never one of the protected IDs, and it re-reads the issue to confirm the comment is gone while both protected comments remain. Use it to remove the duplicate a failed `upsert-comment.sh` run (exit 2/3) left behind, once the replacement comment is published and read back. A comment with no marker cannot be proven yours and stays for a human.
- **The protected comments of a JIRA delete are identified by account ID, not by requiring a marker on them.** A replacement TL;DR published through the JIRA MCP fallback still carries the `cr-comment:actor=` marker, exactly as the helper's own publish would — every sanctioned comment path on JIRA appends one, per `@rules/compound-engineering/tracker.md` *Every comment an agent publishes on GitHub or JIRA carries a marker*. The delete helper's own protection does not depend on that marker being present on the protected comment: it takes the account ID from the comment directly, and requires the marker only on the comment it deletes.
- **A GitHub-shaped instruction on a JIRA source is re-routed, never followed literally.** A workflow step that names `skills/code-review-github/scripts/upsert-comment.sh` describes the GitHub destination. On a JIRA source, publish through this rule's own helper and its `pr-summary-jira.md` template instead; a GitHub helper cannot address a JIRA key, and improvising past it produces exactly the unformatted comment above.
- **Verify before posting — valid ADF only.** Scan the intermediate source for leaked Markdown. Then require the helper to validate an ADF root with `version: 1`, `type: doc`, and a `content` array before the first external write. The final `acli` write must use `comment update --body-adf`; a successful plain-text create is not publication success.

## Issue Description Format
- An issue description follows the same format as a comment. JIRA Cloud stores the description as ADF and shows Wiki Markup sent as plain text verbatim, so `h2.`, `*`, and `{{code}}` appear as literal text.
- Author the description in the Wiki Markup subset of *Comments Format*. Convert it with `php skills/code-review-jira/scripts/wiki-markup-to-adf.php < <source> > <adf-file>` and pass the ADF file to `acli jira workitem create --description-file <adf-file>`. Never pass the Wiki Markup source to `--description`, `--description-file`, or the JIRA MCP server.
- A round-3 deferred subtask goes through `skills/process-code-review/scripts/file-deferred-moderate.sh`, which performs the conversion itself.
