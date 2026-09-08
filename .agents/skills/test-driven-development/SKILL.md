---
name: test-driven-development
description: "Use when implementing a feature or bugfix with strict TDD. Enforce failing-test-first, minimal implementation, and safe refactoring."
license: MIT
metadata:
  author: "Petr Král (pekral.cz)"
---

## Constraints
- Apply `@rules/php/core-standards.md`
- Apply `@rules/code-testing/general.md`
- If the current project uses Laravel, also apply `@rules/laravel/laravel.md`, `@rules/laravel/architecture.md`, `@rules/laravel/filament.md`, and `@rules/laravel/livewire.md`
- Follow test conventions from `@skills/create-test/SKILL.md`

## Core principle
If you did not watch the test fail, you do not know whether it tests the right thing.

## Iron law
`NO PRODUCTION CODE WITHOUT A FAILING TEST FIRST`

## Use when
- Implementing a new feature
- Fixing a bug
- Changing behavior
- Refactoring code that should remain behaviorally stable

## Read, Map & Verify before the first RED (mandatory pre-flight)

Reading, mapping, and verifying come first; implementing comes last. This pre-flight is **blocking** — do not add or modify a single line of production code until all three steps pass, and never act on an assumption you have not confirmed by reading the code.

1. **Read** — open and read the actual target files and the code they depend on (callers, called methods, related tests, configuration). Confirm what the code does by reading it, not by guessing from names or the assignment description.
2. **Map** — map the change's blast radius: every call site, caller, data-flow path, and existing test that the behavior touches, plus the conventions and helpers already in the codebase to reuse instead of reinventing.
   Then run a **completeness sweep** over the whole tree. Grep the entire repository for every name, pattern, convention, and section title the behavior change renames, removes, or redefines — never only the files the assignment names, and never only the files you have already opened.
   Cover every file category the repository carries: source, tests, `rules/`, `skills/`, `agents/`, documentation, configuration, and generated assets such as `CHANGELOG.md` or `README.md`. Record the full match list before the first RED test, then classify each match as in scope for this cycle or as a stated exception. An incomplete sweep hides a call site the cycle never covers, so GREEN reports done while that path still runs the old behavior.
3. **Verify** — check your assumptions against the real code and its observed behavior (reproduce the current behavior so the first RED test asserts the real gap). If what you read contradicts the assignment framing, stop and surface the discrepancy instead of writing a test on a wrong premise.

Only after Read, Map, and Verify are complete may the first RED test be written.

## Pre-flight (mandatory before the first RED)

Before writing the first failing test, run `@skills/prepare-issue-context/SKILL.md` with `MODE=tdd` and the assignment reference, scoped to the scenario(s) the upcoming RED step will cover. The skill seeds the development database with the records the failing test will depend on and captures a reproduction record (entry point + inputs + observed output) that becomes the *arrange* block of the first test. If the skill returns `blocked: <count> open gap(s)`, stop and surface the gaps — writing a RED test against missing or guessed fixtures is the most common cause of stub-grade tests that drift from real behavior.

## Required cycle

### 1. RED
Write one minimal test for the next behavior.
- Keep the test focused and readable
- Prefer real code paths; mock only where appropriate by project testing rules
- Do not generate `covers()`

### 2. VERIFY RED
Run the test and confirm:
- it fails
- it fails for the expected reason
- it is not failing because of syntax, setup, or typo issues

If the test passes immediately, it does not prove the new behavior.

**RED is a state of the working tree, never a commit.** Watch the test fail, then go to GREEN and commit the failing test together with the change that makes it pass. Committing the RED state — or a test written to fail so a later commit can "fix" it — leaves a commit that no one can cherry-pick or deploy, which `@rules/git/general.md` *The merged head is green; intermediate commits are not gated* forbids at **Critical** severity — that obligation survives the gate deferral unchanged, because it is about not encoding a lie in the history, not about where the gate runs. The cycle below is unchanged; only the commit boundary is.

### 3. GREEN
Write the smallest production change needed to make the test pass.
- Do not add extra features
- Do not broaden scope
- Do not refactor unrelated code yet

### 4. VERIFY GREEN
Run the relevant tests and confirm:
- the new test passes
- affected existing behavior still passes

### 5. REFACTOR
Only after green:
- remove duplication
- improve naming
- simplify code
- keep behavior unchanged

### 6. REPEAT
Move to the next behavior and repeat the cycle.

## Bug-fix rule
Never fix a bug without first writing or updating a test that reproduces it.

## Scope control
- Fix obvious blocking issues only when necessary for safe implementation
- Keep unrelated cleanup out of scope unless it is trivial and low risk

## Post-cycle validation
1. Verify 100% code coverage for all changed or added code paths — if coverage tooling exists, run it.
2. Discover available fixers and checkers (prefer Phing targets from `build.xml`/`phing.xml`; fall back to Composer scripts in `composer.json`).
3. Run available fixers on changed files and fix any violations.
4. Run available checkers/analyzers on changed files and resolve all reported errors.
5. Run a quick code review of all tests written during the TDD cycle against `@rules/code-testing/general.md` and fix any findings.

## Done when
- Every implemented behavior is backed by a test
- Each new test was observed failing before implementation
- Production code was added only to satisfy failing tests
- Changed behavior, edge cases, and failure paths are covered
- Relevant tests pass
- 100% code coverage is verified for all changes
- Code style and quality checks pass (fixers and checkers ran clean)
- Test review passed with no findings
- Refactoring did not introduce new behavior

## Output Humanization
- Use [blader/humanizer](https://github.com/blader/humanizer) for all skill outputs to keep the text natural and human-friendly.
