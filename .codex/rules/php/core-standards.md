---
description: Unified coding standards for PHP/Laravel projects
paths:
  - "**/*.php"
---

## Naming
- Use clear, descriptive names that reveal purpose.
- Prefer descriptive method and variable names over comments.
- Classes: PascalCase.
- Methods and variables: camelCase.
- Routes: kebab-case URLs and dot notation route names.
- Config keys: snake_case.
- Controllers: plural noun + `Controller`.
- Jobs: action-oriented names.
- Events: past-tense or domain-event names.
- Enums: descriptive case names.
- **A misleading name — one whose claim about behavior or shape is actively contradicted by what the method, variable, or property actually does — is a binding naming rule, not a stylistic nit; it applies identically to methods and to variables/properties.** It is narrower than "could be more descriptive": the name must make an affirmative, checkable claim that the body then breaks, so a reader who trusts the name alone is actively misled. Concrete, testable triggers (every parenthetical list below is illustrative, not exhaustive):
a name **implying read-only / non-destructive access** — a **getter-shaped name** (`get*`, `find*`, `fetch*`, `resolve*`, `list*`, `read*`, a `$cached*` variable, a bare noun with no verb such as `$user->invoices()` or `total()`, or a boolean predicate — an `is` / `has` / `can` prefix followed by an uppercase letter, e.g. `isActive`, `hasItems`, `canEdit`, never `issueInvoice`, `hashPassword`, `cancelOrder`, or `canonicalUrl`) — whose body (or, for a variable/property, the expression assigned to it and the writes performed through it) **writes a property, persists a record, dispatches an event/job, deletes, or otherwise mutates persisted or shared state** beyond producing the value the name promises;
an **`is*` / `has*` / `can*`-prefixed name** (the same camelCase-boundary test as above) that **holds or returns a non-boolean value** (an array, a model, a string, or a nullable object used for more than an existence check); or a name that **describes one specific action or condition** while the body **performs a materially different action or represents a materially different condition** (e.g. `sendWelcomeEmail()` that also charges a payment, `isEligibleForDiscount()` that always returns `true` regardless of the order, `$activeUsers` that also holds inactive ones). Exemptions to the read-only/getter-shaped trigger above (do **not** flag):
a mutation that only produces the value the name promises — memoization / lazy initialization of the returned value (`$this->x ??= …`), read-through cache population (`Cache::remember()` / `Cache::get() ?? …put()`), a lock acquired solely to guard that population, and an explicit get-or-create contract whose name states it (`firstOrCreate()`, `getOrCreateX()`); and a method overriding a parent / interface owned by `vendor/`. The exemption must be cited explicitly wherever the rule is enforced (CR finding, refactoring proposal).
A name that is merely **less descriptive than it could be**, without misrepresenting behavior or shape, is not this violation — it stays under the general naming guidance above. See **CR Severity Rules** below for severity and the explicit carve-out that keeps this finding and the existing generic naming-nit bucket from ever firing on the same identifier.

