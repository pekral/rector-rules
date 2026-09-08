---
description: SQL query optimization, index design, schema standards, and advanced SQL patterns for MySQL/MariaDB.
paths:
  - "**/database/migrations/**/*.php"
  - "database/migrations/**/*.php"
  - "**/*Repository.php"
  - "**/*ModelManager.php"
  - "**/*.sql"
---

## General
- No N+1: use `with()`, `load()`, or JOINs
- SARGable WHERE clauses (no functions on indexed columns)
- Seek pagination over OFFSET
- Never `SELECT *`; fetch only needed columns
- Use EXPLAIN for new or changed queries: avoid type ALL, high rows, Using filesort, Using temporary
- Prepared statements with bound parameters; never concatenate user input into SQL
- Push filtering, sorting, aggregation into SQL; avoid doing it in application code
- Refactor or split very complex joins when EXPLAIN shows poor plans; when profiling use slow query log and prioritize frequent or longest queries
- **Indexes:** index columns used in WHERE, JOIN, ORDER BY, GROUP BY; composite index order must match query filter/sort; avoid low-cardinality-only indexes; use covering indexes when a query can be satisfied from the index; drop unused or redundant indexes when changing schema; aim for 3–5 well-chosen indexes per table; prefer parallel index creation on large tables
- **Transactions:** keep transactions short; avoid holding locks during app logic; batch writes in single transactions where appropriate; reduce lock contention via batching and suitable isolation levels; use `SHOW ENGINE INNODB STATUS` to diagnose lock waits when investigating issues
- Index JOIN columns on both tables; composite index order matters (left-to-right)

## Query Analysis
- Run `EXPLAIN` on every new or modified query.
- Flag: type `ALL`, high `rows`, `Using filesort`, `Using temporary`.
- Use `EXPLAIN ANALYZE` for actual vs estimated row counts.
- Check slow query log — prioritize frequent or longest-running queries.
- Apply one optimization at a time; measure before and after.

## Performance Non-Regression on Query Changes
Whenever a query is **refactored or changed** (Eloquent / query-builder rewrite, raw-SQL edit, added / removed `JOIN` / `WHERE` / `ORDER BY` / `GROUP BY` / subquery / eager load, pagination change, index-driven rewrite, or a refactor that moves the query into another layer), the changed query **must be at least as fast as the original — ideally faster**. Never ship a query change that is slower without a documented justification.

- **Capture the baseline first.** Before changing the query, record the original query's plan and cost: `EXPLAIN` (and `EXPLAIN ANALYZE` when DB access is available) — note `type`, `key`, `rows`, `filtered`, `Extra`, and the actual execution time / rows examined. This is the number the new query is held against.
- **Compare after the change.** Run the same `EXPLAIN` / `EXPLAIN ANALYZE` on the new query and compare against the captured baseline. The new query passes only when it is **equal or better** on the decisive signals: rows examined, access `type`, index usage, `filesort` / `temporary` avoidance, and measured latency. Equal-or-fewer rows examined and equal-or-lower latency is the gate.
- **When the change is slower, it does not ship silently.** If the changed query is measurably slower than the original, you must document, in the PR description / commit body / analysis report:
  1. **Why it is slower** — the concrete cause (e.g. an added `JOIN` widens the row set, a correctness fix removes an index-only path, a denormalization was undone).
  2. **What further optimization options remain** — concrete, actionable next steps (index addition / reorder, covering projection, SARGable rewrite, batching, caching, denormalization, splitting the query), **or** an explicit statement that no further optimization is possible and why (e.g. the slowdown is the unavoidable cost of a required correctness fix).
  3. **Why the slower query is still acceptable** — the trade-off that justifies shipping it (correctness, removed N+1 elsewhere, net round-trip reduction across the request).
- **A slowdown with no documented reason and no listed optimization options is a defect**, not an acceptable change — treat it as a blocking finding in review and as a stop condition in refactoring.
- **When the change legitimately alters the result set** (a new feature adds a filter / join / aggregation so the query intentionally returns different rows), the equal-or-faster comparison is **informational, not a pass/fail gate** — there is no behavior-preserving baseline to match. The gate is strict for optimization- or refactoring-intent changes (same result, different shape); for result-changing changes, still capture the cost and apply the document-why-slower + optimization-options requirement so the added cost is understood, but do not block solely because the richer query is slower than the narrower original.
- **When DB access is unavailable**, compare statically from the `EXPLAIN` plan shape and index reasoning, hold the same equal-or-better bar against the reconstructed baseline, and state the limitation explicitly — never claim a measured improvement you did not measure.

## Query Optimization
- SARGable WHERE clauses only — no functions on indexed columns (`DATE(col)`, `LOWER(col)`, `col + 1`).
- Prefer ranges: `col BETWEEN ? AND ?` instead of `DATE(col) = ?`.
- Seek pagination (`WHERE id > ? LIMIT ?`) instead of OFFSET for large datasets.
- Push filtering, sorting, and aggregation into SQL — never in application code.
- Never `SELECT *` — fetch only needed columns.
- Prepared statements with bound parameters; never concatenate user input into SQL.
- Avoid negative conditions (`<>`, `!=`, `NOT IN`, `NOT LIKE`) — they prevent index usage.
- Prefer `EXISTS` over `COUNT(*)` for existence checks — stops at first match.
- Use set-based operations over row-by-row processing.

