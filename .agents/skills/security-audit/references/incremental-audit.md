# Incremental audit

`@skills/security-audit/SKILL.md` reads this file in step 2 when the user names a base run. An incremental audit does not audit again what did not change. It compares a base run with the git diff, finds the security surfaces the change reaches, invalidates their coverage and findings, verifies the affected findings again, and hunts the new and the uncovered surfaces.

## The base run

- The base run is an earlier, finished run of the same project. Its directory sits beside the directory of the new run, under the same `security-audit/` directory, and is named after its `run_id`.
- The base run has artefacts of the current schema version. A run written before this version has no security inputs, no digests, and no AI and agent threat classes, so it cannot be a base run. Run a full audit instead.
- The new run is a run of its own. It has its own `run_id`, its own budget, and the same four artefacts as a full run. `coverage-ledger.json` names the base run in `base_run`.

## The impact of the change

Run `scripts/audit-artifacts.sh impact <base-run-dir>`. It reads the base run and the current working tree and prints:

| Field | Content |
|-------|---------|
| `changed_paths` | Every path whose bytes or mode differ between the base run's commit and the working tree: a committed, a staged, or an unstaged edit, a deletion, and an untracked, not ignored file. |
| `new_paths` | The changed paths that no base unit holds in its `paths` or `inputs`. |
| `units` | One decision per base unit, with the inputs and paths of the unit that changed. |
| `findings` | One decision per base finding. |

| Decision | Meaning |
|----------|---------|
| unit `reuse` | The base unit was `covered`, the digest of its paths and inputs equals its `inputs_digest`, and every finding it lists is held by reusable units only. |
| unit `invalidated` | The digest changed, or the unit shares a finding with an invalidated unit. |
| unit `uncovered` | The base run did not cover the unit: it was `blocked`, `deferred`, or `out_of_scope`. |
| finding `reuse` | Every unit that lists the finding is `reuse`. |
| finding `reverify` | A unit that lists it is not `reuse`. |

**A change to a security input invalidates the unit and its findings.** A changed source, sink, authorization layer, middleware, validation, configuration, trust boundary, tool authority, or action binding changes the digest. So does a new file under the unit's paths, such as a new tool next to the tools the unit audited. Invalidation then spreads through shared findings: a finding stays valid only while every unit that lists it is unchanged.

**Coverage is reused only with proof.** The proof is the digest, not the diff. Equal digests mean that the raw bytes and the mode of every file on the unit's paths and inputs are the ones the base run audited. `validate` computes the digest again from the working tree and refuses a reused unit whose digest differs.

## The inventory

Write `coverage-ledger.json` from the impact before the first hunter opens:

1. Set `base_run` to the base run's `run_id`.
2. Copy every unit the impact marks `reuse` unchanged, and add `reused_from`: the base unit's `reused_from`, or the base run's `run_id` when the base unit has none.
3. Queue every other base unit again under its `coverage_id`. Every base unit is in the new ledger.
4. Walk every path in `changed_paths` in reconnaissance. A new surface, a new attack class, or a new AI or agent trust boundary in a changed file is a new unit, even when a reused or a queued unit already holds that file.
5. Run `scripts/audit-artifacts.sh inventory <run-dir>`. It applies the reuse rules already, so a reuse it cannot prove fails before any pass is spent.

## Verifying again

- Give the hunter of an invalidated unit the earlier findings of that unit as leads. It traces each one against the current code and returns it as a candidate, with its current basis, or with the evidence that its path no longer exists.
- Every lead goes to a new verifier, like any other candidate. The old verdict never carries over: a finding that is not reused is verified in this run or does not appear in `findings.json`.
- A base finding leaves `findings.json` only when a base unit held it and every unit that held it is `blocked` or `deferred` in this run. *Incremental basis* in `REPORT.md` lists such a finding as invalidated and not verified again, with the step that settles it.
- A base finding that no base unit lists is verified again.
- Copy every finding the impact marks `reuse` unchanged, and add `reused_from` as for a unit.
- Give the coverage critic of each wave the impact output, so it checks every changed path.

## What `validate` checks

- The base run sits beside the run directory and its artefacts are valid.
- Every base unit is in the ledger under its `coverage_id`.
- A reused unit or finding equals its base record, apart from `reused_from`.
- The digest of every covered unit, reused or hunted, equals the digest of its paths and inputs now.
- A reused unit shares no finding with a unit this run does not reuse, and a reused finding is listed only by reused units.
- A base finding is in `findings.json` unless a base unit held it and every unit that held it is `blocked` or `deferred`.
- A reused unit or finding spends no pass and names the workers of the run that hunted and verified it. The rules for waves, hunters, and verifiers apply to the units and findings of this run only.

## Limits

- The digest sees only what the snapshot sees: tracked files and untracked, not ignored files. A git-ignored file, a file inside a submodule or a nested git repository, and a file outside the work tree are not part of it. `digest` and `validate` refuse a git-ignored input, so a dependency is recorded by its lock file.
- The digest hashes a symbolic link as the link, not as the file it points to. A change to the target would not change the digest. `digest` and `validate` therefore refuse a path that is a symbolic link or passes through one, and name the target path to record instead. A symbolic link inside a recorded directory is hashed the same way. `digest` and `validate` refuse it unless the unit also records its target, and name the target to add.
- `digest` and `validate` refuse a path that matches no tracked or untracked, not ignored file. Its digest is the digest of the empty set, so it proves nothing about the path.
- A unit's inputs are as complete as its hunter and its verifier made them. The digest proves that the recorded path is unchanged. It does not prove that the recorded path is the whole path. The coverage critic checks the ledger for a surface or a trust boundary no unit holds.
- `changed_paths` compares the working tree with the base run's commit, not with the working tree the base run saw. A file that was edited but not committed at the base run and is restored now is not a changed path. The digest of a unit that holds it still differs, so the unit is invalidated.
- The impact refuses a base run whose commit is not in the repository, for example after a history rewrite. Run a full audit then.
