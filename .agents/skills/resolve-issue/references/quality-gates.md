# Quality Gates

Project fixers and checkers run **once per branch, at the merge boundary** — not before every push. Discover available tooling using this priority:

1. **Phing** — check for `build.xml` or `phing.xml` in the project root. If present, list available targets (`phing -l`) and use relevant fixer/checker targets.
2. **Composer scripts** — if Phing is not available, inspect `composer.json` `scripts` section for fixer and checker commands (e.g. `fix`, `check`, `build`, `pint-fix`, `phpcs-fix`, `rector-fix`, `pint-check`, `phpcs-check`, `rector-check`, `test:coverage`).

Run in this order:
1. **Fixers** — run all available fixers (e.g. code style, rector, normalize). Fix any issues they report.
2. **Checkers** — run all available checkers/analyzers (e.g. code style check, static analysis, audit). Resolve all reported errors before proceeding.
   **Resolve means change the code, never silence the tool.** A `phpcs:ignore`, `@phpstan-ignore`, `@psalm-suppress`, `@SuppressWarnings`, a new baseline / `ignoreErrors` line, or a PHP `@` operator must never enter the diff — `@rules/php/core-standards.md` PHP Practices admits no exception, and a new suppression annotation is a **Critical** review finding. Narrow a type, split a method, introduce a DTO, or assert an invariant the analyser cannot infer. For a genuine false positive in a surface the project does not own, add one scoped entry to the project's own tool configuration naming the single rule and the single path, with a comment naming the external contract that forces it.
When neither works, **stop and report it** — state what the checker flags, what was tried, and why neither route resolved it, and let a human decide. Never write the suppression to get the gate green.
3. **Coverage** — if a coverage command exists, run it and confirm 100% coverage for changed code paths.

If both fixers and checkers fail or are not found, stop and inform the user.

## Gate placement — deferred to the merge boundary (issue #65, revised)

A branch used to run the project's full build several times: once per implementation phase, once before the PR opened, and once per review-loop iteration. Every one of those runs proved the same thing the next one would prove again, and on a larger task the repeated full builds dominated the wall-clock cost of delivering the change. The gate now runs **once, immediately before the merge**, and the fixes it produces land as their own commit.

- **During implementation and during the review loop — no gate.** Do not run fixers, checkers, or the full build while authoring commits, after applying a review fix, or before pushing. A push is not a gate boundary: nothing is released by it, and the branch is still being worked on. Author the change, commit it, push it.
- **Once the work is finished — the full gate, once.** The project's full build (`composer build`, the Phing target, or the project's equivalent — install + fixers + full `check`, including full-suite coverage) runs after the code review has converged, before the pull request is offered as ready. `@skills/process-code-review/SKILL.md` *Finalization* owns that run: the review loop deliberately ran no fixers and no checkers, so this is the first point where they execute, and the fixes they produce land as the branch's last commit.
- **The merge re-checks rather than re-runs.** `@skills/merge-github-pr/SKILL.md` *Pre-merge quality gate* is the last safety net before an irreversible action: it accepts the recorded Finalization run only when all four of that step's conditions hold — the record is authentic, names this exact head commit, is a pass, and the tree is clean — and it runs the gate itself otherwise — for a PR that never went through the review loop, or one whose head moved afterwards. Together the two guarantee a merge never lands with a broken project (issue #75) while the gate still executes only once per set of bytes.
- **Fixes from the gate land as a new commit.** When the gate reports anything — a fixer rewrote a file, a checker flagged an error, coverage fell short — resolve it and commit the result as a **new commit** on the branch (`chore(gate): apply pre-merge fixer and checker fixes`, or a `fix(scope):` subject when the resolution changed behaviour). Never amend a commit already under review, and never force-push a branch a reviewer has commented on (`@rules/git/general.md`).
- **Re-run the gate after the fix commit.** The fix commit is a new tree, so the gate has not passed on it yet. Re-run the full build on the new head and repeat until it is green on the exact commit being merged. A merge proceeds only on a head commit whose own gate run passed.
- **A behaviour-changing fix re-opens the code review.** Whether the fix commit invalidates the converged review depends on what it changed, and the distinction is load-bearing:
  - **Tool-generated formatting only** — the commit contains nothing but the verbatim output of the project's fixers (code style, import order, normalization) with no hand-written change. The converged review still stands; record in the merge report which fixer produced the commit, so the exemption is auditable.
  - **Anything else** — a static-analysis error resolved by hand, a failing test, a coverage gap closed with new test code, or a `rector` rewrite that changed behaviour rather than formatting. Recompute the effective PR diff fingerprint. When it differs from `Reviewed diff fingerprint:`, this is a real change to reviewed content: the code-review gate is **stale** and the review must be re-run to convergence (`@skills/code-review-github/SKILL.md` + `@skills/process-code-review/SKILL.md`) before the merge proceeds. A new SHA with an identical fingerprint is a history-only rewrite and does not re-open CR.
  When it is unclear which of the two applies, treat the commit as behaviour-changing and re-review. The cheap outcome of a wrong guess here is one extra review; the expensive one is an unreviewed change merged under a stale approval.

The rule is one full build at the merge boundary, nothing during the branch's working life — not a full build per phase, not one per push, and never a merge on no gate at all.

### Retired with the repeated builds they deduplicated

Three mechanisms existed only to stop the same commit being built more than once. Deferring the gate to the end of the work removed the repeats, so all three are retired rather than left as guidance nothing can reach.

- **Head-SHA push-level dedup (issue #212, retired).** It deduplicated the full build across the three call sites that each ran one — the implementation's Finalization, `hephaestus`'s scoped validation, and the review loop's Finalization. All three are gone, so there is no second execution on the same commit to deduplicate; the `## Gate log` brief section it was keyed to is retired with it.
- **CI-result reuse for the loop gate (issue #124, retired).** It applied only to the per-iteration loop gate, which no longer exists — and it was already structurally unreachable in this repository, whose `pull_request` workflow checks out the merge ref and so could never satisfy its staleness guard.
- **Savings-mode build-gate cache (issue #119, retired).** It cached a passing build keyed by the working-tree hash so the *next* full build in the same run could cite it. With one gate run per branch there is no next build to serve, and the cache was left with readers and no writer. The one reuse that still matters — the merge accepting the Finalization run — is keyed to the head SHA and lives in `@skills/merge-github-pr/SKILL.md` *Pre-merge quality gate*, which needs no cache. The `## Build gate cache` brief section is retired with it.

**`security-audit` is never reused by anything.** `composer audit` queries a live advisory database at run time, so a green verdict is a function of *when* it ran, not only of *what* it read. It runs fresh on every gate execution — that was true of each retired mechanism's carve-out and stays true without them.
