# Security audit — <repository or audited subsystem>

The canonical report shape for `@skills/security-audit/SKILL.md`. One report per run. It summarises `findings.json`, `coverage-ledger.json`, and `metadata.json`; those files stay the source of truth. `scripts/audit-artifacts.sh validate` requires every `##` heading below.

## Scope

- **Audited scope:** <the whole repository, or the part the user named>
- **Requested by:** <the user's own words for the request>
- **Commit audited:** <SHA>
- **Profile:** <quick | standard | deep>
- **Working tree at start:** <`git status --short` output before the audit began, or `clean`>

## Budget

| Stage | Reserved or ceiling | Spent |
|-------|---------------------|-------|
| Hunting | <hunting_max> | <spent.hunting> |
| Verification | <verifier_reserve> | <spent.verification> |
| Coverage critics | <coverage_critic_reserve> | <spent.coverage_critic> |

Total: <total> passes. <State every limit the budget put on the audit, or `none`.>

## Confirmed findings

One block per finding of verdict `confirmed`, ordered by severity. Write `None.` when there are none.

### <fingerprint> — <one-line statement> (<severity>)

- **Boundary:** <the security boundary that fails>
- **Entrypoint:** <where the attacker input enters>
- **Sink:** <where it does harm>
- **Root cause:** <why the flow is possible>
- **Evidence:** `<path>:<line>` — <what the cited line shows>
- **Remediation:** <the minimal fix>

## Needs validation

One line per finding of verdict `needs_validation`: fingerprint, the suspected weakness, and the step in `validation_needed` that settles it. Write `None.` when there are none.

## Rejected candidates

One line per finding of verdict `rejected`: fingerprint and the control that stops the flow. Write `None.` when there are none.

## Coverage

One line per ledger row: ID, subsystem, final status, and the reason for every `skipped` or `gap` row. State the omissions the coverage critics found and how each was closed.