## Structure
- Keep one clear responsibility per class and per method.
- Avoid god classes and mixed responsibilities.
- Prefer composition over inheritance unless inheritance is clearly justified.
- Expose clear interfaces and keep implementation details internal.
- **A method called only from inside its own class is `private`.** Visibility is the class's contract. A `public` or `protected` method states that code outside the class depends on it, so a reader has to search the whole codebase before changing its signature, and the analyser cannot report it as unused once its last caller is gone. Declare the narrowest visibility the real callers need: `private` when every call site is inside the class, `protected` only when a project subclass calls or overrides the method, `public` only when another class calls it. A test is never a caller for this decision (see *Testing* → *Never widen visibility for a test*).
**The method keeps a wider visibility when something outside the project's own calls needs it:** it implements an interface or overrides a parent method; the framework or a vendor calls it by name or by convention (a controller action, a job or command `handle()`, an Eloquent scope, accessor, or mutator, a Livewire action or lifecycle hook, an event-listener method, a magic method); a container, an attribute, or reflection wires it up; it belongs to the published API of a package; or a trait exposes it to the classes that use the trait. Cite the specific contract wherever the rule is enforced.
**A string or array callable runs in the scope of the code that receives it.** A method referenced as `'name'` or `[$this, 'name']` and handed to code outside the class fails once it is `private` — a parameter typed `callable` rejects it with a `TypeError`. Before narrowing such a method, replace the reference with first-class callable syntax (`$this->name(...)`), which a private method supports. Until that replacement is made, the method keeps its visibility.
- Extract deeply nested conditionals into well-named methods where it improves readability.
- Prefer small, simple classes or functions unless state is genuinely needed.
- **A file that is already past the size threshold must not grow.** This is a ratchet on the diff, never a limit on the codebase as it stands. A file under **400 lines** takes new code freely. A file over 400 lines must not gain net lines: put the new behaviour in a new class the existing one calls, or extract enough of the old one to pay for the addition. A file over **800 lines** is expected to leave the change shorter than it found it, and the change says what was extracted and why the split falls where it does. The reason is that a class of that size carries no summary a reader can hold — finding the one method that matters means reading past hundreds of unrelated ones, and every change to it risks behaviour nobody remembered was there.
The same ratchet applies to a **method** the diff pushes past roughly **50 lines** or past three levels of nesting; the fix is the extraction *Extract deeply nested conditionals into well-named methods* above already prescribes.
**Never split by moving lines somewhere arbitrary.** A `FooHelper` that exists only to hold the overflow is the same class under two names. Split along a responsibility and name the new class after it; when no name presents itself, the boundary is wrong.
- Prefer typed DTOs over raw arrays across important boundaries.
- **Prefer a DTO or a value object over an associative array whenever the array carries named, heterogeneous fields.** An associative array states neither which keys exist nor what type each holds, so every consumer re-derives the shape by reading the producer, a typo in a key fails at runtime instead of at analysis time, and a renamed field leaves no trace at the call sites. A DTO carries the shape in the type system; a value object additionally owns the invariant that makes the value valid (a `Money` that cannot hold a negative amount with no currency, an `EmailAddress` that cannot hold an unparsable string) — reach for the value object when the data has rules of its own, and the DTO when it is a plain record.
This is the general form of the two rules above: the >4-parameter rule and the public-return rule are the two places where it is mandatory, and this bullet is the default everywhere else. The exemptions stay the same — a framework / vendor contract fixed outside the project, and a genuinely internal short-lived helper structure whose producer and consumer are the same private method. The data-carrier exemption below belongs to the >4-parameter rule alone: replacing an array with a DTO never lands back on the same class, so this bullet carries no circularity to exempt.
- When a method, function, closure, constructor, `__invoke()`, or other callable requires more than 4 parameters, introduce a dedicated typed DTO (preferably `final readonly` with promoted constructor properties) and pass it as a single argument instead of a long parameter list. Promoted constructor properties count as parameters; a variadic (`...$args`) counts as one. Exactly two categories are exempt, and no other case is.
**First — a signature fixed outside the project.** An entry-point signature fixed by an external framework / vendor contract that the project cannot change: a controller action whose argument list is resolved by the service container, a magic method bound by the framework, an event listener whose signature is dictated by the dispatched event, and a method overriding a parent / interface owned by `vendor/`.
**Second — the data carrier's own constructor.** The prescribed fix is *introduce a DTO*, and that fix cannot be applied to a DTO's own constructor: obeying it produces the same class a second time. A data carrier's own constructor is therefore exempt from the count. So is every named constructor of that same class (`fromModel()`, `fromRequest()`, `fromArray()`, `from()`) and every `with*()` copy method, but only when its parameters are the class's own field list or a subset of it — without that half the rule fires again one line lower on an identical parameter list, and the fix stays as circular as before.
**What counts as a data carrier.** All four conditions hold: every constructor parameter is a promoted property, so the parameters are the class's own fields; the constructor injects no collaborator — no repository, client, manager, or other service — and takes data only; every public method other than the constructor is a named constructor of the same class, an accessor or derived-value getter over its own properties, a `with*()` copy method, or a serialization method fixed by a framework / vendor contract (`toArray()`, `jsonSerialize()`); and the class performs no I/O, no persistence, no dispatching, and no other side effect.
A **value object** qualifies on the same four conditions and for the same reason: its constructor has the same shape and carries the same circularity. It may additionally validate its own invariant in the constructor — throwing on an invalid value is not a side effect — and expose pure comparison or formatting methods (`equals()`, `format()`). A class that fails any of the four conditions is not a data carrier, whatever it is named: a renamed `Service` injects collaborators and does work in its public methods, so it fails two of them and stays subject to the rule.
This exemption covers the **parameter count only**. *Keep one clear responsibility per class* above still applies to the data carrier itself, so a DTO that has grown into a bag of unrelated fields is still a finding — under that bullet, never under this exemption.
The exemption must be cited explicitly wherever the rule is enforced (CR finding, refactoring proposal), naming the parent class / interface for the first category or the data carrier being constructed for the second, plus a one-line reason.
- When a **public** method returns a structured set of values — an associative array representing a record, a multi-key payload, or an array shape with named string keys — return a typed DTO (preferably `final readonly` with promoted constructor properties) instead of the raw array. A DTO names and types each field, turning an opaque `array` return type into a self-documenting contract the caller can rely on. This does **not** apply to: a single scalar / `bool` / `string` / `int` / `enum` / `void` return; a homogeneous list or collection of one type (`list<int>` of IDs, `array<int, OrderData>`, `Collection<int, UserModel>`);
or a return whose array shape is fixed by an external framework / vendor contract the project cannot change — `toArray()`, `jsonSerialize()`, `Arrayable::toArray()`, Eloquent `casts()` / `$attributes`, FormRequest `rules()`, a config callback the framework invokes, or a method overriding a parent / interface owned by `vendor/`. The exemption must be cited explicitly wherever the rule is enforced (CR finding, refactoring proposal) with the contract and a one-line reason.
- Use `readonly` for immutable data where practical.
- **Make a data-carrying class immutable (`final readonly`) unless it has a reason to mutate.** A DTO, a value object, a command / query payload, an event, and a configuration object are all read after construction and never legitimately changed in place, so `readonly` is the accurate declaration — and it removes the class of bug where one collaborator mutates an object another still holds. Model a change as a new instance from a `with*()` method rather than a setter. This is a default, not a mandate: an Eloquent model, a builder that accumulates state by design, a mutable collection, and a class the framework hydrates after construction are all legitimately mutable and stay that way.
- Use PHP attributes when they provide a cleaner and more idiomatic solution than manual wiring.