```sql
-- Bad — function on indexed column
SELECT * FROM users WHERE DATE(created_at) = '2025-01-01';

-- Good — SARGable range
SELECT * FROM users WHERE created_at BETWEEN '2025-01-01 00:00:00' AND '2025-01-01 23:59:59';

-- Bad — OFFSET pagination on large table
SELECT * FROM users ORDER BY id LIMIT 25 OFFSET 25000;

-- Good — seek pagination
SELECT * FROM users WHERE id > 25000 ORDER BY id LIMIT 25;

-- Bad — COUNT for existence
SELECT * FROM users WHERE (SELECT COUNT(*) FROM orders WHERE orders.user_id = users.id) > 0;

-- Good — EXISTS
SELECT * FROM users WHERE EXISTS (SELECT 1 FROM orders WHERE orders.user_id = users.id);
```

## Reuse existing indexes first
- Before adding a new index, verify that the query cannot be rewritten to hit an existing one. Re-order `WHERE` / `JOIN` / `ORDER BY` columns to match an existing composite index (left-to-right rule), strip functions wrapping indexed columns (SARGable rewrite), and project only the columns the index already covers (covering query).
- During code review of new or modified SQL / Eloquent / query-builder code, locate the current schema (migrations, model `$table` metadata, live `SHOW INDEX` when DB access is available) and flag every query that bypasses an existing index that could satisfy it. The fix is a query rewrite, not a new index.
- Add a new index only when the existing schema genuinely lacks one that can cover the query, EXPLAIN confirms the gap, and the rewrite alternative has been ruled out. Then follow the **Index Design** constraints below (composite order, 3–5 indexes per table, drop redundant).

## Index Design
- Index columns used in `WHERE`, `JOIN`, `ORDER BY`, `GROUP BY`.
- Composite index order must match query filter/sort (left-to-right rule).
- Use covering indexes when a query can be satisfied from the index alone.
- Index JOIN columns on both sides.
- Aim for 3–5 well-chosen indexes per table.
- Drop unused or redundant indexes when changing schema.
- Prefer parallel index creation on large tables.
- Do not create indexes on low-cardinality columns alone.
- Do not keep single-column indexes when a composite index already covers them.
- Nullable columns should appear last in composite indexes.

```sql
-- Query filters by (user_id, status) and sorts by created_at
-- Composite index must match this order:
ALTER TABLE orders ADD INDEX idx_user_status_created (user_id, status, created_at);
```

## Batch over per-row operations
- Solve database tasks and queries as a batch whenever possible. Per-row queries issued from inside a loop are a smell — flag during refactoring and code review.
- **Bulk update:** prefer a ModelManager batch method (e.g. `batchUpdate($model, $rows, 'id')` backed by `Iksaku\Laravel\MassUpdate`) over looping per-row `Model::update()` / `$model->save()` calls.
- **Bulk insert:** prefer a ModelManager batch method (e.g. `batchInsert($model, $rows)`) over looping per-row `Model::create()` calls.
- **Bulk delete:** prefer a single `whereIn(...)->delete()` over per-row `Model::delete()` calls.
- **Bulk read:** fetch the whole working set in one query (e.g. `findBy{Attribute}In(...)`) and key it in memory; never look rows up one by one inside a loop.
- **Goal:** minimize DB round-trips and lock contention.
- **Acceptable exception:** per-row work that genuinely cannot be batched because each iteration depends on a side effect of the previous one (e.g. each row triggers a downstream API call that mutates DB state the next row reads). The exception must be justified in a short code comment or in the PR description.

```php
// Bad — per-row update inside a loop
foreach ($users as $user) {
    $user->update(['status' => 'active']);
}

// Good — single batch update via ModelManager
$this->userModelManager->batchUpdate(User::class, $rows, 'id');

// Bad — per-row delete
foreach ($staleIds as $id) {
    Token::query()->whereKey($id)->delete();
}

// Good — single bulk delete
Token::query()->whereIn('id', $staleIds)->delete();

// Bad — per-row lookup inside a loop
foreach ($externalIds as $externalId) {
    $contact = $this->contactRepository->findByExternalId($externalId);
    // ...
}

// Good — one bulk read keyed in memory
$contacts = $this->contactRepository->findByExternalIdIn($externalIds)->keyBy('external_id');
foreach ($externalIds as $externalId) {
    $contact = $contacts->get($externalId);
    // ...
}
```

## Bounded reads over unbounded materialisation
Batching the *writes* is only half the problem. A loop that batches perfectly still falls over if the collection it iterates was loaded whole: `Model::all()`, an unfiltered `->get()`, or a `->pluck()` over a table that grows with the business holds every row and every hydrated model in memory at once. It passes every test against a seeded fixture set and dies in production against real volume, which is why it survives review — the defect is invisible at the size the reviewer sees.

- **A result set whose size grows with the data is read in chunks, never materialised whole.** Use `chunkById()` for a keyset walk, `lazyById()` / `cursor()` when the caller wants a single `foreach` over a lazy stream, and pass an explicit chunk size. A set with a hard, small upper bound the schema itself guarantees — a lookup table, an enum-backed list, a `LIMIT`ed top-N — is materialised whole without a finding.
- **Prefer `chunkById()` / `lazyById()` over `chunk()` / `lazy()` when the loop writes to the same table it reads.** Offset-based `chunk()` re-runs the query per page, so a row the loop updates out of the filtered set shifts every later page and the walk **silently skips rows**. Keyset-based `chunkById()` walks `id > lastSeen` and cannot skip. This is a correctness bug, not only a performance one.
- **`cursor()` bounds PHP memory, not the driver's.** It streams hydrated models one at a time, but the underlying PDO connection still buffers the whole result unless the driver is put into unbuffered mode. Reach for `chunkById()` when the set is large enough that the buffer itself is the problem.
- **An `IN (…)` list is bounded too.** A `whereIn()` built from an unbounded caller-supplied array grows the statement until it hits `max_allowed_packet` or the placeholder limit. Chunk the list (`array_chunk($ids, 1000)`) and issue one query per chunk.
- **Goal:** peak memory and statement size stay flat as the table grows, instead of tracking it.

