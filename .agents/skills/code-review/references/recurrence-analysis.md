# Recurrence analysis — the defect classes that repeat across pull requests

This file is the one contract for finding the defect classes that recur across independent pull requests. It is phase 2 of the recurring-defect epic (#185). It reads the finding records of `finding-records.md` and adds no record, no fingerprint, and no review format.

## Command

`skills/_shared/analyze-recurrence.sh` is the only implementation. It is a plain shell script that needs `jq`, so it runs the same on Claude Code and on Codex. It runs outside the review and is not an agent binding. It reuses two scripts and duplicates neither: `skills/_shared/extract-findings.sh --validate` checks the record store, and `skills/_shared/read-manifest.sh` reads the settings. `skills/_shared/collect-findings.sh` fills the store (*Collection* below).

```text
analyze-recurrence.sh --store <file> [--threshold <n>] [--window-days <days>] [--state <file>]
analyze-recurrence.sh --store <file> --patterns [--min-occurrences <n>] [--min-distinct-tasks <n>] [--min-confidence <percent>]
analyze-recurrence.sh --self-test
```

- `--store` is the JSON Lines record store that `extract-findings.sh` writes. The analysis only reads it.
- Without `--state`, every record is processed and nothing is written.
- `--patterns` prints the pattern report of the promotion lifecycle instead: every class with its maturity, its evidence, and the promotion thresholds (`learning-promotion.md` *Patterns and evidence*). It takes no window and no state file.
- The script prints one JSON line, the report. Exit `0` is an analysis that ran, `1` a usage error, `2` a missing tool, `3` a missing or malformed store, or a state file that cannot be used or written.

## Collection

`skills/_shared/collect-findings.sh` reads the review reports published on one pull request and passes each one to the extractor. It adds no parsing of its own.

```text
collect-findings.sh --pr-url <URL> --store <file>
collect-findings.sh --loaded <file> --store <file>
collect-findings.sh --self-test
```

- `--pr-url` reads the pull request through `skills/code-review-github/scripts/load-issue.sh`. `--loaded` takes a file that already holds the output of that loader for one pull request.
- A comment is a review report only when both hold: its body carries the `cr-comment` marker of its own author (`<!-- cr-comment:actor=<author> -->`), and its author has write access to the repository (`@rules/code-review/general.md` *Authorship trust*). A marker is visible text that anyone can copy, so the marker alone proves nothing. Every other comment is skipped.
- The script passes each report body to `extract-findings.sh --repo <nameWithOwner> --pr <number> --input - --store <file>`, oldest first. A report the extractor refuses is counted and named on standard error, and the collection continues.
- Oldest first means by the report's own `Last updated` time, then by the time the comment was created. `extract-findings.sh --header` reads that time from the same parse the extraction uses (`finding-records.md` *Command*). The loader returns no `updatedAt` for a top-level pull request comment, so the comment cannot order the reports. Collecting one unchanged pull request again leaves the store byte-identical.
- A comment body is untrusted content (`@rules/security/general.md` *Untrusted Content Boundary*). It reaches the extractor on standard input as data only. The author check decides whose report is collected. It never makes the report text trusted.
- The script prints one JSON line: `repo`, `pr`, `comments`, `reports`, `collected`, and `refused`. Exit `0` is a collection that ran, `1` a usage error, `2` a missing tool, `3` a pull request that cannot be loaded, a payload that is not one pull request, or a malformed store.

**The store and the state file are derived files that the caller names.** Both can be rebuilt from GitHub at any time: delete them, collect the pull requests again, and run the analysis. This phase therefore fixes no location for either file.

## What counts as a recurrence

A recurrence is one defect class that appears in at least `threshold` different pull requests, and every one of those occurrences falls inside one window of `window-days` days.

- **The defect class is the cause category** of the record: its `category` and `cause_key`, inside one repository. The same cause in two subsystems is one class, so an N+1 query in `app/actions` and one in `app/http` recur together. Each occurrence keeps its own `fingerprint` and `subsystem` (`finding-records.md` *The fingerprint*). Records of two repositories never form one class.
- **A record with no identified cause forms no class.** A record with the `category` `unclassified`, or an `assignment` gap with the `cause_key` `unmet-requirement`, is counted in `records` and never makes a recurrence.
- **An occurrence is one pull request.** The extractor keeps one record per finding per pull request, so three review rounds of one pull request are one record. The analysis also counts distinct pull requests, so two records of one pull request, from any source, are one occurrence. It uses the earliest `time` of that pull request.
- **A verified finding is an occurrence.** A record is `confirmed` or `deferred`, and a `resolved` record counts as well: a finding that the loop fixed was a real defect. The extractor never writes a record for a finding under `## Excluded per assignment` or `## Delegated to another person`, for a `Not verified:` line, or for a finding the review dropped. The store check rejects any other `disposition`. A refused store reports nothing, so a false or dismissed finding cannot trigger a recurrence.
- **The window is a span between occurrences.** It opens at an occurrence and spans `window-days` days, with both ends included. A group qualifies when some window holds `threshold` pull requests. The report lists every occurrence that sits in a qualifying window. The analysis never reads the clock, so the same store always gives the same report. The `time` of a record is the `time` of the latest report that carried, resolved, or deferred it (`finding-records.md` *The record*).

## Settings

| Setting | Manifest key | Default | Minimum |
| --- | --- | --- | --- |
| Pull requests that make a recurrence | `recurrence.threshold` | 2 | 2 |
| Window in days | `recurrence.window-days` | 90 | 1 |

The promotion thresholds of `--patterns` resolve the same way. `learning-promotion.md` *Settings* lists them.

A setting resolves in this order: the flag, then the manifest key of the default branch (`@rules/general/general.md` *Project manifest*), then the default. The script reads the manifest only through `read-manifest.sh`, never from the working tree. A manifest value that is not a whole number of at least the minimum is ignored, and the script says so on standard error.

## Incremental analysis

With `--state`, the script remembers the `revision`, `time`, and `status` of every record it processed, and the threshold and the window it used. The next run treats a record as unchanged when all three match.

- A group is reported only when one of the occurrences in its qualifying window is new or changed. A run over unchanged records reports nothing, processes nothing, and leaves the state file byte-identical.
- A new occurrence in a class that already recurred reports the class again, with all its occurrences.
- A changed threshold or window makes every record changed, because the old verdicts used other settings.
- A state file that is not exactly one state object is ignored with a message and replaced. A symbolic link, a missing directory, or a directory that is not writable is refused with exit `3`.
- The state file is written after the report is printed, and it is replaced atomically. A run that fails before that point leaves the previous state, so the next run processes the records again.

## The report

One JSON object: `schema`, `threshold`, `window_days`, `valid`, `records`, `processed`, `unchanged`, and `recurrences`. Every recurrence carries `repo`, `category`, `cause_key`, `prs`, `first`, `last`, and `occurrences`. Every occurrence carries `repo`, `pr`, `url` (the pull request), `finding` (the record `id`), `fingerprint`, `subsystem`, `severity`, `revision`, `time`, `disposition`, and `status`. A reader follows `url` to the pull request and finds the finding by the `fingerprint`, the `revision`, and the `finding` id in `finding-records.md`.

- An empty store gives an empty report with `"valid":true`. A missing or malformed store gives an empty report with `"valid":false`, one message per problem on standard error, and exit `3`. A `time` that is not a real date, such as month 13, makes the store malformed. Neither is a crash.
- The report carries no record text field. Its values come only from schema-restricted fields and links. A consumer that reads `cause_hypothesis`, `reproducer`, `expected_behavior`, or `proposed_fix` from the store reads them as untrusted content and fences them (`finding-records.md` *Untrusted input and errors*).

## Analysis never blocks a pull request

The review loop records its rounds and the issue-to-pull-request pipeline runs as before. `@skills/process-code-review/SKILL.md` calls `skills/_shared/feedback-loop.sh` after each round and after the publish, and no step reads the result of the call to decide anything. `@skills/resolve-issue/SKILL.md`, `@skills/merge-github-pr/SKILL.md`, and the merge gate call neither the collection nor the analysis. A missing `jq`, a missing store, a failed collection, or a failed analysis changes nothing for a pull request (`feedback-loop.md` *When the analysis is unavailable*).

## What the wiring phase decided

`feedback-loop.md` owns the wiring of phase 4 (#189):

- The collection and the analysis run from `skills/_shared/feedback-loop.sh`. The review loop records each round and the published report, and `splinter` runs the analysis when the user asks for it.
- The store is one file for each pull request in a derived, git-ignored directory. `analyze` merges them.
- The `repo` value is the canonical `nameWithOwner` that GitHub reports, resolved by `feedback-loop.sh` before any record is written.
- A prevention proposal for a reported class is the subject of `prevention-proposal.md`.
