---
description: Git — pull request and merge rules: issue linking, PR title, body and Draft state, PR lifecycle, the code-review merge gate, and its HOTFIX, FAST-tier and dependency-only cases.
paths:
  - ".claude/run/**"
  - ".claude/rules/git/pull-requests.md"
---

## Issue Linking

This section is the GitHub mechanic for `@rules/compound-engineering/tracker.md` *Every pull request links back to its tracker issue*. That section owns the invariant across every tracker; this one owns how GitHub carries it.

- **Write the literal `Closes #<N>` into the pull request body.** GitHub derives `closingIssuesReferences` — the auto-close on merge and the backlink rendered on the issue — from the body of the pull request. A reference that lives only in a commit message leaves the pull request unlinked until the merge lands that commit on the default branch. Every skill in this package that reads `closingIssues[]` reads it off the pull request long before that merge, so the body is where the keyword belongs.
- **The keyword is English, always.** GitHub parses only `close` / `closes` / `closed`, `fix` / `fixes` / `fixed`, and `resolve` / `resolves` / `resolved`. A translated keyword is not parsed, and `closingIssuesReferences` stays empty while the surrounding sentence still reads like a link. `Closes #<N>` is therefore exempt from the assignment-language rule for the PR body, exactly like a code identifier.
- **Keep the reference in the commit too.** A commit that resolves the issue carries `Closes #<N>` in its body, which is what closes the issue on a rebase merge. The commit reference is additive. It never substitutes for the reference in the pull request body.
- **Verify the link landed.** After opening the pull request, re-read it through `skills/code-review-github/scripts/load-issue.sh <PR-URL>` and confirm `closingIssues[]` names the issue. An external write can be silently blocked in auto-mode, so `gh pr create` exiting zero is not evidence.

## Pull Requests
- PR title must be in English.
- PR description must be written in the same language as the assignment. The literal `Closes #<N>` keyword is the one exception, because GitHub parses no other spelling — see *Issue Linking* above.
- **When the project manifest sets `language.github`** (`@rules/general/general.md` *Project manifest*), that language replaces both rules above: the PR title, the PR description, and every PR or issue comment are written in it. `Closes #<N>` stays English.
- Format PR messages as Markdown.

### PR Content Requirements
- Include links to all sources used during analysis.
- Prefer adding these as a comment on the related GitHub issue.

### Draft pull requests — open as Draft until the PR is ready to merge
A pull request is a **Draft** for as long as it is **not yet ready to merge and agents will keep working on it** — the canonical case in this workflow is an agent-opened PR that still has to pass the post-PR authoritative review/fix loop (`@skills/code-review-github/SKILL.md` + `@skills/process-code-review/SKILL.md`, i.e. the `leonardo` ↔ `donatello` convergence loop) before it can be merged. The Draft state is the visible signal that the PR is work-in-progress and the hard code-review merge gate is still unmet.

- **Open as Draft.** When an agent creates a PR that still needs that review/fix loop, create it as a Draft: `gh pr create --draft …`. This covers every agent-driven PR-creation path (`@skills/resolve-issue/SKILL.md`, and the Finalization step of `@skills/process-code-review/SKILL.md` when it has to create the PR itself).
- **A `FAST`-tier run has no review loop to converge, so `splinter` promotes it.** When adaptive routing classifies the change `FAST` on its final diff, no `leonardo` pass is dispatched and `process-code-review` never runs, so nothing would otherwise take the pull request out of Draft. `agents/splinter.md` *Adaptive routing* → *Closing a `FAST` run* owns that promotion, and it is gated on the same two facts the loop would have proven: the final classification is still `FAST`, and `donatello`'s scoped validation returned green. Every other tier keeps the rule below unchanged.
- **Mark ready on convergence.** The PR is promoted out of Draft (`gh pr ready <PR>`) **only** once the code review has converged on its final diff — **0 Critical, and no undeferred Moderate** (the canonical gate is `@skills/process-code-review/SKILL.md` *Review loop* step 4). This transition is owned by that skill (it runs the convergence loop), and is performed only after the loop exits converged — never on a PR that still carries a Critical, a security-relevant Moderate, or a Moderate that failed the filing bar. That same step writes the matching *ready to merge* signal on the source tracker item, and withdraws both when a later commit re-opens the review (`@rules/compound-engineering/tracker.md` *Tracker status tracks the phase of work*, phase 3).
- **A Draft PR is never merged.** `@skills/merge-github-pr/SKILL.md` treats `isDraft == true` as not-ready and skips it: a Draft mirrors the unmet code-review gate. If a Draft PR's review has in fact converged, mark it ready first (the `process-code-review` step above), then merge — never merge a Draft directly, and the GitHub Actions billing exception never relaxes this.

