# Audit profiles and execution budget

`@skills/security-audit/SKILL.md` reads this file in step 1. The profiles set the depth of the audit. They are not the risk tiers `FAST`, `STANDARD`, and `CRITICAL`, and the two sets never map onto each other.

## Profiles

| Profile | Hunting | Verification | Coverage critic | Default total |
|---------|---------|--------------|-----------------|---------------|
| `quick` | One pass per coverage unit of the attack classes `auth_authz` and `injection_input`, on attacker-reachable surfaces only. Every other unit is `deferred` with the reason `outside the quick profile`. | Every candidate whose boundary is authentication, authorization, or tenant isolation first, then the others while the verifier reserve lasts. A candidate no verifier reached stays `needs_validation` with severity `unrated`. | A fresh critic after each wave; at most one follow-up wave for the omissions it found. | 20 passes |
| `standard` | One pass per coverage unit of every attack class, each walking the lenses its class names in `references/roles-and-lifecycle.md` *Hunting areas*. | Every candidate. | A fresh critic after each wave; the omissions it found are hunted in the next wave. | 60 passes |
| `deep` | Every unit of `standard`, plus one `wildcard` unit per subsystem, cross-subsystem data-flow traces as their own units, and units for dependencies, configuration, and CI files. | Every candidate; a finding a critic reports as `assumption_based_finding` goes to a second new verifier, whose ID replaces the first. | A fresh critic after each wave; waves repeat while a critic still finds an omission and budget remains. | 180 passes |

`standard` is the profile when the user names none. A user may name a profile and an explicit total together.

## The budget

The unit is a **pass**: one bounded worker pass. One hunter on one coverage unit is one pass. One verifier on one candidate is one pass. One coverage critic on one wave is one pass.

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
- **Every wave needs a pass of the coverage-critic reserve.** Open a wave only while the reserve still holds a pass for its critic. `scripts/audit-artifacts.sh validate` checks that the waves are not more than `spent.coverage_critic`, that the hunters the waves opened are not more than `spent.hunting`, and that the verifiers are not more than `spent.verification`.
- A unit that did not get a hunting pass is `deferred` in the ledger with a reason. A budget that ran out is a stated limit of the audit, never a silent one.
- **A reused unit spends no pass.** In an incremental run, a unit or a finding reused from the base run (`references/incremental-audit.md`) costs nothing, so the budget goes to the invalidated, the uncovered, and the new units. Hunt the invalidated units first: a finding of an invalidated unit the budget does not reach leaves `findings.json`.
