# Code quality self-check (single pass)

Referenced from `skills/resolve-issue/SKILL.md` *Code quality self-check (single pass)*. Extracted to keep the skill body under the skill-check token limit; the rules are unchanged, including the 0 Critical / 0 Moderate PR gate the skill states inline.

After implementation, and **before creating the pull request**, run one self-check pass on the local changes:

1. **Run the review inline.** Invoke `@skills/code-review/SKILL.md` directly in this skill's context, passing the current branch / diff context plus the instruction "run `@skills/code-review/SKILL.md` on the local changes and return the Critical / Moderate / Minor findings with their reproducer fields (Faulty Example, Expected Behavior, Test Hint, Suggested Fix)". Do not dispatch the review as a subagent — run it sequentially in the current context.
2. If **Critical** or **Moderate** findings exist:
   - Apply the **Suggested Fix** snippet from each finding directly to the working tree
   - Add or update a reproducer test for each finding using its **Faulty Example**, **Expected Behavior**, and **Test Hint**
3. **Do not re-run the full review to convergence.** The full-diff review runs exactly once; after applying the fixes, re-verify each fixed finding in a targeted way — re-read the finding's code path — instead of re-invoking the full review over the whole diff. Full-diff convergence is owned exclusively by the authoritative post-PR review loop (`code-review-github` / `process-code-review` — the `athena` ↔ `hephaestus` loop), which reviews the complete diff again after the PR exists; duplicating that convergence here doubles the review cost without raising the quality bar of the merged result.
4. **PR gate — 0 Critical / 0 Moderate.** The pull request may be created only when every Critical / Moderate finding surfaced by this pass is resolved (0 Critical + 0 Moderate remaining). When a surfaced finding cannot be resolved, stop as **Blocked** and surface it to the user instead of opening a PR that knowingly carries it.
   **This is deliberately stricter than the merge gate, and it is not a leftover of the old one.** The merge gate accepts a Moderate deferred into a tracker sub-issue (`@rules/git/general.md` *Merging*), because that deferral is a round-3 outcome of the review loop. This pass is a single pass before any PR exists, so it has no round 3, no loop, and nothing to defer into — a finding it surfaces is either fixed here or the run stops.

PR-comment processing via `@skills/process-code-review/SKILL.md` remains the path used **after** a PR exists; it is not part of this pre-PR self-check because it requires an open PR to operate on.
