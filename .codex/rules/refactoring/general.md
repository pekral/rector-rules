---
description: Shared definition of refactoring (legacy → modern architecture). Applies to refactoring skills and code review whenever refactoring is in scope.
paths:
  - ".claude/rules/refactoring/**"
---

## What Refactoring Is
- Refactoring is a **behavior-preserving change of code structure**.
- The application keeps doing the same thing; only how it does it changes.
- Goals: readability, structure, and readiness for further development.
- Refactoring is **technical debt reduction**, not a feature.

## Behaviour stays identical — bugs included

A refactoring-only change keeps every observable behaviour of the code it restructures, including behaviour that is wrong. A change is refactoring-only when its assignment asks for a structural change and names no behaviour change.

- **A bug stays a bug.** Return values, exceptions, persisted data, emitted events, side effects, response contracts, ordering, rounding, and edge-case results stay identical. A wrong result, an inconsistency between two code paths, and a race condition are part of that behaviour. The refactoring does not fix them — not in the refactor commit, and not in a separate commit of the same pull request.
- **Why the fix waits.** A refactoring pull request is reviewed and merged on one claim: nothing changed. A fix inside it breaks that claim:
  1. The pre-existing tests stop being the proof, because one of their assertions has to change.
  2. A consumer that depends on the old result breaks, and nothing announces it.
  3. A revert of the refactoring also reverts the fix.

  A fix gets its own failing test, its own review, and its own release note.
- **Every discrepancy becomes a follow-up issue.** A discrepancy is a bug, an inconsistency between two code paths, code that contradicts its name, its test, or its documentation, a race condition, or a security weakness. The run that finds it files it in the originating tracker before it reports completion, per `@rules/compound-engineering/tracker.md` *File deferred points as follow-up tracker issues* — a preserved discrepancy always clears the filing bar there. The issue states the current behaviour, the expected behaviour, a reproducer, the location before and after the refactoring, and a link to the refactoring pull request. The pull request lists each discrepancy under `## TODO` with its issue URL.
- **A security weakness keeps the security floor.** The refactoring does not fix it either. It is filed under `agents/leonardo.md` *Never disclose an unfixed vulnerability on a public tracker* and fixed in its own pull request. A finding that meets the S1–S3 carve-out of `@rules/code-review/general.md` still blocks the refactoring's merge, so that fix merges first.
- **An assignment that also asks for a behaviour change is not refactoring-only.** Its pre-existing problems follow `@skills/resolve-issue/references/pre-existing-issue-handling.md`.

## Symptoms of Legacy Code
- Large methods (e.g. controllers doing everything).
- Mixed validation, business logic, and persistence in one place.
- Code duplication.
- Poor testability.
- Hidden bugs and race conditions.

## What Refactoring Brings
- Faster delivery of new features.
- Fewer bugs and regressions.
- Better readability.
- Easier onboarding.
- The ability to scale both the application and the team.

## Core Rule
- **Never** do a big-bang rewrite.
- **Always** migrate incrementally, one piece at a time.

## Recommended Process
1. **Stabilize** — add at least smoke tests. A critical bug found here is filed per *Behaviour stays identical — bugs included* and fixed in its own change, never inside the refactoring.
2. **Identify entry points** — start at controllers, jobs, commands, listeners, Livewire components.
3. **Introduce the Action pattern** — keep entry points thin; delegate orchestration to Actions. Simple logic that does not repeat stays in the entry point (`@rules/php/core-standards.md` Design Principles → *Do not create a class for simple logic that does not repeat*).
4. **Split responsibilities** — Action (orchestration), Service (business logic), Repository (read), ModelManager (write).
5. **Modernize code**:
    - raw arrays → DTOs (e.g. Spatie Laravel Data)
    - static helpers → dependency injection
    - fat models → service layer
    - inline validation → Data Validators / FormRequests
