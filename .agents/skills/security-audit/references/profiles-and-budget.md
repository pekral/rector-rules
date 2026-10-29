# Audit profiles and execution budget

`@skills/security-audit/SKILL.md` reads this file in step 1. The profiles set the depth of the audit. They are not the risk tiers `FAST`, `STANDARD`, and `CRITICAL`, and the two sets never map onto each other.

## Profiles

| Profile | Hunting | Verification | Coverage critic | Default total |
|---------|---------|--------------|-----------------|---------------|
| `quick` | One pass per subsystem, on the attacker-reachable surface only: authentication and authorization, input to sink flows, secrets. | Every candidate whose boundary is authentication, authorization, or tenant isolation first, then the others while the verifier reserve lasts. A candidate no verifier reached stays `needs_validation` with severity `unrated`. | One pass over the ledger. | 20 passes |
| `standard` | One pass per subsystem over every lens of the *Core Checks* of `@skills/security-review/SKILL.md`. | Every candidate. | One pass over the ledger, then the omissions it found. | 60 passes |
| `deep` | A second pass per subsystem with a different lens assignment, cross-subsystem data-flow traces, dependencies, configuration, and CI files. | Every candidate, by a verifier that did not see the hunter's reasoning. | Repeated while a critic still finds an omission and budget remains. | 180 passes |

`standard` is the profile when the user names none. A user may name a profile and an explicit total together.

## The budget

The unit is a **pass**: one bounded worker pass. One hunter on one subsystem is one pass. One verifier on one candidate is one pass. One coverage-critic review is one pass.

`scripts/audit-artifacts.sh budget` splits the total. It takes the reserves first, each at least one pass, and leaves the remainder to hunting:

| Profile | Verifier reserve | Coverage-critic reserve | `hunting_max` |
|---------|------------------|-------------------------|---------------|
| `quick` | 30% of the total, rounded up | 10% of the total, rounded up | total minus both reserves |
| `standard` | 30% of the total, rounded up | 15% of the total, rounded up | total minus both reserves |
| `deep` | 35% of the total, rounded up | 20% of the total, rounded up | total minus both reserves |

- A total that leaves hunting less than one pass is refused. The smallest total is 3 passes.
- **Hunting cannot consume the whole budget.** `hunting_max` is below the total by both reserves, so hunting reaches its ceiling while the passes for verification and coverage critics are still unspent. The coordinator stops opening hunting passes at `hunting_max`.
- A reserve that hunting did not need stays available. Verification and coverage critics may spend any pass hunting did not, up to the total. Hunting may never spend a pass of either reserve.
- Record the budget exactly as the script printed it in `metadata.json`, and record what each stage spent in `spent`. `scripts/audit-artifacts.sh validate` checks that `spent.hunting` is not above `hunting_max` and that the passes spent are not above the total.
- A row that did not get a hunting pass is a `gap` in the ledger with a reason. A budget that ran out is a stated limit of the audit, never a silent one.