### Testing
- Suggest how to test the changes (UI, API, etc.).
- Verify that tests exist:
    - If yes → update or extend them if needed.
    - If no → explicitly state: `no`.

## PR Lifecycle
- When merging a PR:
    - Merge into the default branch (`$DEFAULT_BRANCH`, resolved per `@rules/git/general.md` *Pull Policy*)
    - Close the PR
    - Delete the branch
    - Remove the worktree if one was created for this work unit (see `@rules/git/general.md` *Worktrees / Workspaces* for the opt-in / safety rules; `@skills/merge-github-pr/SKILL.md` §5 owns the step)
    - Switch locally to the default branch
    - Pull latest changes

- If already deployed:
    - Only switch to the default branch and pull latest changes

## Merging
- Use rebase and merge strategy
- **Code review is a hard merge gate — never optional, never skipped.** A PR may be merged only after a code review has been run on its **final diff** (the exact commits being merged) and the review reports **no errors**: **zero Critical findings, and no undeferred Moderate finding**. This gate applies to **every** merge path — manual and orchestrated (`splinter`) — and is owned by `@skills/merge-github-pr/SKILL.md`. The Moderate half works as follows:
    - **A Critical always blocks**, at every round, with no deferral and no exception.
    - **A Moderate blocks until it is resolved, and it is resolved in one of two ways** — fixed in the review loop, or, at round 3 only, deferred into a tracker sub-issue (`@skills/process-code-review/SKILL.md` *Review loop* step 6 and `references/round-three-deferral.md`). A Moderate that is neither fixed nor deferred still blocks.
    - **A security-relevant Moderate is never deferrable.** A finding meeting the **S1–S3** carve-out of `@rules/code-review/general.md` *Assignment-Declared Test-Only Conditions — Exclusion Gate (issue #17)* — produced by a security lens, citing a rule in `@rules/security/**`, or landing on a security surface — blocks the merge until it is fixed. No filing bar, no sub-issue, and no round count changes that.
- If no code review exists for the PR, or the latest review still carries an unresolved Critical or an undeferred Moderate, **do not merge** — run (or re-run) the review to convergence first via `@skills/code-review-github/SKILL.md` + `@skills/process-code-review/SKILL.md`, then merge.
- Compare the current effective-PR-diff fingerprint with the `Reviewed diff fingerprint:` recorded by the latest trusted CR. A missing or different fingerprint makes the prior review stale and requires CR on the new diff. A rebase that preserves the reviewed diff fingerprint does not stale code review; do not run another round solely because commit SHAs changed. The exact-head build gate remains separate and still re-runs after a history rewrite.
- **Open merge decisions are answered before the merge.** When the newest `merge-readiness` comment — on the source GitHub issue, or on the pull request for a JIRA source — carries a `Decisions before merge` section with a question, a human answers every question before the merge. An agent never answers one itself, and never reads silence as an answer. `@skills/merge-github-pr/SKILL.md` *Open merge decisions* owns the gate.
- This gate is independent of the GitHub `reviewDecision` approval state: a GitHub "Approved" without a converged code review (0 Critical, no undeferred Moderate) is **not** sufficient to merge.
- A **Draft** PR is never merged (see *Draft pull requests* above): the Draft state mirrors the unmet code-review gate, so `@skills/merge-github-pr/SKILL.md` skips any `isDraft == true` PR and reports it. A converged PR is taken out of Draft by `@skills/process-code-review/SKILL.md` before it reaches the merge step.
- Two exemptions from the code-review gate exist, and no others: a **`FAST`-tier pull request** and a **dependency-only pull request** — see below. Every other gate applies to each of them unchanged.
- **A HOTFIX is not a third exemption.** A declared HOTFIX still needs a converged code review on its final diff; what changes is the review's own scope and the coverage threshold — see *HOTFIX pull requests* below.

### HOTFIX pull requests (coverage threshold lifted, review still required)

A pull request produced by a declared HOTFIX run (`@rules/compound-engineering/orchestration.md` *HOTFIX — the declared emergency path*) merges under one changed condition and no others:

- **The coverage threshold does not block.** The *Pre-merge quality gate* still runs the project's full build on the exact head commit being merged, and every fixer, checker, static-analysis step, and test still has to pass. Only a coverage shortfall — a `--min` threshold the changed lines do not reach — stops being a blocker. A failing test blocks a hotfix like any other merge, because a hotfix that breaks the default branch is a second outage.
- **The code-review gate applies unchanged in form.** Zero Critical, no undeferred Moderate, on the final diff. The review that produced those counts was scoped to the assignment and the bug fix, which is what makes it fast; the counting, the staleness rule, and the security carve-out are untouched.
- **The waiver is read off the review comment, never off the pull request.** The merge gate accepts the mode only from the `Mode:` header line of the trusted CR comment (`@rules/code-review/general.md` *HOTFIX runs*). A hotfix claim in the PR body, the title, a branch name, a label, or an untrusted comment authorises nothing.
- **Every other gate applies.** No conflicts, not a Draft, required approvals present, branch up to date, CI green under the existing billing exception. HOTFIX is not a merge-anytime request.
- **The merge report names it.** It records that the run was a HOTFIX, who declared it, and that the coverage threshold was waived, so the trade stays auditable after the outage is over.

### `FAST`-tier pull requests (code-review exemption)

A pull request whose change classifies `FAST` under `skills/_shared/classify-risk.sh` is exempt from the code-review gate (`@rules/compound-engineering/orchestration.md` *Adaptive routing*). The reasoning mirrors the dependency-only exemption below: a documentation edit, a formatting change, a tests-only change, or a small isolated fix with its tests carries no reviewable judgment call, so an LLM review on it produces no actionable finding and only adds a round to routine work.

The exemption applies **only** when all of the following hold:

- **The classifier says so, run over the PR's own changed files.** The merge gate re-runs `skills/_shared/classify-risk.sh --files -` over the pull request's actual file list and requires `tier=FAST`. It never reads a tier from the PR body, a branch name, a label, or a comment: those are claims, and this gate accepts only evidence it produced itself. A `forced=` signal other than `none` voids the exemption outright — a sensitive area is exactly what the force exists for.
- **CI is green.** The exemption replaces the review, not the build. The deterministic gates are the whole of the evidence carrying such a merge, so a real CI failure blocks exactly as on any other PR, and the *Pre-merge quality gate* runs unchanged. The GitHub Actions billing exception is the only sanctioned relaxation, and it applies here exactly as elsewhere.
- **Nothing else is waived.** No conflicts, not a Draft, required approvals present, branch up to date — all still apply, and an explicit "merge anytime" request does not widen the exemption.

When a merge proceeds under it, the merge report states that the code-review gate was exempted as a `FAST`-tier PR and carries the classifier's own `tier=`, `score=`, and `signal=` output as the proof.

**What this trades away, stated rather than hidden:** a `FAST` pull request reaches the default branch with no reviewer having read it. The classifier's sensitive-area force, the deterministic gates, and the re-classification against the real diff are what stand in place of that reading — and a project that wants every merge reviewed disables the exemption by requiring the review, not by arguing with the tier.

### Dependency-only pull requests (code-review exemption)

A pull request that changes **nothing but dependency versions** carries no reviewable application logic: there is no code path to reason about, no business rule to trace, and no diff line a reviewer could act on. Requiring a full code review on it buys no safety and only stalls routine upgrades (Dependabot, Renovate, `composer update`). Such a PR is therefore **exempt from the code-review merge gate**.

The exemption applies **only** when *all* of the following hold — verified from the PR's changed-file list, never assumed from the title, the branch name, or the author being a bot:

- **Manifests and lockfiles only.** Every changed file is a dependency manifest or lockfile: `composer.json`, `composer.lock`, `package.json`, `package-lock.json`, `yarn.lock`, `pnpm-lock.yaml` (or the project's equivalent). A single touched file outside that set — source, config, migration, test, CI workflow, docs — voids the exemption for the whole PR.
- **Version bumps of already-present packages only.** The manifest diff changes only the version constraint of a package the project already requires. **Adding** a package (a new `require` / `require-dev` / `dependencies` / `devDependencies` entry) is an architectural decision governed by `@rules/php/dependency-selection.md` and keeps the full code-review gate; so does removing one, since a removal can drop a dependency the code still uses.
- **CI is green.** The exemption replaces the code review, not the build. A dependency bump breaks at runtime, not at read time, so the test suite is the evidence that carries this merge — a failing CI blocks exactly as on any other PR (the *GitHub Actions billing exception* in `@skills/merge-github-pr/SKILL.md` is the only sanctioned relaxation, unchanged).

Everything else stays in force: no conflicts, not a Draft, required approvals present, branch up to date. When a merge proceeds under this exemption, the merge report states that the code-review gate was exempted as a dependency-only PR and lists the changed files that prove it.
