# Simplification audit — <repository or audited part>

The canonical report shape for `@skills/simplification-audit/SKILL.md`. One report per audit run. It is the coverage contract, the findings, and the audit log in one place — never several competing scratchpads.

## Scope

- **Audited scope:** <the whole repository, or the part the user named>
- **Requested by:** <the user's own words for the request>
- **Commit audited:** <SHA>
- **Working tree at start:** <`git status --short` output before the audit began, or `clean`>

## Subsystem inventory (the coverage contract)

| ID | Subsystem | Ownership boundary | Key files | Interfaces, call sites, tests | Status |
|----|-----------|--------------------|-----------|-------------------------------|--------|
| S1 | <name> | <exactly what this row owns, and what it does not> | <paths> | <public interfaces, major call sites, covering tests> | `queued` / `in review` / `recommend` / `skip` |

Every row's status is final when the audit ends. A `skip` is completed coverage, not a gap.

## Accepted recommendations

One block per accepted recommendation, each assigned to exactly one authoritative subsystem.

### R1 — <one-line statement of the simplification> (<subsystem ID>)

1. **Verdict:** recommend
2. **Evidence:** `<path>:<line>` — <what the cited lines show>
3. **Current complexity or invalid states:** <…>
4. **Proposed representation and why it is simpler:** <…>
5. **Smallest credible implementation scope:** <affected files and interfaces>
6. **Regression risks and migration concerns:** <…>
7. **Existing and additional validation required:** <tests that cover it now, tests to add first>
8. **Confidence:** high / medium / low

## Explicit skip decisions

| Subsystem | Why nothing met the threshold |
|-----------|-------------------------------|
| <ID> | <the reason, in one sentence — "already clear", "complexity is intentional and named", …> |

## Cross-cutting patterns

Patterns a single subsystem cannot own, recorded so they are visible without widening any boundary.

## Duplicates and superseded findings

| Dropped finding | Kept as | Reason |
|-----------------|---------|--------|
| <…> | <R-id> | duplicate / narrowed / relocates complexity / misreads intentional semantics |

## Priorities and dependencies

Ranked by concrete impact, confidence, implementation effort, blast radius, and prerequisites.

| Rank | Recommendation | Impact | Confidence | Effort | Blast radius | Depends on |
|------|----------------|--------|------------|--------|--------------|------------|
| 1 | <R-id> | <…> | <…> | <…> | <…> | <R-id or none> |

**Best first implementation slices:** <the one or two recommendations to implement first, and why they are first>

Implementation happens in a separate, separately requested run — `@skills/class-refactoring/SKILL.md` or `@skills/refactor-entry-point-to-action/SKILL.md`. This report changes no file.

## Audit log

| When | Step | Subsystem | Action | Outcome |
|------|------|-----------|--------|---------|
| <ISO-8601> | 2 | <ID> | worker dispatched / harvested | recommend / skip |
| <ISO-8601> | 3 | <ID> | coordinator verification | accepted / narrowed / rejected (<reason>) |
| <ISO-8601> | 4 | — | coverage / duplication / materiality / schema / priority pass | <outcome> |
