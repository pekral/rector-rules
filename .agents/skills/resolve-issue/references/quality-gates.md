# Quality Gates

Project fixers and checkers run **once per branch, at the merge boundary** — not before every push. This file is the one place that defines how the project's gate and coverage commands are discovered; every other file points here. Discover them in this order, and resolve the gate and the coverage command separately — each comes from the first source that defines it:

1. **Project manifest** — read `extra.ai-olympus` with `skills/_shared/read-manifest.sh` (`@rules/general/general.md` *Project manifest*). The script reads the default-branch copy, never the working tree of a branch under review. When the manifest sets `gate`, that list is the project's full gate: run its commands in the listed order, and every command must pass. When the manifest sets `coverage`, that command is the project's coverage command.
2. **Phing** — when the manifest sets no `gate`, check for `build.xml` or `phing.xml` in the project root. If present, list available targets (`phing -l`) and use relevant fixer/checker targets.
3. **Composer scripts** — when neither source applies, inspect `composer.json` `scripts` section for fixer and checker commands (e.g. `fix`, `check`, `build`, `pint-fix`, `phpcs-fix`, `rector-fix`, `pint-check`, `phpcs-check`, `rector-check`, `test:coverage`).

Before you run a gate or coverage command, whichever source supplied it, export exactly the `NAME=value` lines `skills/_shared/read-manifest.sh --env` prints — never the raw manifest `env`. When that call exits `4`, it refused a variable that changes which program runs (`PATH`, `GIT_*`, `LD_*`, …): stop and report the refused name instead of running the gate.

A manifest `gate` already fixes the order: run its commands as listed. Otherwise run in this order:
1. **Fixers** — run all available fixers (e.g. code style, rector, normalize). Fix any issues they report.
2. **Checkers** — run all available checkers/analyzers (e.g. code style check, static analysis, audit). Resolve all reported errors before proceeding.
   **Resolve means change the code, never silence the tool.** A `phpcs:ignore`, `@phpstan-ignore`, `@psalm-suppress`, `@SuppressWarnings`, a new baseline / `ignoreErrors` line, or a PHP `@` operator must never enter the diff — `@rules/php/core-standards.md` PHP Practices admits no exception, and a new suppression annotation is a **Critical** review finding. Narrow a type, split a method, introduce a DTO, or assert an invariant the analyser cannot infer. For a genuine false positive in a surface the project does not own, add one scoped entry to the project's own tool configuration naming the single rule and the single path, with a comment naming the external contract that forces it.
When neither works, **stop and report it** — state what the checker flags, what was tried, and why neither route resolved it, and let a human decide. Never write the suppression to get the gate green.
3. **Coverage** — if a coverage command exists, run it and confirm 100% coverage for changed code paths.

If the manifest sets no `gate` and both fixers and checkers fail or are not found, stop and inform the user.

## A flaky test outside the diff and the assignment is left alone

A flaky test fails on one run and passes on the next, on the same commit, with no change in between. When such a test has nothing to do with the task, fixing it widens the pull request and delays the finish for a problem the task did not create.

1. **Confirm it is flaky.** Re-run the same test command on the same commit, in the same order — the whole suite, never the test alone. It passes → it is flaky. It fails again → it is a real failure, and the gate handles it as any other failure. A test that fails in the suite but passes alone is order-dependent: the PR may leak state into it, so it counts as related.
2. **Check that it is unrelated.** The test is unrelated only when all of these hold:
   - the PR's diff does not add or change the test file;
   - the test does not cover code the PR changes, and does not call code that the changed code calls;
   - the test does not belong to the area the assignment describes.

   When one of these does not hold, or it is unclear, the test is related: find and fix the cause per `@rules/code-testing/general.md` *Flaky Test Prevention*.
3. **Unrelated → ignore it.** Do not modify, skip, or delete the test, and do not file an issue for it. The run counts as green when the re-run in step 1 passed. Record it as green on the `Quality gate:` line with the flaky test named (`green — flaky, left alone: <test>`), and name the test, the failure message, and the passing re-run in the handoff and in the merge report.

## HOTFIX — what the mode relaxes here

A caller may declare a run a HOTFIX (`@rules/compound-engineering/orchestration.md` *HOTFIX — the declared emergency path*). The mode waives the coverage gates and nothing else; it is declared by the caller and never inferred from how urgent the assignment sounds.

