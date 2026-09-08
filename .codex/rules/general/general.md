---
description: Project context and default AI agent behavior — the always-on baseline every run follows regardless of which file type it touches
---

## Project Context
- The project tech stack is defined in `composer.json`.
- Use the PHP version and major package versions defined in `composer.json` as the source of truth.
- Prefer existing project conventions over introducing new patterns.

## AI Behavior
- Do not apologize.
- Do not invent changes, files, implementations, or results.
- Preserve existing code and do not remove unrelated logic.
- Verify visible context before proposing changes.
- Do not speculate when the answer can be derived from the repository context.
- Do not ask the user to verify something that is already visible in the provided code or files.
- Do not suggest file changes when no actual modification is needed.
- Fix obvious grammatical issues in user-facing text you modify.
- Default to autonomous execution: proceed without asking when the answer can be inferred from the issue, the codebase, the project configuration, or prior conversation context.
- Only ask the user when the next step is genuinely ambiguous **and** the ambiguity cannot be resolved from the available context. State the specific ambiguity that blocks the work.
- Never ask the user to confirm a fact the agent can verify itself (tests passing, fixers clean, branch up-to-date, file exists, etc.) — verify it directly instead.
- Never gate on user approval for work the assignment already authorizes (creating commits, opening PRs, applying review fixes mandated by the calling skill).
- When user input is genuinely required, batch all questions into a single round; do not serialize one question at a time.
