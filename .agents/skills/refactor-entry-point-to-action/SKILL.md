---
name: refactor-entry-point-to-action
description: "Use when refactoring controller, job, command, listener, or Livewire entry-point logic into a dedicated Action class while preserving behavior and response contracts."
license: MIT
metadata:
  author: "Petr Král (pekral.cz)"
---

## Constraints
- Apply `@rules/refactoring/general.md` — incremental migration only, never a big-bang rewrite. The **Test Coverage Contract** in that rule is binding: 100% coverage of the target lines must exist in a dedicated `test(scope): cover <area> before refactor` commit *before* the entry-point change lands, and the assertion logic of those tests must remain unchanged through the refactor commit.
- Apply `@rules/php/core-standards.md`.
- If the current project uses Laravel, also apply `@rules/laravel/laravel.md`, `@rules/laravel/architecture.md`, `@rules/laravel/filament.md`, and `@rules/laravel/livewire.md`
- Preserve behavior, signatures, response contracts, and tenant/account scope. Rewrite the entry-point code **strictly per the applied rules** — anything that would deviate (parameter count, naming, nesting, layer placement, validation home) is rewritten until it complies.
- Do not report review output to any third-party service.
- After changes (`MODE=apply` only), run an internal architecture-first review and fix important findings immediately. In `MODE=cr` there are no changes — emit the Action-extraction proposal and stop.

## Modes

This skill runs in one of two modes, selected by the caller via `MODE` (default `apply`):

- **`apply` (default)** — perform the entry-point → Action refactoring: create / update the Action, move orchestration, run fixers / checkers, and chain the After Completion review. The Execution and Done-when steps below behave as written.
- **`cr` (read-only lens — invoked by a caller that explicitly asks for a read-only proposal)** — **never modify code, never create files, never stage / commit / push, never run fixers or checkers, and never chain `code-review` / `process-code-review`.** Scope the analysis to entry points (controller / job / command / listener / Livewire) touched by the PR diff that still hold business orchestration, and return — as markdown only — the proposed Action extraction for each:
the entry-point `Class::method`, the orchestration that should move out, the target `app/Actions/<Domain>/<ActionName>` and Data Validator, and the rule reference. No code review invokes this mode any more — the two review sections it used to fill are retired (`@rules/code-review/review-process.md` *Refactoring & Tech Debt (DRY) Analysis — retired*), so the proposals are returned to the caller. Execution steps 3–11 below apply to `MODE=apply` only.

## Use when
- A controller, job, command, listener, or Livewire component method contains business orchestration that should be moved into an Action.
- You want a thin entry point that delegates one use case to one Action.

## Manual invocation
Always include:
- Entry-point file path
- Target method (`Class::method`)
- Expected Action class name and domain folder (optional — the skill proposes a default name and domain when not provided, instead of asking the user)
- Any response/signature compatibility constraints

Example input:
- `Refactor entry point <Class::method> in <path> to Action pattern.`
- `Keep behavior and response contract unchanged.`
- `Create or reuse Action in app/Actions/<Domain>/<ActionName>.php and delegate from the entry point.`
- `Respect @rules/laravel/architecture.md.`

