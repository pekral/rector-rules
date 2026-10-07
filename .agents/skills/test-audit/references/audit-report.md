# Audit report and removal evidence

Companion to `@skills/test-audit/SKILL.md` *Audit mode*. It holds the evidence a removal needs and the report the audit returns.

## Removal evidence

Record every field before you recommend changing a test:

```
- Test:
- Location:
- Behavior / contract actually protected:
- Failure it can currently detect:
- Production owner:
- Non-test callers:
- Stronger overlapping test:
- Relevant history:
- Production/test-support code removable with it:
- Risk:
- Focused validation command:
```

- **A missing critical field blocks `DELETE`.** When the protected contract, the detectable failure, the stronger overlapping test, or the history is unknown, the recommendation is `KEEP` or `NEEDS INVESTIGATION`.
- **`Non-test callers` decides a seam.** A production method whose only callers are tests is removable together with the test; one real caller keeps it.
- **`Focused validation command`** runs the owner test and its siblings, e.g. `vendor/bin/pest tests/Feature/Billing --filter=Invoice`, never the whole suite.

## Report

```
# Test Audit

## Scope

<the scope the caller named, and what was read>

## Candidates

### Test: <name>

**Location:** <file:line>

**Current contract:** <what it protects today, or "none found">

**Failure detected:** <the regression it can catch, or "none">

**Owner boundary:** <where this contract belongs>

**Overlap:** <the stronger test that covers the same contract, or "none">

**History:** <why it exists, from git log / blame / show>

**Recommendation:** KEEP | CONSOLIDATE | MOVE | DELETE | NEEDS INVESTIGATION

**Reason:** <one or two sentences>

**Risk:** <what could regress if the recommendation is wrong>

**Validation:** <focused command>

## Production seams

<test-only methods, wrappers, flags, or config paths found, with their callers>

## Retained tests

<tests that looked suspect and stay, with the contract from the retention bar that keeps them>

## Summary

- Tests reviewed:
- Keep:
- Consolidate:
- Move:
- Delete:
- Needs investigation:
- Production LOC removable:
- Test LOC removable:
```

List a candidate only with enough evidence for its recommendation. A `DELETE` without complete removal evidence is a defect of the report, never a candidate to act on.
