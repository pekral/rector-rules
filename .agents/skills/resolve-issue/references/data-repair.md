# Data repair — the second half of a bug fix

A defect that ran in production wrote its result somewhere: a table, a JSON column, a file, a cache
entry, a queued payload. The fix in step 10 corrects the code path and leaves every one of those
records exactly as the defect wrote it. Resolving the issue means delivering both halves, in this
order — the cause first, then the repair — per `@rules/compound-engineering/tracker.md` *Fix the
cause first, then repair the data it already wrote*. The order is causal rather than a preference: a
repair that runs while the defect is still live is re-corrupted by the next request that takes the
broken path.

## 1. Decide whether damage exists — from the storage, not from the code

The analysis input for step 7 carries the assessment when one was made (`@skills/analyze-problem/SKILL.md`
records it in *Problem Impact*). When it does not, make it here, before the fix is called done.

Query the affected storage for records the cause could have written and state the finding as a
**count plus the predicate that identifies a damaged record**:

- *"1 842 orders where `total_gross` is below the sum of their items, all created after 2026-03-01"*
  is an assessment, and it is also the repair's own `WHERE` clause.
- *"the defect probably corrupted some orders"* is not one. Never infer the damage from reading the
  code; read the records.

**No damaged record found is an answer, and it is recorded as one.** An unstated answer reads as an
unasked question to whoever picks this up next.

## 2. Ship the repair with the fix

The repair is its own command or migration — never a side effect hidden inside the request path
step 10 just corrected, where it would run on traffic nobody scheduled:

- **Bounded and re-runnable.** Read in chunks, skip what it has already done, and produce the same
  result when run twice (`@rules/sql/optimalize.md` *Bounded reads over unbounded materialisation*).
- **Outside the schema migration.** A backfill never rides inside the DDL
  (`@rules/sql/optimalize.md` *A data backfill never rides inside the schema migration*).
- **Covered by its own test.** Seed a record in the damaged shape, run the repair, assert the record
  is consistent afterwards — and assert that a healthy record was left untouched.

## 3. Report it

- **Technical report (GitHub PR):** the command, the predicate, and the record count.
- **Non-technical report (source tracker):** in plain language, that already-affected records were
  corrected, and what the tester should re-check.

## 4. The two ways out — both are stated, neither is silence

- **File it.** A repair that genuinely cannot ship here — it needs a maintenance window, a data
  owner's decision, or a volume this pull request cannot carry — becomes a follow-up issue per
  *Deferred-item follow-up issues* in the skill, and is named in the report. Inconsistent stored data
  the assignment's own defect produced clears the filing bar as a critical gap in that assignment's
  business logic, so it is never left as unrecorded cleanup.
- **State that it is disposable.** When the damaged data regenerates on its own — a cache entry that
  misses and is rebuilt, a derived value the next run recomputes — say so and say why, in the
  technical report.

Skipping both is the one outcome that is never available.
