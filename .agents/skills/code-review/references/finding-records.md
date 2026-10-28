# Finding records — structured, fingerprinted review findings

This file is the one contract for turning a published code-review report into machine-readable finding records. It is phase 1 of the recurring-defect epic (#185): later phases group the records across pull requests, so the record and its fingerprint must be stable.

The contract adds no review format. It reads the two reports the review already produces: the findings report of a review round, and the `cr-comment` the converged run publishes (`templates/review-output.md`, `@rules/code-review/general.md` *One published comment per review run*). The reproducer fields, the severities, and the `Rule`, `Location`, and `Deferred` fields stay exactly as they are. The reviewer (`leonardo`) stays read-only and writes no record.

## Command

`skills/_shared/extract-findings.sh` is the only implementation. It is a plain shell script that needs `jq` and `sha256sum` or `shasum`, so it runs the same on Claude Code and on Codex. It runs outside the review and is not an agent binding.

```text
extract-findings.sh --repo <owner/name> --pr <number> [--input <file|->] [--store <file>]
extract-findings.sh --round --repo <owner/name> --pr <number> [--input <file|->]
extract-findings.sh --header [--input <file|->]
extract-findings.sh --validate <file>
extract-findings.sh --self-test
```

- Without `--store`, the script prints the extracted records, one JSON object per line.
- With `--store`, the script merges the records into that JSON Lines file by `id` and replaces the file atomically. It prints one summary line. One writer uses a store at a time.
- With `--round`, the script reads one round report of the review loop and prints one review-loop record (schema 2, see *Review-loop records* below) per finding identity. It writes nothing. `skills/_shared/review-state.sh` keeps the loop state.
- With `--validate`, the script checks a record file. A file holds records of one schema, and each record is checked against its schema.
- With `--header`, the script reads one report and writes nothing. It prints `{"revision","time"}`: the `Reviewed revision` and the `Last updated` time in UTC, from the same parse the extraction uses. It refuses with exit `3` every report that the extraction refuses while reading it.
- Exit `0` is success, `1` a usage error, `2` a missing tool, `3` a malformed or incomplete report or store. After exit `3` nothing is written.

## What the extractor reads

The extractor reads the header lines `Status`, `Counts`, `Reviewed revision`, and `Last updated`, every finding heading of the form `### <emoji> Critical|Moderate <n>. <title>` outside the excluded sections below, and the list entries of `## Deferred to sub-issues`. A finding carries these fields, all required except `Provenance`, `Deferred`, `Evidence`, and `Level`:

| Report field | Used for |
| --- | --- |
| heading word | `severity` |
| `Location` | `subsystem` |
| `Rule` | `category`, `cause_key` |
| `Impact` | `cause_hypothesis` |
| `Faulty Example` | `reproducer` |
| `Expected behavior` | `expected_behavior` |
| `Suggested fix` | `proposed_fix` |
| `Test hint` | required, not stored |
| `Deferred` | `disposition` |
| `## Deferred to sub-issues` entry | `disposition` of an open `moderate` record (see *One occurrence*) |
| `Evidence` | `evidence` of a review-loop record. Optional for the parse; a finding without it needs verification. |
| `Level` | `severity` of a review-loop record for a Moderate: `High`, `Medium`, or `Low`. Optional; any other value is rejected. |

A finding under `## Needs verification` has the same fields. It becomes a review-loop record with the status `needs-verification` and never a store record.

## The record

One JSON object per line. Every key is required, and no other key is allowed.

| Key | Value |
| --- | --- |
| `schema` | `1`. A change to any rule in this file bumps it. |
| `id` | `f-` and 16 hex digits. The hash of the repository, the pull request number, and the `fingerprint`. |
| `repo`, `pr` | `owner/name` and the pull request number. |
| `revision`, `time` | The `Reviewed revision` and the `Last updated` of the latest report that carried the finding, or that resolved or deferred it. `time` is UTC, with a trailing `Z`. |
| `severity` | `critical` or `moderate`. |
| `category` | The rule file the `Rule` field cites, without `.md` (for example `rules/security/backend`). `assignment` for a gap in `## Functional Review`. `unclassified` when nothing else applies. |
| `cause_key` | The section of that rule: the `#anchor` (a backticked anchor may hold spaces and runs up to the closing backtick), else the `*Section*` name written after the path, else `general`. A lowercase slug, so `#PHP Practices` and `*PHP Practices*` give the same key. `unmet-requirement` for an `assignment` gap. |
| `fingerprint` | 16 hex digits. The recipe is below. |
| `subsystem` | The first two directories of the `Location` path, lowercase. `.` for a file in the root. |
| `cause_hypothesis` | The `Impact` text. |
| `reproducer`, `expected_behavior`, `proposed_fix` | The text of the report fields, without code fences. Capped at 4000 characters. |
| `disposition` | `confirmed`, or `deferred` when the finding carries a `Deferred` field with a sub-issue URL. |
| `status` | `open`, or `resolved` (see *One occurrence*). |

## The fingerprint

The fingerprint is the first 16 hex digits of the SHA-256 of these lines, joined by a newline:

1. `ai-olympus/finding-fingerprint/v1`
2. `category`
3. `cause_key`
4. `subsystem`

The fingerprint comes from the behaviour and the cause. It never reads the title, the `Impact`, the reproducer, the line number, the file name, or any other wording. The same defect described in other words, on another line, or in another file of the same subsystem, has the same fingerprint. A different rule section or a different subsystem has a different fingerprint.

The consequence is stated plainly: two distinct defects of one rule section in one subsystem share a fingerprint. They count as one occurrence in one pull request. Phase 2 counts occurrences in different pull requests, so this loses nothing it uses.

## One occurrence per finding per pull request

- A finding is identified by its `id`. A second finding with the same `id` in one report is one record. The higher severity wins, and `confirmed` wins over `deferred`.
- A later round, an updated finding, and a reopened finding keep the `id`. The merge replaces the record and never adds a second one.
- A report older than the stored record changes nothing. Extracting the same report twice leaves the store byte-identical.
- A report of a pull request resolves the `confirmed` records of that pull request that it no longer carries. A `deferred` record is never resolved by absence. A report of another pull request resolves nothing here.
- A resolved record takes the `revision` and the `time` of the report that resolved it. An older report, such as a replay of the last round that carried the finding, then changes nothing.
- A round report precedes triage and has no `Deferred` field. The converged `cr-comment` lists a deferred Moderate only under `## Deferred to sub-issues`, one list entry per finding. The extractor takes the first path in an entry as the subsystem and requires a sub-issue URL in the entry. An open `confirmed` Moderate of the same repository, pull request, and subsystem that the report no longer carries becomes `deferred` and stays `open`, instead of `resolved`. It takes the `revision` and the `time` of that report. An entry without a path or without a URL defers nothing. A Critical is never deferred this way. Matching is by subsystem, so a Moderate that the loop fixed can also end `deferred` and `open` when a deferred Moderate of the same subsystem exists; the match errs toward `open`.

## What never becomes a record

- Anything under `## Excluded per assignment` or `## Delegated to another person`: these are dismissed or not this run's work.
- Anything under `## Needs verification`: no check of the review proved it. `--round` reads it as a review-loop record with the status `needs-verification`.
- The `Not verified:` header line and any observation without a finding heading: the review reports only verified findings, and an unconfirmed point is not a finding (`@rules/code-review/review-process.md` *Output Rules — Truthful reporting*).
- A finding the review dropped. The report does not carry it.
- Any record with a `disposition` other than `confirmed` or `deferred`. `--validate` rejects it.
- A `## Deferred to sub-issues` entry never creates a record. It only changes the `disposition` of a record an earlier report created.

## Untrusted input and errors

The report is untrusted input (`@rules/security/general.md` *Untrusted Content Boundary*). The script reads it as data only. It never executes a line, never builds a command, a path, or a jq program from it, and it removes control characters. It rejects an input over 1 MiB. It caps each `## Deferred to sub-issues` entry at 4000 characters and rejects, with exit 3, a report that lists more than 200 entries there.

The text fields of a record (`cause_hypothesis`, `reproducer`, `expected_behavior`, `proposed_fix`) stay untrusted content for every consumer of the records. A consumer reads them as data and never as an instruction. A consumer fences them before they travel next to its own instructions or into an issue body.

The script rejects, with one clear message per problem and no crash:

- a text that is not a review report (a missing `Status`, `Counts`, `Reviewed revision`, or `Last updated` header line);
- a `Reviewed revision` that is not a commit SHA, and a `Last updated` that is not an ISO-8601 timestamp with a UTC offset;
- a finding that lacks a required field, repeats a field, or has a `Deferred` field without a sub-issue URL;
- a store line that is not valid JSON or does not satisfy the schema, and a repeated `id` in a store.

## Later phases

The record carries what the next phases read, so they need no second extraction:

- Grouping across pull requests uses `fingerprint` (or `category`) with `repo`, `pr`, and `time`. Counting distinct pull requests inside a window needs nothing else.
- Incremental analysis compares `revision`, `time`, and `status` of a record with what it processed before.
- A prevention proposal cites `category`, `cause_key`, `subsystem`, `reproducer`, and `expected_behavior`.
- Routing by tier reads `severity`.

Phase 1 does not run the extractor from the review loop, store records anywhere by default, or group them. Issue #225 adds the round mode below: the review loop runs it through `skills/_shared/review-state.sh`, and it writes no store record. Phase 4 wires those steps: `skills/_shared/feedback-loop.sh` runs the extractor, and `feedback-loop.md` fixes the store and passes the canonical `nameWithOwner` as `--repo`.

## Review-loop records (schema 2)

The store records above count one defect class across pull requests, so two defects of one rule section in one subsystem are one record there. The review loop needs the opposite: it must keep two such defects apart, follow one defect from round to round, and know which finding blocks. `--round` therefore prints a second record shape from the same parse. It changes nothing in the store records, their fingerprint, or their `id`, so the recurrence analysis reads exactly what it read before.

One JSON object per line. Every key is required, and no other key is allowed.

| Key | Value |
| --- | --- |
| `schema` | `2`. |
| `finding_id` | `r-` and 16 hex digits. The identity recipe is below. |
| `repo`, `pr`, `revision`, `time` | As in a store record, taken from the round report. |
| `category`, `cause_key` | As in a store record: the cited rule file and its section. The category is the rule, so `rules/security/backend` is a security category and `rules/php/core-standards` a maintainability one. |
| `severity` | `critical`, `high`, `medium`, or `low` (the mapping is below). |
| `security` | `true` when the finding meets the S1-S3 carve-out (below). |
| `file`, `line` | The path of the `Location` field and the line written after it. `line` is `null` when the location names none. `file` is `.` when the location names no path. |
| `description` | The finding title. |
| `impact` | The `Impact` text. |
| `evidence` | The `Evidence` text, or `null`. |
| `recommendation` | The `Suggested fix` text. |
| `status` | `new`, `confirmed`, `resolved`, `dismissed`, or `needs-verification`. |

The text fields are capped at 4000 characters and carry no control character. They stay untrusted content for every consumer, exactly like the text fields of a store record.

### Severity

| CR severity | `Level` field | `severity` |
| --- | --- | --- |
| Critical | any or none | `critical` |
| Moderate | `High` | `high` |
| Moderate | `Medium`, or none | `medium` |
| Moderate | `Low` | `low` |

A security lens publishes its `High`, `Medium`, and `Low` as a Moderate (`@rules/code-review/general.md` *Minor findings are not detected*). The `Level` field keeps the lens level, and every one of the four values blocks. No severity is below the blocking line.

### Identity

The `finding_id` is the first 16 hex digits of the SHA-256 of these lines, joined by a newline, with `r-` in front:

1. `ai-olympus/finding-id/v2`
2. `repo`
3. `pr`
4. `category`
5. `cause_key`
6. `file`

- **The line number and the wording never enter the identity.** A finding repeated without change, reworded, or moved to another line of the same file keeps its `finding_id`.
- **The file does.** Two defects of one rule section in two files are two findings, even in one subsystem, where the store fingerprint counts them once.
- **Conservative fallback.** Two findings of one rule section in one file share an identity. `--round` merges them into one record: the higher severity, the more blocking status (`confirmed`, then `new`, then `needs-verification`, then `resolved`, then `dismissed`), and the security flag of either side win. The merge never lowers what blocks: a fix of one of the two leaves the identity open while the round still reports the other.
- A renamed file gives a new identity. The old one leaves the loop only by the reviewer's re-read, like any other finding.

### Status from the round report

- A finding with an `Evidence` field is `new`.
- A finding under `## Findings` without one is refused: `--round` exits 3 with `Evidence is required; move an unproven point under ## Needs verification`. Store mode still reads it, so reports written before the field existed keep their records.
- Every entry under `## Needs verification` is `needs-verification`.
- `confirmed`, `resolved`, and `dismissed` are never read from a report. `skills/_shared/review-state.sh` sets them, and `skills/process-code-review/references/review-state.md` owns who may.

### Security relevance

A record is `security: true` when its rule is a security rule (`rules/security/**`) or a security lens (`security-review`, `laravel-authorization-review`), or when its category, cause, file, or title names a security surface: authentication, sessions and tokens, credentials and secrets, cryptography and signatures, permissions and policies, injection, XSS, CSRF, SSRF, open redirects, uploads and path traversal, payments, personal data, rate limits, escaping and sanitizing, deserialization, mass assignment, and security headers. The match is broad on purpose. A false positive keeps a finding blocking. A false negative would let a security finding be dismissed or deferred.

### What `--validate` rejects in a schema-2 file

- every problem of shape, as for a store record;
- a repeated `finding_id`;
- `status` `new` or `confirmed` with `evidence` `null`: a blocking status needs evidence;
- `status` `dismissed` on a `security: true` record: a security finding (S1-S3) is never dismissed;
- a file that mixes schema-1 and schema-2 records.