## Required architecture
- Entry point must become thin and delegate directly to an Action via `$action(...)`.
- **Reuse before you create: an Action that already covers the use case is the target of the extraction.** Search `app/Actions/**` before you write a new class — read the `__invoke()` of every Action in the target domain folder and grep for the collaborators the extracted orchestration would compose. Point the entry point at that Action, or widen it, instead of adding a second Action for one use case. Match on the flow, never on the class name; two Actions that share collaborators while orchestrating different use cases stay two Actions (see `@rules/laravel/architecture.md` **Actions** → *Before you create an Action*).
- Create one dedicated Action per use case under `app/Actions/<Domain>/`.
- Action class must be `final readonly`.
- Action must expose exactly one public business method: `__invoke(...)` with an explicit return type.
- When the extracted `__invoke(...)` needs a DTO to carry its input, give it **exactly one** — a single carrier named after the use case, never two DTOs and never a DTO beside a loose scalar / array holding part of the same payload. The acted-on model (or its identifier) and the returned DTO are not second payloads. An input that is a single model or a single scalar needs no DTO at all (see `@rules/laravel/architecture.md` **Action Rules** → *One DTO per `__invoke()`*).
- Action must orchestrate only: it delegates validation, mapping, and persistence to the dedicated layers.
- **Never pass the HTTP request into the Action.** The extracted `__invoke(...)` declares no `Illuminate\Http\Request` and no `FormRequest` parameter, and never reaches for the request from inside its body (`request()`, the `Request` facade, `app('request')`). This is the input-side half of preserving the response contract: the entry point keeps both ends of client↔server communication.
Convert the request in the entry point — `$request->toDto()` on the endpoint's FormRequest, or `$request->validated()` mapped by a Data Builder — and pass that DTO. Concrete values pulled off the request (an `UploadedFile`, a route-bound Model, the authenticated user, a scalar) are not the request; once there is more than one of them they belong together in the one DTO (see `@rules/laravel/architecture.md` **Action Rules**).
- **The Action returns plain domain data, never an HTTP response.** Keep `response()` / `response()->json()` / `redirect()` / `back()` / `view()` and any `Response` / `JsonResponse` / `RedirectResponse` construction in the entry point — the controller stays the owner of client↔server communication. The Action's `__invoke()` returns a Model / DTO / Collection / scalar / `void`, and the controller builds the HTTP response from it. This is part of preserving the response contract.
- Do not place inline validation inside the Action. Extract every validation-style guard — `instanceof` / null / range / amount checks that reject or skip input via `throw`, `return`, or `continue`, plus `throw_if()` / `throw_unless()` calls — into a dedicated Data Validator (default location `app/DataValidators/<Domain>/`, but follow the project's existing convention; `Pekral\Arch\DataValidation\DataValidator` trait when the package is installed). Data Validators must use validation rules from reusable traits in `app/Concerns/`.
- Do not place inline data mapping/transformation inside the Action. Any payload-building, model/collection mapping, key renaming, default fallback, or value formatting (e.g. a private `buildPayload()` helper) must be extracted into a Data Builder (`Pekral\Arch\DataBuilder\DataBuilder` trait when the package is installed) that the Action calls.
- Do not use direct Eloquent queries or `DB::` calls inside the Action.
- Keep reads in repositories (`Pekral\Arch\Repository\Mysql\BaseRepository`) and writes/updates/deletes in model managers (`Pekral\Arch\ModelManager\Mysql\BaseModelManager`) / services according to project architecture.
- When the orchestration touches the database in a loop, prefer ModelManager batch methods (`batchUpdate`, `batchInsert`) and bulk delete/read patterns (`whereIn(...)->delete()`, `findBy{Attribute}In(...)` keyed in memory) over per-row queries (see `@rules/sql/optimalize.md` "Batch over per-row operations"). Per-row queries inside the Action are allowed only when iterations have an unavoidable side-effect dependency that must be justified in a code comment.
- Add or update PHPDoc where needed for PHPStan clarity.
- **Livewire entry points — Blade view co-refactor.** When the entry point being refactored is a Livewire component, also inspect its Blade view (`resources/views/livewire/<...>.blade.php`). Walk it against the triggers in `@rules/laravel/livewire.md` *HTML / Blade Layout Splitting* (repeated markup, >150 Blade lines, self-contained `wire:*` cluster, self-contained data shape, cross-page reuse, independent loading / empty / error state, distinct named UI concern). For every match, propose the extraction in the refactor plan: name the extracted concern, pick the correct component type per the rule's **Component-type decision** (Livewire only for stateful / lifecycle / server-interactive blocks;
Blade for stateless presentation — never a Livewire wrapper around a pure presentational block), and place the new component under the concern's domain folder (`app/Livewire/<Domain>/` or `resources/views/components/<domain>/`). The extracted children must satisfy the **Reusability contract** in the rule (typed input, one concern, no business logic, events not parent reach-through, independently renderable, concern-based name). **Apply-mode requirement:** the extractions must land in a dedicated `refactor(scope):
split <view> into reusable components` commit that follows the Action-extraction commit and respects the **Test Coverage Contract** in `@rules/refactoring/general.md` in spirit — every rendered branch of the touched view is covered by a Livewire / Blade feature test committed before the layout refactor, and those feature tests stay green through the refactor commit unchanged. PHP `--coverage-clover` does not measure `.blade.php` line-by-line, so the binding gate is feature-test parity, not a numeric coverage percentage on the view file. **CR-mode requirement:** the proposals must be emitted as markdown findings (`file:line`, concern name, Livewire-vs-Blade choice, target folder, rule reference) and the skill stops without modifying code.

## Read, Map & Verify before refactoring (mandatory pre-flight)

> **`MODE=cr`:** perform Read and Map read-only to ground the extraction proposal in the real code; Verify is the read-only audit. Do not modify code.

Reading, mapping, and verifying come first; refactoring comes last. This pre-flight is **blocking** — do not edit a single line of production code until all three steps pass, and never act on an assumption you have not confirmed by reading the code.

1. **Read** — open and read the actual entry point and the code it orchestrates (called Services / Repositories / ModelManagers, the Blade view for Livewire components, related tests, configuration). Confirm what the orchestration does by reading it, not by guessing from names.
2. **Map** — map the change's blast radius: the entry point's response contract and signature, its callers and routes, the orchestration that must move into the Action, and the existing Actions / Data Validators / `app/Concerns/` traits to reuse instead of reinventing. **Reading the existing Actions is mandatory, not optional context.** Open the `__invoke()` of every Action in the target domain folder and decide, per Action, whether it already orchestrates this use case. That decision drives Execution step 4, and skipping it is how a second Action for one use case gets written.
   Then run a **completeness sweep** over the whole tree. Grep the entire repository for every name, route, signature, and convention the extraction moves or redefines, and every call site, test, and public API consumer bound to them — never only the files the assignment names, and never only the files you have already opened.
   Cover every file category the repository carries: source, tests, `rules/`, `skills/`, `agents/`, documentation, configuration, and generated assets such as `CHANGELOG.md` or `README.md`. Record the full match list before you move a single line into the Action, then classify each match as in scope for this extraction or as a stated exception. An incomplete sweep leaves a caller, a route, or a documented contract still bound to the entry point's old shape, and that binding surfaces later as a failing pinned test or a broken cross-reference.
3. **Verify** — check your assumptions against the real code and its observed behavior so the extraction preserves behavior, signatures, and tenant/account scope. If reading and mapping contradict the task framing, stop and surface the discrepancy instead of refactoring on a wrong premise.

Only after Read, Map, and Verify are complete may the Test Coverage Gate and the extraction proceed.

## Execution

> **`MODE=cr`:** run steps 1–2 read-only, then emit the Action-extraction proposal described under Modes and stop — do not run steps 3–12 (they author tests, create files, run fixers, and chain reviews).

1. Inspect the target entry point and identify orchestration responsibilities.
2. Scan touched files for obvious pre-existing issues that would block or compromise the refactor. Fix only safe, relevant issues; keep unrelated cleanup out of scope.
3. **Test Coverage Gate (blocking pre-flight).** Verify coverage of the *current* entry-point method that the refactor will touch, using the project's available coverage tooling scoped to that file (per `@rules/php/core-standards.md` Testing section). Every line, branch, and condition must already be at 100%. If coverage is below 100% on the target lines, **stop and write the missing tests first** via `@skills/create-test/SKILL.md`, then commit them in a dedicated `test(scope): cover <area> before refactor` commit per `@rules/git/general.md` Allowed Types. The pre-refactor coverage commit and the refactor commit are **always two separate commits**. Only after the gate is green may the refactor proceed.
4. **Reuse-or-create decision (blocking).** Search `app/Actions/**` for an Action that already orchestrates this use case, as the Map step required. Reuse that Action when one exists — point the entry point at it, or widen it. Create a new Action in the correct domain folder only when the search finds none, and record in the refactor plan which Actions you read and why none of them fits.
5. Move orchestration from the entry point into the Action `__invoke(...)`.
6. Extract inline validation into a dedicated Data Validator (using validation traits from `app/Concerns/`) if needed.
7. Preserve repository/service/manager boundaries and multitenancy/account scope.
8. Update the entry point to delegate via `$action(...)` and keep its public contract unchanged.
9. **Do not modify assertion logic of pre-existing tests inside the refactor commit.** The pre-refactor coverage commit fixed the behavior-preservation contract; the refactor commit changes structure only. Mechanical renames forced by the refactor itself (namespace move, constructor / argument shape forced by the extracted DTO) are the only allowed test edits and must be flagged in the commit body. If an assertion would have to change to make the refactor green, you are no longer refactoring — split the behavior change into its own commit. New tests covering newly introduced code paths (e.g. the Data Validator's failure modes that did not exist before) belong in a separate `test(scope): …` commit *after* the refactor.
**After the refactor commit, re-run the coverage tooling scoped to the changed files and confirm coverage stayed 100% with the pre-existing assertions passing unchanged** — a refactored line that is no longer covered signals an untested path to fix, never a number to restore by editing the pre-refactor tests (step 4 of the **Test Coverage Contract** in `@rules/refactoring/general.md`).
10. Discover available fixers and checkers (prefer Phing targets from `build.xml`/`phing.xml`; fall back to Composer scripts in `composer.json`). Run fixers first, then checkers/analyzers on all changed files. Resolve all reported issues.
11. **Run the review inline.** Invoke `@skills/code-review/SKILL.md` directly in this skill's context, passing the refactor commit range plus the instruction to return Critical / Moderate / Minor findings with their reproducer fields. Do not dispatch the review as a subagent — run it sequentially in the current context.
12. Run `@skills/process-code-review/SKILL.md` inline (per its own contract) and fix critical or medium findings before finishing.

## Do not
- Do not leave business orchestration in the entry point.
- Do not place Actions outside `app/Actions/**`.
- Do not add a second Action for a use case an existing Action already orchestrates — reuse or widen that Action instead.
- Do not add multiple public business methods to an Action.
- Do not place validation logic directly inside an Action (incl. `instanceof` / null / amount skip-guards and `throw_if()` / `throw_unless()`) — extract into a Data Validator.
- Do not place data mapping/transformation directly inside an Action — extract into a Data Builder.
- Do not return or construct an HTTP response inside an Action — the Action returns domain data, the controller builds the response.
- Do not bypass repository/model-manager/service boundaries.
- Do not introduce unrelated behavioral changes.
- Do not add speculative flexibility, configurability, or error handling while extracting the Action. The extraction moves orchestration as-is into the Action and the Data Validator; new parameters, mode switches, strategy hooks, retry knobs, or guards for scenarios the original entry point did not handle belong to a separate `feat(scope): …` commit and a separate issue. Apply the **Simplicity First** rule from `@skills/class-refactoring/SKILL.md` Refactoring Guidelines and the YAGNI rules in `@rules/php/core-standards.md` Design Principles.

## Done when

**`MODE=apply`:**
- The target entry point is thin and delegates to a dedicated Action.
- `app/Actions/**` was searched before the Action was written, and the refactor plan records either the existing Action that was reused or the Actions that were read and why none of them fits.
- The Action follows project Action-pattern rules.
- Validation is delegated to a dedicated Data Validator (using validation traits from `app/Concerns/`) when applicable.
- Behavior, signatures, and response format remain unchanged.
- The pre-refactor coverage commit reports 100% coverage on the entry-point lines that were refactored, and the assertion logic in those tests is unchanged through the refactor commit (mechanical renames flagged in the commit body excepted).
- After the refactor, coverage scoped to the changed files was re-verified and **stayed** 100% with the pre-existing assertions passing unchanged.
- New tests covering paths introduced by the refactor (e.g. Data Validator failure modes) live in a separate `test(scope): …` commit after the refactor.
- Fixers and checkers ran clean on all changed files.
- Internal architecture-focused review was completed and important findings were fixed.

**`MODE=cr`:** the Action-extraction proposal was emitted as markdown for every qualifying entry point in the diff (entry-point `Class::method`, orchestration to move out, target Action / Data Validator, rule reference) and **no files were created or modified**.

## Output Humanization
- Use [blader/humanizer](https://github.com/blader/humanizer) for all skill outputs to keep the text natural and human-friendly.
