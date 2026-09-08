---
name: github-issue-triage
description: "Use when GitHub issues must be prioritized, sorted, or labelled by type — seeds the repository's priority and type label taxonomy and assigns the derived priority to every open issue, so work can be filtered and picked in priority order."
license: MIT
metadata:
  author: "Petr Král (pekral.cz)"
---

## Constraints
- Output must be in English
- The taxonomy below is fixed — never rename a label, change a color, or invent a new one
- `priority: critical` is a **human decision**: no script assigns it, and an existing one is never removed or downgraded
- Never delete a label from the repository; the only sanctioned removal is a label on an issue that an explicit title prefix proves wrong
- `security` and `question` are topic labels, not primary types — they are never removed from an issue
- Run the shipped scripts; never write a new ad-hoc `gh` labelling script

---

## Use when
- The priority / type labels are missing in a repository, or drifted from the taxonomy
- Open issues carry no priority and the backlog cannot be sorted
- A new issue was just created and needs its type and priority
- Someone asks which issue to work on next

---

## The taxonomy

**Priority labels** — exactly one per issue.

| Label | Color | Meaning |
| --- | --- | --- |
| `priority: critical` | `b60205` | Blokuje jádro produktu nebo bezpečnostní incident — řeší se první |
| `priority: high` | `d93f0b` | Bug s reálným dopadem — řeší se po critical |
| `priority: medium` | `fbca04` | Nová funkcionalita / enhancement |
| `priority: low` | `0e8a16` | Nice-to-have, testy, chore, docs, marketing, refactor, plány |

**Type labels** — the primary type is exclusive; `security` and `question` are topics that may accompany it.

| Label | Color | Primary type |
| --- | --- | --- |
| `bug` | `d73a4a` | yes |
| `enhancement` | `a2eeef` | yes |
| `documentation` | `0075ca` | yes |
| `test` | `bfd4f2` | yes |
| `refactor` | `c5def5` | yes |
| `chore` | `cfd3d7` | yes |
| `marketing` | `f9d0c4` | yes |
| `plan` | `5319e7` | yes |
| `security` | `ee0701` | no — topic |
| `question` | `d876e3` | no — topic |

---

## Priority derivation

Applied in this order, first match wins:

1. A **bug that blocks the core product**, or a **confirmed security incident** → `priority: critical`. Neither condition is derivable from an issue title, so this step is **human-only**: the scripts never assign `priority: critical` and never take it away.
2. Any other **bug** → `priority: high`.
3. **Enhancement** / new functionality → `priority: medium`.
4. Everything else — `test`, `chore`, `refactor`, `documentation`, `marketing`, `plan`, nice-to-have → `priority: low`.

## Type derivation

The type comes from the conventional-commits prefix in the title. The **scope in parentheses is not the type**: `test(security): …` is a `test`, not a `security` issue. A breaking-change `!` marker is tolerated (`fix(api)!: …`).

| Title prefix | Type |
| --- | --- |
| `fix(…):` / `fix:` / `[Bug]` | `bug` |
| `feat(…):` / `feat:` / `[Feature]` | `enhancement` |
| `docs(…):` / `docs:` | `documentation` |
| `test(…):` / `test:` | `test` |
| `refactor(…):` / `refactor:` | `refactor` |
| `chore(…):` / `chore:` | `chore` |
| `marketing:` | `marketing` |
| `PLAN (…):` | `plan` |

When the title carries no recognized prefix, the **issue body** decides — matched on the `### ` headings the GitHub issue forms generate, at the start of a line:

| Body heading | Type |
| --- | --- |
| `### Expected behavior` / `### Actual behavior` | `bug` |
| `### What problem does this solve?` / `### Proposed solution` | `enhancement` |

The match is anchored to the heading on purpose: a sentence in the prose (*"Expected behavior: the label appears right away"*) is not a form field, and an unanchored match would label a feature request as a bug.

An issue that matches neither form is **skipped and reported** — never guessed at. So is an issue whose body carries the headings of **both** forms: an ambiguous body is a conflict for a human, not something to resolve by whichever form the script happens to test first.

