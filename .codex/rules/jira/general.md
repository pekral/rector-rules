---
description: JIRA CLI (acli) usage and fallback rules
---

## JIRA Rules

- Never change JIRA issue status, with three exceptions: (1) an early transition to the project's In Progress status at the start of work, performed only via `skills/code-review-jira/scripts/transition-to-in-progress.sh`; (2) a transition to the project's Code Review status when the PR opens, performed only via `skills/code-review-jira/scripts/transition-to-code-review.sh`; (3) a transition to the project's Ready to Merge status when the code review converges (`@skills/process-code-review/SKILL.md` *Review loop* step 4 — zero Critical, zero unfulfilled reviewer comments, no undeferred Moderate; this rule cites that one definition rather than restating it), before the merge itself, performed only via `skills/code-review-jira/scripts/transition-to-ready-to-merge.sh`.
Every other transition (To Do, Done, Closed, …) stays human-only (L3, per `@rules/compound-engineering/orchestration.md` *Externally-visible actions & consent levels*). All three helpers refuse any out-of-scope target, re-read the status to confirm the issue actually reached the column before reporting success, and are idempotent (no-op when already in the target status).
Reverting exception (3) — a later commit re-opens the review, so the issue moves back to the review column — needs no fourth helper: that move is exception (2)'s own transition, run again. Each project may name these columns differently, so the target is resolved and validated by each helper, never hardcoded.
- The In Progress helper accepts the Czech status name `Rozpracováno` as a built-in safe progress target. Before changing an already in-progress issue, it verifies that `assignee = currentUser()`; otherwise it aborts instead of stealing another run's claim. For a new claim it assigns the issue to the account currently authenticated in `acli` by running `acli jira workitem assign --key <KEY> --assignee "@me" --yes`, then verifies the same JQL predicate. A failed or unverified assignment blocks implementation even when the status transition succeeded.

## Tooling
- Use `acli` as the primary tool for all JIRA operations (read, comment, attachments).
- If `acli` is unavailable, use a JIRA MCP server.
- If no JIRA tool is available, stop and report that JIRA access is not available.

## Comments Format
- Every JIRA comment must reach the API as an Atlassian Document Format (ADF) document. JIRA Cloud stores comments as ADF. `acli comment create --body-file` stores Wiki Markup such as `h2.` and `*bold*` as flat text instead of rendering it.
- Publish only through `skills/code-review-jira/scripts/upsert-comment.sh`. The helper accepts the Wiki Markup subset below as an intermediate authoring format, converts it to real ADF, creates a fresh comment, and applies the ADF with `acli jira workitem comment update --body-adf <file>`. Never send Wiki Markup directly to `acli` or the JIRA MCP server.
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
- **Verify before posting — valid ADF only.** Scan the intermediate source for leaked Markdown. Then require the helper to validate an ADF root with `version: 1`, `type: doc`, and a `content` array before the first external write. The final `acli` write must use `comment update --body-adf`; a successful plain-text create is not publication success.
