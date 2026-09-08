---
description: Unified Git workflow, commits and pull request rules
---

## Branch Context
- If working outside `main`, always analyze commits in the current branch before making changes to understand context.

## Git Rules
- Never push directly to `main` branch. NEVER.
- Use small, focused commits (one logical change per commit).
- **The three bullets below are authoring guidance, not review criteria.** *One phase = one commit*, *One assignment point = one commit*, *Prefer independent, cherry-pickable commits*, and *No commit ships dead code* shape how an implementing agent lays out a branch. **The code review no longer checks any of them and raises no finding from commit history for them.** A review reads the diff that will be merged, and the granularity of the commits under it changes nothing about what that diff does; checking it cost rounds and produced findings whose fix was a rebase. Write the history this way because it reads better for the next human — nobody will fail your pull request over it.
  Three commit-history rules are **not** covered by that sentence and stay fully enforced, because none of them is about granularity: *A test and the change that makes it pass land in the same commit* (a committed failing or simulated-failing test is still a **Critical** finding — it encodes a lie in the history), *The merged head is green*, and *A history rewrite re-runs the gate* (both gate-execution discipline, enforced by `@skills/merge-github-pr/SKILL.md`).
- **One phase = one commit.** When the issue is complex and split into phases — explicit `Phase N` headings, numbered milestones, ordered acceptance-criteria blocks, or a step-by-step plan written by the reporter — resolve each phase as **exactly one commit** in the PR, in the original phase order. Never merge, reorder, or re-scope phases into a single commit. When no phases are marked but the work covers multiple distinct concerns, split it into independently reviewable phases the same way and map one phase per commit; keep a small atomic change as a single commit (do not invent artificial phases).
- **One assignment point = one commit.** This is the same rule applied to an assignment that enumerates *points* instead of phases: recommended fixes, review findings with their suggested fixes, a checklist (`- [ ]`), a bulleted list of defects, or individually testable acceptance criteria. Each point is **exactly one commit**, in the assignment's own order, so the PR's commit list reads as the list of resolved points and a reviewer can check the assignment off against it. Before mapping, deduplicate points that describe the same change and split a point that bundles two unrelated changes; a point the PR does not implement (deferred, out of scope) never becomes a commit.
Each commit carries everything that makes its point verifiable — the production change, its tests, and any doc or locale update the point requires — so nothing is left to a later fixup commit.
- **Prefer independent, cherry-pickable commits.** Group and order the commits so each one can be cherry-picked onto the default branch on its own and still pass the project's gate: prefer disjoint file sets over two commits editing the same lines, and put shared groundwork (a new helper, a signature change, a migration) in the commit of the point that introduces it, ordered before the points that use it. When two points genuinely cannot be separated, keep them as two commits, order the dependent one after its prerequisite, and state the dependency in the commit plan. Independence is a **preference**, never a reason to merge two points into one commit, to invent an artificial split, or to reorder points whose order is meaningful.
- **No commit ships dead code.** The rule above orders groundwork before the points that consume it. Read on its own, that ordering invites the mirror-image defect: a commit that adds a helper, a parameter, a config key, a branch, or a whole class that **nothing in that same commit's tree calls**. Such a commit compiles, so no gate below catches it. Code review does not catch it either — the review reads the final diff, where a later commit has already made the code live. Nothing between the two sees the commit that shipped it dead. The cost lands on the two readers who cannot recover the intent:
a reviewer cannot tell a deliberate seam from a forgotten wire-up, and whoever cherry-picks that commit alone ships code that runs nowhere. **Every symbol a commit adds is referenced inside the tree that commit produces** — by production code, by a test the same commit ships, or by configuration the same commit wires up. Four obligations follow.
  - **Move the groundwork, do not split it off.** A helper with exactly one consumer is one point with its consumer, so both land in one commit. Groundwork earns a commit of its own only when **two or more** later points consume it, and that commit still carries its own first real consumer.
  - **A test counts as a consumer, but only a real one.** A test that drives the new code through its actual call path makes that code live. A test that merely names the symbol so the commit looks complete does not — that is the same defect wearing a test's clothes.
  - **A removal leaves dead code too.** A commit that deletes the last caller of a method leaves that method dead. Delete the method in that same commit; never defer it to a later cleanup commit.
  - **Reachable-from-outside code is not dead.** A symbol the repository publishes for consumers it does not own is exempt: an exported package API, a new file the installer distributes, a framework-mandated member (an interface implementation, an override, a migration, a route action), or a member a container or an attribute wires up by reflection. Cite the specific consumer surface when claiming this exemption.

  Not a code-review finding. This bullet used to carry a **Moderate** severity for a symbol that is dead at the commit introducing it and live in the final tree; the review no longer walks commit history, so it raises nothing. The obligation on the author is unchanged.