## Code Style
- Follow active PHP-FIG standards used by the project.
- Never reformat unrelated existing code.
- Keep formatting readable and consistent with surrounding code.
- Add blank lines between distinct logical blocks, but avoid unnecessary vertical noise.
- Avoid cramped formatting and avoid excessive empty lines.

## PHP Practices
- Always declare explicit return types.
- **Do not introduce a new `mixed` unless it is genuinely unavoidable.** `mixed` on a parameter, a property, a return type, or inside a generic annotation (`array<string, mixed>`, `iterable<mixed>`) opts that value out of static analysis entirely: every consumer must re-check what it holds, and the analyser can no longer prove the call is safe. Declare the real type instead — a union when the value genuinely has more than one shape (`int|string`), a generic template when the type varies by caller, a DTO or value object when the value is a structured record, an interface when the variation is behavioural, or `object` / `iterable` when only the category matters.
`mixed` is acceptable where the value is genuinely unconstrained and the code says so: a generic serializer, a cache or container that stores arbitrary values, a variadic passthrough that only forwards, or a signature fixed by a framework / vendor contract the project cannot change. An unavoidable `mixed` is narrowed at the boundary — validate or assert the type once on entry and pass the narrowed type inward, rather than letting it travel through the call stack. CR severity for a new avoidable `mixed`: **Minor**, escalating to **Moderate** when it reaches a public API or replaces a type that was previously declared.
- Use the PHP version supported by `composer.json`.
- Prefer modern PHP syntax when supported by the project.
- Use `match` where it improves clarity.
- Use named arguments when they improve readability and reduce ambiguity.
- Document iterable value types with generics where applicable.
- Use array shapes for fixed structured arrays when DTOs are not appropriate (e.g. an internal / private helper, or a framework / vendor contract); for a **public** method returning a structured record the *Structure* section's public-return rule applies — return a DTO.
- Avoid magic numbers; extract meaningful constants when the value has domain meaning.
- Prefer specific exceptions over generic ones.
- **Do not return `null` when the absence is a failure — throw a domain exception.** A nullable return is the right shape when *not found* is an ordinary, expected outcome the caller is meant to branch on (a lookup that legitimately misses, an optional configuration value, a `find()` alongside a `findOrFail()`). It is the wrong shape when the absence means the operation could not be completed: returning `null` there discards the reason, forces every caller to invent its own handling, and defers the failure to a `null`-dereference far from the cause. Throw a named domain exception (`OrderNotFound`, `InsufficientBalance`, `PaymentDeclined`) that states what went wrong and carries the context needed to handle or log it. The test:
if the caller can do nothing meaningful with `null` except fail, the method should have thrown. A nullable return that every caller immediately turns into an exception is that rule already being applied at the wrong place — move it into the method.
- Catch specific exceptions only when recovery or translation is meaningful.
- Never suppress errors with `@`.
- **Do not introduce new static-analysis / linter suppressions.** A new suppression on a line the change adds or modifies — a PHPCS ignore (`// phpcs:ignore`, `// phpcs:disable`, `@phpcsSuppress`, `@codingStandardsIgnoreStart` / `…Line` / `…End`; each `phpcs:` annotation also matches in its `@`-prefixed spelling — `// @phpcs:ignore`, `// @phpcs:disable` — which PHP_CodeSniffer honors identically), a PHPStan ignore (`@phpstan-ignore`, `@phpstan-ignore-line`, `@phpstan-ignore-next-line`, a new `ignoreErrors` entry or baseline addition in `phpstan.neon` / `phpstan-baseline.neon`), a Psalm / Phan suppression (`@psalm-suppress`, `@phan-suppress`, baseline addition), a PHPMD `@SuppressWarnings(...)`, or the PHP `@` operator —
silences the tool instead of fixing what it flagged. **Fix the underlying issue rather than suppressing it.** **There is no exception: a suppression annotation never appears in a diff, however narrowly it is scoped and however well it is documented.** The previous carve-out for a documented, single-line, third-party false positive is withdrawn — in practice it became the escape hatch for every finding that was merely inconvenient to fix, and a reviewer had no way to tell one from the other without reproducing the analyser's verdict.