6. **Remove duplication** — apply DRY pragmatically, not dogmatically.
7. **Address concurrency** — DB transactions, `lockForUpdate`, atomic operations instead of read-modify-write on shared state. A race condition changes behaviour when it is fixed, so a refactoring-only change keeps the existing transaction and locking semantics and files the race per *Behaviour stays identical — bugs included*.
8. **Split oversized HTML / Blade layouts** — when the refactor touches a Livewire / Blade view, analyze its HTML as a tree of UI concerns and split it into the smallest set of reusable Livewire and Blade components per `@rules/laravel/livewire.md` *HTML / Blade Layout Splitting*. Treat the layout split as a structural refactor: the **Test Coverage Contract** below applies in spirit — every rendered branch of the touched view must be exercised by a Livewire / Blade feature test that stays green through the refactor commit unchanged, since PHP `--coverage-clover` does not measure `.blade.php` line-by-line. See the rule's *Process for splitting an existing view* step 6 for the binding wording.

## When to Refactor
- Changes are slow and painful.
- The code is unreadable.
- The team is afraid to touch it.
- The same bugs keep coming back.

## When Not to Refactor
- Just to make the code "look nice".
- Without a business reason.

## Reality Check
- Refactoring does not deliver immediate business value.
- Without it, however:
    - delivery slows down,
    - technical debt grows,
    - error rate increases.
- Refactoring is an investment in future delivery speed and system stability.

## Test Coverage Contract (mandatory)

Refactoring is behavior-preserving by definition, so behavior preservation must be **proven** by a test suite that exists **before** the structural change lands. Every refactor must respect the following four-step contract:

1. **Before the refactor commit — verify 100% coverage of the target lines.** Verify coverage of the *current* code that is about to be refactored, using the project's available coverage tooling scoped to those files (see `@rules/php/core-standards.md` Testing section). Every line, branch, and condition the refactor will touch must already be exercised by tests. If coverage is below 100% on those lines, **stop and write the missing tests first**.
2. **Add missing tests in a dedicated commit before the refactor commit.** This contract recommends this commit split and the post-refactor test commit in step 3; `@rules/git/general.md` *Commit granularity* otherwise leaves commit division to the author. The new tests live in their own commit using the `test(scope): cover <area> before refactor` form per `@rules/git/general.md` Allowed Types. Keep new test code out of the refactor commit — the separation is what makes the safety net auditable. **Authoring guidance only; not verified by review** — see *What the review no longer verifies* below.
3. **The refactor commit must not modify pre-existing tests.** Once the safety net is in place, the refactor commit changes structure only. Renaming, restructuring, or rewriting tests that existed before the refactor invalidates the proof that behavior was preserved. The only test changes allowed in the refactor commit are those forced by mechanical renames the refactor itself introduces (e.g. moving a class to a new namespace), and even those must be flagged in the commit body. New tests that *cover newly introduced code paths in the refactor* belong in yet another commit after the refactor — not in the refactor commit and not in the pre-refactor coverage commit. **Authoring guidance only; no longer verified by review** — see *What the review no longer verifies* below.
4. **After the refactor commit — re-verify coverage of the changed lines is still 100%.** Run the project's coverage tooling again, scoped to the refactored files, and confirm every line, branch, and condition the refactor touched is still exercised. The pre-existing assertions must pass unchanged *and* coverage must not have regressed. If a refactored line is no longer covered, the refactor introduced an untested path (typically dead code or a new branch) — fix it before finishing, do not paper over it by editing the pre-refactor tests. This proactive re-verification is part of the apply step, not only a code-review check.

### What the review no longer verifies — and what that costs

The code review does not walk commit history (`@rules/code-review/core-analysis.md` *Refactoring test-coverage contract*). Steps 2 and 3 above are commit-history claims — a dedicated test commit exists **before** the refactor commit, and the refactor commit touches **no** pre-existing test file — so nothing verifies them. They stay in this contract because they are how a refactor should be authored; they are not a gate.

**What is lost, stated rather than hidden: the proof that behaviour was preserved across the refactor.** That proof was never the coverage number. It was the ordering — tests written against the *old* structure, passing unchanged after the new one, with no opportunity to quietly adjust an assertion that the refactor broke. A refactor that rewrites a test in the same commit and reports 100% coverage now passes review, and the review cannot tell it apart from one that preserved behaviour. Only the author's own discipline stands between the two.

