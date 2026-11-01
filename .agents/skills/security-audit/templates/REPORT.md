# Security audit — <repository or audited subsystem>

The canonical report shape for `@skills/security-audit/SKILL.md`. One report per run. It summarises `findings.json`, `coverage-ledger.json`, and `metadata.json`; those files stay the source of truth. `scripts/audit-artifacts.sh validate` requires every `##` heading below.

## Scope

- **Audited scope:** <the whole repository, or the part the user named>
- **Requested by:** <the user's own words for the request>
- **Commit audited:** <SHA>
- **Profile:** <quick | standard | deep>
- **Working tree at start:** <`git status --short` output before the audit began, or `clean`>
- **Base run:** <the `run_id` of the base run of an incremental run, or `none` for a full run>

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
- **Controls checked:** <each of the six kinds of control and its effect, with `<path>:<line>` for every control found>
- **Hunted by / verified by:** <hunter IDs> / <verifier ID>
- **Remediation:** <the minimal fix>

## Needs validation

One line per finding of verdict `needs_validation`: fingerprint, the suspected weakness, and the step in `validation_needed` that settles it. Write `None.` when there are none.

## Rejected candidates

One line per finding of verdict `rejected`: fingerprint and the control that stops the flow. Write `None.` when there are none.

## Coverage

One line per coverage unit: `coverage_id`, subsystem, surface, attack class, final status, and the reason for every `blocked`, `deferred`, or `out_of_scope` unit. Then one line per wave: its hunters, its critic, whether the working-tree snapshot still equals the baseline, and each gap the critic reported with its kind and how it was closed.

## Incremental basis

For a full run, write `None. This is a full run.` For an incremental run: the base run and its commit, then each changed path, each unit reused from the base run, each unit invalidated with the inputs or paths that changed, and each changed path no base unit held with the unit that now holds it. Then one line per invalidated finding: its fingerprint and the verdict this run gave it, or `not verified again` with the step that settles it.