Write the code so the finding does not arise. That is almost always possible: narrow a type, split a method, introduce a DTO, replace a dynamic call with an explicit one, assert an invariant the analyser cannot infer (`assert($value !== null)` is a real assertion that resolves the warning, not an annotation that hides it). Reach for the restructuring, not the annotation.

When the finding is a genuine false positive in a surface the project does not own — a framework contract fixing a signature, a vendor stub the analyser misreads — the answer is **one scoped entry in the project's own tool configuration**, never a comment in the code: a `<rule>` element in the PHPCS ruleset naming the sniff and the path, or the analyser's equivalent. It is scoped to the narrowest path and the single rule identifier, it carries a comment stating which external contract forces it, and it lives in one auditable place a reviewer reads once instead of scattered through the source. A new `phpstan-baseline.neon` line and a blanket `ignoreErrors` entry are not that — they are the same silence in a different file and stay banned.

When neither the restructuring nor a scoped configuration entry resolves it, **stop and report it**. An agent never writes a suppression on its own authority; it states what the analyser flags, what it tried, and why neither worked, and a human decides. A blocked run is recoverable; a silenced analyser is not, because nothing later distinguishes it from a finding that was never raised. CR severity for a new suppression annotation: **Critical**.
- **Do not create a local variable that adds nothing.** Every local variable is one more name a reader must hold and one more place the value can change. A variable earns its line only when it does work the expression cannot do on its own. These shapes do no work and are inlined:
    - a variable assigned and then only returned (`$result = $this->calculate($order); return $result;`);
    - a variable assigned and then read exactly once, directly below, where the inlined expression reads as clearly (`$total = $order->total(); $this->charge($total);`);
    - a variable that only copies another variable or a property (`$user = $this->user;`) with no narrowing, no snapshot, and no rename that adds meaning;
    - a variable that exists only to name an argument at the call site — use a named argument (see *Named Arguments*).

  **A variable stays when it does one of these jobs:** the value is read more than once; its name explains a non-obvious expression that would otherwise need a comment (the *Naming comes first* rule in *Documentation*); it splits an expression too long or too nested to read in one piece; it fixes the evaluation order or captures a value before a side effect changes it; a language construct requires one (a by-reference argument such as `preg_match()` `$matches`, `end()`, `list()` / array destructuring); or it narrows a type the analyser cannot otherwise infer. Inlining never moves an expensive call above a guard that used to skip it.
- When fixing an unused variable (e.g. PHPCS `UnusedVariable`): delete the variable if it is not required. If the variable is required (e.g. assigned from a function call with side effects), suppress the warning with `assert($variable !== null)` or similar `assert()` instead of removing the assignment.

