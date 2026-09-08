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
- Extract deeply nested conditionals into well-named methods where it improves readability.
- Prefer small, simple classes or functions unless state is genuinely needed.
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
- **The default state of the codebase is no comment.** A comment is an exception a fact has to earn, never the baseline a reader is owed. Two obligations follow — the same rule read from both ends — then the gate every surviving comment passes, and the rails that keep the deletion safe.
    - **Delete every unnecessary comment sitting in code you are already changing.** Unnecessary means: narration of the statement below it, a restatement of the signature, a redundant type docblock the native types already carry, commented-out code, a section banner, a changelog note, and any comment that no longer matches the code beside it. Deleting one is not scope creep — it removes a second, unexecuted source of truth from a region you already had to read to make your change. Do not go hunting through untouched files for more.
    - **Only these survive, and only while they stay true:** logic genuinely complex enough that a competent reader cannot recover it from the code in seconds; the *why* behind a decision — a rejected alternative, a trade-off, an upstream bug worked around; a domain definition the code references but cannot state; a navigation marker (`@see`, `@rules/…`, *this pairs with Y*); and a comment this ruleset itself mandates — the comment naming the external contract on a scoped tool-configuration entry, and the justification on an unavoidable per-row DB operation. Everything else goes.
    - **Naming comes first, even for a *why* comment.** The keep bar above is what a comment may explain, never permission to explain it in prose the code could have carried. Before keeping any comment, extract everything nameable into the code: turn the condition into a named predicate, the step into a named private method, the shape into a DTO, the constant into a named constant. Only the residue that survives that pass may stay, and it stays at the length the residue needs — not the length the original narrative needed. A multi-line comment explaining what a condition tests is a **finding**, not a *why* comment:
the explanation belongs in the predicate's name. A comment is a *why* comment only for the part naming genuinely cannot reach — a consequence outside this codebase, a rejected alternative, an external reference such as a ticket, CVE, or RFC identifier. The test: read the comment, then ask which sentences a reader would still need after the code is named well. Those sentences are the comment; the rest was a missing name.
    - **Two rails before any deletion.** When a comment was compensating for an unclear name, rename or extract **first** and delete it after — the comment goes either way, but the clarity has to land in the code before the prose leaves it. When a comment's value is genuinely unclear, keep it and name it in the pull request rather than deleting it blind.
- **Never generate a docblock that describes the logic of a class, a method, or a property.** *Naming comes first* above governs the comment a fact has earned; this governs the docblock no fact asked for — the block an IDE template or an agent emits above a declaration to fill the space, narrating what the declaration below it already is. Three shapes recur, and no shorter docblock fixes any of them: a **class** docblock telling the reader what the class does; a **property** docblock describing what the property holds (a `@var` line paired with prose such as *"holds the resolved customer for this order"*); and a **generated template** that describes logic while carrying no fact the code cannot carry.
The prescribed fix is the **rename**, never the shorter docblock — the class's name states what it is, the method's name what it does, the property's name what it holds, so `InvoicePdfRenderer` replaces `Renderer` plus the three lines explaining that it renders invoices to PDF, and `$resolvedCustomer` replaces `$customer` plus the line saying which customer it is.
**Not findings — these stay, because the code cannot carry them:** a `@param` / `@return` line carrying a constraint the type system cannot express (an array shape, a unit, a bound, a nullability narrower than the signature); `@see` and the other navigation markers; a docblock generated or owned by `vendor/`; a docblock this ruleset itself mandates; and a *why* comment — a decision, a rejected alternative, an external ticket / CVE / RFC reference.
- **Write the code so that extensive PHPDoc and inline commentary are not needed.** Prose next to code goes stale — the code is refactored, the comment is not, and the reader is then left with two sources of truth of which only one is executed. Clean, readable code is the durable form of that documentation, so a comment block that is growing is a signal to restructure the code rather than to keep writing: rename the method or variable so it states its own purpose, extract a well-named private method for the step the comment was narrating, introduce a DTO or a value object so the shape needs no explanation, or split the method until each part is obvious. Reach for a comment only after the code genuinely cannot carry the fact.
- Document APIs, complex business rules, non-obvious side effects, and important constraints — **concisely**. These are the facts the code provably cannot carry, and they stay; the requirement is that they are stated in as few lines as the fact needs, never expanded into a narrative the next refactor will invalidate.
- PHPDoc should describe intent and domain meaning, not restate the method name or implementation steps.
- Keep PHPDoc high-level and useful for maintainers.

