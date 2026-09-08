---
name: create-missing-tests-in-pr
description: Use when a PR review already exists and missing tests must be completed with 100% coverage for current changes. Reads the pull request code review, verifies that all recommended test coverage is implemented in the codebase, and adds missing tests using the create-test skill.
license: MIT
metadata:
  author: Petr Král (pekral.cz)
---

## Constraints

-   Apply @rules/php/core-standards.md
-   Apply @rules/git/general.md
-   Apply @rules/code-testing/general.md
-   If the current project uses Laravel, also apply `@rules/laravel/laravel.md`, `@rules/laravel/architecture.md`, `@rules/laravel/filament.md`, and `@rules/laravel/livewire.md`
-   If you are not on the main git branch in the project, switch to it.
-   This task is based on the existing pull request review.
-   First read your existing code review for the current pull request
    and identify all testing recommendations related to current changes.
-   Never change the assignment scope.
-   Only add or modify tests when needed.
-   Production code may only be changed if it is strictly required by
    the existing create-test skill or test infrastructure, otherwise do
    not modify it — the only exception is the **Pre-existing issue
    handling** workflow below, which lands its production-code fixes in
    their own separate commits.
-   Use @skills/create-test/SKILL.md for all test-writing work.

---

## Read, Map & Verify before writing tests (mandatory pre-flight)

Reading, mapping, and verifying come first; writing tests comes last. This pre-flight is **blocking** — do not add or modify a single line until all three steps pass, and never act on an assumption you have not confirmed by reading the code.

1.  **Read** — open and read the actual changed code and the code it depends on (callers, called methods, related existing tests, configuration). Confirm what the code does by reading it, not by guessing from the review text or names.
2.  **Map** — map the change's blast radius: every uncovered code path the review flagged, its call sites, the branches a test must exercise, and the existing test conventions, helpers, and fixtures to reuse instead of reinventing.
    Then run a **completeness sweep** over the whole tree. Grep the entire repository for every name, pattern, and convention the flagged code path touches, and every test path, helper, and fixture that already exercises it — never only the files the assignment names, and never only the files you have already opened.
    Cover every file category the repository carries: source, tests, `rules/`, `skills/`, `agents/`, documentation, configuration, and generated assets such as `CHANGELOG.md` or `README.md`. Record the full match list before you add the first missing test, then classify each match as in scope for this batch of missing tests or as a stated exception. An incomplete sweep re-adds coverage that already exists elsewhere in the tree, or closes the review item while a sibling call site of the same code path stays untested.
3.  **Verify** — check your assumptions against the real code and its observed behavior, and confirm each recommended test does not already exist before adding it. If what you read contradicts the review recommendation, surface the discrepancy instead of writing tests on a wrong premise.

Only after Read, Map, and Verify are complete may test-writing begin.

---

## Execution

-   Load the current pull request context using GitHub CLI (`gh`) first.
    If `gh` is not available, use a GitHub MCP server. If neither is
    available, stop and return a failed result about missing GitHub tools.
-   Read your existing code review for the pull request.
-   Extract all recommendations related to missing tests, missing
    scenarios, edge cases, regression coverage, and coverage gaps.
-   **Take the data a finding names verbatim.** When a finding's **Test Hint** carries concrete values from the assignment — an input value, a
    payload, a boundary value, an expected output or error message — write the test with exactly those values. Never substitute a rounder number,
    a simplified payload, or an invented equivalent: that value is what reproduces the defect, and replacing it re-opens the finding the review
    raised (`@rules/code-review/review-process.md` *Validation & Coverage Gate*). Reaching the same value through a named fixture or constant is
    fine, and adding further cases beyond the named ones is allowed — the stated data are a minimum, not a ceiling.
-   Analyze the current branch changes against the review findings.
-   Verify whether the recommended tests already exist in the codebase.
-   Check whether current changes have 100% coverage **for the changed files only**, using the project's available coverage tooling (per the Coverage gate in `@skills/code-review/SKILL.md`). Do not gate on the project-wide coverage percentage — if the project ships no coverage tooling at all, stop and report it as a blocker, and **do not add a new bespoke coverage script** to the consuming project.
-   If coverage is incomplete or recommended test scenarios are missing,
    use @skills/create-test/SKILL.md.
-   Follow existing project test conventions, helpers, patterns, and
    abstractions.
-   Prefer updating existing tests first. Create new tests only if
    required.
-   Create deterministic every time!
-   Make sure tests are deterministic and not flaky.
-   In tests, avoid reflection; use mocks instead (even partial ones, if they are effective and easy to read).
-   Tests must not contain conditions (e.g., `if`, `switch`); split conditional logic into separate test cases instead.
-   Use data providers where they improve readability and simplify
    repeated test cases.
-   After adding or updating tests, run only the necessary tests for the
    current changes.
-   If coverage tooling exists, verify that current changes are covered
    with 100% coverage for the changed files only, using the project's available coverage tooling (per the Coverage gate in `@skills/code-review/SKILL.md`) — do not gate on the full-suite coverage percentage. Delete any generated coverage report file once read so it is not accidentally committed.
-   If fixers or test-related wrappers exist in the project, use them (prefer Phing targets from `build.xml`/`phing.xml`; fall back to Composer scripts in `composer.json`).
-   Do not run the whole test suite unless it is required for the
    changed files workflow.
