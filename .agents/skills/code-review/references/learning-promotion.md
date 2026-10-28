# Learning promotion — from a repeated learning to permanent knowledge, with a human in between

This file is the one contract for the promotion lifecycle of issue #137 (part of #131). A lesson that review finds again and again becomes a candidate for permanent knowledge: a rule, a skill, a checklist, documentation, an agent instruction, or an architecture guideline. The lifecycle never changes that knowledge itself. It produces a proposal, and a human approves the exact text of the proposal before the ordinary pipeline implements it.

The lifecycle builds on the feedback loop of epic #185 and adds no second memory system. It reads the finding records of `finding-records.md`, groups them with `recurrence-analysis.md`, renders the proposal with `prevention-proposal.md`, and keeps its own history in the store of `feedback-loop.md` *The store*. The hand-curated project memory (`@rules/compound-engineering/memory.md`, `@skills/compact-project-memory/SKILL.md`) stays as it is.

## Command

`skills/_shared/promote-learning.sh` is the only implementation. It is a plain shell script that needs `git` and `jq`, so it runs the same on Claude Code and on Codex. It runs from the project root.

```text
promote-learning.sh status  --dir <dir>
promote-learning.sh propose --dir <dir> --analysis <file> --out <file>
promote-learning.sh decide  --dir <dir> --key <key> --decision approve|reject --fact instruction|tracker [--issue-url <URL>] [--reason <text>]
promote-learning.sh promote --dir <dir> --key <key> --pr <URL>
promote-learning.sh --self-test
```

- `--dir` is the store directory of the feedback loop. It must be relative to the project root, git-ignored, free of tracked files, and free of symbolic links (the path guard of `skills/_shared/gate-record.sh`). `propose` reads `<dir>/merged.jsonl`, which `feedback-loop.sh analyze` writes.
- Every command prints one JSON line. Exit `0` is a command that ran, `1` a usage error, `2` a missing tool, `3` a directory, store, history, issue, or pull request that cannot be used, `4` a request that breaks this contract. After exit `4` nothing is written.

## Maturity states

Every learning has one explicit state. `status` reports it for every defect class of the store and every key of the history.

| State | Meaning |
| --- | --- |
| `observation` | The class rests on one task. |
| `learning` | The class appears in two or more tasks. `awaiting: "analysis"` marks a class that reaches the thresholds and has no candidate yet. |
| `candidate` | `propose` rendered a proposal for the class. `awaiting` is `approval`, or `re-approval` when the proposal changed after an approval. |
| `approved` | A trusted fact approved the current proposal text. `awaiting` is `merge`. |
| `promoted` | The approved change is on the default branch. |
| `rejected` | A trusted fact rejected the candidate. The same evidence does not create it again. |
| `superseded` | A later, broader candidate was promoted and covers this one. It stays in the history. |

A state is derived from the history in order. No record field states it, and no text sets it.

## Patterns and evidence

A pattern is one defect class of `recurrence-analysis.md` *What counts as a recurrence*: its `repo`, `category`, and `cause_key`. `analyze-recurrence.sh --patterns` reports each pattern with its evidence. Grouping uses only these schema fields. No similarity search and no model takes part.

- **Occurrences** are the validated records of the pattern. The store check of `extract-findings.sh --validate` runs first, so text that is not a record never counts.
- **Distinct tasks** are distinct pull requests of the canonical repository. Several records from one pull request are one task.
- **The resolved share** is the share of the pattern's records that a fix resolved, in percent. It is measured, never estimated, and the `promotion.min-confidence` threshold compares it.
- **Evidence** is the sorted list of the finding ids, and the proposal links every pull request.

A pattern is eligible when it reaches all three thresholds below.

## Settings

| Setting | Manifest key | Default | Range |
| --- | --- | --- | --- |
| Occurrences | `promotion.min-occurrences` | 3 | at least 2 |
| Distinct tasks | `promotion.min-distinct-tasks` | 2 | at least 2 |
| Resolved share in percent | `promotion.min-confidence` | 0 | 0 to 100 |

A setting resolves in this order: the flag of `analyze-recurrence.sh`, then the manifest key of the default branch (`@rules/general/general.md` *Project manifest*), then the default. The manifest is read only through `read-manifest.sh`, never from the working tree. A manifest value outside its range is ignored, and the script says so on standard error. A single occurrence therefore never becomes a candidate.