```php
// Bad — the whole table is hydrated before the first iteration
foreach (Order::all() as $order) {
    $rows[] = ['id' => $order->id, 'total' => $order->recalculateTotal()];
}

// Bad — offset paging while writing to the same filtered set skips rows
Order::query()->where('needs_recalc', true)->chunk(500, function (Collection $orders): void {
    $this->orderModelManager->batchUpdate(Order::class, $this->recalculate($orders), 'id');
});

// Good — keyset paging cannot skip, and peak memory is one chunk
Order::query()->where('needs_recalc', true)->chunkById(500, function (Collection $orders): void {
    $this->orderModelManager->batchUpdate(Order::class, $this->recalculate($orders), 'id');
});

// Good — an unbounded id list is chunked instead of one oversized statement
foreach (array_chunk($externalIds, 1_000) as $chunk) {
    $contacts = $this->contactRepository->findByExternalIdIn($chunk);
    // ...
}
```

## Transactions and Locking
- Keep transactions short — no external calls or heavy logic inside.
- Batch related writes in a single transaction.
- Use appropriate isolation levels for the use case.
- Deadlock-prone operations must include retry logic.
- Reduce lock contention via batching and suitable isolation levels.
- Use `SHOW ENGINE INNODB STATUS` to diagnose lock waits.

## Deploy-safe schema changes
A query is judged against the rows it reads. A schema change is judged against the moment it runs — the deploy window, while the previous release still serves traffic and the table is at production size. An `ALTER TABLE` that finishes in milliseconds against a seeded fixture table can hold a metadata lock for minutes against a real one, and every statement behind that lock queues until it times out. The defect hides for the same reason an unbounded read does: the reviewer only ever sees the small table.

- **Every `ALTER TABLE` states the algorithm and the lock it expects** — `ALTER TABLE orders ADD INDEX idx_status_created (status, created_at), ALGORITHM=INPLACE, LOCK=NONE`. MySQL picks both silently, and the pick is not always the cheap one. Naming them makes the statement **fail immediately** when the server cannot perform the change online, instead of falling back to a full table copy that blocks writes for its whole duration.
A change that genuinely cannot run online — most type changes (`MODIFY` / `CHANGE COLUMN`), a `PRIMARY KEY` change, a column added to a table with a compressed row format — does not ship as a plain `ALTER`: route it through an online-schema-change tool (`pt-online-schema-change`, `gh-ost`) or split it into steps that each run online.
- **A data backfill never rides inside the schema migration.** One `UPDATE` over a populated table holds a row lock per row for a single transaction, grows the undo log for the whole run, and stalls replicas by exactly the time it takes. Split the two: the migration performs the DDL only, and the backfill runs afterwards as a separate, re-runnable, chunked command (`chunkById()` per **Bounded reads over unbounded materialisation**, an explicit chunk size, and a `WHERE` that skips the rows already done). The deploy order is expand → backfill → contract, never one migration doing all three.
- **DDL is not transactional in MySQL, so a mixed migration cannot roll back.** Each DDL statement commits implicitly, so a migration that runs DDL and then DML leaves the DDL applied when the DML fails. `down()` is then the only way back: it must exist and must actually reverse the change. A migration whose `down()` is empty or throws is a migration that cannot be reverted in the one deploy window that needs it.
- **Adding a foreign key is a full-table operation.** `ADD FOREIGN KEY` validates every existing row and cannot run with `LOCK=NONE` while `foreign_key_checks` is on. On a populated table it is its own deploy step, sized on its own — never bundled into a migration that also adds columns or indexes.
- **Size the change against production, not against the local database.** State in the PR description the row count of every populated table the change touches and the measured or estimated duration of each DDL statement. A change nobody has sized is a change nobody can schedule.

## Schema Design
**Scope: MySQL 8.0.16+ on InnoDB.** Everything from here through **When to Break These Rules** assumes that version — it is the one from which `CHECK` constraints are enforced instead of silently parsed and ignored — and assumes strict `sql_mode` (see **Strict SQL Mode** below). On PostgreSQL these are not a syntax translation but different semantics — its timestamp types are 64-bit so the `TIMESTAMP` prohibition below does not transfer, `UNSIGNED` does not exist, and neither does `utf8mb4` — so use `@skills/postgres-patterns/SKILL.md` for that engine instead.

- Primary keys on every table.
- Fitting data types: `INT`, `DECIMAL`, `VARCHAR(n)`, `DATETIME`. Read that as a starting point, not as the permitted set — `DATE`, `BIGINT`, `TEXT` / `MEDIUMTEXT`, `ENUM`, and `CHAR(n)` are each mandated by a type section below (**Date and Time Column Types**, **Primary Key Sizing**, **String, Text, and ENUM Types**, **Money and Decimal Types**). Pick the type there; a reader who treats this one line as exhaustive stores a calendar day as `DATETIME`, which is the bug **Date and Time Column Types** exists to prevent.
- InnoDB engine.
- `lower_case_snake_case` naming.
- Normalized unless denormalization is justified by read performance.
- Partition large tables by range where beneficial.
- Non-blocking index creation on large tables where supported.

## Strict SQL Mode
Strict `sql_mode` is the second prerequisite the whole schema block rests on (the first — MySQL 8.0.16+ on InnoDB — is stated under **Schema Design**). Without it, every rule in that block degrades from an enforced guarantee to a best-effort default with a silent fallback.

