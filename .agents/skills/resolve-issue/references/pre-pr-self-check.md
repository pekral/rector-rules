# Pre-PR self-check (lightweight, deterministic)

Referenced from `skills/resolve-issue/SKILL.md` *Pre-PR self-check*. Extracted to keep the skill body under the skill-check token limit; the items themselves are stated inline there, and this file carries the procedure and the boundary.

## What this pass replaced, and why

It used to run `@skills/code-review/SKILL.md` and `@skills/security-review/SKILL.md` inline over the implementer's own diff, gate PR creation on 0 Critical / 0 Moderate, and hand off to `leonardo`, who then ran the same two lenses over the same diff again. The second pass is the authoritative one, so the first bought a marginally cleaner starting point at the price of a complete duplicate LLM review on every run — the single largest avoidable cost in the pipeline. `@rules/compound-engineering/orchestration.md` *Adaptive routing* → *One authoritative LLM review, not two* removed it.

**What is lost, stated rather than hidden:** `leonardo` now reads a less pre-polished diff, so a finding the implementer would have caught and quietly fixed can instead cost one review round. That is the intended trade — one round is cheaper than one duplicated review on every run — and on a `FAST`-tier run, where no `leonardo` pass is dispatched at all, the deterministic gates below plus the classifier's sensitive-area force are what stand in its place.

## Procedure

1. **Walk the items in order** (the seven listed in the skill body) against the working tree and the diff that is about to become the pull request.
2. **Fix what an item surfaces**, directly — a stray `dd()`, an uncommitted scratch file, a criterion with no test. These are defects with one obvious correction, not findings that need a severity.
3. **Record each item's result in the handoff**, so the orchestrator and the reviewer see what was verified rather than assuming it. A self-check whose result nobody can read is indistinguishable from one that did not run.
4. **Stop as `Blocked` when an item cannot be satisfied.** A failing test on the changed surface, a red static-analysis run, or an acceptance criterion with no implementation is a stop — never a PR opened knowingly carrying it.

## The boundary

- **It is not a review.** It invokes no review skill, produces no severity-graded findings, and gates nothing on a finding count. Judgment calls — architecture, reuse, security reasoning — belong to `leonardo`.
- **It does not run the build.** The project's full gate runs once immediately before the merge (`references/quality-gates.md` *Gate placement — deferred to the merge boundary*); this pass runs the diff-targeted tests and the static analysis for the changed files.
- **It never claims a verdict it did not produce.** The technical report says what this pass checked, never "code review clean" or "security review passed".

PR-comment processing via `@skills/process-code-review/SKILL.md` remains the path used **after** a PR exists; it is not part of this pre-PR pass because it requires an open PR to operate on.