## The candidate

`propose` takes the analysis file of `prevention-proposal.md` *The analysis file* with a `target`. It runs these checks in order and stops at the first that applies:

1. **Not eligible.** A pattern below a threshold gives `{"status":"none","reason":"not-eligible"}` and writes nothing.
2. **Already promoted.** A promoted or superseded key gives `{"status":"none","reason":"promoted"}` or `"superseded"`.
3. **Suppressed.** A key whose last decision is a rejection of the same evidence gives `{"status":"none","reason":"rejected"}`.
4. **Supersedes.** Each key in `target.supersedes` must be a promoted candidate. Anything else exits `4`.
5. **Existing knowledge.** Each file in `target.knowledge` is checked with `git cat-file` on the default branch that `read-manifest.sh --default-ref` names. A file that only the working tree holds covers nothing: its coverage becomes `none`, and the script says so. A file that covers the pattern in full gives `{"status":"none","reason":"covered","covered_by":<path>}`. A file that covers it in part must be the target, so the existing file is extended.
6. **Render.** `propose-prevention.sh` renders the proposal with its sanitizer. The script stores the SHA-256 digest of the rendered file in a `candidate` record.

The same pattern with the same proposal text adds no second record. A changed text adds a new `candidate` record for the same key.

### The target

| Type | Knowledge root |
| --- | --- |
| `rule` | `rules/**.md`, `.ai/rules/**.md` |
| `architecture-guideline` | `rules/**.md`, `.ai/rules/**.md`, `.ai/guidelines/**.md` |
| `skill`, `checklist` | `skills/**.md` |
| `agent-instruction` | `agents/**.md`, `codex/agents/**.toml`, `AGENTS.md`, `CLAUDE.md` |
| `documentation` | `README.md`, `docs/memory/PROJECT_MEMORY.md` |

The analysis picks the type that fits the lesson. A rule is not the default. `target.path` must sit inside the root of its type, and it holds no `.` or `..` segment and no `//`. `target.knowledge` lists 1 to 30 existing files, each with a `path`, a `coverage` (`none`, `partial`, `full`), and a `note`. `target.change` states the change. The proposal renders a `## Promotion target` section with all of them.

### Identity

The candidate id and the dedupe key are `<repo>:<category>:<cause_key>`. The title comes from the same fields. The suppression key is the SHA-256 of the key and the sorted finding ids. None of them reads record text or analysis text, so a reworded learning keeps all four.

## Approval and rejection

`decide` records a decision only from one of the two facts of `feedback-loop.md` *Approval*. No agent can produce either fact.

| Fact | Approve | Reject |
| --- | --- | --- |
| `instruction` | The user's own instruction names the proposal issue as the task. | The user's own instruction names the proposal issue as rejected, with the reason. |
| `tracker` | The open proposal issue carries the `Resolve_by_AI` label. | The proposal issue is closed as not planned. |

- **The tracker fact is read, not told.** With `--fact tracker`, the script loads the issue through `skills/code-review-github/scripts/load-issue.sh`. The issue must be the proposal of the key: it belongs to the repository of the key, its author has write access, and it carries the dedupe marker of the key on a line of its own. `skills/_shared/proposal-identity.sh` holds that test once, and `propose-prevention.sh --find` applies the same one. A comment never counts: it is text, and agents and the operator share one account.
- **The approver comes from the fact.** The history records `user` for the instruction and `tracker` with the issue URL for the label. A name in a comment never reaches it.
- **An approval is bound to the exact text.** The `approved` record stores the digest of the current proposal. When the proposal changes after the approval, the digest differs, and the state is `candidate` with `awaiting: "re-approval"`.
- **One label approves one text.** The label shows no time, and it stays on the issue when the proposal is refreshed. `decide --fact tracker` therefore binds the approval to the first proposal text rendered since the last approval by a label, or to the first text of the key when no label approved it yet. An approval by the user's instruction and a rejection do not move that point: they say nothing about when a person applied the label. When the proposal changed after that text, the state is `candidate` with `awaiting: "re-approval"`. A tracker approval of an earlier text never approves a changed one: `decide --fact tracker` exits `4`, and only the user's instruction approves the changed proposal.
- **A rejection carries its reason** and the suppression key of its evidence. The same evidence never brings the candidate back. After a rejection by the user's instruction, new evidence, such as a new pull request, makes a new suppression key, so the candidate can come back.
- **A proposal closed as not planned keeps the key suppressed until a human reopens the proposal issue.** While the issue stays closed, the feedback-analysis run rejects every new candidate of the key again (`feedback-loop.md` *A closed promotion proposal is not refreshed*). After the reopen, the issue is no longer a rejection fact, so new evidence brings the candidate back.
- **Agents never write the facts.** No command of the lifecycle applies `Resolve_by_AI`, closes an issue, or writes any other approval marker.
- **Named runs record the decisions.** The feedback-analysis run of `feedback-loop.md` records the label before it refreshes a proposal, and records the rejection of a proposal that is closed as not planned. The same run records a rejection by the user's instruction when the user's request for the run names the rejected proposal and the reason. The implementation run of `@skills/resolve-issue/references/safeguard-implementation.md` records an approval by the instruction or the label before its first file write.