- Set it **server-side**, never only on the connection — a connection-level setting can be silently overridden by any client: `STRICT_TRANS_TABLES,ONLY_FULL_GROUP_BY,NO_ZERO_DATE,NO_ZERO_IN_DATE,ERROR_FOR_DIVISION_BY_ZERO,NO_ENGINE_SUBSTITUTION`.
- Enable it **from day one**. Turning strict mode on over a database that already holds truncated or zero-value data does not fix that data — it only defers the crash to the first `UPDATE` of an affected row, months later.
- Without strict mode: an out-of-list `ENUM` value silently stores as `''` instead of erroring, an overflowing `INT UNSIGNED` clamps to its maximum instead of erroring, a value longer than the declared `VARCHAR(n)` is silently truncated instead of erroring, `'0000-00-00'` is accepted instead of rejected, and a missing `NOT NULL` column silently gets `0` or `''` instead of failing the insert.

## Naming Conventions
Builds on the `lower_case_snake_case` naming rule above. A database name is a public interface other things depend on — application code, but also ad-hoc SQL, reports, exports, and integrations — so renaming a column is the same class of breaking change as renaming a public method.

- **Singular table names** (`post`, not `posts`). Two durable reasons survive any style preference: a singular name maps 1:1 to the class it represents with no plural/singular translation layer in every layer, and it keeps a table's family together alphabetically (`post`, `post_slug`, `post_tag` sort next to each other; `posts` sorts away from them).
- **In Laravel, this needs an explicit `$table` override.** Eloquent derives a model's table name as the plural of the class name by default, so a singular table (`post`) needs `protected $table = 'post';` on the model — decide it once per project and keep it consistent.
- **Primary key column is always `id`.** Foreign keys are `<singular>_id` (`author_id`), or `parent_id` for a self-reference. When more than one FK targets the same table, name the column after its **role**, not its target (`author_id`, `reporter_id` can both point at `user`) — the FK constraint itself already records the target.
- **Module prefix only once it earns its cost** (`shop_order`, `shop_product`). Inside a module, a FK does not need the prefix — the table's own namespace already carries it.
- **Name for meaning, not implementation.** `weight_grams`, `timeout_seconds` — the unit disambiguates a bare number. `amount_int`, `data_json` — these only restate the column's type, which already lives in the schema.

## Nullability and Defaults
- Make a column nullable only when the **absence of a value is a fact about the domain**, not a technical convenience. For numbers and dates this is usually unambiguous — there is no "empty" number, so `NULL` is the only honest way to represent "no value".
- Strings are the ambiguous case, because `''` is also available: decide once, per column, whether `NULL` and `''` mean the same thing. In most cases the answer is `NOT NULL DEFAULT ''`, and application code tests `!== ''`. In PHP, both `null` and `''` are falsy, so a distinction the schema works hard to preserve is usually invisible to the application anyway — the extra state is not just redundant but unobservable.
- The rare legitimate exception is when `NULL` and `''` truly mean different things (e.g. `''` = "intentionally blank, do not inherit from parent" vs `NULL` = "not filled in yet"). When you take this exception, the meaning **must** go in a column `COMMENT`, or nobody will reconstruct it a year later.
- `NULL` earns this caution because it behaves unlike most people expect: `WHERE col <> 'x'` does not return `NULL` rows (the most common silent bug); `col NOT IN (subquery)` returns nothing at all if the subquery contains a single `NULL`; `UNIQUE` treats `NULL` values as mutually distinct, so any number of them are allowed, while `GROUP BY` folds them into one group.
- `DEFAULT` is a semantic claim, not a crash guard — set one only when the value is domain-meaningful **at the moment the row is created**. Let a genuinely required field fail the `INSERT` instead of silently defaulting it. `status DEFAULT 'draft'` is fine, an order really does start as a draft; `price DEFAULT 0` on a required price is not — nobody can later tell a real zero from an import that forgot to set it.

```sql
CREATE TABLE `post` (
    `id` int unsigned NOT NULL AUTO_INCREMENT,
    -- NULL and '' would mean the same thing here, so only one of them is allowed to exist
    `meta_title` varchar(160) NOT NULL DEFAULT '',
    PRIMARY KEY (`id`)
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_0900_ai_ci;
```

## Date and Time Column Types
- **`_at` suffix = a point in time** (`datetime`): `created_at`, `published_at`, `deleted_at`, even a future one like `expires_at` — the suffix follows the type, not the tense.
- **`_date` suffix = a calendar day independent of any timezone** (`date`): `birth_date`, `invoice_date`, `due_date`. Storing a calendar day as a `datetime` is a bug waiting to happen: midnight gets attached to it, and the first time the application converts timezones — which it eventually will — that midnight shifts by an hour and the date silently moves a day in either direction.
- Where the boundary is genuinely fuzzy (`valid_from`, `valid_to`), decide by domain rather than by suffix: a subscription runs from an instant (`datetime`), a coupon is valid from a day (`date`).
- Keep meta-column names consistent across the **whole** schema — always `created_at`, never a mix of `create_time` and `date_added` — and never let the same column name mean two different things in two different tables; a query that joins both and sorts by the column will silently return nonsense.
- **Never use `TIMESTAMP`.** Two independent reasons, either one is sufficient: the year-2038 range limit, and a silent per-connection timezone conversion — what you store and what you read back can differ depending on who is asking. Use `DATETIME` instead: it stores and returns exactly what it was given, with no conversion. This does not remove the need for a timezone convention, it just moves the discipline to the application: pick one zone for the whole database and convert only at display time. `DEFAULT CURRENT_TIMESTAMP` and `NOW()` both insert the **session's** zone, so when the server's `default_time_zone` drifts from the zone historical data was written in, new rows silently get a different zone than old ones — with no error raised.
- **In Laravel, replace `timestamps()` with `datetimes()` or explicit `datetime()` columns.** `$table->timestamps()` emits `TIMESTAMP` columns, which the rule above forbids — use `$table->datetimes()` (Laravel 10.0+) or explicit `$table->datetime('created_at')` / `$table->datetime('updated_at')` calls instead.