Steps 1 and 4 are unaffected. Both read the project's coverage tooling, not the git log, so the review still enforces 100% coverage of every refactored line, branch, and condition — before and after — as a **Critical** finding.

Code review must reject any refactor PR that violates the coverage half of this contract — see the **Code Review Application** section below for the enforcement rules.

## Code Review Application
- Treat this definition as authoritative when reviewing or proposing refactoring.
- Flag big-bang rewrites and mixed-responsibility entry points as findings.
- Prefer incremental migration over wholesale rewrites in suggested fixes.
- **A Suggested Fix that proposes a refactoring is behaviour-neutral, and the finding says so.** This covers every finding on every pull request whose Suggested Fix restructures code: an extraction, a split, a rename, a move, a consolidation, or a collapse.
  1. Before the finding is published, compare the current code with the proposed code path by path. Use the list of *Behaviour stays identical — bugs included*: inputs, return values, exceptions, persisted data, emitted events, side effects, query results, ordering, rounding, and edge-case results.
  2. When every item stays identical, the Suggested Fix ends with the sentence *"The proposed change is behaviour-neutral."*, written in the report language (Czech: *"Navrhovaná změna je z hlediska chování neutrální."*).
  3. When an item changes, the proposal is not a refactoring. Rewrite it until it is behaviour-neutral, or name each behaviour change it brings in the Suggested Fix and leave the sentence out. On a refactoring-only pull request, such a proposal is filed as a follow-up issue instead, per *Behaviour stays identical — bugs included*.
  - Never write the sentence for a comparison this run did not perform (`@rules/general/general.md` *Verified statements only*).
- **On a refactoring-only pull request, behaviour preservation is the primary check.** Run it before every other lens and spend most of the review on it. For each unit the diff restructures, compare the old code on the base branch with the new code, path by path. Check that the inputs, return values, exceptions, persisted data, emitted events, side effects, query results, ordering, rounding, and edge-case results stay identical. Every other lens still runs, but none of them replaces this comparison.
- **On a refactoring-only pull request, a behaviour change is a Moderate finding — a bug fix included.** The Suggested Fix restores the old behaviour and files the fix as a follow-up issue per *Behaviour stays identical — bugs included*.
  - The finding blocks the merge like every undeferred Moderate. It is never deferred at the cap round — neither to a sub-issue nor by linking an existing issue — because restoring the old behaviour is always possible inside the pull request.
  - A behaviour change that also meets the S1–S3 carve-out of `@rules/code-review/general.md` keeps its security severity.
  - **Gating — one finding per behaviour change.** This bullet raises it once, on the changed line. `@rules/code-review/core-analysis.md` *Behaviour changed outside the diff* does not raise it again per affected caller: each affected caller stays an entry in `## Affected behaviour outside the diff`. The Assignment Conformance Gate (`@skills/code-review/references/assignment-conformance-gate.md`) does not raise it again either.
- **A discrepancy the refactoring carries over with identical behaviour is not a finding at its own severity.** The pull request is forbidden to fix it, so a finding that asks for the fix can never converge. Settle it by filing instead:
  - When the pull request's `## TODO` links a follow-up issue for it, list it under `## Deferred to sub-issues` with that URL.
  - When no follow-up issue exists, raise one **Moderate** finding: the discrepancy is not filed. Its Suggested Fix files the issue and changes no code.
  - A finding that meets the S1–S3 carve-out keeps its severity and blocks the merge, per the security bullet of *Behaviour stays identical — bugs included*.
- **Enforce the coverage half of the Test Coverage Contract above on every refactor PR.** Verify with the project's available coverage tooling, scoped to the changed files, that every refactored line, branch, and condition reports 100% coverage. Sub-100% coverage on the changed lines is a **Critical** finding.
- **Do not check (a) that a dedicated test commit precedes the refactor commit or (b) that the refactor commit modifies no pre-existing test file.** Both read the PR's commit history, which the review does not walk; *What the review no longer verifies* above states what that costs.
- For Laravel projects, combine this rule with `@rules/laravel/architecture.md` (Action pattern, Repositories, ModelManagers, Data Validators, DTOs).