## Named Arguments
- Many parameters is a code smell. It often means the method does too much or should accept a DTO/value object.
- Named arguments help most with booleans, null, array values, and unclear strings. For example, `true`, `null`, `[]` without context say nothing.
- They improve call-site readability without unnecessary variables. Instead of `$status = 'active'` just for a hint, use `status: 'active'`.
- They should not replace good design. When a method has 8 parameters, named arguments do not fix the problem. They just make it bearable.
- In public APIs, parameter names become part of the contract. Renaming a parameter in a public method can break consumers using named arguments.
- Keep arguments in the original method signature order even when using named arguments.
- See `rules/php/examples/named-arguments.md` for usage examples.

## Design Principles
- Follow SOLID pragmatically, not dogmatically.
- Keep I/O at the edges where practical.
- Prefer deterministic behavior based on explicit inputs.
- Extract repeated logic into reusable abstractions only when repetition is real and meaningful.
- Keep related code together and maintain a logical folder structure.
- Leave touched code cleaner than you found it.
- Do not add speculative (YAGNI) parameters. Add a parameter to a method, function, action, or constructor only when at least one current caller actually needs it. Optional knobs, "in case" defaults, and parameters introduced solely for hypothetical future callers must be removed; add them later when a real use case appears.
- Do not introduce PHP `interface` types speculatively. Define a project-owned interface only when it has **at least two non-test consumers, and/or at least two non-test implementations** — test doubles, mocks, and fakes do not count toward either threshold. Implementing a framework or third-party interface (e.g. `ShouldQueue`, `HasLabel`, `Arrayable`, contract interfaces from `vendor/`) is always allowed; the rule applies only to interfaces declared inside this project. When refactoring, collapse single-implementation, single-consumer interfaces back into their concrete class unless they exist for a documented architectural reason — a published package API surface, or a plugin extension point with a written contract documented in code or in the package README.

## Documentation
- **The default state of the codebase is no comment.** Retain a code comment or docblock only when it is needed for exactly one of these purposes:
    1. **Type analysis** — PHPDoc conveys a type fact that native declarations cannot express and that PHPStan/Psalm or another static analyser consumes, such as an array shape, generic collection element type, unit, bound, or narrower nullability contract.
    2. **Security or operational context** — the code enforces a security boundary, works around a security or production constraint, or depends on an external operational contract that a reader cannot infer from the code. Name the relevant incident, CVE, ticket, service, or failure mode where that makes the constraint verifiable.
    3. **Non-intuitive behaviour** — the code deliberately behaves in a surprising way, including a workaround for an upstream defect, and a reader needs the reason to avoid safely-looking but incorrect simplification.
  **Remove every other comment in code you are changing.** This includes narration, signatures restated in PHPDoc, type docblocks native types already carry, commented-out code, section banners, changelog notes, domain definitions, navigation markers, and comments that no longer match the code. Do not sweep untouched files.
- **Make the code carry everything it can before retaining an allowed comment.** Use names, predicates, private methods, DTOs, and constants for facts the code can express. A comment must contain only the remaining type, security/operational, or non-intuitive fact; it must not narrate what the code does. Rename or extract first where needed, then remove the obsolete prose.
- **Never generate a docblock that describes the logic of a class, method, or property.** A declaration-level docblock is allowed only for type analysis. The prescribed fix for descriptive class, method, or property PHPDoc is a clearer name or structure, never a shorter description. Vendor-owned docblocks are outside this rule.
- **Write the code so that extensive PHPDoc and inline commentary are not needed.** Prose next to code goes stale — the code is refactored, the comment is not, and the reader is then left with two sources of truth of which only one is executed. Clean, readable code is the durable form of that documentation, so a comment block that is growing is a signal to restructure the code rather than to keep writing: rename the method or variable so it states its own purpose, extract a well-named private method for the step the comment was narrating, introduce a DTO or a value object so the shape needs no explanation, or split the method until each part is obvious. Reach for a comment only after the code genuinely cannot carry the fact.
- Keep an allowed comment concise and verifiable. Do not use comments as general API, business-rule, or implementation documentation.

