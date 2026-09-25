---
name: interactive-testing
description: "Use when verifying user-visible project changes against an assignment and the actual code diff. Requires the testing agent's own interactive browser and returns evidence-backed results, including failures and blocked scenarios."
license: MIT
metadata:
  author: "Petr Král (pekral.cz)"
---

## Constraints

- Apply `@rules/security/general.md` for the untrusted-content boundary.
- The testing agent MUST use its own interactive browser session. In Codex, use the provided `cua_repl` browser tools and their documented browser APIs. A delegated agent must operate the browser itself; another agent's screenshots or test summary do not fulfil this requirement.
- Shell-driven Playwright, headless scripts, HTTP requests, unit tests, source inspection, and generated screenshots never replace this walkthrough. They may supply supplementary evidence only. If an interactive browser tool is unavailable, return `Blocked`.
- Use the project URL supplied by the user or recorded in the consuming project's instructions or memory. If neither identifies the target, ask for it. Do not silently switch hosts, environments, or checkouts.
- Reuse a valid session or complete the normal sign-in flow with already authorized credentials when available. If sign-in cannot be completed, leave the browser open, tell the user where login is needed, and wait for them to log in. Do not ask them to send passwords or one-time codes in chat, bypass authentication, create a session through the database, or treat elapsed time as successful login.
- Test the running application without changing its implementation, configuration, permissions, credentials, or database directly. Report defects with reproduction steps. Fixing, publishing to a tracker, deploying, or merging requires a separate assignment.
- Respect the browser tool's confirmation rules. Use reversible, clearly identified test data within the authorized workspace. Do not trigger AI processing, recurring jobs, external imports, emails, tracker comments, or destructive actions unless that specific effect is authorized for the scenario. Opening a menu is not evidence that its actions work.

## Use when

- A developer asks for a browser acceptance check after a feature, fix, revert, or UI change.
- A new QA agent receives an assignment plus a branch, commit range, PR, or uncommitted diff.
- Automated checks passed but the change still needs verification through real user interactions.

## Inputs

- Assignment and latest user corrections, including behavior that must remain unchanged.
- Repository and the exact diff to test: base/head revisions plus any intended working-tree changes.
- Project URL, account/role, workspace, available test data, and authorized side effects.

Infer routine choices from the current task. Ask only for missing information that blocks a concrete scenario, while continuing independent scenarios.

## Execution

### 1. Derive scenarios from the assignment and diff

1. Read repository instructions and relevant project memory. Inspect `git status`, current revision, and the requested diff without switching branches or modifying files.
2. For a merged change, compare its recorded base and head; an empty working-tree diff does not mean there is nothing to test. Include all commits in the requested change, not just the last styling commit.
3. Turn each requirement and meaningful changed behavior into a row: preconditions, user actions, expected visible result, persistence check, and relevant viewport/role.
4. Include the main successful flow, validation/empty states, navigation, save/reload behavior, and immediate regressions implied by the diff. Distinguish layout changes from processing or integration behavior outside the assignment.
5. Record the revision and browser target. If the served checkout/version cannot be established, state that limitation instead of assuming it matches the diff.

### 2. Open the interactive browser and establish prerequisites

1. Read the browser tool documentation and open the project using its supported interactive browser API. Keep the tab available for user handoff when authentication is needed.
2. Observe the rendered page before interacting. Verify the signed-in identity, selected workspace, record state, and relevant permissions from visible UI.
3. Check data readiness. For example, a task named “draft” may actually have status Error; task creation may require an indexed repository. Do not infer readiness from a record's name or admin access.
4. If the requested workspace is missing, ask for the correct workspace/account. With authorization to use an existing workspace, select one that meets the scenario's prerequisites. Never invent membership or change status/indexing flags to force a pass.
5. Record a time boundary for browser console evidence so old errors are not attributed to the current scenario.

### 3. Exercise the actual user flow

1. Navigate through visible links and menus. Use accessible roles/names or observed test IDs; never guess selectors, use hidden application state, or call backend actions to simulate clicks.
2. After each meaningful action, inspect fresh browser state before choosing the next action. Wait for the specific result, enabled control, selected tab, or loaded form. A deferred panel's heading alone does not prove its form finished loading.
3. For saves, verify the visible success state, then reload or navigate away and back to prove persistence. A changed textbox value alone is insufficient.
4. Exercise keyboard interactions where relevant: focus, tab navigation, arrow keys, Enter, Escape, and modal dismissal. Verify the resulting focus or selection.
5. Test layouts on desktop and at a representative narrow viewport when the diff changes layout. Use the interactive browser's viewport capability. Report width/height and do not claim real-device or touch emulation when only viewport size changed.
6. Capture and actually inspect rendered screenshots for relevant states, especially failures. Check readability, wrapping, clipping, scrolling, control reachability, and correspondence between icons and actions. Restore temporary viewport overrides afterward.
7. Read recent console errors through the browser tool. Reproduce suspicious behavior once with a stable, fully loaded page. Separate reproducible failures, transient observations, environment blockers, and unproven attribution to the diff.
8. For side-effecting flows without authorization or prerequisites, stop before the effect and mark that portion `Blocked`; do not mark the entire action passed because its button rendered.

### 4. Restore test data and report evidence

1. Restore only values changed by this run and verify the restoration in the UI. Do not overwrite unrelated concurrent edits or delete existing user data. Report any remaining test records or side effects.
2. Produce a verdict for every scenario: `Passed`, `Failed`, `Partial`, or `Blocked`. An unexecuted scenario is never `Passed`.
3. For each failure, include exact URL, viewport, account role/record state, minimal steps, expected versus observed behavior, and a screenshot or concrete visible evidence. Redact secrets and avoid embedding unrelated user data.
4. Report which scenarios were not exercised and the exact prerequisite needed to unblock each one.
5. Overall `Passed` requires every required scenario to pass. Failures or blockers must remain explicit even when all automated tests are green.
6. Keep the relevant browser tab open when handing a failure or login step to the user. Otherwise follow the browser tool's cleanup rules.

## Output

Return a concise report in the user's language:

- **Scope:** assignment, tested base/head and working-tree changes, project URL, account role/workspace, browser tool, viewport sizes.
- **Result:** one row per scenario with expected behavior, actual interactions and observation, evidence, and verdict.
- **Findings:** reproducible failures, transient observations, and environment blockers kept distinct; never claim a regression without evidence linking it to the change.
- **Untested:** exact scenarios and missing prerequisites.
- **Cleanup:** restored values and any remaining test artifacts.
- **Next step:** implementation fixes, access/data preparation, or acceptance when all required rows passed.

Report in the current task by default. Do not post messages to external trackers or create a new agent/task unless asked.

## Done when

- The agent itself operated the interactive browser and observed the results.
- Every acceptance criterion has an honest verdict backed by executed interactions or a named blocker.
- Save/reload checks, relevant visual states, and recent browser errors were considered.
- Changed test data and temporary browser settings are restored, or remaining effects are explicitly listed.
- The report makes no claim of full acceptance while a required scenario is failed, partial, or blocked.

## Output Humanization
- Use [blader/humanizer](https://github.com/blader/humanizer) for all skill outputs to keep the text natural and human-friendly.
