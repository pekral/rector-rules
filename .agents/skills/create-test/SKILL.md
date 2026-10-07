---
name: create-test
description: Use when creating or updating tests for current changes. Writes the minimum tests that protect the changed behaviour, risk, or contract at its owner boundary, then verifies full coverage of the changed code.
license: MIT
metadata:
  author: Petr Král (pekral.cz)
---

## Constraints
- Apply @rules/code-testing/general.md
- If the current project uses Laravel, also apply `@rules/laravel/laravel.md`, `@rules/laravel/architecture.md`, `@rules/laravel/filament.md`, and `@rules/laravel/livewire.md`
- Do not modify production code unless strictly required — the only exception is the **Pre-existing issue handling** workflow below, which lands its production-code fixes in their own separate commits
- Prefer the project's existing E2E path for user-visible or cross-boundary behavior. An isolated test is allowed only when it was designed before the production change, after a written failure inventory, per `@rules/code-testing/general.md` *Test Strategy*.
- Run the authoring gate of `@skills/test-audit/SKILL.md` (`MODE=authoring`) before you write or change a test. **Coverage alone is never sufficient justification for creating a test.** Coverage stays the validation step at the end.

---

## Read, Map & Verify before writing tests (mandatory pre-flight)

Reading, mapping, and verifying come first; writing tests comes last. This pre-flight is **blocking** — do not add or modify a single line until all three steps pass, and never act on an assumption you have not confirmed by reading the code.

1. **Read** — open and read the actual code under test and the code it depends on (callers, called methods, related existing tests, configuration). Confirm what the code does by reading it, not by guessing from names or the change description.
2. **Map** — map the change's blast radius: every changed code path, its call sites, the data-flow branches a test must exercise, and the existing test conventions, helpers, and fixtures to reuse instead of reinventing.
   Then run a **completeness sweep** over the whole tree. Grep the entire repository for every name, pattern, and behavior the code under test exposes, and every test path, helper, and fixture that already exercises it — never only the files the assignment names, and never only the files you have already opened.
   Cover every file category the repository carries: source, tests, `rules/`, `skills/`, `agents/`, documentation, configuration, and generated assets such as `CHANGELOG.md` or `README.md`. Record the full match list before you write the first test, then classify each match as in scope for this test change or as a stated exception. An incomplete sweep duplicates a fixture that already exists in a directory nobody opened, or leaves a sibling test still asserting the behavior this change replaced.
3. **Verify** — check your assumptions against the real code and its observed behavior (run the code path or an exploratory assertion where applicable). If what you read contradicts the change description, stop and surface the discrepancy instead of writing tests on a wrong premise.

Only after Read, Map, and Verify are complete may test-writing begin.

---

## Execution

### 1. Analyze Context
Follow this order:

1. Identify the behaviour, risk, or contract the change carries.
2. Find its strongest owner boundary (`@skills/test-audit/SKILL.md` *Owner boundary*).
3. Check the existing tests of that behaviour; extend one before you add one.
4. Write the minimal test that passes the authoring gate.
5. Verify changed-code coverage (step 5).

### 2. Create or Update Tests
- Prefer updating existing tests
- Create new tests only if necessary
- Follow project conventions and helpers
- **Place new test files per `@rules/code-testing/general.md` *Test Organization*** — the test file path mirrors the namespace of the SUT (e.g. `App\Service\Billing\InvoiceCalculator` → `tests/Service/Billing/InvoiceCalculatorTest.php`), the file name is `{ClassName}Test.php` (or `{ClassName}{Scenario}Test.php` for an extracted scenario file of the same SUT), and cross-cutting tests sit under an intent-named directory (`tests/Feature/<flow>`, `tests/Contract/<vendor>`, `tests/Integration/<area>`).
- **Name every `it()` / `test()` block to match the scenario the body asserts** — plain-language descriptions such as `it('returns zero for an empty cart')` or `test('throws InvalidArgumentException when the discount is negative')`. Never use placeholders (`it('it works')`, `test('test1')`, `test('happy path')`), method names (`test('calculate')`, `it('handles getUser')`), or descriptions that contradict the assertions. When changing what a test asserts, rename the description in the same change so the code-review test-organization gate passes downstream.
- **Invoke a job under test with `app()->call([$job, 'handle'])` per `@rules/code-testing/general.md` *Jobs*** — construct the job with the payload the test controls and let the container resolve the `handle()` dependencies. Never hand-build doubles and pass them to `handle()` directly; when a collaborator genuinely cannot run in the test, swap its container binding (`$this->app->instance(...)`, `Http::fake()`, `Process::fake()`) and leave the call site unchanged.
- **Structure every test body arrange-act-assert per `@rules/php/core-standards.md` Testing** — phases in order (setup → action → assertions), separated by blank lines, never by `// Arrange` / `// Act` / `// Assert` comments; see the canonical rule for the exception list.