## modified_at vs updated_at
Two columns that look interchangeable and are not — the deciding question is *what is this column actually supposed to measure?*

- **`modified_at`** measures a **domain-meaningful change** — "date of the last edit, from the reader's point of view". A flag toggle or a view-counter increment must not move it. `ON UPDATE CURRENT_TIMESTAMP` is the wrong mechanism here; maintain it with a trigger that watches only the named columns that count as a real edit.
- **`updated_at`** measures "something changed, period" — it is a row-version / concurrency token used to detect a conflicting concurrent edit. Here `ON UPDATE CURRENT_TIMESTAMP` is exactly correct, and a trigger would be **worse**: it would have to enumerate every editable column and silently go stale the moment an eleventh one is added, quietly dropping optimistic-locking protection for new fields.
- Every magically-maintained column needs a `COMMENT` naming what maintains it — `updated_at` especially ("concurrency token, `ON UPDATE` is intentional"), or a well-meaning future reader "fixes" it onto a trigger and silently breaks optimistic locking.
- **Set `DEFINER` explicitly on the trigger.** A trigger always executes with its definer's privileges — MySQL has no `SQL SECURITY INVOKER` mode for triggers, that clause is a syntax error there — so an omitted `DEFINER` silently binds the trigger to whoever happened to run the migration, typically the deployment's most privileged account, and that choice then travels with `SHOW CREATE TRIGGER` into every dump and every environment restored from one. Name a least-privilege account instead (`@rules/security/backend.md` *Database*), under two constraints that decide *how* you name it:

  - **The definer needs the `TRIGGER` privilege on the table** and whatever else the body touches. Without it every write to the table fails with `ERROR 1142 TRIGGER command denied` regardless of who issued the write — a least-privilege definer without the grant is a table-wide outage, not a silently skipped trigger.
  - **Naming an account other than the creator requires `SET_ANY_DEFINER`** (`SET_USER_ID` before MySQL 8.2) **or `SUPER` on the creating account** — otherwise `CREATE TRIGGER` fails with `ERROR 1227`. Do **not** grant that privilege to the deploy user to make the clause work: it is what allows creating stored objects that run as *any* account, so it hands full privilege escalation to anyone who can land a migration — strictly worse than the omitted clause. Run the migration **as** the intended low-privilege account instead and write `DEFINER = CURRENT_USER`, which is least-privilege and needs no extra grant.

```sql
DELIMITER ;;

-- DEFINER is explicit, and CURRENT_USER because the migration runs as the low-privilege
-- account that should own the trigger — naming a different one would need SET_ANY_DEFINER
-- BEFORE, because only there does SET NEW.* have any effect
CREATE DEFINER = CURRENT_USER TRIGGER `page_before_update_touch_modified_at`
BEFORE UPDATE ON `page` FOR EACH ROW
BEGIN
    -- COLLATE bin on both sides: without it, a diacritics-only fix is not seen as a change (see Collation)
    IF NEW.content COLLATE utf8mb4_0900_bin <> OLD.content COLLATE utf8mb4_0900_bin
       -- <=> is NULL-safe equality; keeps the trigger from overwriting a date set manually (migration, import)
       AND NEW.modified_at <=> OLD.modified_at THEN
        SET NEW.modified_at = CURRENT_TIMESTAMP;
    END IF;
END;;

DELIMITER ;
```

## Boolean Columns
Do not mandate an `is_` prefix mechanically — follow this procedure instead, in order:

- **Verify it should be boolean at all.** A state you also care about the *timing* of belongs in a timestamp instead (`read_at` carries both for free). More than two states belongs in an enum. A value you can compute from another column does not need to be stored at all — whether a category is a subcategory is already implied by `parent_id` being set.
- **Try a positive-polarity adjective or participle**: `published`, `visible`, `pinned`. Always positive polarity — `WHERE NOT disabled` is a needless double negative.
- **When no adjective fits, reframe the question**: `use_avatar` → `avatar_enabled`, `hide_price` → `price_visible`, `noindex` → `indexable`.
- **Otherwise, `is_` is a legitimate fallback**, not a failure — and permissions always get `can_`.
- The point is the procedure, not a fixed prefix: hunting for an adjective is diagnostic. It surfaces columns that should never have been boolean, columns that are derivable (and so removable), and reversed-polarity columns — a mechanical prefix would paper over all three. It matters for templates too, not just SQL: `{if $user->avatarsVisible}` reads as a sentence, `{if $user->isShowAvatars}` does not, and `isXxx` is the ecosystem's method-naming shape, so a *property* with that shape is a visual false friend.
- The column itself is always `tinyint(1) NOT NULL` with a default chosen for the safe state, not for aesthetics — `enabled DEFAULT 1` is fine even though the value is not zero. For a permission or verification flag (`can_*`, `is_admin`, `*_verified`, `two_factor_enabled`) the safe state is the **restrictive** one, so it is always `DEFAULT 0`: a permissive default there grants the privilege to every row created before anyone thought about it, including every row an unrelated migration backfills.

