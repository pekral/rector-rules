---
description: Shared testing conventions for skills that generate or modify tests
paths:
  - "tests/**"
  - "**/tests/**"
  - "**/*Test.php"
---

## Testing Rules

- Follow test conventions from:
    - @rules/php/core-standards.md
    - @rules/laravel/architecture.md (for Laravel projects)

- Write all new tests using Pest syntax (`it()` / `test()` functional blocks). Do not introduce PHPUnit-style class-based tests for new test files.
- When modifying existing PHPUnit tests, prefer rewriting them to Pest via `@skills/rewrite-tests-pest/SKILL.md` rather than extending the legacy class.
- Never use `describe()`; use top-level `it()` / `test()` only.
- Test classes should be `final`.
- Prefer local variables; avoid shared mutable state.
- Never change the visibility of production code so a test can reach it, and never use reflection to call or read a private member. Test through the public method, or extract the logic into its own class — see `@rules/php/core-standards.md` Testing *Never widen visibility for a test*.
- In Laravel Pest projects, define `uses(Tests\TestCase::class)` in `tests/Pest.php` instead of repeating it in every test file.

## Test Strategy

- **Prove behavior end to end first.** For a user-visible or cross-boundary change, use the project's existing browser, HTTP, queue, or CLI E2E path as the primary test. Do not install a test runtime merely to satisfy this rule. An E2E run ends with a repeatable artifact that identifies the scenario and records the outcome, such as a Playwright trace, screenshot/video, JUnit result, request/response capture, or generated report.
- **Write the test before production code.** Never add an isolated unit or feature test after writing the production behavior it is meant to justify. When isolation is genuinely necessary because an E2E path cannot exercise a narrow failure mode economically, first write a failure inventory: the concrete ways the behavior can fail, the observable outcome for each, and the one scenario the test will prove. Then write and observe the failing test before the production change.
- **Test a real behavior gap, not the implementation's reflection.** `@skills/test-audit/SKILL.md` *Regression tests* and *Junk patterns* decide what a regression test must prove and which assertions carry no value.

## Flaky Test Prevention
A flaky test fails inconsistently, is hard to reproduce, and is often "fixed" by simply re-running the pipeline. Flaky tests destroy trust in CI — once a team learns to re-run instead of investigate, it starts ignoring real failures too. Every new or modified test must be deterministic: it must pass repeatedly, in isolation, and in any order. Apply the following:

- **Freeze time; never assert on the wall clock.** Tests that read `now()`, `time()`, `sleep()`, or the ambient timezone fail depending on environment speed and clock drift. Pin time with `Carbon::setTestNow(...)` (or `travelTo()`) and always restore it afterwards — `Carbon::setTestNow()` / `travelBack()` in `afterEach`.
- **Isolate database state.** A test must never rely on rows created by another test. Assertions such as `assertDatabaseCount('posts', 1)` start failing the moment another test seeds the same table. Isolate with `RefreshDatabase` (or `DatabaseTransactions`) and create exactly the rows the test under assertion needs.
- **Make factory data deterministic.** Do not let random factory values decide the outcome. Explicitly set every attribute the assertion depends on (for example the user's role) instead of trusting factory defaults or random states.
- **Test queues and async jobs deterministically.** Never wait for an asynchronous job to finish before asserting. Either assert the dispatch with `Bus::fake()` / `Queue::fake()`, or force `QUEUE_CONNECTION=sync` in the test environment so jobs run inline.
- **Keep shared resources parallel-safe.** Parallel runs do not create flakiness — they expose existing shared state: Redis keys, files, temp directories, config cache, static properties, and singletons. Isolate per test with `Storage::fake()`, unique keys / file names, and by avoiding mutable static or singleton state.
- **Never call external services directly.** Real HTTP requests fail on network issues, rate limits, latency, or sandbox outages — fake every outbound call with `Http::fake()` (and the relevant SDK fakes). See the *External Calls* section below for the full no-network / no-DNS contract.
- **Guarantee order independence.** A test must pass on its own, repeatedly, and in any order. If a test passes only because another test ran before it, fix the hidden dependency — do not rely on suite ordering.
- **A flaky test outside the diff and the assignment is not yours to fix.** Leave it unchanged and report it, per `@skills/resolve-issue/references/quality-gates.md` *A flaky test outside the diff and the assignment is left alone*. The rules above apply to the tests the task writes or changes.

## Data Handling
- For Laravel:
    - Use `Model::factory()` for persisted data.
    - Do not duplicate database defaults unless explicitly required by the test.
- Avoid mocking data that can be created via factories.

## Mocking
- Prefer storing real data in the database over mocking ModelManager or Repository classes.
- Mock only:
    - external services that cannot run in test environment
    - exception scenarios that are hard to reach otherwise
- Prefer partial mocks over full mocks.
- Remove unnecessary or redundant mocks.

## Jobs
- Dispatch jobs using `JobClass::dispatch(...)` only.
- **Assert the dispatch, never the payload — `Queue::assertPushed()` takes the job class and nothing else.** Write `Queue::assertPushed(ProcessPayment::class);`. Never pass a closure: `Queue::assertPushed(ProcessPayment::class, fn (ProcessPayment $job): bool => $job->orderId === $order->id)` is a payload assertion wearing a dispatch assertion's clothes. It reads the job's own properties from the caller's test, so renaming a property or reshaping a constructor inside the job breaks a test that was never about the job's internals — and a closure that matches nothing fails with *"the expected job was not pushed"*, pointing the reader at the dispatch that did happen instead of at the predicate that did not match.
A dispatch test owns exactly one fact: **the caller dispatched the job**. What the job carries, and what it does with it, belongs in the job's own test, which constructs it with known inputs and asserts `handle()`.
    - The same sentence covers the sibling assertions that accept the same closure — `Queue::assertNotPushed()`, `Queue::assertPushedOn()`, `Bus::assertDispatched()`, `Bus::assertNotDispatched()`, `Bus::assertDispatchedSync()` — because the rule is about *where* a payload is asserted, not about which facade spells the assertion.
    - A second argument that is an **integer count** (`Queue::assertPushed(ProcessPayment::class, 2)`) is not a payload assertion and stays allowed: it is still a fact about the dispatch, not about the job's contents.
    - When a test genuinely needs to prove *which* record the job was dispatched for, that is a signal the assertion is at the wrong level — assert the observable outcome the job produces, or move the check into the job's own test. Do not reintroduce the closure to get the fidelity back.
- **Run the job's own test through `app()->call([$job, 'handle'])` — this is the preferred invocation, and it needs no mocks.** Construct the job with the payload the test controls, then let the container invoke `handle()`:

    ```php
    it('marks the order as paid', function (): void {
        $order = Order::factory()->create(['paid_at' => null]);
        $job = new ProcessPayment(orderId: $order->id);

        app()->call([$job, 'handle']);

        expect($order->refresh()->paid_at)->not->toBeNull();
    });
    ```

    A job declares its collaborators as parameters of `handle()`, and the container resolves each one. `app()->call()` performs that resolution, so the test never builds a double just to satisfy the signature. It is also the production call path: the queue worker reaches `handle()` through `Illuminate\Bus\Dispatcher::dispatchNow()`, which calls `$container->call([$job, 'handle'])`. The test therefore runs the same wiring the worker runs.
    - **Never call `$job->handle($mockRepository, $mockService)`.** Passing the arguments by hand forces a double for every dependency, asserts the job against those doubles instead of against real behavior, and breaks the test the moment `handle()` gains, loses, or re-types a parameter — a change that alters no behavior the test was written for.
    - **Replace a dependency in the container, never at the call site.** When a collaborator genuinely cannot run in the test, the *Mocking* section above defines when that holds. Swap its binding before the call — `$this->app->instance(PaymentGateway::class, $fake)`, `Http::fake()`, `Process::fake()`, `Storage::fake()` — and leave the invocation as `app()->call([$job, 'handle'])`. The call site reads the same whether or not a collaborator is faked.
    - **The constructor payload stays the test's own.** `app()->call()` resolves the `handle()` parameters only, so build the job with the identifiers the test created (`new ProcessPayment(orderId: $order->id)`), per the Laravel rule against dispatching hydrated models.
    - **Use `dispatch_sync($job)` only when the test is about the bus pipeline** — job middleware, batch callbacks, or the dispatch events. It reaches `handle()` the same way and wraps that pipeline around it, which is noise in a test of the job's own behavior.
    - This bullet covers the **job's own** test. The caller's test still asserts only the dispatch, per the bullet above.

## External Calls
- Tests must not call external services.
- Mock all HTTP requests.
- Use local or in-memory database connections for tests.
- **A test never reaches the real network below HTTP.** This covers DNS resolution and raw connections: `dns_get_record()`, `checkdnsrr()`, `dns_check_record()`, `getmxrr()`, `dns_get_mx()`, `gethostbyname()`, `gethostbynamel()`, `gethostbyaddr()`, `fsockopen()`, `pfsockopen()`, `stream_socket_client()`, `socket_connect()`, `ftp_connect()`, `ftp_ssl_connect()`, and `ldap_connect()`. The list names the common cases and is not exhaustive: every function that queries a resolver or opens a connection to another host is covered.
- **The rule covers the code under test, not only the test file.** A test that drives production code into `dns_get_record()` performs a real lookup, even when the test file never names the function. A lookup that returns an empty result is still a real query: it depends on the machine's resolver, it stalls the suite when the resolver times out, and it sends the queried host names to the network.
- **Production code calls such a function through an injectable seam class dedicated to that capability.** Wrap the function in a small class that the container resolves, for example `DnsResolver::records(string $hostname, int $type)` for DNS resolution and a separate `SocketConnector::connect(string $host, int $port)` for raw sockets. One seam per capability: every other class depends on the seam for that capability and never on the global function, and a project may hold several such seams without either one becoming the finding.
- **The seam's own delegation line is exempt from Coverage.** The seam class's body is one call to the native function with no branching and no other logic, so covering that single line means a real lookup — exactly what the seam exists to prevent. Exclude that one line from the default coverage run with a documented marker (e.g. `@codeCoverageIgnore`), or cover it only inside the project's explicitly isolated integration test group. Every other line the seam class or its caller adds still needs 100% coverage under `Coverage` below.
- **The base test case replaces the seam by default.** Bind a fake that performs no I/O in the shared test setup. A test that configures nothing then still cannot reach the network. A test that needs records configures them on that fake.
- **A namespace function override is not a replacement.** Declaring `namespace App\Foo; function dns_get_record() {…}` catches only an unqualified call from that exact namespace, and only after a test loads the file. A fully qualified `\dns_get_record()`, a `use function dns_get_record;` import, or a call from another namespace reaches the real resolver again, and nothing reports it.
- CR severity: **Critical**. The review applies the gate **Real DNS lookup or network socket** in `@rules/code-review/review-process.md` *Test isolation — no real HTTP, no real system processes*.

## Consistency
- Ensure new or modified tests follow existing project conventions.

## Test Organization
- Place every new test file under a directory path that mirrors the namespace of the production class it covers (e.g. `App\Service\Billing\InvoiceCalculator` → `tests/Service/Billing/InvoiceCalculatorTest.php`, `Pekral\AiOlympus\InstallerPath` → `tests/InstallerPathTest.php`). A reviewer must be able to walk from a class to its tests by walking the parallel folder tree without searching.
- One production class maps to one primary test file. The file name is `{ClassName}Test.php` (Pest functional test file using the same base name as the SUT plus the `Test` suffix). Helper / scenario test files extracted from a primary test file keep the same directory and a descriptive `{ClassName}{Scenario}Test.php` name so the relationship stays explicit.
- Cross-cutting tests that do not target a single production class (full-stack feature flows, contract tests for an external API, install / boot scripts) go under an intent-named directory at the top of `tests/` (`tests/Feature/<flow>`, `tests/Contract/<vendor>`, `tests/Integration/<area>`). Do not park them next to an unrelated class just to satisfy a parallel path.
- Group multiple `it()` / `test()` blocks for the same SUT in the same test file when they share setup and subject. Do not split one SUT across many files unless the per-file size genuinely hurts readability (then use the `{ClassName}{Scenario}Test.php` form above).
- Each `it()` / `test()` description states the scenario in plain language and matches what the body actually asserts. Examples of *matching* descriptions: `it('returns zero for an empty cart')`, `test('throws InvalidArgumentException when the discount is negative')`. Examples of *non-matching* descriptions that violate this rule: generic placeholders (`it('it works')`, `test('test1')`, `test('happy path')`), descriptions that name the method instead of the scenario (`test('calculate')`, `it('handles getUser')`), or descriptions that contradict the assertions (`it('adds user')` over a body that asserts removal). When changing what a test asserts, rename the description in the same change.

## Test Organization Review Hook
- In code-review and pre-PR contexts, every new or moved test file must satisfy the **Test Organization** rules above. Misplaced files, mismatched file names, and descriptions that do not match the asserted scenario are CR findings — see `@skills/code-review/SKILL.md` "Test organization" Core Analysis bullet for the severity matrix and Suggested Fix template.

## Scope
- Focus tests on behavior, not implementation details.

## Execution
- Run tests in parallel whenever possible (e.g. `php artisan test --parallel` or `pest --parallel`).

## Quality
- Prefer simple, readable tests over complex setups.
- Use data providers (datasets) where they improve readability and reduce duplication across similar test cases.
- Tests must not contain conditions (e.g., `if`, `switch`); split conditional logic into separate test cases or data providers instead.
- Structure every test body arrange-act-assert per @rules/php/core-standards.md Testing (phases in order, separated by blank lines, never by `// Arrange` / `// Act` / `// Assert` comments — see the canonical rule for the exception list).

## Test Value
Every new or changed test passes the authoring gate of `@skills/test-audit/SKILL.md`: it protects a named behaviour, risk, or contract; a real regression makes it fail; no stronger test already guards it; and it needs no test-only production seam. That skill is the single authority on test value — the owner-boundary principle, the regression-test rules, the junk patterns (tautological assertions among them), the falsifiability test, the retention bar, and the evidence a test removal needs. Coverage verifies those tests; it never justifies one.

## Acceptance-Criteria Test Contract

A change is delivered only when three things hold together: every acceptance criterion of the assignment is met, the code is the simplest design that meets them, and the tests prove exactly those criteria with 100% coverage of the changed lines. Each part is weak alone. Coverage without criteria rewards tests that execute lines and prove nothing. Criteria without coverage leave code that no test reaches. Tests beyond the criteria cost maintenance and hide which test guards which promise.

- **Every criterion has a test.** Each acceptance criterion has at least one named test that proves it, with the data the assignment states. The test name says which criterion the test proves. The review-side check is `@rules/code-review/review-process.md` *Acceptance-criteria use-case coverage*; this section is its implementation-side counterpart.
- **Every test proves a criterion.** Each test that the change adds or modifies proves one criterion, or one failure mode that the criteria or the change imply: an error path, a boundary, an authorization check, a fallback. A test that proves neither is removed. A second test that proves the same criterion with the same data is merged into the first one.
- **Coverage comes from those tests.** *Coverage* below requires 100% of the changed lines. Reach it with the tests above, never with a test written only to execute a line. A changed line that no criterion-driven test reaches is one of two things:
  1. a failure mode without its test — add the test;
  2. code that the criteria do not need — delete the code.
- **The code is the simplest design that meets every criterion.** No speculative abstraction, no configuration for a fixed value, no defensive branch for an impossible case (*Simplicity First*, `@rules/code-review/core-analysis.md`). Deleting code is preferred over testing it.
- **The handoff proves the mapping.** The implementer reports a criterion → test table (criterion, test file and test name, result) and the measured coverage of the changed lines. A criterion with no test, a test with no criterion, or coverage below 100% is not delivered: fix it, or stop as `Blocked`.
- **A declared HOTFIX is the only waiver.** It follows `@rules/compound-engineering/orchestration.md` *HOTFIX — the declared emergency path* and the review-side waiver in `@rules/code-review/review-process.md`. No other caller instruction lifts this section.

## Coverage
- Every test change must be verified to be functional — run affected tests after each modification.
- Require 100% code coverage for every changed or added code path — applies equally to code modifications and code review.
- Before running coverage, discover the project's coverage command per `@skills/resolve-issue/references/quality-gates.md`. Do not assume a default command.
- **Coverage reporting is short by default.** Run the coverage check on every change, but report the result on the published CR / tracker comment **only** when there is something the reader must act on:
    - **uncovered changed lines** — list every uncovered line as a Critical finding and render the `## Coverage` section with the tool, exact command, and the uncovered-line list;
    - **coverage tooling unavailable** — raise the missing-tool case as a Critical finding and render the `## Coverage` section with the reason in place of a result. **Sanctioned exception:** a pass running in the optional isolated read-only worktree with no `vendor/` reports `deferred to donatello` here instead of a Critical finding, per `@rules/code-review/review-process.md` *Validation & Coverage Gate*.
  When every changed line is at 100% coverage and the tool ran successfully, **omit the `## Coverage` section entirely, omit the `Coverage:` header line, and omit the `coverage …` slot from the final summary line.** The CR is "clean" on the Counts line and the omission is the signal that coverage is satisfied — never emit `100%` / `clean` / `n/a` placeholders for the section, the header line, or the summary slot. The coverage check itself still runs unconditionally on every CR; only the user-visible reporting is short-circuited.

## Code Style and Quality Gates
- **Do not run fixers or checkers on test changes as you author them.** The project's gate runs once, immediately before the merge (`@skills/resolve-issue/references/quality-gates.md` *Gate placement — deferred to the merge boundary*), run by `@skills/process-code-review/SKILL.md` *Finalization* after the review converges, or by `@skills/merge-github-pr/SKILL.md` *Pre-merge quality gate* when no recorded run covers the head commit. That run commits the fixes it produces as their own commit.
- Do run the **tests** you are writing or changing — that is correctness feedback on the change itself, not a style gate, and it costs no build.
- The gate discovers its own tooling: the project's gate / coverage command, discovered per `@skills/resolve-issue/references/quality-gates.md`.

## Test Review
- After completing test changes, check every changed test against these rules and the *Junk patterns* of `@skills/test-audit/SKILL.md`.