### 3. Cover the Changed Behaviour
- Cover each changed behaviour once, at its owner boundary: the happy path, each edge case with a credible regression, and a regression scenario only for a genuine observable behavior gap
- An uncovered changed line is resolved per `@skills/test-audit/SKILL.md` *Coverage* — a behavioural test, a report that the line is removable code, or an explicit conflict report

### 4. Validate
- Run relevant tests after each change and confirm they pass
- Ensure deterministic behavior
- Remove flakiness

### 5. Verify Coverage
- Ensure 100% code coverage for all changed or added code paths
- If coverage tooling exists, verify coverage **for the changed files only**, using the project's available coverage tooling (per the Coverage gate in `@skills/code-review/SKILL.md`) and verify the result. Do not gate on a project-wide coverage percentage — full-suite coverage is for release gates, not for verifying current changes. Delete any generated coverage report file once read so it is not accidentally committed.

### 6. Quality gates — not run here
- Do not run fixers or checkers in this skill. The project's gate runs once at the merge boundary (`@skills/resolve-issue/references/quality-gates.md` *Gate placement — deferred to the merge boundary*).

### 7. Test Review
- Check every created or updated test against the *Junk patterns* of `@skills/test-audit/SKILL.md` and `@rules/code-testing/general.md`
- Fix any findings before finalizing

### 8. Pre-existing issue handling

While writing tests, you may uncover problems that are **unrelated to the current change** but were already present in the code you had to read or exercise. The following categories qualify:

- **Bugs** — incorrect logic, broken edge cases, or runtime errors revealed by exploratory test runs, but already present before this task.
- **Project-rule violations** — code that contradicts any rule listed in this skill's *Constraints* block or any other rule under `.claude/rules/`.
- **Security vulnerabilities** — anything `@rules/security/backend.md`, `@rules/security/frontend.md`, or `@rules/security/mobile.md` would flag.

Rules:

1. **Do not silently ignore** a pre-existing issue you encountered in code you had to read or exercise to write the tests for the current change.
2. **Do not expand scope** by actively scanning unrelated files for pre-existing issues. Limit attention to files already touched or exercised by the current change.
3. Land each pre-existing fix (and its regression test) in its **own separate commit**, distinct from the test-coverage commit for the current change:
   - Use a Conventional Commits subject per `@rules/git/general.md`: `fix(<scope>): pre-existing — <description>` for bugs and security, `refactor(<scope>): pre-existing — <description>` for rule violations without behavior change.
   - The `pre-existing — ` prefix is mandatory so reviewers can identify these commits at a glance.
   - **Test coverage workflow depends on the commit type:**
     - `fix(<scope>): pre-existing — …` (bug, security) — add the regression test in the **same commit** as the fix; the test must fail before the fix lands and pass after.
     - `refactor(<scope>): pre-existing — …` (project-rule violation, behavior-preserving) — apply `@rules/refactoring/general.md` *Test Coverage Contract*: when the target lines are below 100% coverage, author a dedicated `test(<scope>): cover <area> before pre-existing refactor` commit **before** the refactor commit, and do **not** modify pre-existing tests inside the refactor commit (mechanical renames forced by the refactor itself stay exempt and must be flagged in the commit body).
4. The "Do not modify production code unless strictly required" constraint above is **overridden** for these fixes — the production-code change is the fix itself, and it lives in its own commit.
5. If a pre-existing issue is **non-trivial** (would significantly expand the change or requires architectural discussion), do **not** fix it. Surface it in the skill's output report as a deferred follow-up with the reason.

---

## Output

- Created or updated test files
- The authoring-gate record: one line per new or changed test (what it protects, the regression it catches, its owner boundary, its overlap)
- Coverage status for current changes (must be 100%; a reported conflict or removable line leaves the gate open)
- Test review result
- List of pre-existing fix commits (if any), each with a one-line rationale, plus any pre-existing issue deferred as a follow-up with the reason

---

## Principles

- Prefer updating existing tests over creating new ones
- Keep tests simple and deterministic
- Cover behavior, not implementation
- Focus on changed code only
- Follow project test conventions strictly
- Minimum tests, maximum confidence
- Use data providers where they improve readability and reduce duplication
- Keep tests readable and maintainable

## Output Humanization
- Use [blader/humanizer](https://github.com/blader/humanizer) for all skill outputs to keep the text natural and human-friendly.