- **The merged head is green; intermediate commits are not gated.** A history where the branch tip passes but the commits under it were never checked is not a deployable sequence in the strict sense — but proving every commit green means running the project's full gate once per commit, which on a larger task dominates the cost of delivering the change for a guarantee almost nothing consumes. The gate therefore runs **once, on the exact head commit being merged** (`@skills/resolve-issue/references/quality-gates.md` *Gate placement — deferred to the merge boundary*, executed by `@skills/merge-github-pr/SKILL.md` *Pre-merge quality gate*), and the fixes it produces land as their own commit on the branch. Three obligations survive that change unaltered.
  - **A test and the change that makes it pass land in the same commit.** Never commit a failing test, and never commit a test written to fail: no assertion of the buggy behaviour so a later commit can "fix" it, no `markTestIncomplete()` / `$this->fail()` placeholder standing in for the real assertion, no skipped or commented-out test left to be enabled later. This is not a gate-placement rule and is not relaxed by one — it is about not encoding a lie in the history. The RED step of `@skills/test-driven-development/SKILL.md` stays mandatory — it is a state of the **working tree**, never a commit. Write the failing test, watch it fail, write the fix, then commit both together.
  - **A history rewrite re-runs the gate.** A rebase, an `--autosquash`, a reorder, a squash, or a split changes the tree of the head commit, so a gate that passed before the rewrite proves nothing about the history that came out of it. Whenever the branch is rebased, the pre-merge gate runs again on the new head — a reshaped branch never inherits an earlier run's verdict. Replaying the whole range (`git rebase --exec '<the project gate>' <base>`) is available when a genuinely bisectable history is wanted, and is no longer required by default.
  - **The gate is the project's own.** Run what `composer build`, the Phing target, or the CI workflow runs — not a hand-picked subset. A merge that passed only the tests its author remembered is exactly the merge the next deploy breaks on.

  **What this trades away, stated plainly:** an arbitrary commit picked out of a merged branch is no longer known to be green, so `git bisect` over such a range can land on a commit that fails for reasons unrelated to the bug, and a cherry-pick of a single mid-branch commit may need its own gate run. Cherry-pick *independence* — disjoint file sets, groundwork ordered before its consumers — is unaffected and still required; only the per-commit green guarantee is gone. When a specific branch genuinely needs a bisectable history, run the range replay above and say so in the PR.

  Severity in code review: a committed failing or simulated-failing test is **Critical**. A merge performed without a passing gate run on the merged head commit is **Critical**. Intermediate commits that do not individually pass the gate are **not** a finding.
- **Every change on the branch belongs to a logical commit — amend the commit it belongs to, open a new one when it does not.** The two rules above map the *planned* work; this one covers everything that arrives after the plan — a review-loop fix, a correction to a commit already made, a follow-through the first pass missed, a CHANGELOG or doc update. No such change is left dangling in the working tree, and none is swept into an unrelated commit just because that commit happens to be next.
  - **It completes or corrects a commit already on this branch → fold it into that commit**, provided that commit is **not yet pushed, or pushed but not yet under review**: `git commit --amend` for the branch tip, `git commit --fixup=<sha>` followed by `git rebase --autosquash <base>` for an earlier one. A separate *"follow-up to the commit above"* commit is the wrong shape — it makes a reviewer read two diffs to see one logical change, and it breaks the cherry-pick independence the rule above asks for.
  - **It is a genuinely separate logical unit → new commit.** Never amend an unrelated change into an existing commit to keep the count down; the count is not the goal, one-logical-change-per-commit is.
  - **The branch is already pushed and under review → do not rewrite it.** A force-push moves every later SHA, which detaches review-thread anchors, invalidates any SHA already cited in a posted report or PR description, and can silently drop a reviewer's in-flight comment. There, a new commit naming what it corrects is the correct shape, and rewriting is a deliberate, stated decision — never an incidental side effect of tidying. When you do rewrite, publish with `git push --force-with-lease` (never plain `--force`) and re-derive every SHA you have already cited.
  - **Reconcile before opening the PR.** Walk `git log <base>..HEAD` against the recorded plan and confirm each commit is one logical change and each logical change is one commit. A commit that turned out to bundle two changes is split; two commits that turned out to be one change are folded — while the branch is still yours to rewrite.
