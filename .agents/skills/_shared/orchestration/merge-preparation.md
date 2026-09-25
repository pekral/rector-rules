# Prepare-only mode — `/prepare-issue-for-merge`

Extracted from `agents/splinter.md` so the orchestrator does not carry it on every run. **Loading trigger:** the user invokes `/prepare-issue-for-merge <URL>`, `$verify-merge-readiness`, or asks in words to prepare an issue's pull request for merge without merging it. On every other run this file is not read.

## Prepare-only mode — `/prepare-issue-for-merge`

When the user invokes `/prepare-issue-for-merge <URL>`, `$verify-merge-readiness`, or explicitly
asks you to prepare a GitHub issue's PR for merge without merging, follow
`@skills/verify-merge-readiness/SKILL.md` in full. This is a specialization of the end-to-end run,
not a second implementation of it.

- Resolve and gather the source as usual, then record `## Preparation mode: merge-ready, no merge`
  in the shared brief.
- **When the source issue resolves to no pull request, deliver it first.** The issue is not
  implemented yet, so run steps 4 to 6 of *The end-to-end run* on it — the optional security-risk
  analysis, `donatello` for the implementation, then the `donatello` ↔ `leonardo` review-and-fix
  loop to convergence — and prepare the Draft pull request that path opens. Take the working-tree
  write-lock in step 5 exactly as a full-delivery run does; prepare-only mode is not read-only once
  it delivers. Several matching pull requests remain a hard stop, a closed source issue is never
  implemented, and a delivery path that returns `Blocked` stops the preparation with that blocker.
- Dispatch `leonardo` for `@skills/process-code-review/SKILL.md`. Before a CR round, require the
  canonical effective-diff fingerprint decision. A trusted matching fingerprint means the diff is
  content-identical and the round is recorded as skipped; a missing or different fingerprint or
  new actionable feedback requires review. Never dispatch an identical-diff CR merely because a
  rebase changed the head SHA.
- Dispatch `donatello` only for missing remediation or the exact-head final quality gate. Require
  evidence for every acceptance criterion and all merge-readiness checks.
- Dispatch `april` in *Merge-preparation consolidation mode* only after the readiness state is
  known. April owns both the final TL;DR publication and the skill-bounded cleanup; you perform
  neither write yourself.
- Return `Preparation report done` with the PR, verified TL;DR URL, review decision, gate evidence,
  deleted IDs, and protected IDs. Return `Blocked` when any readiness or cleanup check fails.
- Stop before merge in every case. A later merge requires a separate explicit instruction and
  `@skills/merge-github-pr/SKILL.md`.
