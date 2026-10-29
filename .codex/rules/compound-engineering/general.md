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

## The assignment is the scope

The goal of every assignment is that every acceptance criterion is met. This section is the one owner of that goal and of its boundary. Other files reference it and never restate it.

- **Verify each criterion before you report the work done.** Check every acceptance criterion against the result, with a test or an observation. A criterion with no check is not met. The report names each criterion as met or unmet, and an unmet criterion is never reported as done.
- **Change nothing outside the assignment.** A change is inside the assignment only when one of these requires it:
  1. an acceptance criterion;
  2. a line the change itself writes, including its comments, which `@rules/php/core-standards.md` governs;
  3. a Critical finding, a Moderate finding, or an unfulfilled reviewer instruction on the diff (the convergence gate in `@skills/process-code-review/SKILL.md` *Review loop* step 4);
  4. the exact-head quality gate, required CI, or a merge conflict.
- **The one exception is security.** An agent that changes files and finds a security vulnerability along the way fixes it, in its own `pre-existing — ` commit with a regression test (`@skills/resolve-issue/references/pre-existing-issue-handling.md`). A security vulnerability is a defect that a rule in `@rules/security/**` names and that has an exploit path. A defect that only sits on a security surface is not one. The fix is the smallest change that closes the vulnerability, in a file the change had to read. Anything more is outside the assignment. `@skills/security-audit/SKILL.md` covers its whole requested scope by design. A refactoring-only change files the vulnerability instead (`@rules/refactoring/general.md` *Behaviour stays identical — bugs included*).
- **Record everything else; implement none of it.** This covers a pre-existing bug, a project-rule violation, a comment outside the lines the change writes, a refactoring, an optimization, and a nice-to-have point. The existing filing path decides what happens to it: `@rules/compound-engineering/tracker.md` *File deferred points as follow-up tracker issues*, and in merge preparation an open decision (`@skills/verify-merge-readiness/SKILL.md` *Scope — the assignment only*). A point that clears no bar is dropped, not carried forward.

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

- A change outside the assignment that is not a security fix is a finding of the Assignment Conformance Gate, direction *Changes → requirements* (`@skills/code-review/references/assignment-conformance-gate.md` step 2). Raise it there and nowhere else.
- Treat a change that makes future work harder — new abstraction where an existing part fit, undocumented non-obvious decision, hidden coupling — as a finding, with the concrete existing part it should have used.