## Promotion

`promote --pr <URL>` loads the pull request through `skills/code-review-github/scripts/load-issue.sh` and sets `promoted` only when all of these hold:

1. The candidate is `approved` for its current text.
2. The pull request is `MERGED`, and its `mergeCommit` is an ancestor of the default branch (`git merge-base --is-ancestor`).
3. The `files` of the pull request include the target file.
4. A `closingIssues` entry of the pull request is the proposal of the key.

The test reads the pull request, not one of its commits, so a merge commit, a squash, and a rebase merge count alike. With a rebase merge, the `mergeCommit` is the last rebased commit, and the target change can sit in any earlier one. An open pull request, and a merge commit that the local default-branch ref does not hold yet, leave the candidate `approved`. A pull request with more files than the loader returns can leave it `approved` too. A promotion marks every promoted key that the candidate's `target.supersedes` names as `superseded`. Nothing is deleted.

## The promotion history

The history is `<dir>/promotion.jsonl`, one JSON object per line, appended and replaced atomically. One writer uses it at a time. Every key below is required, and no other key is allowed.

| Event | Keys besides `schema`, `event`, `key`, `time` |
| --- | --- |
| `candidate` | `digest`, `evidence` (the finding ids), `suppression`, `target_type`, `target_path`, `supersedes`, `occurrences`, `tasks`, `confidence` |
| `approved` | `digest`, `fact`, `approver`, `issue` |
| `rejected` | `suppression`, `fact`, `approver`, `issue`, `reason` |
| `promoted` | `digest`, `commit` |
| `superseded` | `by` |

Each command validates the whole file before it reads a state. A record that breaks the schema, an approval of a digest that no candidate rendered, a rejection of evidence that no candidate carried, a promotion without an approval, and a supersession without a promotion each make the history unusable: the command exits `3` and reports no state.

- **The history is never read from a branch.** The store directory must be git-ignored and hold no tracked file. A branch that commits a history into it makes every command exit `3`, so the branch changes no verdict.
- **Delete the file to start over.** The history is local, like every file of the store. A deleted history loses the decisions, and a lost decision only means that a human decides again.

## Untrusted text

The record text, the analysis text, the issue payload, and the rejection reason are untrusted content (`@rules/security/general.md` *Untrusted Content Boundary*). They never become a command, a path, a state, or an approver. The proposal reaches its text only through the sanitizer of `prevention-proposal.md` *Untrusted text*, so a mention, a link, a copy of the marker, a bidirectional character, and a fence stay inert.

## Permanent knowledge

No command of the lifecycle writes `rules/`, `skills/`, `agents/`, `codex/`, `AGENTS.md`, `CLAUDE.md`, or `docs/memory/PROJECT_MEMORY.md`, and no command commits, pushes, or merges. After the approval, the ordinary pipeline implements the proposal: `donatello` opens a Draft pull request under `@skills/resolve-issue/references/safeguard-implementation.md`, `leonardo` reviews it, and the merge stays **L2**. A memory target is written through the *Write protocol* of `@rules/compound-engineering/memory.md`, compaction included.