- **Step 3 does not block.** Run the coverage command when one exists, record the figure, and proceed even when it falls short. Steps 1 and 2 are untouched — a fixer rewrite, a checker error, a static-analysis error, and a failing test all block a hotfix exactly as they block any other change, because a hotfix that breaks the default branch is a second outage.
  Under a machine gate record, a `run-gate.sh` exit `4` counts as that shortfall only when both hold, and blocks otherwise:
  1. the record's `commands` hold every command of the tier, and only the last one has a non-zero `exit_code` — `run-gate.sh` stops at the first failing command, so an earlier failure leaves the later commands unproven;
  2. `skills/_shared/verify-gate.sh --tier full <sha>`, run after the gate, reports `fresh_exit_code` `0` — `run-gate.sh` skips `gate-fresh` after a failure, and the waiver never covers the dependency audit.
- **The reproduction stays; the committed test becomes optional.** `@skills/resolve-issue/SKILL.md` *If bug* requires a failing test before the fix. Under HOTFIX that relaxes to: observe the failure before the fix and its absence after, by whatever is fastest — a test, a one-off script, or the running application — and state which was used in the handoff and the pull request.
- **Write the regression test when it is cheap.** When it is not, say so in the pull request, so the gap is visible rather than assumed. Everything else in the bug branch is unchanged, the data repair included.

## Gate placement — deferred to the merge boundary (issue #65, revised)

A full build proves the same thing on every run over the same bytes, and on a larger task repeated builds dominate the wall-clock cost of delivering the change. The gate therefore runs **once, immediately before the merge**, and the fixes it produces land as their own commit.