The body is the weaker signal, so it never overrules a person: when the body suggests one type and the issue already carries a different primary type label, the existing label wins and the conflict is reported instead of pinning a second type onto the issue.

---

## Execution

### 1. Seed the labels

Run `scripts/seed-labels.sh` in the target checkout. It creates the 14 labels above with `gh label create --force`, so it also repairs a drifted color or description and is safe to re-run. It deletes nothing.

```bash
skills/github-issue-triage/scripts/seed-labels.sh
```

### 2. Preview the triage

Run `scripts/assign-priorities.sh --dry-run` first. It prints, per open issue, the derived type and priority and the labels it would add or remove — and writes nothing.

```bash
skills/github-issue-triage/scripts/assign-priorities.sh --dry-run
```

Read the preview before applying it: an issue reported as `skipped` needs a human type, and one reported as *kept the existing priority* has a manual priority the script refuses to overwrite.

### 3. Apply

```bash
skills/github-issue-triage/scripts/assign-priorities.sh
```

The run is idempotent: an issue that already carries the derived type and priority produces no API call at all. Removals happen only when an explicit **title prefix** proves a label wrong — a contradicting primary type label, or a contradicting priority label that is not `priority: critical`. Nothing else on the issue is touched.

### 4. Label a newly created issue

After opening an issue (`@skills/create-issue/SKILL.md`, `@skills/create-issues-from-text/SKILL.md`, or by hand), run step 3 again. Because the run is idempotent, it labels the new issue and leaves every already-triaged one untouched. Give the new issue a conventional-commits title (`fix(...)`, `feat(...)`, …) or use one of the issue forms, otherwise it is reported as skipped and stays unlabelled.

### 5. Work in priority order

Pick work by filtering on the priority label:

```bash
gh issue list --state open --label "priority: critical"
gh issue list --state open --label "priority: high"
gh issue list --state open --label "priority: medium"
gh issue list --state open --label "priority: low"
```

Narrow further by type, or list a whole priority band with its type and age:

```bash
gh issue list --state open --label "priority: high" --label bug
gh issue list --state open --label "priority: critical" --json number,title,labels,updatedAt
```

Everything without a priority label is untriaged — surface it and re-run step 2:

```bash
gh issue list --state open --search 'no:label' --json number,title
```

---

## Why labels and not the Projects v2 priority field

GitHub Projects v2 has a native single-select **Priority** field, and it is the richer model — but writing it needs a token carrying the `project` OAuth scope (`gh auth refresh -s project`). That scope is not available for this repository, so every Projects v2 write would fail. Labels need no extra scope, are visible in `gh issue list`, the web UI, and the API alike, and are what the scripts above use. If the `project` scope ever becomes available, the labels stay the source of truth and can be mirrored into the field — do not split priority across two systems.

---

## Output

Both scripts open with the repository they resolved from the working directory — `<script>: target repository: <owner>/<repo>` — printed **before** the first write, so a transcript always names where the labels landed.

- **Seed:** the target repository, one `ok <label>` line per label, plus a count of labels in sync.
- **Triage:** the target repository, one line per open issue with its derived type, the derivation source (`title` / `body`), and the labels applied, would-be-applied (`--dry-run`), or the reason it was skipped or kept — closed with a summary of changed / already-triaged / skipped / kept counts. A backlog large enough to hit the listing's page limit is reported on stderr rather than silently truncated.

---

## Done when
- Every label of the taxonomy exists with its exact name, color, and description
- Every open issue whose type is derivable carries exactly one primary type label and one priority label
- Issues reported as `skipped` or as keeping a manual priority are surfaced for a human, not silently relabelled
- No `priority: critical` was assigned or removed by a script
- The backlog can be listed in priority order with `gh issue list --label "priority: …"`

## Output Humanization
- Use [blader/humanizer](https://github.com/blader/humanizer) for all skill outputs to keep the text natural and human-friendly.
