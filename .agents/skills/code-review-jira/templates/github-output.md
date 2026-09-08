# Code Review — GitHub PR comment (JIRA-sourced review)

> **Canonical output template.** This wrapper renders `@skills/code-review-github/templates/pr-comment-output.md` verbatim on the GitHub PR comment — every section, field, and conditional-rendering rule lives there, not here (issue #289). This file states only the two tracker-specific slots the canonical template leaves open for a JIRA-sourced review.

- **Tracker-mirror field** (header block label): `Linked-tracker mirror`
- **Tracker-mirror status** (header field value and the `Summary` line slot): `posted JIRA summary on <KEY> (+ mirrored to GitHub issue #N)` | `JIRA only — no linked GitHub issue` | `failed: <reason>`

Render the canonical template with those two slots filled in as above. See `@skills/code-review-jira/SKILL.md` Output Rules for the authoritative statement of these values.