## String, Text, and ENUM Types
- **`VARCHAR(255)` is a cargo-cult default**, not an optimization. The number comes from historical limits — a one-byte length prefix maxed out at 255 bytes, and the old index-key limit was 767 B — that no longer apply under `utf8mb4`: 255 characters is up to 1020 bytes anyway, the length prefix is 2 bytes regardless, and the modern key limit is 3072 B. Today, 255 optimizes nothing — it is only a number copied from someone else's table.
- Choose a length that is a **declared domain constraint**, which strict mode then enforces: derive it from a standard when one exists (`email varchar(254)` per RFC, `country char(2)` per ISO 3166, `variable_symbol varchar(10)` because a bank will not accept a longer one). Where no standard exists, at least pick a length you can justify as a conscious cap — the goal is to bound the data and reject garbage, not to hit a magic constant.
- **`TEXT` is 64 KB of *bytes*, not characters** — it can be surprisingly tight. Use `MEDIUMTEXT` for HTML/article content.
- **`ENUM` is fine for a small, fixed set of values** — it costs one byte per index entry, an admin UI can read the allowed values straight from `information_schema` to build a dropdown, and appending a value is `ALGORITHM=INSTANT`. Its costs are elsewhere: `ORDER BY` sorts by the enum's internal position, not by the text, `WHERE status = 1` compares against that position rather than the value, and renaming a value is the same widen-backfill-cleanup dance as any other column rename.

## Money and Decimal Types
- **`FLOAT` / `DOUBLE` are banned for anything computed or compared for equality.** They are binary approximations, errors accumulate across `SUM()`, and `= 0.3` does not reliably work. Reserve float for genuine measurement where approximation is inherent to the value (a sensor reading, a coordinate).
- Between `DECIMAL` and integer cents: PHP has no exact decimal type, so holding an amount as an int × 100 is reasonable *in the application*. It is not automatically reasonable *in the column* — a cents column exports the interpretation outside the schema, and sooner or later someone reads it out without dividing by 100. The clean split is `DECIMAL` in the schema and integers or a money object in PHP, with the conversion in exactly one place. The driver returns `DECIMAL` as a string precisely because PHP has no exact type for it — do not cast it to float, that throws away exactly what the column bought you.
- Choose scale from the domain, not from generic caution: `DECIMAL(9,2)` for amounts, `(9,4)` for unit prices and rates, `(12,6)` for exchange rates.
- Enforce non-negativity with `CHECK`, not `UNSIGNED` — `UNSIGNED` on `DECIMAL` has been deprecated since 8.0.17.
- A trap strict mode will not catch: inserting a value with more precision than the column declares is **silently rounded**, only with a warning. Rounding is a domain decision — make it deliberately. MySQL's `ROUND()` is half-away-from-zero; there is no banker's rounding built in.

## Foreign Key Actions (ON DELETE / ON UPDATE)
Declare foreign keys explicitly, with both clauses set — never leave either to the engine default.

- **`ON UPDATE CASCADE` as the default.** A surrogate key almost never changes, so this virtually never fires and costs nothing. The rare time an ID really does get renumbered (manual data merges, comparing IDs across environments), cascading updates it atomically instead of forcing `SET FOREIGN_KEY_CHECKS=0` — which is the actual danger, since references silently stop being validated while it is off and orphans are created.
- **`ON DELETE` is decided by one question: is the child part of the parent, or an independent thing that merely points at it?**
  - Composition → `CASCADE` (`order_item` → `customer_order`, pivot tables).
  - Association → `RESTRICT` (`post.author_id` → `user`).
  - Meaningful disconnect → `SET NULL` (`log.user_id` after anonymization).
- **`SET NULL` is the worst possible default.** The reference disappears, the child row is left dangling, and it forces the column to be nullable. Use it only where an orphaned child still makes sense and the resulting `NULL` carries meaning.
- Two traps surface later: **cascaded deletes do not fire triggers** (InnoDB handles them below the SQL layer), so an invariant a trigger enforces is silently bypassed by a cascade. And **a cascade is meaningless under soft delete** — no real `DELETE` ever runs, so a carefully designed cascade is dead code.

## CHECK Constraints
`CHECK` constraints are enforced from MySQL 8.0.16 onward (earlier versions silently parse and ignore them) — treat them as a real tool for moving a domain rule from the application into the schema.

- **Decide what belongs in a `CHECK` by one axis: domain invariant vs. business policy.** An invariant is a timeless truth (`price >= 0`, an end cannot precede a start) and belongs in the schema. A policy is a rule that changes (e.g. "orders over 10,000 need approval") — put a `CHECK` on that and the next policy change becomes a migration.
- The best use is what no other mechanism can express: cross-column relationships on the same row, and conditional obligation — an implication `A -> B` written as `NOT A OR B`.
- **Name constraints after the rule, not the columns** — the name is what surfaces in the database error message a developer reads in the log, not something an end user ever sees directly: never pass a raw constraint-violation message to a user, map it to a generic validation message instead (see `@rules/security/backend.md` *Safe Validation & Error Messages*). The test: you can read the name in a log and know what happened without opening the schema.
- What `CHECK` cannot do: anything spanning multiple rows (no subqueries), anything non-deterministic (`CURDATE()` is rejected, so is `birthdate <= CURDATE()`), and it cannot reference an `AUTO_INCREMENT` column.
- Do not add a redundant `CHECK` where a cheaper mechanism already guarantees the same thing — `CHECK (age >= 0)` over a `TINYINT UNSIGNED` column is pure noise plus a cost on every write.

```sql
-- Conditional obligation: A -> B written as NOT A OR B
ALTER TABLE `customer_order`
    ADD CONSTRAINT `chk_order_shipped_needs_date`
        CHECK (`status` <> 'shipped' OR `shipped_at` IS NOT NULL);
```

