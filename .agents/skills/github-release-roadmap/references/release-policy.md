# Release policy

Read before choosing a version. This file decides three things: where the current version comes from, how the next one is derived, and what evidence a `breaking` classification needs.

## Contents

- [Version sources and their precedence](#version-sources-and-their-precedence)
- [Change types](#change-types)
- [Evidence required for `breaking`](#evidence-required-for-breaking)
- [Deriving the next version](#deriving-the-next-version)
- [Milestone shape](#milestone-shape)
- [Category to label mapping](#category-to-label-mapping)
- [Scheduling and dates](#scheduling-and-dates)

---

## Version sources and their precedence

Read every source, then resolve in this order:

1. **The latest published GitHub Release** — the version the consumers actually received.
2. **The latest semantic git tag** reachable on the default branch — covers a tagged-but-unreleased state.
3. **A version declared in a manifest** (`composer.json`, `package.json`) — authoritative only for packages that declare one; most Composer packages deliberately do not.
4. **The newest released heading in `CHANGELOG.md`.**

When two sources disagree, that is a **conflict, not a tie-break**: state both values, say which one the proposal uses, and ask. A roadmap built on the wrong baseline proposes the wrong next version.

When no source exists at all, the repository is pre-release. Propose `0.1.0` for the first feature release, and say in the confirmation package that the baseline was absent rather than inferred.

## Change types

Every selected issue carries exactly one:

| Type | What it means | Effect on the bump |
| --- | --- | --- |
| `breaking` | A consumer following the documented contract must change something to keep working | MAJOR |
| `feature` | New capability, backward compatible | MINOR |
| `bugfix` | Restores documented behaviour, backward compatible | PATCH |

Classify from the issue's **content**, not from a label already on it — a repository's label conventions are evidence, never the verdict. Documentation, tests, chores, and refactors carry no consumer-visible change and map to `bugfix` for bump purposes unless the issue itself states otherwise.

## Evidence required for `breaking`

Do not classify edge-case work as breaking without evidence of **backward incompatibility**. At least one of these must be demonstrable from the issue or the code:

- a removed or renamed public symbol, endpoint, route, CLI flag, config key, or event name;
- a changed signature, required-parameter addition, or narrowed accepted input on a public surface;
- a changed default that alters behaviour for a consumer who changed nothing;
- a dropped runtime, framework, or dependency major version;
- a storage, payload, or wire-format change that existing data or in-flight messages cannot survive.

A bug fix that makes previously-accepted invalid input fail is a judgement call: state it as such in the proposal, with the reason, and let the user decide. Never resolve it silently in either direction.

## Deriving the next version

The bump is derived from the **selected scope**, never from the size of the backlog:

1. Any `breaking` in scope → MAJOR (`2.4.1` → `3.0.0`).
2. Otherwise any `feature` in scope → MINOR (`2.4.1` → `2.5.0`).
3. Otherwise → PATCH (`2.4.1` → `2.4.2`).

Precedence is strict: breaking outranks feature, feature outranks bugfix. On a `0.x` baseline the same ladder applies one position down by convention — a breaking change bumps MINOR (`0.4.2` → `0.5.0`) — but say so explicitly in the proposal instead of leaving the reader to infer the convention.

Always record the **bump rationale**: the baseline version, its source, the highest change type in scope, and the issue that carries it.

## Milestone shape

- **Title** — the version alone (`v2.5.0`), matching the repository's existing tag style. Read the existing tags rather than imposing a `v` prefix.
- **Description** — the release outcome in one or two sentences, plus the categories it covers. Not a list of issue numbers; the milestone's own issue list is that.
- **Due date** — the agreed target date. Absent an agreed date, leave it empty and say so; an invented due date makes the roadmap misleading, which is exactly the case the skill must ask about instead of guessing.

Reuse an exact matching **open** milestone when one exists and was approved for reuse. Never reuse a closed milestone, and never retitle an existing one.

## Category to label mapping

The user's categories are **release outcomes**, not label names. Map them in this order:

1. An existing label whose **description** covers the category → reuse it.
2. An existing label whose name covers it and whose description does not contradict it → reuse it, and say in the proposal that the match was by name.
3. No adequate existing label → propose a new one, carrying its name, description, and colour into the confirmation package.

Never replace an existing label to make a category fit, and never remove a label from an issue. Where the repository already runs a fixed taxonomy — for example one seeded by `@skills/github-issue-triage/SKILL.md` — that taxonomy wins over a newly proposed label.

Use **labels** for categories that stay meaningful outside this release. Use **Project fields** for values that only describe this release's schedule: `Start date`, `Target date`, `Priority`, `Release`.

## Scheduling and dates

- Derive `Start date` / `Target date` only when the user supplied a window or a capacity rule. Otherwise propose the ordering and leave the dates unset.
- Order the scope by dependency first, then by priority. An issue that blocks another is scheduled before it, whatever its priority.
- State every scheduling assumption in the confirmation package. An assumption that would make the roadmap misleading if wrong is a question, not an assumption.
