---
description: Compound engineering — every change must make future work easier; the per-project memory file is read at task start.
---

## Compound Engineering

Compound engineering is **not** "let the AI write the code". It is a system where AI agents plan, implement, and review the work, while the human directs the direction, decides on quality, and curates what was learned so the next task is easier. Every loop is supposed to compound: each feature, fix, and review should lower the cost of the next change, never raise it.

- **Every change must make future work easier, not harder.** A change that adds hidden coupling, ships an undocumented decision, or introduces a new abstraction where an existing part of the system already fit is a defect to correct — not something to ship and move on from.
- **Every mistake, insight, or decision worth more than this one task gets written down** where the next agent *and* the next human will find it. Knowledge that lives only in someone's head, a chat thread, or a closed PR does not compound.
- The human stays in the loop on direction and quality; the agents do the planning, implementing, and reviewing against that direction.

## Compound Memory — the companion file

Durable, project-specific lessons live in `docs/memory/PROJECT_MEMORY.md` in the project being worked on. The sections that govern that file live in `@rules/compound-engineering/memory.md`, not in this file: *Compound Memory (per project)*, with *Where to store it*, *Entry format*, *Read protocol* (with *Per-dispatch memory slice* and *Per-role read filter*), and *Write protocol*. That file loads on demand, so this file stays inside the total instruction budget Claude Code enforces across every always-on file.

- **A run that reads, slices, or writes `docs/memory/PROJECT_MEMORY.md` reads and applies `@rules/compound-engineering/memory.md` first.** Reading the memory file itself attaches the rule. Every skill and agent that reads or writes the memory names the file.

## Tracker workflow — the companion file

The sections that govern a run taking its assignment from a tracker item live in `@rules/compound-engineering/tracker.md`, not in this file: *Analyze every comment before you act on a tracker assignment*, *Fix the cause first, then repair the data it already wrote*, *Claim a tracker issue before working on it*, *Tracker status tracks the phase of work*, *Every pull request links back to its tracker issue*, *File deferred points as follow-up tracker issues*, and *Label tracker issues, and keep the labels true*. That file loads on demand, so this file stays inside the total instruction budget Claude Code enforces across every always-on file.

- **A run that reads, claims, updates, links, labels, or files a tracker item reads and applies `@rules/compound-engineering/tracker.md` first.** Every skill and agent that performs one of those steps names the file.

## No generated documentation in `docs/`

An agent never generates documentation into `docs/` — no new file and no new subdirectory, unless the user explicitly asks for that file. Nothing checks generated documentation: no test, no fixer, no reviewer. The code moves and the document does not, so the next reader trusts a description of code that no longer exists. The one path an agent writes under `docs/` on its own is `docs/memory/PROJECT_MEMORY.md` (`@rules/compound-engineering/memory.md`).

| Documentation | Where it belongs |
|---|---|
| Conventions for agents and contributors | the project instruction sources (`@rules/general/general.md` *Project instructions take precedence*) |
| Path-scoped traps and settled decisions | the project's own rule files (e.g. `.ai/rules/**`) |
| The repository entry point | `README.md` |
| Analysis, plans, and reports for one task | the tracker item |

- **Deleting a committed file is a stated decision, never a side effect.** Run `git status` before you commit and stage only the changes you intended. The commit message says who decided the deletion and why.
- In code review, a diff that adds a file under `docs/`, other than the memory file, is a **Moderate** finding. The Suggested Fix names the row of the table the content moves to.

## What Not To Do

- Do not write a project-specific lesson into this shared rules package as a new global rule — only genuinely universal standards belong here.

## Blocked delegation is a hard stop

When an orchestrator delegates a step (analysis, implementation, review) and the delegate returns a blocker it cannot resolve — most commonly a write-capable implementer (e.g. `donatello`) whose `Write` / `Edit` is refused by the harness sandbox / permission layer even though the agent declares those tools, but equally an unresolvable merge conflict or a non-converging review loop — the run **stops and reports the blocker with its remediation**, never a silent bypass. Do **not** silently complete the blocked agent's work in the main thread (or in another agent's context): that bypasses the delegated, reviewed pipeline (no implementer→reviewer loop, no quality gates), hides the failure from the human, and breaks the compounding loop.
Surface *what was blocked*, *why* (the denied capability), and *how to unblock it* (the environment change the human must make), then halt.

## Code Review Application

- Treat a change that makes future work harder — new abstraction where an existing part fit, undocumented non-obvious decision, hidden coupling — as a finding, with the concrete existing part it should have used.