## Collation
- **`utf8mb4` always, never `utf8`** — the latter is a 3-byte alias that breaks emoji.
- Collation must be from the **`utf8mb4_0900_*` family** (UCA 9.0). Legacy `utf8mb4_czech_ci`, `unicode_ci` (UCA 4.0.0), `general_ci`, and `utf8mb4_bin` have no place in a new schema.
- **Comparisons and `REGEXP` inside a `CHECK` honor the column's collation.** Under the default case-insensitive `_ai_ci` collation, the constraint below happily accepts `'CS'` — the case-sensitive part of the pattern does nothing. Only the *case* sensitivity is lost: anchors and quantifiers are unaffected by collation, so `'cs_CZ'` is still rejected on length either way. A format/case-sensitive `CHECK` only has an effect over a column with a `_bin`, `ascii_bin`, or `_as_cs` collation.
- The same trap bites the trigger in **modified_at vs updated_at** above: without `COLLATE utf8mb4_0900_bin` on both sides, a diacritics-only fix is not seen as a change under the default collation — a routine correction a domain reader would call an edit is silently invisible to `modified_at`.

```sql
-- Over a `_ai_ci` column this accepts 'CS' as readily as 'cs' — the pattern's
-- case-sensitive half only bites once `lang` carries a `_bin` or `_as_cs` collation
ALTER TABLE `page`
    ADD CONSTRAINT `chk_page_lang_format`
        CHECK (`lang` REGEXP '^[a-z]{2}$');
```

## Charset Choice for Externally-Queried Columns
Charset is not chosen by what a column happens to store — it is chosen by what the value is **compared against**. Almost every schema has a few columns that, by definition, only ever hold ASCII: an article slug, a coupon code, a login name, an API token. `CHARACTER SET ascii` looks like a smart choice there (one byte per character in the key instead of four) — but these are also exactly the columns queried with **external, attacker-influenced input**.

The connection is `utf8mb4`, so external input always arrives as `utf8mb4`. While it contains only ASCII characters, MySQL silently converts and compares it; the moment it contains a single non-ASCII character, that conversion is not possible and the query **errors instead of returning an empty result**. A value that is not in the table normally just fails to match — this query never gets that far, so the application never gets the chance to return its own 404, and the visitor gets a raw 500 for typing a diacritic into a URL. Tests will not catch this either: they exercise existing and non-existing values, not values containing diacritics.

Two properties are what let you recognise this rule when you are staring at the error:

- **Every string operator fails, not just `=`.** `=`, `<>`, `>`, `LIKE`, `IN`, and `REGEXP` all raise `ERROR 1267 Illegal mix of collations`, and so do `CONCAT` and `GREATEST`; `LOCATE` and `REPLACE` raise `ERROR 3854 Cannot convert string ... from utf8mb4 to ascii` instead. What decides it is the operand, not the operator: no operator that brings a **non-ASCII** operand into contact with the column stays safe, while operations on the column alone are unaffected (`LENGTH(slug)`, `UPPER(slug)`, even `CONCAT(slug, '-x')` with an ASCII literal all return normally). Which of the two error codes you see depends only on which operator the query reached first, so do not go looking for a second cause when the message changes.
- **The table contents decide nothing; the compared string decides everything.** The identical query against an **empty** table errors exactly the same way, because the failure happens while the expression is resolved, before any row is read. An empty staging table, a fresh tenant, or a column the feature has not started writing yet therefore gives no warning at all — the first non-ASCII value in production is the first time anyone sees it.

There is exactly one way to make a single such query survive: casting the parameter down with `CONVERT(? USING ascii)`, which returns an empty result instead of erroring. It is named here only to close the question, never as the fix — it has to be remembered at **every** call site that touches the column, so the first one that forgets restores the outage. The durable answer is the charset decision below.

Ask "can a non-ASCII value ever reach this comparison?", not "is the data itself ASCII?". Reserve `CHARACTER SET ascii` for columns populated exclusively by the application and never queried with external input (`lang`, `country` — only where the value never originates from a request; `ip_address` typically does, so ascii does not belong there). Everything else gets `utf8mb4_0900_bin`, which does the same job at a few extra bytes per index entry. A wrong ASCII choice is an outage; a wrong `utf8mb4` choice is a few bytes.

A binary collation also makes the `UNIQUE` guard byte-exact and case-sensitive — for an identity column such as a login name, that shifts the entire burden onto the application-side NFC + confusable/case normalization mandated by `@rules/security/backend.md` *Hidden / Invisible Characters in Stored Fields*, which must run **before** the uniqueness lookup. A slug, coupon code, or API token carries no such exposure: an exact byte match is exactly what those columns want.

This overlaps with `@rules/security/backend.md`'s existing principle — "Use error handling without revealing sensitive information." — since an unhandled illegal-mix-of-collations error reaching the client is exactly that: an availability/information leak triggered by attacker-controlled input. The fix here is a schema/charset decision, not an application error handler, so the rule stays here rather than duplicating content there.

```sql
-- slug varchar(100) CHARACTER SET ascii; every statement below behaves the same on an empty table
SELECT * FROM post WHERE slug = 'muj-clanek';   -- passes
SELECT * FROM post WHERE slug = 'můj-článek';   -- ERROR 1267 Illegal mix of collations
SELECT CONCAT(slug, 'č') FROM post;             -- ERROR 1267 — not only comparisons
SELECT REPLACE(slug, 'č', 'c') FROM post;       -- ERROR 3854 Cannot convert string from utf8mb4 to ascii
```