## Testing
- Add or update tests for every meaningful behavior change.
- Write all new tests using Pest syntax (`it()` / `test()` functional blocks); do not introduce PHPUnit-style class-based tests for new test files.
- Require 100% test coverage for every changed or added code path.
- **In code review / pre-PR contexts (CR skills, `process-code-review`, `create-missing-tests-in-pr`, `create-test`) verify coverage for the changed files only** — every line, branch, and condition added or modified by the current changes must be covered, but do not gate on a project-wide coverage percentage. Use the coverage tooling the project already provides (a Phing coverage target, a Composer `test:coverage` / `coverage` script, or a direct `vendor/bin/pest --coverage-clover=<file>` / PHPUnit `--coverage-clover` invocation); do not add a new bespoke coverage script to the project. Full-suite coverage commands remain the release / CI gate.
- Scope the run to the changed source files whenever the runner allows it (`--coverage-clover` plus a path filter, PCOV `pcov.directory` scoped to the changed directories); otherwise generate the report and read off only the changed files.
- **Delete any auto-generated coverage report file (the `--coverage-clover` output or other coverage artifact) as soon as it has been read**, so it is never accidentally committed to git, and keep such artifacts in `.gitignore` as a second line of defence.
- **Report the coverage result short by default (issue #528 follow-up).** Run the coverage check on every change, but report it on the published CR / tracker comment **only** when there is something the reader must act on — uncovered changed lines (listed as Critical findings) or unavailable coverage tooling (also a Critical finding, except the sanctioned savings-mode isolated-worktree deferral in `@rules/code-review/review-process.md` *Validation & Coverage Gate*, which reports `deferred to donatello` instead). When every changed line is at 100% coverage and the tool ran successfully, omit the `## Coverage` section, the `Coverage:` header line, and the `coverage …` slot from the summary line. The Counts line carries the clean signal;
the omission is the report. The check itself still runs unconditionally on every CR run.
- Prefer deterministic tests.
- **Structure every test body arrange-act-assert (AAA), in that order** — setup first, then the action on the SUT, then assertions; each phase contiguous, phases separated by a blank line when the body has more than one multi-statement phase. `// Arrange` / `// Act` / `// Assert` comments are optional, never required — prefer self-documenting structure. Not violations: single-expression or single-assertion tests with no distinct phases; act and assert merged in one idiomatic expression (e.g. `expect($sut->run())->toBe(...)`, `expect(fn () => ...)->toThrow(...)`); a fixture sanity-check assertion inside the arrange phase;
sequential workflow tests where each act→assert step depends on the state left by the previous step — each step still follows AAA order internally. When multiple independent act→assert cycles share no state, split them into separate tests or a dataset.
- Use clear, human-readable test names.
- Do not use `describe()` in Pest tests.
- Prefer top-level `it()` or `test()` blocks only.
- Prefer data providers through test arguments rather than PHPDoc annotations.
- Avoid reflection in tests unless there is no reasonable alternative, and never use it to reach a private member (see *Never widen visibility for a test* below).
- **Never widen visibility for a test.** Production visibility is decided by production callers only (see *Structure* → *A method called only from inside its own class is `private`*). A test never changes it. The following are all the same defect: a `private` method made `protected` or `public` so a test can call it; a `@internal`, `@visibleForTesting`, or similar annotation on a member widened for a test; a test-only subclass that re-exposes a `protected` member; and reflection (`ReflectionMethod::setAccessible()`, `Closure::bind()`, `invoke()` on a private member) that reaches past the visibility instead of changing it. When a private method needs tests, write the tests another way:
    1. Test the behaviour through the public method that calls the private one, with inputs that drive each branch of the private method.
    2. When that path is too long to set up, the private method holds a responsibility of its own. Extract it into a new class with its own public method, inject that class, and test the new class directly.
    3. When neither works, stop and report it. Never change the visibility to make the test pass.
- Split complex conditional test setups into separate test cases instead of branching inside a test.
- Never generate `covers()` methods unless the repository explicitly requires them.
- Mock only external services or exception paths that are otherwise hard to reach.
- Prefer partial mocks over full mocks when mocking is necessary.
- Follow existing project testing conventions unless introducing a new pattern is clearly justified.

## Bug Fix Workflow
- Write or update a failing test before fixing a bug when practical.
- Refactor only after behavior is covered.
- Run the most relevant tests for changed code first.

## Fluent API Design
- Prefer readable, intention-revealing APIs over vague helper utilities.
- Use factory methods like `of()` or `from()` when they match existing project style.
- Prefer explicit domain language over generic utility method naming.
- Avoid god utility classes with many unrelated static helpers.

## Globals
- Do not use global variables.
- Do not introduce `global` state in application or test code unless the platform truly requires it.

## Time

A runtime resolves a bare date call against an ambient default — `date.timezone`, the framework's own configuration, the container's locale. The result carries no mark saying which zone produced it, so it looks identical to a value that is explicit and diverges only when it meets a value that really is in another zone. That divergence follows daylight saving, so it appears twice a year and in production.

- **Every date call names its timezone.** `new DateTimeImmutable('now', $timezone)`, `Carbon::now($timezone)`, `Carbon::parse($value, $timezone)`. Never leave the ambient default to supply it. The explicit argument is also the only thing that tells the next reader which zone the instant is in.
- **Compute, compare, and store in one zone.** A stored timestamp, an interval, a range predicate, a TTL, and a scheduled-at value all use it. Convert at the boundary where a human reads or types a time, and convert straight back before storing or comparing.
- **Never take the time from the database.** SQL `NOW()`, `CURDATE()`, and `CURRENT_TIMESTAMP` resolve against the database session's zone, which is a third source nobody sets deliberately. Resolve the instant in PHP and bind it as a parameter.
- **A value that crosses a process boundary carries its zone.** A queue payload, an API response, a cache entry, and a log line are read by a different process that cannot ask which zone produced them.
- **Never assume an existing value is already in the expected zone.** A codebase carrying both shapes proves nothing about the value in front of you. Follow it back to the call that produced it before comparing it with anything.

Severity in code review: **Moderate** for a date the diff constructs, parses, or compares with no explicit timezone, and for a new SQL `NOW()` / `CURRENT_TIMESTAMP` where the instant belonged in PHP. The scope is the changed lines. Existing bare calls elsewhere are not a finding, and this rule is never a licence to open a migration pull request for them.

## Async Review Note
- When reviewing asynchronous jobs, first verify whether retry, timeout, and backoff behavior is defined in the job itself or centrally in configuration.

## CR Severity Rules
- Mark as **Moderate**:
  - a method, variable, or property name that actively contradicts what its own body does, per the *Naming* misleading-name triggers above (a getter-shaped name that mutates state, an `is*`/`has*`/`can*`-prefixed name holding or returning a non-boolean value, a name describing one action while the body performs a materially different one, a name implying read-only access that writes/deletes) — a real maintainability hazard a fixer cannot catch, but not an architectural/structural violation, so it stays below Critical per the existing stratification (`@rules/code-review/general.md` *Default severity for a rule violation*).
Escalate to **Critical** when the misleading identifier is itself a security control — an authn/authz predicate (`isAuthorized()`, `canAccess()`, `hasPermission()`), a sanitization / escaping / validation routine (`sanitize()`, `escape()`, `validate()`), a signature / token verification (`verifySignature()`, `checkToken()`), or a variable whose name asserts a trust boundary (`$validated`, `$sanitized`, `$escaped`) — a name that lies about a security control is a broken control, not a readability defect.
When `@skills/security-review/SKILL.md` already raises the same identifier under broken access control / improper input validation, that walk owns the finding — raise it once, not twice. **Gating — a name that merely reads less clearly is not this finding:** a name that is less descriptive, inconsistently cased, or could read better, without contradicting the code's actual behavior, has no applicable binding rule here. It used to fall to the "naming ... wording nits without a binding rule" Minor default, and the review no longer detects a Minor at all (`@rules/code-review/general.md` *Minor findings are not detected*), so it is not reported;
a name matching one of the triggers above is no longer "without a binding rule" and is always this Moderate finding instead. That boundary never suppresses a finding another walk raises on the same identifier; a security finding from `@skills/security-review/SKILL.md`, or a layer-placement finding from the `@rules/laravel/architecture.md` walk (e.g. a write inside a Repository), is raised independently and at its own severity.
  - a method the diff adds, whose visibility the diff changes, or whose last outside caller the diff removes, that is `public` or `protected` while every non-test call site is inside its own class and none of the exemptions in *Structure* applies;
  - a local variable the diff adds that matches a shape in *PHP Practices* → *Do not create a local variable that adds nothing* and does none of the jobs that keep a variable.
- Mark as **Critical**: a visibility widened for a test, per *Testing* → *Never widen visibility for a test* — a `private` member made `protected` / `public`, a test-visibility annotation, a test-only subclass re-exposing a `protected` member, or reflection reaching a private member. The rule states *never*, so the default for a required-pattern violation applies.
