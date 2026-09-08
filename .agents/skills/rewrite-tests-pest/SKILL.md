---
name: rewrite-tests-pest
description: "Use when rewriting existing tests to Pest syntax. Preserve behavior, follow project testing conventions, reduce duplication where helpful, and verify rewritten tests are deterministic and passing."
license: MIT
metadata:
  author: "Petr Král (pekral.cz)"
---

## Constraints
- Apply `@rules/php/core-standards.md`
- Apply `@rules/code-testing/general.md`
- If the current project uses Laravel, also apply `@rules/laravel/laravel.md`, `@rules/laravel/architecture.md`, `@rules/laravel/filament.md`, and `@rules/laravel/livewire.md`
- Do not generate `covers()`

## Use when
- Existing tests are written in PHPUnit-style syntax and should be rewritten to Pest
- You want to modernize tests without changing their intended behavior

## Required approach
- Preserve test intent and coverage of the rewritten behavior
- Keep tests deterministic and non-flaky
- Prefer simple, readable Pest syntax
- Use helper methods or datasets when they clearly reduce duplication
- Avoid reflection; prefer mocks or partial mocks when readable and effective
- Avoid branching in tests; prefer separate test cases or datasets instead

## Read, Map & Verify before rewriting (mandatory pre-flight)

Reading, mapping, and verifying come first; rewriting comes last. This pre-flight is **blocking** — do not rewrite a single line until all three steps pass, and never act on an assumption you have not confirmed by reading the code.

1. **Read** — open and read the actual tests being rewritten and the code they exercise (the system under test, shared setup, helpers, datasets). Confirm what each test asserts by reading it, not by guessing from its name.
2. **Map** — map the change's blast radius: every assertion and covered code path that must survive the rewrite, the shared setup/helpers to reuse, and the project's existing Pest conventions.
   Then run a **completeness sweep** over the whole tree. Grep the entire repository for every name, helper, dataset, and convention the rewrite renames, removes, or redefines, and every test path that references them — never only the files the assignment names, and never only the files you have already opened.
   Cover every file category the repository carries: source, tests, `rules/`, `skills/`, `agents/`, documentation, configuration, and generated assets such as `CHANGELOG.md` or `README.md`. Record the full match list before you rewrite the first test, then classify each match as in scope for this rewrite or as a stated exception. An incomplete sweep leaves a PHPUnit-era helper referenced by a file nobody opened, so the rewritten tests pass here while that file stops running.
3. **Verify** — run the existing tests first and confirm they pass, so you rewrite from a known-green baseline. If the original behavior or coverage is unclear, stop and clarify instead of rewriting on a wrong premise.

Only after Read, Map, and Verify are complete may the rewrite begin.

## Execution
1. Identify existing tests that should be rewritten to Pest syntax.
2. Analyze repeated setup and assertions before rewriting.
3. Rewrite tests to Pest syntax without changing covered behavior.
4. Use datasets/data providers where they simplify similar test cases.
5. Move broadly shared lightweight test helpers to `Pest.php` when it improves clarity and reuse.
6. If a Pest test needs to call a helper method defined on the test case for abstract-class scenarios, use `test()->methodName()`.
7. Keep tests structured and easy to read, with arrange / act / assert flow per `@rules/php/core-standards.md` Testing (mandatory; see the canonical rule for the exception list).
8. Separate success and failure scenarios into distinct test cases where practical.
9. Run the rewritten tests and confirm they pass consistently.
10. Simplify nearby similar tests only when the cleanup is small, safe, and clearly improves maintainability.

## Post-rewrite validation
1. Run all rewritten tests and confirm they pass.
2. Verify 100% code coverage for all rewritten test paths — if coverage tooling exists, run it.
3. Discover available fixers and checkers (prefer Phing targets from `build.xml`/`phing.xml`; fall back to Composer scripts in `composer.json`).
4. Run available fixers on changed test files and fix any violations.
5. Run available checkers/analyzers on changed test files and resolve all reported errors.
6. Run a quick code review of rewritten tests against `@rules/code-testing/general.md` and fix any findings.

## Done when
- Target tests are rewritten to Pest syntax
- Rewritten tests preserve original intent and behavior
- Tests are deterministic and pass reliably
- 100% code coverage is verified for rewritten code paths
- Code style and quality checks pass (fixers and checkers ran clean)
- Test review passed with no findings
- Duplication is reduced where it meaningfully improves readability
- Shared lightweight helpers are extracted appropriately
- The rewritten tests follow project testing conventions

## Output Humanization
- Use [blader/humanizer](https://github.com/blader/humanizer) for all skill outputs to keep the text natural and human-friendly.