## Primary Key Sizing
`INT UNSIGNED AUTO_INCREMENT` as the default primary key; `BIGINT` for tables that are only ever appended to (queues, logs).

- The primary key is physically part of **every secondary index** in InnoDB — so it never needs repeating inside one, which often turns an index into a free covering index — and it must be type-identical (including `UNSIGNED`) in every foreign key pointing at it, or the FK cannot even be created. Its size is therefore paid `(1 + index count + reference count)` times, not once.
- **`AUTO_INCREMENT` follows the maximum, not the row count.** It never recycles, and gaps left by rollbacks or `INSERT IGNORE` are never refilled — a queue or log table can exhaust `INT` with only a few million *live* rows. Size for how many rows will ever be inserted over the table's life, not how many will be sitting in it at once.
- **The risk is asymmetric.** Undersizing is a production incident: the next `INSERT` fails, and converting to `BIGINT` is a long, heavy operation happening at the worst possible time. Oversizing costs four bytes per row. When in doubt, take `BIGINT`.
- `UNSIGNED` is worthwhile on `INT` — doubling the range to 4.29 billion often means `BIGINT` is not needed at all. On `BIGINT` it no longer matters: the signed range is already absurd on its own, and the extra upper half is unreachable from PHP anyway.
- **A sequential key is enumerable, and its unguessability is never a security control.** In Laravel this `id` reaches the URL through route-model binding by default, so `/invoice/41` invites `/invoice/42` and the whole set is walkable. The control is authorizing every lookup, on every route, per `@skills/laravel-authorization-review/SKILL.md` — never the fact that an identifier is hard to reach. Where the *size* or *membership* of the set is itself sensitive (an order count a competitor can read off the last ID, a private-beta user list), keep the sequential `id` internally and expose a separate non-sequential public identifier; do not swap the primary key for a UUID to hide it, which pays the full InnoDB index cost above for a property that was never a defence.

## Index and Constraint Naming
- **Always name indexes and constraints explicitly.** Left unnamed, MySQL generates `post_ibfk_1`, `post_chk_1` — numbered by creation order. Drop and re-add one constraint, or create the same table from a dump instead of from migrations on a different environment, and the numbering diverges: `DROP FOREIGN KEY post_ibfk_2` then succeeds on one environment and fails — or drops something else entirely — on another.
- **Indexes get no prefix; constraints get one** (`fk_post_blog`, `chk_post_lang_format`). The difference has a reason: a constraint's name surfaces in the database error message a developer reads in application logs, so it belongs where that reader will see it; an index's name is seen only by whoever is tuning a query.
- **Name an index by what it is, not blindly by convention.** A technical index (backing a FK, or a `UNIQUE` on a natural key) exists from day one — it is a constraint, not an optimization — so name it after its columns, since its columns are its whole purpose. A performance index is added later from `EXPLAIN` and the slow log — name it after the query it serves (`post_listing`).

## When to Break These Rules
Only the prerequisites above (strict mode, `utf8mb4`, explicit foreign keys) and plain facts about MySQL are non-negotiable — what cannot be created, cannot be created. Everything else may be broken, but only with a reason that would survive being read as a written decision two years later. "I don't like it" does not qualify; "this table has 500 million rows and cannot survive a rebuild" does.

Record the deviation where the next reader will actually encounter it: a table or column `COMMENT`. Not a commit message, not a wiki page, not only in your head — `SHOW CREATE TABLE` is the one piece of documentation that travels with the data.

## Advanced SQL Patterns
- Use CTEs for complex multi-step queries — prefer over nested subqueries.
- Use window functions (`ROW_NUMBER`, `RANK`, `LAG`, `LEAD`) for analytics and ranking without self-joins.
- Use recursive CTEs for hierarchical data (categories, org trees).

```sql
-- CTE for multi-step logic
WITH active_users AS (
    SELECT id, name, email
    FROM users
    WHERE status = 'active'
)
SELECT au.name, COUNT(o.id) AS order_count
FROM active_users au
JOIN orders o ON o.user_id = au.id
GROUP BY au.id, au.name;

-- Window function for ranking
SELECT
    user_id,
    amount,
    ROW_NUMBER() OVER (PARTITION BY user_id ORDER BY amount DESC) AS rank_num
FROM orders;

-- Recursive CTE for hierarchical data
WITH RECURSIVE category_tree AS (
    SELECT id, name, parent_id, 0 AS depth
    FROM categories
    WHERE parent_id IS NULL
    UNION ALL
    SELECT c.id, c.name, c.parent_id, ct.depth + 1
    FROM categories c
    JOIN category_tree ct ON c.parent_id = ct.id
)
SELECT * FROM category_tree;
```

## New storage reuse analysis
When a diff introduces a new storage surface — a new DB table (`Schema::create(...)` in a migration), a new cache store or Redis namespace, a new filesystem disk, or a new NoSQL / DynamoDB table — an explicit analysis must appear in the PR description or a PR comment before the change merges. The analysis must answer: *"Can this data be stored in an existing storage without a drastic impact on performance?"* It must name the candidate existing storage(s) evaluated and state the reason they were ruled out — or confirm that an existing storage is reused instead. A diff that adds a new storage surface without this documented analysis is a **Moderate** finding in code review (see `@skills/code-review/SKILL.md` *New storage reuse analysis*).
Do not flag migrations that only add a column or index to an existing table — only net-new storage surfaces trigger this check.

## Caching at DB Level
- Use query result caching for repeated expensive queries with same parameters.
- Invalidate cache on relevant data changes.
- Mitigate cache stampede (locking, stale-while-revalidate).
