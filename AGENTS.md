# AGENTS.md

Behavioral guidelines to reduce common LLM coding mistakes. Merge with project-specific instructions as needed.

**Tradeoff:** These guidelines bias toward caution over speed. For trivial tasks, use judgment.

## Codex integration

- Before changing files, inspect `.codex/rules/` and read every rule whose `paths` frontmatter matches the files in scope. Rules without `paths` apply to every task.
- Reusable workflows live in `.agents/skills/`. Invoke a matching skill with `$skill-name`, and follow its `SKILL.md` in full.
- Project-scoped custom agents live in `.codex/agents/`. Use the specialist named by the workflow and preserve the role boundaries in its instructions.
- AI Olympus run state lives in `.codex/run/`. In imported role instructions, interpret `.claude/run/` as `.codex/run/`, `@skills/` as `.agents/skills/`, `@rules/` as `.codex/rules/`, and `agents/<name>.md` as `.codex/agent-instructions/<name>.md`.

## 1. Think Before Coding

**Don't assume. Don't hide confusion. Surface tradeoffs.**

Before implementing:

- State your assumptions explicitly. If uncertain, ask.
- If multiple interpretations exist, present them; don't pick silently.
- If a simpler approach exists, say so. Push back when warranted.
- If something is unclear, stop. Name what's confusing. Ask.

## 2. Simplicity First

**Minimum code that solves the problem. Nothing speculative.**

- No features beyond what was asked.
- No abstractions for single-use code.
- No flexibility or configurability that wasn't requested.
- No error handling for impossible scenarios.
- If you write 200 lines and it could be 50, rewrite it.

Ask yourself: "Would a senior engineer say this is overcomplicated?" If yes, simplify.

## 3. Surgical Changes

**Touch only what you must. Clean up only your own mess.**

When editing existing code:

- Don't improve adjacent code, comments, or formatting.
- Don't refactor things that aren't broken.
- Match existing style, even if you'd do it differently.
- If you notice unrelated dead code, mention it; don't delete it.

When your changes create orphans:

- Remove imports, variables, and functions that your changes made unused.
- Don't remove pre-existing dead code unless asked.

Every changed line should trace directly to the user's request.

## 4. Goal-Driven Execution

**Define success criteria. Loop until verified.**

Transform tasks into verifiable goals:

- "Add validation" becomes "write tests for invalid inputs, then make them pass."
- "Fix the bug" becomes "write a test that reproduces it, then make it pass."
- "Refactor X" becomes "ensure tests pass before and after."

For multi-step tasks, state a brief plan with a verification check for every step.

Strong success criteria let you loop independently. Weak criteria require constant clarification.

## Project conventions

- The quality gate runs once, immediately before merge. Do not run `composer build`, fixers, or checkers during implementation or the code-review loop unless the active skill explicitly owns the pre-merge gate.
- Git worktrees are supported, but create one only when the user explicitly requests it.
- Generated `.claude/`, `.codex/`, and `.agents/` directories are not source files in this package. Edit the tracked `rules/`, `skills/`, `agents/`, and `codex/` sources instead.
- Read relevant entries in `docs/memory/PROJECT_MEMORY.md` before starting a task.
