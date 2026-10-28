---
description: Laravel DynamoDB query safety — scan prevention and Tinker-based verification
paths:
  - "app/**/*.php"
  - "config/dynamodb.php"
  - "tests/**/*.php"
---

# Laravel DynamoDB

## Scope
Apply these rules whenever the project integrates with DynamoDB — via the `baopham/laravel-dynamodb` package, a DynamoDB-backed Eloquent model, a custom DynamoDB query builder, or the AWS SDK called directly from PHP.

## Core Principle
- Every read must target a key. `Scan` is the slow, expensive default and must never be the access pattern for production code paths.
- Treat every change to a DynamoDB query builder, repository, or any code that issues DynamoDB requests as a place that may silently introduce a `Scan`.
- A missing partition key turns the call into a `Scan` even when a `FilterExpression` is present — filters run **after** the read and do not replace a key condition.

## Required Access Patterns
- `GetItem` / `BatchGetItem` — single-item or known-keys reads.
- `Query` with a partition key (and optionally a sort key) — collection reads inside one partition.
- `Query` against a Global Secondary Index (GSI) — non-primary-key access patterns. Pass the index name to the query (`->index('status-createdAt-index')` with `baopham/laravel-dynamodb`; `IndexName` in `QueryInput` when calling the AWS SDK directly).
- `Scan` is allowed only for explicit, documented offline/admin tasks (one-off backfills, maintenance scripts) — see the Review Checklist below for the justification requirement.

Reject patterns that omit a key:

```php
Model::all();                                  // full scan
Model::where('status', 'active')->get();      // scan if `status` is not the PK / GSI hash
Model::whereNotNull('email')->first();        // scan
```

Prefer patterns that target a key:

```php
Model::find($id);                                                       // GetItem
Model::where('userId', $userId)->get();                                 // Query on PK
Model::index('status-createdAt-index')                                  // Query on GSI
    ->where('status', 'active')
    ->get();
```

## Local Scopes on DynamoDB Models
- `baopham/laravel-dynamodb` supports local scopes: `DynamoDbQueryBuilder::__call()` forwards `->name()` to `scopeName()` on the model. Name a repeated condition with a scope exactly as on an Eloquent model (`@rules/laravel/laravel.md` **Database and Eloquent**). An outdated package version is not a reason to fall back to a private Repository method.
- **The builder adds a scope's conditions flat to the query.** `callScope()` does not group them, so a scope that returns `$query->where('hidden', false)->orWhereNull('hidden')` turns the whole `FilterExpression` into `A AND B AND C OR D`. On a table that holds the rows of every tenant, that expression returns rows of other tenants. Every scope that combines `OR` wraps itself:

```php
public function scopeOnlyVisible(DynamoDbQueryBuilder $query): DynamoDbQueryBuilder
{
    return $query->where(static fn (DynamoDbQueryBuilder $builder): DynamoDbQueryBuilder => $builder->where('hidden', false)->orWhereNull('hidden'));
}
```

- **A misspelled scope is silently ignored.** `__call()` returns the builder for every unknown method, and static analysis reports nothing on the call. Only a test catches it: the test proves that the scope narrows the result.
- Verify every new scope with `toDynamoDbQuery()`: `op` is `Query`, and the `FilterExpression` shows the scope's conditions in parentheses.
- Severity in code review: **Critical** for a scope that combines `OR` without the nested `where()`, because the read can cross tenants. **Moderate** for a scope that no test exercises.

## Review Checklist
For every PR that touches DynamoDB code, reviewers must verify:

- Each new or changed read specifies a partition key or uses `GetItem` / `BatchGetItem`.
- No new `Scan` requests were introduced.
- Any pre-existing `Scan` that is modified is re-justified in the PR description.
- `FilterExpression` is not used as the primary access pattern.
- When a GSI is used, the index exists in the table definition and the query passes the correct index name.

## Testing and Debugging with Tinker
- If Laravel Tinker is available in the project (check `composer.json` for `laravel/tinker`), use `php artisan tinker` for every ad-hoc DynamoDB query verification or debug session instead of writing throwaway routes, commands, or seeders.
- Tinker complements but does not replace the Pest tests required by `@rules/code-testing/general.md` for every behavior change.
- Use Tinker to:
  - Confirm whether a builder produces a `Query` or a `Scan` before merging — inspect the builder, dump the underlying AWS SDK request, or enable SDK logging.
  - Verify the shape of items returned by repositories against real data.
  - Reproduce production-like read paths against the configured DynamoDB endpoint.
- Never paste secrets or production credentials into Tinker — rely on the project's configured `.env` or IAM role.

## Red Flags
- A new method on a DynamoDB repository or query builder that has no `where()` on the partition key.
- `FilterExpression` used as the only constraint on a read.
- `Scan` calls added without a clear maintenance/offline justification.
- Ad-hoc verification scripts or temporary routes added "just to test" a query when Tinker would suffice.
