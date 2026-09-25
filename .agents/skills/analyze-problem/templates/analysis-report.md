# Problem Analysis

## 1. Summary

**Task type:**
<!-- The primary classification of this task, stated first so a reader sees it immediately.
Pick the single value that best fits the assignment context:
Feature / Bug / Regression / Performance / Data issue / Security / UX / Refactor / Tooling / Unclear requirement / Other.
A feature adds new behavior; a bug fixes incorrect existing behavior. -->

...

<!-- Short summary in 2–5 sentences.
For a bug: what is happening, where, and the most likely reason.
For a feature: the target behavior to build and where it belongs. -->

...

---

## 2. Problem Definition

**Problem:**
<!-- One precise sentence describing the actual problem. -->

...

**Expected behavior:**
<!-- What should have happened. -->

...

**Actual behavior:**
<!-- What is happening instead. -->

...

**Affected area:**
<!-- Module, feature, page, API endpoint, command, job, database table, external service, etc. -->

...

---

## 3. Verified Facts

<!-- Only confirmed information from the assignment, issue, comments, logs, screenshots, attachments, or code.
Do not put assumptions here. -->

- ...
- ...
- ...

---

## 4. Assumptions and Missing Information

### Assumptions

<!-- What we assume but cannot confirm. -->

- ...
- ...

### Missing Information

<!-- What would help verify the cause or the proposed solution. -->

- ...
- ...

---

## 5. Probable Root Cause

**Most probable cause:**
<!-- Clearly describe the root cause. -->

...

**Why this cause is probable:**

- ...
- ...
- ...

**Certainty level:**
<!-- High / Medium / Low -->

...

**Alternative possible causes:**

- ...
- ...

---

## 6. Problem Impact

### User / Business Impact

<!-- What the problem causes from the perspective of users, customers, support, or the business. -->

- ...
- ...

### Technical Impact

<!-- Impact on the application, data, performance, queues, cache, integrations, security, etc. -->

- ...
- ...

### Data Damage Already Written

<!-- Whether the root cause has already stored inconsistent data, verified against the storage
and not inferred from the code. State the storage (table, JSON column, cache key space, queued
payload), the predicate that identifies a damaged record, and how many records match.
When the cause writes nothing, or wrote nothing yet, say so explicitly — never leave this blank. -->

**Damaged data found:** <!-- Yes / No -->

...

**Where and how it is recognised:**
<!-- e.g. `orders` — `total_gross < (SELECT SUM(...) FROM order_items ...)`, 1 842 rows since 2026-03-01 -->

...

### Risk Areas

<!-- What can break or what to watch out for when fixing. -->

- ...
- ...

---

## 7. Recommended Solution

**Smallest safe solution:**
<!-- Describe the smallest effective fix. No unnecessary refactoring. -->

...

**Data repair (only when section 6 found damaged data):**
<!-- The second half of the fix, which always runs after the cause fix, never before — a repair
executed while the cause is still live is re-corrupted by the next request that takes the broken
path. Describe it as its own bounded, re-runnable command or migration, with the predicate it
uses and the test that proves it (seed a damaged record, run the repair, assert consistency, and
assert a healthy record was left untouched). When the damaged data is disposable — a cache entry
that regenerates, a derived value the next run recomputes — say that and say why instead. -->

...

**Why this solution fits:**

- ...
- ...
- ...

**What to avoid:**

<!-- For example: large refactoring, architecture change, migration without reason, fixing symptoms instead of the cause. -->

- ...
- ...

**Possible side effects:**

- ...
- ...

---

## 8. Implementation Outline

<!-- Concrete technical direction, but without the implementation itself unless the user asked for code. -->

### Likely Change Locations

- `app/...`
- `routes/...`
- `database/...`
- `tests/...`

### Recommended Steps

1. ...
2. ...
3. ...

### Architecture Notes

<!-- If relevant, mention e.g. Action, Service, Repository, Validator, DTO, Job, etc. -->

- ...
- ...

---

## 9. Solution Verification

### Manual Verification

1. ...
2. ...
3. ...

### Automated Tests

<!-- Which tests to add or update. -->

- ...
- ...
- ...

### Edge Cases

<!-- Boundary situations the solution must cover. -->

- ...
- ...

### Regression Checks

<!-- What to check so the fix does not break existing behavior. -->

- ...
- ...

---

## 10. Non-Technical Explanation

<!-- Explanation for someone outside development: PM, support, client, product owner.
Without unnecessary technical detail. -->

...

---

## 11. Final Recommendation

<!-- Clearly state what should be done first and why. -->

**Recommendation:**
...

**Priority:**
<!-- Low / Medium / High / Critical -->

...

**Next step:**
...

---

## 12. Sources

<!-- Every source the analysis was actually built from. Mandatory — never leave empty.
List the issue / error and its comments and replies, linked / sub-issues, attachments,
code files, commits, and external URLs you consulted. If the only input was the inline
problem description with no issue-tracker source available, state that explicitly. -->

### Issue Tracker

<!-- Issue / PR / error URL, comment threads, linked & sub-issues, attachments. -->

- ...

### Codebase & Commits

<!-- Files, classes, and commits inspected (file:line, commit SHAs). -->

- ...

### External References

<!-- Documentation, advisories, or articles relied on. -->

- ...