-   If the review recommendation is already satisfied by existing tests,
    do not duplicate test coverage.
-   **Place new test files per `@rules/code-testing/general.md` *Test Organization*** — the test file path mirrors the namespace of the SUT (e.g. `App\Service\Billing\InvoiceCalculator` → `tests/Service/Billing/InvoiceCalculatorTest.php`), the file name is `{ClassName}Test.php` (or `{ClassName}{Scenario}Test.php` for an extracted scenario file of the same SUT), and cross-cutting tests sit under an intent-named directory (`tests/Feature/<flow>`, `tests/Contract/<vendor>`, `tests/Integration/<area>`).
-   **Name every `it()` / `test()` block to match the scenario the body asserts** — plain-language descriptions such as `it('returns zero for an empty cart')` or `test('throws InvalidArgumentException when the discount is negative')`. Never use placeholders (`it('it works')`, `test('test1')`, `test('happy path')`), method names (`test('calculate')`, `it('handles getUser')`), or descriptions that contradict the assertions, so the code-review test-organization gate passes when the PR is re-reviewed.
-   **Structure every test body arrange-act-assert per `@rules/php/core-standards.md` Testing** — phases in order (setup → action → assertions), comments optional; see the canonical rule for the exception list.

### Pre-existing issue handling

While writing the missing tests, you may uncover problems that are **unrelated to the current PR scope** but were already present in the code you had to read or exercise. The following categories qualify:

-   **Bugs** — incorrect logic, broken edge cases, or runtime errors revealed by exploratory test runs, but already present before this task.
-   **Project-rule violations** — code that contradicts any rule listed in this skill's *Constraints* block or any other rule under `.claude/rules/`.
-   **Security vulnerabilities** — anything `@rules/security/backend.md`, `@rules/security/frontend.md`, or `@rules/security/mobile.md` would flag.

Rules:

1.  **Do not silently ignore** a pre-existing issue you encountered in code you had to read or exercise while writing the missing tests.
2.  **Do not expand scope** by actively scanning unrelated files for additional pre-existing issues. Limit attention to files already touched or exercised by the current PR's changes.
3.  Land each pre-existing fix (and its regression test) in its **own separate commit** inside the same PR, distinct from the missing-tests commit:
    -   Use a Conventional Commits subject per `@rules/git/general.md`: `fix(<scope>): pre-existing — <description>` for bugs and security, `refactor(<scope>): pre-existing — <description>` for rule violations without behavior change.
    -   The `pre-existing — ` prefix is mandatory so reviewers can identify these commits at a glance.
    -   **Test coverage workflow depends on the commit type:**
        -   `fix(<scope>): pre-existing — …` (bug, security) — add the regression test in the **same commit** as the fix; the test must fail before the fix lands and pass after.
        -   `refactor(<scope>): pre-existing — …` (project-rule violation, behavior-preserving) — apply `@rules/refactoring/general.md` *Test Coverage Contract*: when the target lines are below 100% coverage, author a dedicated `test(<scope>): cover <area> before pre-existing refactor` commit **before** the refactor commit, and do **not** modify pre-existing tests inside the refactor commit (mechanical renames forced by the refactor itself stay exempt and must be flagged in the commit body).
4.  The "Production code may only be changed if it is strictly required" constraint above is **overridden** for these fixes — the production-code change is the fix itself, and it lives in its own commit.
5.  If a pre-existing issue is **non-trivial** (would significantly expand the PR or requires architectural discussion), do **not** fix it. Surface it in the delivered markdown summary as a deferred follow-up with the reason, and file it as a follow-up issue in the originating tracker per `@rules/compound-engineering/general.md` *File deferred points as follow-up tracker issues* (mechanics in `@skills/resolve-issue/SKILL.md` *Deferred-item follow-up issues*); include the created issue URL in the summary.

### After completing the tasks

-   Discover available fixers and checkers (prefer Phing targets from `build.xml`/`phing.xml`; fall back to Composer scripts in `composer.json`).
-   Run available fixers on all changed test files and fix any violations.
-   Run available checkers/analyzers on all changed test files and resolve all reported errors.
-   Run a quick code review of all added or updated tests against `@rules/code-testing/general.md` and fix any findings.
-   Summarize what testing recommendations from the code review were
    verified.
-   List added or modified test files.
-   Confirm whether current changes now meet the required test coverage (must be 100%).
-   If something is still missing, clearly describe the blocker or
    uncovered scenario.
- Create a new commit with the missing tests, separate from any pre-existing fix commits produced by *Pre-existing issue handling* above

---

## Output

Provide a brief markdown summary including:

-   reviewed PR testing recommendations
-   which recommendations were already covered
-   which tests were added or updated
-   whether 100% coverage for current changes was achieved
-   list of pre-existing fix commits (if any), each with a one-line rationale, plus any pre-existing issue deferred as a follow-up with the reason
-   any blocker preventing full completion

---

## Principles

- Follow code review recommendations strictly
- Data a finding names are copied verbatim, never re-invented
- Do not duplicate existing tests
- Prefer minimal changes for full coverage
- Use data providers where they improve readability and reduce duplication
- Every test change must be verified to pass before moving on
- Focus on changed code only

## Output Humanization
- Use [blader/humanizer](https://github.com/blader/humanizer) for all skill outputs to keep the text natural and human-friendly.
