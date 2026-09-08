# Code Review

> **Section visibility — render only sections that have content.** Always render the header block (Status / Counts / Last updated / tracker-mirror field) and the final `Summary` line. The `Coverage:` header line, the `## Coverage` section, and the `coverage …` slot in the summary line are conditional — render them **only** when the coverage gate produced something to report (uncovered changed lines or unavailable / non-runnable tooling, both Critical findings per `@skills/code-review/SKILL.md` Coverage gate). When every changed line is at 100% coverage and the tool ran successfully, drop all three coverage surfaces; the Counts line is the clean signal. The `## Architecture` section follows the same conditional rule (issue #530):
> on Laravel projects the walk runs on every CR run, but the heading is rendered **only when the walk produces at least one finding** — when the walk is clean, omit the heading entirely (no "walked, 0 findings" line, no "clean" placeholder, no confirmation that the check ran). On non-Laravel projects (`laravel/framework` not in `composer.json` `require`), omit the `## Architecture` section entirely. Every section is conditional: omit its heading and body entirely when it has no items. Never emit `None.` / `Not applicable.` / `n/a` / `100%` / `walked, 0 findings` placeholders for empty sections or omitted coverage surfaces — drop them entirely. The Counts line in the header is the single source of "zero" signal;
> the goal is a clean, scannable PR comment a human can read at a glance — only items that still need action remain in the body.
>
> **Incremental review scope (rounds after the first).** A round with a resolved baseline reviews the **delta since the last reviewed revision** (`git diff <baseline>..HEAD`), not the whole PR: new findings come from the delta, every unsettled finding from an earlier round is carried over at its original severity, and the Coverage / Assignment Conformance / Reviewer Comment Fulfillment gates still read the whole PR. Render both header lines below on every run, and a `Provenance` field on every finding. Canonical contract: `@rules/code-review/general.md` *Incremental Review Scope — Diff Since the Last Reviewed Revision*.
>
> **Minor findings are not detected.** The review raises Critical and Moderate findings only (`@rules/code-review/general.md` *Minor findings are not detected*). The `🟡 Minor` sub-headings and the `Minor` slot of the `Counts:` line below exist for the one exception — a **security-lens** finding published at whatever severity its own scale assigns — and render nothing on a review that found none.

**Status:** clean / needs-fix  *(`clean` when the run converged — no Critical, no unfulfilled reviewer comment, and every remaining Moderate carrying a `Deferred:` field. A Moderate without that field is outstanding, so the status is `needs-fix`.)*
**Counts:** Critical {n} · Moderate {n} · Minor {n}  *(always the real detected counts; `Minor` counts security-lens findings only)*
**Reviewed revision:** {full head SHA this round reviewed}  *(always rendered — the next round resolves its baseline from this line)*
**Reviewed diff fingerprint:** {patch-id of the effective PR diff}  *(always rendered — preserves the verdict across a content-identical history rewrite)*
**Review scope:** delta since {baseline SHA} (round {n}) — carried-over findings re-reported  *(or `full PR ({reason: no prior reviewed revision | baseline {sha} not an ancestor of HEAD after a history rewrite})` — always rendered, never omitted as an empty section)*
**Coverage:** {result} (tool: {name or "not available — <reason>"})  *(render this line only when the `## Coverage` section is rendered — i.e. uncovered changed lines or unavailable tooling)*
**Last updated:** {ISO-8601 timestamp of this CR run}
**{tracker-mirror field}:** {tracker-mirror status}  *(field name and status wording are defined per-wrapper in that skill's own Output Rules section — see `@skills/code-review-github/SKILL.md`, `@skills/code-review-jira/SKILL.md`, or `@skills/code-review-bugsnag/SKILL.md` for the concrete values)*

---

## Technical Review

> The technical half of the review — the Core Analysis bullets, the Architecture conformance walk, security, and the coverage gate. Wraps `## Findings` through `## Coverage` below, unchanged in content and conditional-rendering behavior (see `@rules/code-review/general.md` *Two-Part CR Output — Technical & Functional Review*). This heading always renders, even when every subsection beneath it is empty — the header block's `Status: clean` / `Counts: Critical 0 · Moderate 0 · Minor 0` above is the "nothing to fix" signal in that case.

## Findings

> Render only when at least one Critical, Moderate, or Minor finding exists. Within this section, render only the severity sub-headings that have items — omit the others entirely. When all three severities are empty, omit the entire `## Findings` parent heading.

### 🔴 Critical 1. <short title>

- **Location:** `path/to/file.php:42`
- **Rule:** `@rules/<area>/<file>.md#<section>`
- **Provenance:** `regression — introduced in this revision` | `pre-existing — carried from round {n}` | `pre-existing — untouched by this revision`
- **Impact:** one sentence — what breaks or what risk this introduces.
- **Faulty Example:**
  ```php
  // minimal code or input that reproduces the issue (no secrets / PII)
  ```
- **Expected behavior:** single assertable statement (return value, thrown exception, persisted state, emitted event).
- **Test hint:** test layer (unit / integration / feature) + entry point, in one sentence.
- **Suggested fix:**
  ```php
  // minimal corrected snippet — must comply with @rules/php/core-standards.md (and @rules/laravel/architecture.md on Laravel projects). Use `n/a — <reason>` only when a snippet adds no value.
  ```

### 🟠 Moderate 1. <short title>

(same fields as Critical, Provenance included, plus one field that renders only on a round-3 deferral)

- **Deferred:** `<sub-issue URL>` — filed as a sub-issue of the source tracker item per `@skills/process-code-review/references/round-three-deferral.md`; the finding is recorded, not resolved. *(Omit this field entirely unless the finding was deferred.)*

### 🟡 Minor 1. <short title>  *(security-lens findings only — no other walk raises a Minor)*

- **Location:** `path/to/file.php:42`
- **Provenance:** `regression — introduced in this revision` | `pre-existing — carried from round {n}` | `pre-existing — untouched by this revision`
- **Note:** one sentence — naming, dead code, etc. Faulty Example / Expected behavior / Test hint / Suggested fix may be omitted when no behavior change is implied.

---

## Delegated to another person

> Render only when the **Reviewer Comment Fulfillment Gate** (`@skills/code-review-github/references/cr-wrapper-contract.md` *Delegation of a reviewer comment to another account*) classified at least one reviewer comment as delegated. Omit the entire section — no `None.` placeholder — when nothing was delegated. Entries here are not actionable findings: they block no merge, they count toward `M` in the `reviewer comments: M/N fulfilled` verdict rather than toward the Counts line, and they are never turned into a reproducer test or a fix.

1. **Reviewer comment:** `<comment URL>` — targets `path/to/file.php:42`
   **Addressed to:** `@<mentioned account>`
   **Mention:** "verbatim quote of the mention as written in the comment"
   **Declared by:** `<@author>` (`authorAssociation: OWNER|MEMBER|COLLABORATOR`)
   **Instruction:** one sentence describing what the reviewer asked for.
   **Note:** delegated — not this run's work, not resolved.

---

## Documentation Requests

> Render only when **Third-Party API & Service Analysis** step 7 in `@skills/code-review/SKILL.md` produced at least one blocking documentation request — i.e. the ordered source walk in step 2 resolved no reference for a third-party contract the diff touches. Each entry accompanies (never replaces) the Moderate finding raised for that contract; it is what lets the author close it with a single link. Omit the entire section when every affected contract resolved a reference — no `None.` placeholder.

1. **Vendor / service:** {name of the API, SDK, or webhook provider}
   **Version in use:** {resolved version + where it was read from — `composer.json` / lock file / pinned API version in config — or `could not determine`}
   **Verifying:** the concrete endpoints / SDK methods / webhook events / message contracts under review, one per line
   **Needed:** a link to the official documentation for that version covering the items above.

---

## Database Analysis

> Render only when the diff touches database operations (raw SQL, Eloquent / query-builder calls, eager loads, model scopes, ModelManager / Repository methods, migrations, seeders, DynamoDB / NoSQL access) **and** at least one finding is produced by the run's DB lens (`@skills/mysql-problem-solver/SKILL.md` on MySQL / MariaDB and on an unresolved engine, `@skills/postgres-patterns/SKILL.md` on PostgreSQL).
> Render one section whichever lens produced the findings — never a per-engine variant and never two sections. On MySQL / MariaDB the schema-feature trigger may add `@skills/mysql-patterns/SKILL.md` with `MODE=cr` as a second producer of this same section — render its findings here beside the engine lens's, still as one section. Omit the entire section when no DB operations are present in the diff, or when DB ops are present but no findings result — never leave a placeholder or fold it into Coverage. Report only findings and their fix recommendations — never the trigger decision, an inspected `file:line` list, or an EXPLAIN / static-analysis summary.

- **Findings:**
  1. **{Critical / Moderate / Minor}** — `file:line` — one-sentence problem
     **Suggested Fix:** {one-sentence fix category — query rewrite to reuse an existing index per `@rules/sql/optimalize.md`, batch operation per "Batch over per-row operations", or new-index proposal justified by EXPLAIN when no existing index covers the query}
     ```sql
     -- concrete rewritten query, index DDL, or batch-operation replacement implementing the fix above (issue #132) — never a category label alone
     ```

---

## Architecture

> **Laravel-only, conditional on findings (issue #530).** On every Laravel project (`laravel/framework` is in `composer.json` `require`), the architecture walk per `@skills/code-review/SKILL.md` Core Analysis "Architecture conformance (Laravel) — mandatory standalone walk-through" runs on every CR run, but this section is rendered **only when the walk produces at least one finding**. When the walk is clean, omit the entire `## Architecture` heading and body — do not render a `walked, 0 findings` status line, a `clean` placeholder, or any other confirmation that the check ran. On non-Laravel projects, omit the entire `## Architecture` section as well.
>
> Render findings under the standard severity sub-headings (Critical / Moderate / Minor) with the same six reproducer fields used in `## Findings`.

### 🔴 Critical 1. <short title>

(same fields as `## Findings` — Location / Rule / Provenance / Impact / Faulty Example / Expected behavior / Test hint / Suggested fix)

### 🟠 Moderate 1. <short title>

(same fields as Critical, Provenance included, plus one field that renders only on a round-3 deferral)

- **Deferred:** `<sub-issue URL>` — filed as a sub-issue of the source tracker item per `@skills/process-code-review/references/round-three-deferral.md`; the finding is recorded, not resolved. *(Omit this field entirely unless the finding was deferred.)*

### 🟡 Minor 1. <short title>  *(security-lens findings only — no other walk raises a Minor)*

- **Location:** `path/to/file.php:42`
- **Rule:** `@rules/laravel/architecture.md#<subsection>`
- **Provenance:** `regression — introduced in this revision` | `pre-existing — carried from round {n}` | `pre-existing — untouched by this revision`
- **Note:** one sentence. Faulty Example / Expected behavior / Test hint / Suggested fix may be omitted when no behavior change is implied.

---

## Coverage

> Render this section **only** when the coverage gate produced something to report — uncovered changed lines (Critical findings) or unavailable / non-runnable coverage tooling (Critical finding). When every changed line is at 100% coverage and the tool ran successfully, omit the entire `## Coverage` section, the `Coverage:` header line, and the `coverage …` slot in the summary line — the Counts line is the clean signal.

- **Tool:** {discovered coverage command name, or "not available — <reason>"}
- **Command:** `<exact command run>`
- **Result:** {list of uncovered added/changed lines — which must also appear as Critical findings — or "coverage tooling unavailable — <reason>"}

---

## Functional Review

> Always rendered — never omitted, the one exception to the omit-empty-section convention that governs `## Technical Review` above (see `@rules/code-review/general.md` *Two-Part CR Output — Technical & Functional Review*). Computed from the same Assignment Conformance Gate direction 1 already behind the `assignment conformance:` token on the Summary line below — no new analysis, only this explicit, always-present placement. Direction 2 (changes → requirements traceability / scope-creep) stays in `## Findings` above — it is diff hygiene, not "did the code satisfy the requirement".

{conformant → "All stated assignment requirements are satisfied." | gaps → list every Critical functional / business-logic gap below — still counted in the Counts line above}

### 🔴 Critical 1. <short title>  *(gaps case only)*

(same fields as `## Findings` — Location / Rule / Provenance / Impact / Faulty Example / Expected behavior / Test hint / Suggested fix; **Rule** cites the unmet requirement / acceptance criterion and its source instead of a `@rules/*.md` path)

(Repeat for every gap.)

---

**Summary:** {n} Critical · {n} Moderate · {n} Minor · assignment conformance: {conformant | N gap(s) | no linked issue}{` · coverage {result}` — appended only when the `## Coverage` section is rendered; omitted on a clean 100% pass}
{` · Assumption: <the assumption sentence verbatim from the branch that fired>` — appended **only** when a lens ran on an engine that is unresolved or has no dedicated lens, per `@skills/code-review/references/specialized-reviews.md`; omitted when the engine resolved to `mysql` / `mariadb` / `pgsql`, and omitted when neither trigger fired at all, so no resolution step ran and no lens is waiting on its answer}
{` · security: owned by athena (<url of athena's security comment>)` — appended **only** when the inline `security-review` pass was skipped because the caller set `SECURITY_OWNER=athena`; omitted when the pass ran here. **The URL is mandatory**: the token records a delegation, and without a link to the delivered review there is nothing to distinguish a security pass that ran from one that died mid-run. A token with no URL is itself the visible gap, and `@skills/merge-github-pr/SKILL.md` blocks the merge on it} · {tracker-mirror status}