- **During implementation and during the review loop — no gate.** Do not run fixers, checkers, or the full build while authoring commits, after applying a review fix, or before pushing. A push is not a gate boundary: nothing is released by it, and the branch is still being worked on. Author the change, commit it, push it.
- **The one exception is the project's own `pr-gate`.** When the manifest sets it, the implementer runs `skills/_shared/run-gate.sh --tier pr` before each push (*Machine gate record* below). Without `pr-gate` nothing runs before a push, exactly as before.
- **Once the work is finished — the full gate, once.** The project's full gate (discovered in the order at the top of this file — install + fixers + full `check`, including full-suite coverage) runs after the code review has converged, before the pull request is offered as ready. `@skills/process-code-review/SKILL.md` *Finalization* owns that run: the review loop deliberately ran no fixers and no checkers, so this is the first point where they execute, and the fixes they produce land as the branch's last commit.
- **The merge re-checks rather than re-runs.** `@skills/merge-github-pr/SKILL.md` *Pre-merge quality gate* is the last safety net before an irreversible action: it accepts the recorded Finalization run only when all four of that step's conditions hold — the record is authentic, names this exact head commit, is a pass, and the tree is clean — or, on a project that opted into the machine record, only when `verify-gate.sh` accepts it (*Machine gate record* below) — and it runs the gate itself otherwise —
  for a PR that never went through the review loop, or one whose head moved afterwards. Together the two guarantee a merge never lands with a broken project (issue #75) while the gate still executes only once per set of bytes. After a rebase that only moved the base, *Rebase that moves the head — analyse the incoming changes first* below decides whether the recorded run carries forward to the new head.
- **Fixes from the gate land as a new commit.** When the gate reports anything — a fixer rewrote a file, a checker flagged an error, coverage fell short — resolve it and commit the result as a **new commit** on the branch (`chore(gate): apply pre-merge fixer and checker fixes`, or a `fix(scope):` subject when the resolution changed behaviour). Never amend a commit already under review, and never force-push a branch a reviewer has commented on (`@rules/git/general.md`).
- **Re-run the gate after the fix commit.** The fix commit is a new tree, so the gate has not passed on it yet. Re-run the full build on the new head and repeat until it is green on the exact commit being merged. A merge proceeds only on a head commit whose own gate run passed.
- **A behaviour-changing fix re-opens the code review.** Whether the fix commit invalidates the converged review depends on what it changed, and the distinction is load-bearing:
  - **Tool-generated formatting only** — the commit contains nothing but the verbatim output of the project's fixers (code style, import order, normalization) with no hand-written change. The converged review still stands; record in the merge report which fixer produced the commit, so the exemption is auditable.
  - **Anything else** — a static-analysis error resolved by hand, a failing test, a coverage gap closed with new test code, or a `rector` rewrite that changed behaviour rather than formatting. Recompute the effective PR diff fingerprint. When it differs from `Reviewed diff fingerprint:`, this is a real change to reviewed content: the code-review gate is **stale** and the review must be re-run to convergence (`@skills/code-review-github/SKILL.md` + `@skills/process-code-review/SKILL.md`) before the merge proceeds. A new SHA with an identical fingerprint is a history-only rewrite and does not re-open CR.
  When it is unclear which of the two applies, treat the commit as behaviour-changing and re-review. The cheap outcome of a wrong guess here is one extra review; the expensive one is an unreviewed change merged under a stale approval.

The rule is one full build at the merge boundary, nothing during the branch's working life — not a full build per phase, not one per push, and never a merge on no gate at all.

## Machine gate record — one run per tree

The textual `Quality gate:` line proves a run only to the extent its author is trusted, so every later step used to run the gate again on the same bytes. Two scripts replace that declaration with a record a script can check.
The record is opt-in: it applies when the manifest sets at least one of `pr-gate`, `gate-fresh`, or `gate-evidence`. `gate` is then tier `full`, and `pr-gate` is tier `pr`. A project that sets none of the three keeps the built-in path of this file exactly as before, even when it sets `gate`.

- **`skills/_shared/run-gate.sh --tier full|pr [--actor <name>]`** runs the tier's commands from the default-branch manifest, in order, as an argv without a shell, with only `read-manifest.sh --env` exported. It refuses a working tree with any uncommitted or untracked change.
  It holds the lock `<evidence>/gate.lock` — an atomic `mkdir` with a holder file and a reclaim on confirmed death only (`@rules/compound-engineering/concurrency.md`); `flock(1)` does not exist on macOS. A second run on the same tree waits for the lock and takes the finished result over instead of running the gate again.
  It writes the log `<evidence>/<tree>.<tier>.log`, then the record `<evidence>/<tree>.<tier>.json`: the tier, the commands with their exit codes and durations, `HEAD`, the tree, the merge base, the environment fingerprint (PHP version, lockfile hashes, manifest `env`), the actor, the start and end, the overall exit code, and the SHA-256 of the log.
  A change of the tree or of `git status` during the run fails the gate: a fixer rewrite is a reported problem, never a pass.
- **`skills/_shared/verify-gate.sh --tier full|pr <sha>`** accepts a record only when its tree equals the tree of `<sha>`, its commands equal the current manifest, its environment fingerprint matches, its log matches its hash, and it passed. The record is keyed to the tree, so a rebase, squash, or amend that keeps the bytes keeps it, and any other tree has none. It then runs `gate-fresh` on every call.
- **`gate-fresh` is never reused.** Its commands run fresh on every `verify-gate.sh` call and after every passing `run-gate.sh` run, and their result is never written to a record. A missing or empty `gate-fresh` means `composer audit` when `composer.lock` exists — the rule that `security-audit` is never reused now lives in configuration, with that rule as the default.
- **`gate-evidence`** names the record directory, default `.claude/run/gates`. It must be relative, git-ignored, free of tracked files, and free of symlinks, or both scripts refuse it. Records are `0600` in a `0700` directory.
- **The `Quality gate:` line carries the record.** On a machine-recorded run it names the tree and the record path next to the command, the verdict, and the head SHA, so a reader finds the evidence instead of trusting the sentence.

What the exit code tells the caller:

| Exit | `run-gate.sh` | `verify-gate.sh` | The caller |
|---|---|---|---|
| `0` | passed, or taken over from a valid record | the record is valid and `gate-fresh` passed | treats the gate as green for this tree |
| `4` | the gate or `gate-fresh` failed | — | resolves the problem, commits, and runs the gate again |
| `10` / `11` / `12` | — | missing / failed / stale, with the reason | runs `run-gate.sh --tier full`, or stops; never merges on it |
| `3` | refused | refused | stops and reports the reason; never runs the commands another way and never merges on it |
| `1` / `2` | usage error / `git` or `jq` missing | usage error, including an invalid or unknown `<sha>` / `git` or `jq` missing | handled like `3`: stops and reports the reason; never merges on it |
| `5` | not configured | not configured | follows the built-in path of this file unchanged |
| `6` | a live run holds the lock | — | stops and reports; never runs a second gate beside it |
| `7` | the tree is not clean | — | commits the change, then runs the gate |

Any other non-zero exit code is handled like `3`. A code the table does not list is never a pass.

A project whose manifest sets none of `pr-gate`, `gate-fresh`, and `gate-evidence` gets exit `5` and keeps the textual record exactly as before. Run the scripts unconditionally; the exit code says which path applies.

**Trust model.** The record is a local cache on one machine and one account. A public commenter cannot write it, so it is stronger than a textual line in a comment. The code the gate runs — tests and Composer scripts from the branch — runs under the same account and can forge a record, exactly as it can already make its own gate pass. The defence against hostile branch code is code review, required CI, and a fresh `gate-fresh` run, never the record. The SHA-256 of the log detects a damaged or swapped log; it does not prove that the log is authentic. A record from another machine is missing, and the gate runs again.

**The gate scripts come from the package install, not from the branch.** The copy of `run-gate.sh`, `verify-gate.sh`, `gate-record.sh`, and `project-commands.sh` that runs is the copy the installer wrote from `vendor/pekral/ai-olympus`. A project that tracks its installed skills carries that copy in the branch, so a branch can change it, and the merge runs it on the checked-out head. A diff that changes an installed copy of one of these four scripts is therefore a change to the merge gate. Review it under `@rules/security/general.md` *Code Review Application* at severity **Critical**, never as an ordinary script edit.

## Rebase that moves the head — analyse the incoming changes first

A rebase onto the newest default branch gives the head a new SHA. The branch's own change can stay identical while only the base moved. Re-running the full gate in that case repeats every checker for changes the branch never touched, and it delays the finish of the task. Analyse what the rebase brought in before you decide.

1. **Find the last green gate run.** Take the head SHA `G` (a 40-character hex SHA; anything else means no record) from the `head` of a machine gate record that `verify-gate.sh` accepts for `G` (*Machine gate record* above), or from the trusted `Quality gate:` record (the four authenticity conditions in `@skills/merge-github-pr/SKILL.md` *Pre-merge quality gate* apply to it). `H` is the current head. No trusted record, or `G` is not available locally or by `git fetch origin <G>` → run the gate.
2. **Compare the branch's own change.** Compute the effective-PR-diff fingerprint (`@rules/code-review/general.md` *Incremental Review Scope*) for `G` against its merge base and for `H` against its merge base. A different fingerprint means the branch's own change moved → run the gate, exactly as before.
3. **List the incoming changes.** `git diff --name-only "$(git merge-base G origin/$DEFAULT_BRANCH)" "$(git merge-base H origin/$DEFAULT_BRANCH)"` lists what the default branch brought in.
4. **Classify each incoming change as related or unrelated.** An incoming change is **related** when any of these holds:
   - it touches a file the PR changes, or the rebase had a conflict;
   - it changes code the PR's changed code calls, extends, or is called by, or a test that covers the PR's changed code;
   - it falls into the area the assignment describes;
   - it has a project-wide effect: a dependency manifest or lockfile, a tool or checker configuration, a test bootstrap or shared test helper, a CI workflow, or an environment or build file.

   Search the PR's changed symbols in the incoming files and the incoming symbols in the PR's files; never classify from file names alone. When the classification is unclear, the change is related.
5. **Related → the rebase behaves exactly as before.** Run the full gate on `H` (*A history rewrite re-runs the gate* in `@rules/git/general.md`).
6. **Unrelated and CI green on `H` → carry the gate verdict forward.** CI must have run and passed on `H` itself; when it did not run (the billing exception included), run the gate. Do not run the fixers, checkers, or coverage again on `H`. Run only the dependency advisory audit (for example `composer audit`, or the manifest `gate-fresh` commands), because its verdict depends on when it ran. Record in the merge report: `G`, `H`, both fingerprints, the incoming file list, and the reason each change is unrelated.

The trade, stated rather than hidden: the combined tree `H` is not re-tested as a whole. The default branch's own gate covers the incoming changes, and the analysis above covers their interaction with the branch. A related change, an unclear one, or a changed fingerprint always takes the full gate.

**`security-audit` is never reused by anything.** `composer audit` queries a live advisory database at run time, so a green verdict is a function of *when* it ran, not only of *what* it read. It runs fresh on every gate execution, and on a machine-recorded gate it is the default `gate-fresh` command (*Machine gate record* above).