- Use meaningful branch names, always written in English regardless of the assignment language.

## Worktrees / Workspaces
- **Do not create git worktrees or separate workspaces automatically.** By default an agent works in the current branch and working tree (a feature / fix branch off the default branch is enough); never run `git worktree add`, clone into a side directory, or spin up an isolated workspace on your own initiative.
- Create an isolated worktree **only on explicit request** — when the caller / user asks for it, or when a workflow the user explicitly opted into (e.g. parallel multi-unit orchestration) genuinely requires per-unit isolation to avoid corrupting a shared tree. Absent that explicit request, stay in the current tree.
- When an isolated worktree *was* requested, remove it after the PR for the work unit has been merged (deployed) — the post-merge step of `@skills/merge-github-pr/SKILL.md` owns this. Before removing, verify the worktree is not the currently active working tree and has no uncommitted changes; never pass `--force`. Run `git worktree remove <path>` followed by `git worktree prune` to clean up metadata. This keeps git clean and leaves no orphaned trees behind.

## Pull Policy
- Resolve the default branch by name first — it is `main` on some repos and `master` on others. Never hardcode `origin/main`; on a `master`-default repo that reference does not exist and the command fails. Derive it once: `DEFAULT_BRANCH="$(git symbolic-ref --short refs/remotes/origin/HEAD | sed 's@^origin/@@')"`.
- The default branch is pulled directly: `git checkout "$DEFAULT_BRANCH" && git pull`. No rebase step applies to it.
- Before pulling any **other** branch you are working on (a feature / fix / PR branch), sync it so it always carries the latest default branch, in this exact order:
    1. `git fetch origin`
    2. Take the branch's own remote **first**, so the rebase in step 3 is not undone later: `git pull --rebase` (keeps history linear; a no-op when you are the sole contributor and nothing new was pushed).
    3. Rebase the default branch into the side branch: `git rebase "origin/$DEFAULT_BRANCH"` (replays the branch's commits on top of the newest default branch).
    4. Resolve any conflicts (`@skills/git-workflow/SKILL.md`), then `git rebase --continue`.
- Do **not** run `git pull` again after step 3 — pulling after the rebase replays your commits back onto the branch's old remote tip and discards the sync. The branch's own remote was already taken in step 2; the only remaining publish step is the force-push below.
- If the rebase changed `composer.lock` (the default branch updated dependencies), run `composer install` immediately afterwards so the installed packages match the new lockfile. Resolve a `composer.lock` conflict before installing.
- Publishing the rebased branch to its remote uses `git push --force-with-lease` (never plain `--force`, and only when you are the sole contributor — see `@skills/git-workflow/SKILL.md`).
- **Read-only review skills are exempt.** A read-only skill switches to the branch and runs `git pull` only to read the diff; it must never rebase, `composer install`, or otherwise rewrite the branch or working tree.

## Commit Messages
- Language: always English, regardless of the assignment language. Unlike the PR description (which follows the assignment language), commit messages and PR titles are never translated.
- Format: `type(scope): short description`
- Keep messages concise and specific.
- Use lowercase for `type` and `scope`.
- Do not end with a period.
- Never include signatures or attribution. This covers AI co-author trailers: no `Co-Authored-By:` lines and no "Generated with"/"Made with" notes (e.g. "Made with Cursor", "Generated with Claude Code").

### Allowed Types
- feat: New feature
- fix: Bug fix
- docs: Documentation changes
- style: Formatting or style-only changes
- refactor: Code changes without behavior change
- test: Adding or updating tests
- chore: Maintenance tasks

## Issue Linking

This section is the GitHub mechanic for `@rules/compound-engineering/general.md` *Every pull request links back to its tracker issue*. That section owns the invariant across every tracker; this one owns how GitHub carries it.

- **Write the literal `Closes #<N>` into the pull request body.** GitHub derives `closingIssuesReferences` — the auto-close on merge and the backlink rendered on the issue — from the body of the pull request. A reference that lives only in a commit message leaves the pull request unlinked until the merge lands that commit on the default branch. Every skill in this package that reads `closingIssues[]` reads it off the pull request long before that merge, so the body is where the keyword belongs.
- **The keyword is English, always.** GitHub parses only `close` / `closes` / `closed`, `fix` / `fixes` / `fixed`, and `resolve` / `resolves` / `resolved`. A translated keyword is not parsed, and `closingIssuesReferences` stays empty while the surrounding sentence still reads like a link. `Closes #<N>` is therefore exempt from the assignment-language rule for the PR body, exactly like a code identifier.
- **Keep the reference in the commit too.** A commit that resolves the issue carries `Closes #<N>` in its body, which is what closes the issue on a rebase merge. The commit reference is additive. It never substitutes for the reference in the pull request body.
- **Verify the link landed.** After opening the pull request, re-read it through `skills/code-review-github/scripts/load-issue.sh <PR-URL>` and confirm `closingIssues[]` names the issue. An external write can be silently blocked in auto-mode, so `gh pr create` exiting zero is not evidence.

## Pull Requests
- PR title must be in English.
- PR description must be written in the same language as the assignment. The literal `Closes #<N>` keyword is the one exception, because GitHub parses no other spelling — see *Issue Linking* above.
- Format PR messages as Markdown.

### PR Content Requirements
- Include links to all sources used during analysis.
- Prefer adding these as a comment on the related GitHub issue.

### Draft pull requests — open as Draft until the PR is ready to merge
A pull request is a **Draft** for as long as it is **not yet ready to merge and agents will keep working on it** — the canonical case in this workflow is an agent-opened PR that still has to pass the post-PR authoritative review/fix loop (`@skills/code-review-github/SKILL.md` + `@skills/process-code-review/SKILL.md`, i.e. the `athena` ↔ `hephaestus` convergence loop) before it can be merged. The Draft state is the visible signal that the PR is work-in-progress and the hard code-review merge gate is still unmet.

- **Open as Draft.** When an agent creates a PR that still needs that review/fix loop, create it as a Draft: `gh pr create --draft …`. This covers every agent-driven PR-creation path (`@skills/resolve-issue/SKILL.md`, and the Finalization step of `@skills/process-code-review/SKILL.md` when it has to create the PR itself).
- **Mark ready on convergence.** The PR is promoted out of Draft (`gh pr ready <PR>`) **only** once the code review has converged on its final diff — **0 Critical, and no undeferred Moderate** (the canonical gate is `@skills/process-code-review/SKILL.md` *Review loop* step 4). This transition is owned by that skill (it runs the convergence loop), and is performed only after the loop exits converged — never on a PR that still carries a Critical, a security-relevant Moderate, or a Moderate that failed the filing bar. That same step writes the matching *ready to merge* signal on the source tracker item, and withdraws both when a later commit re-opens the review (`@rules/compound-engineering/general.md` *Tracker status tracks the phase of work*, phase 3).
- **A Draft PR is never merged.** `@skills/merge-github-pr/SKILL.md` treats `isDraft == true` as not-ready and skips it: a Draft mirrors the unmet code-review gate. If a Draft PR's review has in fact converged, mark it ready first (the `process-code-review` step above), then merge — never merge a Draft directly, and the GitHub Actions billing exception never relaxes this.

### Testing
- Suggest how to test the changes (UI, API, etc.).
- Verify that tests exist:
    - If yes → update or extend them if needed.
    - If no → explicitly state: `no`.

## PR Lifecycle
- When merging a PR:
    - Merge into `main`
    - Close the PR
    - Delete the branch
    - Remove the worktree if one was created for this work unit (see *Worktrees / Workspaces* above for the opt-in / safety rules; `@skills/merge-github-pr/SKILL.md` §5 owns the step)
    - Switch locally to `main`
    - Pull latest changes

- If already deployed:
    - Only switch to `main` and pull latest changes

## Cleanup
- Remove any temporary `.md` files created during PR preparation.

## Tooling
- Use GitHub CLI (`gh`) as the primary tool for all operations.
- If `gh` is unavailable, use a GitHub MCP server.
- If no GitHub tool is available, stop and report that GitHub access is not available.

## Merging
- Use rebase and merge strategy
- **Code review is a hard merge gate — never optional, never skipped.** A PR may be merged only after a code review has been run on its **final diff** (the exact commits being merged) and the review reports **no errors**: **zero Critical findings, and no undeferred Moderate finding**. This gate applies to **every** merge path — manual and orchestrated (`daedalus`) — and is owned by `@skills/merge-github-pr/SKILL.md`. Read the second half precisely, because it is where the gate changed:
    - **A Critical always blocks**, at every round, with no deferral and no exception.
    - **A Moderate blocks until it is resolved, and it is resolved in one of two ways** — fixed in the review loop, or, at round 3 only, deferred into a tracker sub-issue (`@skills/process-code-review/SKILL.md` *Review loop* step 6 and `references/round-three-deferral.md`). A Moderate that is neither fixed nor deferred still blocks.
    - **A security-relevant Moderate is never deferrable.** A finding meeting the **S1–S3** carve-out of `@rules/code-review/general.md` *Assignment-Declared Test-Only Conditions — Exclusion Gate (issue #17)* — produced by a security lens, citing a rule in `@rules/security/**`, or landing on a security surface — blocks the merge until it is fixed. No filing bar, no sub-issue, and no round count changes that.
    - **Minor findings do not block**, and the review no longer detects one outside a security lens (`@rules/code-review/general.md` *Minor findings are not detected*).
- If no code review exists for the PR, or the latest review still carries an unresolved Critical or an undeferred Moderate, **do not merge** — run (or re-run) the review to convergence first via `@skills/code-review-github/SKILL.md` + `@skills/process-code-review/SKILL.md`, then merge.
- Compare the current effective-PR-diff fingerprint with the `Reviewed diff fingerprint:` recorded by the latest trusted CR. A missing or different fingerprint makes the prior review stale and requires CR on the new diff. A rebase that preserves the reviewed diff fingerprint does not stale code review; do not run another round solely because commit SHAs changed. The exact-head build gate remains separate and still re-runs after a history rewrite.
- This gate is independent of the GitHub `reviewDecision` approval state: a GitHub "Approved" without a converged code review (0 Critical, no undeferred Moderate) is **not** sufficient to merge.
- A **Draft** PR is never merged (see *Draft pull requests* above): the Draft state mirrors the unmet code-review gate, so `@skills/merge-github-pr/SKILL.md` skips any `isDraft == true` PR and reports it. A converged PR is taken out of Draft by `@skills/process-code-review/SKILL.md` before it reaches the merge step.
- The single exemption from the code-review gate is a **dependency-only pull request** — see below. Every other gate applies to it unchanged.

### Dependency-only pull requests (code-review exemption)

A pull request that changes **nothing but dependency versions** carries no reviewable application logic: there is no code path to reason about, no business rule to trace, and no diff line a reviewer could act on. Requiring a full code review on it buys no safety and only stalls routine upgrades (Dependabot, Renovate, `composer update`). Such a PR is therefore **exempt from the code-review merge gate**.

The exemption applies **only** when *all* of the following hold — verified from the PR's changed-file list, never assumed from the title, the branch name, or the author being a bot:

- **Manifests and lockfiles only.** Every changed file is a dependency manifest or lockfile: `composer.json`, `composer.lock`, `package.json`, `package-lock.json`, `yarn.lock`, `pnpm-lock.yaml` (or the project's equivalent). A single touched file outside that set — source, config, migration, test, CI workflow, docs — voids the exemption for the whole PR.
- **Version bumps of already-present packages only.** The manifest diff changes only the version constraint of a package the project already requires. **Adding** a package (a new `require` / `require-dev` / `dependencies` / `devDependencies` entry) is an architectural decision governed by `@rules/php/dependency-selection.md` and keeps the full code-review gate; so does removing one, since a removal can drop a dependency the code still uses.
- **CI is green.** The exemption replaces the code review, not the build. A dependency bump breaks at runtime, not at read time, so the test suite is the evidence that carries this merge — a failing CI blocks exactly as on any other PR (the *GitHub Actions billing exception* in `@skills/merge-github-pr/SKILL.md` is the only sanctioned relaxation, unchanged).

Everything else stays in force: no conflicts, not a Draft, required approvals present, branch up to date. When a merge proceeds under this exemption, the merge report states that the code-review gate was exempted as a dependency-only PR and lists the changed files that prove it.
