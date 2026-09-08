---
description: Core Laravel architecture and coding conventions
paths:
  - "**/*.php"
---

## Architecture
- Keep business logic out of controllers, middleware, and Blade views.
- **Simple, self-contained domain logic** (predicates on the model's own attributes, computed values derived from already-loaded data, simple state derivations that touch nothing else) **may live as methods on the Eloquent model itself** — see the **Database and Eloquent** section for the boundary. Anything that needs external services, repositories, model managers, or new database queries goes through an Action.
- Use Actions for orchestration-heavy use cases.
- Treat controllers, jobs, events, listeners, and commands as entry points.
- Entry points must stay slim: validate input, delegate work, return a response.

## Layer Responsibilities
- Controllers: accept validated input, authorize access, delegate work.
- Actions: orchestrate use cases and business flows.
- Services: focused stateless domain/application services.
- Repositories: read-only data access.
- ModelManagers: write-only persistence.
- Data Builders: multi-method classes that map, hydrate, or normalize input into DTOs. Not Action pattern — no `__invoke()`. Never query the database.
- Eloquent Models: framework boilerplate (relationships, scopes, casts, accessors) **plus** simple self-contained domain methods on own data — see the **Database and Eloquent** section for the boundary.
- Shared Concerns (`app/Concerns/`): globally shared and reusable logic — typically traits — that is domain-agnostic and consumed across two or more unrelated domains. Never a home for domain-specific code. See the **Shared Concerns** section below.

## Shared Concerns
- `app/Concerns/` is the canonical home for all globally shared and reusable logic in the application — typically traits, but also small reusable helpers and value objects that exist purely to be consumed across unrelated domains.
- Place a trait or helper in `app/Concerns/` only when it is **globally applicable** (consumed across two or more unrelated domains, layers, or entry points), **domain-agnostic** (no knowledge of a concrete model, aggregate, feature flow, or business rule), and **reusable as-is** (consumers use it without further specialization).
- Never put domain-specific logic in `app/Concerns/` — anything tied to a concrete model, feature flow, or business rule must live in the relevant business-logic layer under `app/{Domain}/`.
- Validation rule traits (see the **Validation** section below) are one specific worked example of this rule, not the only allowed category.

## Validation
- Use FormRequest classes for controller input validation.
- Store all validation rules as reusable traits in `app/Concerns/` (e.g. `GitHubIssueNumbersValidationRules`, `JiraIssueKeysValidationRules`). Keep this approach consistent across the entire application.
- All non-FormRequest validation logic must be encapsulated in dedicated Data Validator classes (default location `app/DataValidators/{Domain}/`, but follow the project's existing convention). Data Validators must use validation rules from traits in `app/Concerns/` — never define rule arrays inline.
- Use custom Rule classes in `app/Rules/` for complex or reusable validation.
- Before adding validation logic, check `app/Rules/` for an existing custom Rule. If none exists and the logic is non-trivial or reusable, create a new custom Rule class and use it.
- Never inline `Validator::make()`, throw `ValidationException`, or use imperative guard clauses (e.g. `if (!in_array(...)) throw new InvalidArgumentException(...)`) directly in Actions, Services, Facades, controllers, jobs, commands, listeners, or Livewire components — extract into a Data Validator using validation traits from `app/Concerns/`.
- When `pekral/arch-app-services` is installed, Data Validators must use the `DataValidator` trait and call `$this->validate()` — see `@rules/laravel/architecture.md` for details.

## DTOs
- Prefer typed DTOs over raw arrays across layer boundaries.
- Use Spatie Laravel Data when the project already uses it.
- Prefer attribute-based mapping over overriding `from()` only for key renaming.
- DTOs should be simple, explicit, and immutable where practical.

## Controllers
- Use method injection.
- Never call `validate()` directly in controllers.
- Never execute database queries directly in controllers.
- Keep resource controllers CRUD-only:
    - `index`
    - `create`
    - `store`
    - `show`
    - `edit`
    - `update`
    - `destroy`
- For non-CRUD endpoints, prefer single-action invokable controllers.
- Call invokable classes using `$action($payload)`, never `$action->__invoke($payload)`.

## Database and Eloquent
- All database read operations must be encapsulated in Repository classes — never inline Eloquent queries or `DB::` calls for data retrieval in Actions, Services, Facades, controllers, jobs, commands, listeners, or Livewire components. Delegate reads to a Repository.
- All database write operations must be encapsulated in ModelManager classes (when using `pekral/arch-app-services`) — never perform inline persistence in Actions, Services, controllers, jobs, commands, listeners, or Livewire components.
- Prefer Eloquent over Query Builder or raw SQL unless there is a measured reason not to.
- **Simple, self-contained domain logic may live as methods on the model.** Allowed: predicates on the model's own attributes (`$user->isActive()`), computed values from already-loaded data (`$invoice->getFormattedTotal()`), simple state derivations (`$order->canBeCancelled()`), and similar own-data helpers. **Forbidden on models:** anything that needs external services, repositories, model managers, new database queries beyond own loaded attributes, persistence side effects, multi-entity orchestration, or HTTP / queue / event dispatching — that work must move to an Action / Service per `@rules/laravel/architecture.md`. Concrete forbidden examples:
`$user->sendWelcomeEmail()` (queue dispatch is orchestration → Action), `$order->getRecentForCustomer()` (new query is the repository's job → Repository), `$user->updatePassword(...)` (persistence belongs in a ModelManager → ModelManager / Action).
- **Accessors and methods that lazy-load relationships count as new database queries.** A method or accessor that touches `$this->relation->...` when the caller has not eager-loaded the relationship issues a query and breaches the simple-logic boundary above. Either eager-load the relationship at the call site (a Repository method) and let the model method consume already-loaded data, or move the logic out of the model entirely.
- Define relationships, scopes, casts, and accessors in models.
- Use eager loading to avoid N+1 queries.
- Do not query inside loops.
- Use `withCount()` for counts where appropriate.
- Use chunking for large datasets.
- Prefer the smallest fitting column types.
- Use snake_case for table and column names.
- When adding or changing Repository queries, verify indexes for every high-cardinality `where`, `join`, `orderBy`, and `groupBy` used by the query.
- For non-trivial, high-traffic, or large-table queries, check `EXPLAIN` before shipping. Avoid full table scans, filesort, and temporary tables unless the dataset is intentionally small.
- For composite indexes, match the query shape and left-most prefix. Put equality filters before range/order columns when that matches the actual query.
- Do not add indexes blindly. Index columns that are actually used by read paths, and account for write overhead.

## Migrations
- Write `up()` methods only if that is the project convention.
- Prefer database-level defaults as the source of truth.
- When adding columns, update `$fillable` only if the project still relies on `$fillable`.
- Never chain multiple migration-generating commands in one shell line because of timestamp collisions.
- Use `Schema::hasForeignKey()` to verify a foreign key exists before creating or dropping it, so migrations stay readable and safe to re-run. Prefer it over manual `information_schema` lookups or wrapping constraint changes in a `try`/`catch`.

## Blade and Views
- Analyze the existing UI before creating or changing views.
- Keep layout, colors, spacing, and typography consistent with the application.
- Blade views are for presentation only.
- Never execute queries in Blade templates.

## Localization and Translatable Strings
- **Every string a user can see must go through Laravel's translation layer** (`__()`, `trans()`, `@lang`, `trans_choice()`), never a hard-coded literal. This covers all three surfaces:
    - **UI** — Blade / Livewire / Filament / Vue / React labels, button text, placeholders, flash and toast messages, validation messages, Notification subject and body, Mailable and Markdown mail views, enum `getLabel()`, and Filament resource / form / table labels.
    - **Console** — human-readable output of Artisan commands: `$this->info()`, `$this->error()`, `$this->warn()`, `$this->line()`, `$this->comment()`, prompts (`ask()`, `confirm()`, `choice()`), and table headers. Purely technical / debug-only commands meant solely for developers or CI may keep literal strings when that is the project convention.
    - **API** — any human-readable text returned to a client: JSON `message` fields, `abort()` / `abort_if()` descriptions, exception messages surfaced to users, and human-readable strings in API Resources. Machine-readable error codes, enum keys, and technical identifiers stay as literals.
- Store keys in `lang/{locale}/*.php` or `lang/{locale}.json`, and add every new key to **all** shipped locales, not only the default one.
- Use translation placeholders (`:name`) instead of string concatenation so word order stays translatable; never build a sentence by concatenating translated fragments.
- Use `trans_choice()` for pluralization instead of manual singular/plural `if` branching.
- Exempt from this rule: internal log messages not shown to end users, developer-only exception messages, technical identifiers / machine codes, and debug output.

## Testing
- Prefer `Http::fake()` over mocking HTTP integrations manually.
- **Never allow real external HTTP calls in tests.** Every test that exercises an outbound HTTP integration must register `Http::fake()` (or an equivalent fake / mock client). A test that can reach a real network endpoint is a defect, even when the endpoint happens to be available.
- **Never let tests run real system processes outside the application.** Tests must not shell out to or spawn real OS processes via `Process::run()` / `Process::start()` (Laravel), `Symfony\Component\Process`, `exec()`, `shell_exec()`, `system()`, `passthru()`, `proc_open()`, or backticks. **Tests must never invoke an external binary or script directly on the system** (`git`, `node`, `npm`, `composer`, `ffmpeg`, `docker`, a `.sh` / `.py` script, or any other host executable) — the process layer must be mocked. Fake them with `Process::fake()` (Laravel 10+) or inject a test double, so the test asserts the intended command without executing it on the host.
The only exception is a process the test itself owns end-to-end (e.g. the project's own Artisan command run through `Artisan::call()`), never an external binary or system command.
- Use factories for Eloquent persistence in tests.
- Prefer storing real data in the database and using it in tests over mocking ModelManager or Repository classes. Only mock external services that cannot run in test environment.
- Add or update tests for every meaningful behavior change.
- Use `Artisan::call(CommandClass::class)` for console command execution in tests.
- Use `app()->call([$job, 'handle'])` to invoke a job under test. The container resolves the `handle()` dependencies, so the test needs no doubles and runs the same wiring the queue worker runs. See `@rules/code-testing/general.md` *Jobs* for the full contract, including when to swap a container binding instead.

## Queue and Jobs
- Queue long-running or external-dependent work.
- Jobs should be idempotent.
- Avoid heavy logic in job constructors.
- Define retries, timeout, and backoff explicitly or via config.
- When reviewing jobs, verify whether queue behavior is configured in the job class or centrally in config.
- When using an SQS FIFO queue or an SQS deduplicator package, the job class itself must expose a `deduplicationId(): string` method that returns the deduplication key.
- Do not configure the deduplication key outside the job (in dispatchers, middleware, service providers, or config callbacks) — the job is the source of truth for its own deduplication identity.
- Compose the deduplication key from stable, business-meaningful inputs (e.g. payload identifiers) so retries of the same logical event resolve to the same key.
- Do not dispatch full Eloquent models to queued jobs. Dispatch stable scalar identifiers or small explicit payload DTOs.
- Fetch fresh models inside `handle()` through Repository / ModelManager boundaries as appropriate.
- If dispatch-time state is required, serialize only the explicit fields needed by the job, never the whole model or loaded relationships.
- Queue constructors must only accept lightweight scalar values, DTOs, enums, or value objects. Avoid hydrated models, collections, large arrays, files, and service instances.
- Use `Bus::bulk()` to dispatch many jobs onto the queue in a single call when you do **not** need batch tracking — bulk notifications, imports, email campaigns, and mass background tasks. It enqueues the jobs without the overhead of a tracked batch.
- Reserve `Bus::batch()` for cases that genuinely need progress tracking, completion/failure callbacks, or cancellation. When none of those are required, prefer `Bus::bulk()` as the lighter option, and never loop over `dispatch()` per job when a single bulk call covers the same work.

## Scheduling
- Attach structured metadata to scheduled commands with `withAttributes()` (e.g. a tag or a priority) so monitoring, logging, and alerting can group, filter, and prioritize scheduled runs.
- Keep scheduling metadata declarative at the schedule definition site; do not encode the same tags or priorities ad hoc inside the command's own logic.
- Multi-server scheduled tasks must still guard against duplicate runs — see the `onOneServer()` requirement in the **Stateless Runtime** section.

## Middleware
- Use middleware only for cross-cutting concerns.
- Keep middleware focused on one concern.
- Do not place business logic in middleware.
- Middleware order must be intentional.
- Apply middleware selectively. Health checks, public API endpoints, webhooks, and static-like endpoints must not run session, auth, CSRF, or heavy middleware unless required.
- Put cheap fast-failing middleware before expensive middleware.
- Do not perform database queries, service orchestration, or external API calls in middleware unless the middleware's single cross-cutting concern requires it.

## Dependency Injection
- Always pass service dependencies via constructor, never as method parameters. This applies to Actions, Services, and all other classes.
- Exception: Livewire components do not support constructor injection — use the `boot()` lifecycle hook instead.
- Do not call `app()`, `resolve()`, or `$container->make()` inside loops or hot paths. Resolve dependencies once through constructor injection.
- Bind stateless expensive services as singletons when they are safe to share across requests in the current runtime model.
- Prefer lazy service resolution for optional or rarely used dependencies. Do not eagerly instantiate services that a request may not use.
- Keep service constructors lightweight. Constructors must not run queries, call external APIs, read large files, or perform expensive computation.

## New Feature Implementation
- Before implementing a new feature, check if an existing solution already covers the use case:
  1. Check Spatie packages first (https://github.com/orgs/spatie/repositories)
  2. Search for other well-maintained community packages
  3. Only build a custom solution if no suitable package exists
- When using an existing package, prefer the simplest and most efficient integration

## Image Processing
- Prefer Laravel's native image processing (`Illuminate\Support\Facades\Image`, added in Laravel 13.20 on top of Intervention Image v4) over `intervention/image` used directly, another image package, or raw GD/Imagick calls, whenever it covers the use case — resizing, cropping, format conversion, quality control, and simple effects. This sits ahead of the **New Feature Implementation** package waterfall (Spatie → community package → custom) for images: reach for a package or a raw driver call only when a transformation the `Image` facade does not expose is genuinely required.
- Create the image through the facade or the request helper, not by instantiating an Intervention Image manager directly: `$request->image('avatar')` for an uploaded file, or `Image::fromPath(...)`, `Image::fromStorage(...)`, `Image::fromUrl(...)`, `Image::fromBytes(...)`, `Image::fromBase64(...)` for every other source.
- Pick the resizing method that matches the intent instead of defaulting to `resize()`: `cover($width, $height)` for fixed-size thumbnails/avatars (crops to fill, no distortion), `contain($width, $height, $background)` to fit inside the dimensions with padding, `scale($width, $height)` to shrink proportionally without upscaling, and `crop($width, $height, $x, $y)` for an explicit region. Reserve `resize($width, $height)` for a call site that intentionally accepts distortion.
- Every transformation call returns a **new**, immutable `Image` instance and processes nothing until an output call (`store()`, `toBytes()`, `width()`, …) runs the pipeline. Branch variants (e.g. a thumbnail and a display size) from one base `Image` instance instead of re-reading the source per variant.
- An `Image` instance cannot be serialized and throws `ImageException` when passed into a queued job. Store the processed result first (`store()` / `storeAs()` / `storePublicly()`) and dispatch the resulting path, consistent with the existing **Queue and Jobs** rule against dispatching heavyweight objects to queued jobs.

## General Laravel Practices
- Prefer Laravel conventions and built-in features first.
- Prefer dependency injection over manual resolution.
- Prefer named routes and `route()` for URL generation.
- Follow the Laravel 11/12 application structure when the project uses it:
    - middleware, exceptions, routes in `bootstrap/app.php`
    - providers in `bootstrap/providers.php`
    - console configuration in `routes/console.php`

## Stateless Runtime
- Production application servers must be disposable. Do not rely on local mutable state that must survive a server restart or scale-out.
- Use shared session and cache stores such as Redis or Memcached for multi-server production environments.
- Store user uploads through Laravel Storage on shared/object storage disks, not hardcoded local paths.
- Use `Storage` and configured disks instead of direct `storage_path()` / `public_path()` file writes for user-facing or cross-server files.
- Scheduled tasks that may run on multiple servers must use `onOneServer()` or another explicit distributed mutex.

## Caching
- Use Redis or another shared cache for sessions, queues, cross-server locks, shared application cache, and data that must be visible across servers.
- Use APCu only for local per-server cache where stale or server-specific values are acceptable.
- Always set explicit TTLs for cached values unless the project has a documented invalidation strategy.
- Cache expensive read models or computed values at Repository / Service boundaries, not inside controllers or Blade views.
- Do not cache user-specific or permission-sensitive data without including the relevant identity and permission scope in the cache key.

## Long-Running Runtime Safety
- Write code that is safe for long-running PHP processes unless the project explicitly forbids Octane/RoadRunner/Swoole.
- Do not store request-specific data in static properties, globals, or long-lived singletons.
- Do not let singleton services accumulate per-request state.
- Prefer request-scoped local variables and explicit DTOs for request data.
- When using Octane, review memory growth, reset mutable services, and configure worker recycling.

## String Emptiness Checks
- In conditions, prefer the Laravel `filled()` / `blank()` helpers over `!== ''` / `=== ''` comparisons. Write `filled($value)` instead of `$value !== ''` and `blank($value)` instead of `$value === ''`.
- Keep the raw `!== ''` / `=== ''` form only when the exact PHP semantics matter (e.g. a `null`, whitespace-only, or empty-collection value must be treated as non-empty).

## Collections
- **Chain collection operations into one fluent pipeline.** A `Collection` method returns a `Collection`, so a sequence of transformations reads as a single expression that states what the data becomes. Write the pipeline, not a running tally of intermediate variables:
```php
$results = $coupons->chunk(
        config()->integer('coupons.import.chunk_size'),
    )->map(
        fn (Collection $chunk): CouponImportResult => $this->processChunk($chunk, $folderId),
    );
```
- **Reassigning one variable step by step is the shape to replace.** `$x = $c->filter(...); $x = $x->map(...); $x = $x->values();` names the same value three times, and each name says only *step 2 of something* — the reader reconstructs the pipeline the code took apart. Chain the calls instead. The same applies to a `foreach` that walks a collection only to accumulate into an array a `map()` / `filter()` / `groupBy()` / `sum()` call already expresses.
- **Never leave the collection mid-pipeline.** A `->toArray()` (or `->all()`) followed by an array function and a `collect()` back re-materializes the whole set twice to reach a method the collection already has. Stay on the collection until the pipeline's final value is what the caller consumes. Convert once, at the boundary that requires an array.
- **Break a long chain across lines, one operation per line**, as in the example above, so the pipeline reads top to bottom. Length is not what makes a chain unreadable — a step whose closure needs more than one statement is, and that step becomes a named method the chain calls (`->map($this->toImportResult(...))`), which is also where the Action / Data Builder boundary already puts it.
- **Name an intermediate result when it genuinely has more than one consumer.** A collection two later statements both read is a value with a name, not a broken chain, and forcing it back into two pipelines computes it twice. This rule replaces reassignment of a single-use temporary; it never mandates one expression per method.
- **A chain is not permission to load the set.** How much the pipeline holds at once is owned by `@rules/code-review/general.md` *Bulk Data & Batch Processing (issue #223)*, and what the database should have done instead by `@rules/sql/optimalize.md` — a fluent `->get()->filter()` over a whole table is that finding, at that severity, never this one's.