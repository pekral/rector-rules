# Code Review — GitHub PR comment (Bugsnag-sourced review)

> **Canonical output template.** This wrapper renders `@skills/code-review-github/templates/pr-comment-output.md` verbatim on the GitHub PR comment — every section, field, and conditional-rendering rule lives there, not here (issue #289). This file states only the two tracker-specific slots the canonical template leaves open for a Bugsnag-sourced review.

- **Tracker-mirror field** (header block label): `Linked-tracker mirror`
- **Tracker-mirror status** (header field value and the `Summary` line slot): the Bugsnag error the summary was posted on, or `no linked GitHub issue — mirror skipped` when `closingIssues[]` is empty.

Render the canonical template with those two slots filled in as above. See `@skills/code-review-bugsnag/SKILL.md` Output Rules for the authoritative statement of these values.