## Testing
- Add or update tests for every meaningful behavior change.
- Write all new tests using Pest syntax (`it()` / `test()` functional blocks); do not introduce PHPUnit-style class-based tests for new test files.
- Require 100% test coverage for every changed or added code path.
- **In code review / pre-PR contexts (CR skills, `process-code-review`, `create-missing-tests-in-pr`, `create-test`) verify coverage for the changed files only** — every line, branch, and condition added or modified by the current changes must be covered, but do not gate on a project-wide coverage percentage. Use the coverage tooling the project already provides (a Phing coverage target, a Composer `test:coverage` / `coverage` script, or a direct `vendor/bin/pest --coverage-clover=<file>` / PHPUnit `--coverage-clover` invocation); do not add a new bespoke coverage script to the project. Full-suite coverage commands remain the release / CI gate.
- Scope the run to the changed source files whenever the runner allows it (`--coverage-clover` plus a path filter, PCOV `pcov.directory` scoped to the changed directories); otherwise generate the report and read off only the changed files.
- **Delete any auto-generated coverage report file (the `--coverage-clover` output or other coverage artifact) as soon as it has been read**, so it is never accidentally committed to git, and keep such artifacts in `.gitignore` as a second line of defence.
- **Report the coverage result short by default (issue #528 follow-up).** Run the coverage check on every change, but report it on the published CR / tracker comment **only** when there is something the reader must act on — uncovered changed lines (listed as Critical findings) or unavailable coverage tooling (also a Critical finding, except the sanctioned savings-mode isolated-worktree deferral in `@rules/code-review/review-process.md` *Validation & Coverage Gate*, which reports `deferred to hephaestus` instead). When every changed line is at 100% coverage and the tool ran successfully, omit the `## Coverage` section, the `Coverage:` header line, and the `coverage …` slot from the summary line. The Counts line carries the clean signal;
the omission is the report. The check itself still runs unconditionally on every CR run.
- Prefer deterministic tests.
- **Structure every test body arrange-act-assert (AAA), in that order** — setup first, then the action on the SUT, then assertions; each phase contiguous, phases separated by a blank line when the body has more than one multi-statement phase. `// Arrange` / `// Act` / `// Assert` comments are optional, never required — prefer self-documenting structure. Not violations: single-expression or single-assertion tests with no distinct phases; act and assert merged in one idiomatic expression (e.g. `expect($sut->run())->toBe(...)`, `expect(fn () => ...)->toThrow(...)`); a fixture sanity-check assertion inside the arrange phase;
sequential workflow tests where each act→assert step depends on the state left by the previous step — each step still follows AAA order internally. When multiple independent act→assert cycles share no state, split them into separate tests or a dataset.
- Use clear, human-readable test names.
- Do not use `describe()` in Pest tests.
- Prefer top-level `it()` or `test()` blocks only.
- Prefer data providers through test arguments rather than PHPDoc annotations.
- Avoid reflection in tests unless there is no reasonable alternative.
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

## Async Review Note
- When reviewing asynchronous jobs, first verify whether retry, timeout, and backoff behavior is defined in the job itself or centrally in configuration.

## CR Severity Rules
- Mark as **Moderate**:
  - a method, variable, or property name that actively contradicts what its own body does, per the *Naming* misleading-name triggers above (a getter-shaped name that mutates state, an `is*`/`has*`/`can*`-prefixed name holding or returning a non-boolean value, a name describing one action while the body performs a materially different one, a name implying read-only access that writes/deletes) — a real maintainability hazard a fixer cannot catch, but not an architectural/structural violation, so it stays below Critical per the existing stratification (`@rules/code-review/general.md` *Default severity for a rule violation*).
Escalate to **Critical** when the misleading identifier is itself a security control — an authn/authz predicate (`isAuthorized()`, `canAccess()`, `hasPermission()`), a sanitization / escaping / validation routine (`sanitize()`, `escape()`, `validate()`), a signature / token verification (`verifySignature()`, `checkToken()`), or a variable whose name asserts a trust boundary (`$validated`, `$sanitized`, `$escaped`) — a name that lies about a security control is a broken control, not a readability defect.
When `@skills/security-review/SKILL.md` already raises the same identifier under broken access control / improper input validation, that walk owns the finding — raise it once, not twice. **Gating — a name that merely reads less clearly is not this finding:** a name that is less descriptive, inconsistently cased, or could read better, without contradicting the code's actual behavior, has no applicable binding rule here. It used to fall to the "naming ... wording nits without a binding rule" Minor default, and the review no longer detects a Minor at all (`@rules/code-review/general.md` *Minor findings are not detected*), so it is not reported;
a name matching one of the triggers above is no longer "without a binding rule" and is always this Moderate finding instead. That boundary never suppresses a finding another walk raises on the same identifier; a security finding from `@skills/security-review/SKILL.md`, or a layer-placement finding from the `@rules/laravel/architecture.md` walk (e.g. a write inside a Repository), is raised independently and at its own severity.