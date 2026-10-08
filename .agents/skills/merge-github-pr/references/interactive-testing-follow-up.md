# Interactive-testing follow-up issue — only for a front-end UI change

Some projects ask for a follow-up issue labelled `interactive-testing` after a merge, so an agent clicks the change through in a real browser. Create that issue only when the merged diff changes the front-end UI. Otherwise create none, and the merge report says `interactive-testing: skipped, no front-end UI change`.

- **A front-end UI change** is a changed file on the frontend surface that `@skills/code-review/references/specialized-reviews.md` *Frontend surface detected in the diff* defines, or one of these files the step adds to it:
  - a script under `resources/js/**`, or a `*.vue`, `*.jsx`, or `*.tsx` component under `resources/**`,
  - a public asset under `public/` that a page loads,
  - a user-visible string in `lang/**`.
- **Not a front-end UI change:** tests (`tests/**`, a browser test included), documentation, build and CI configuration, dependency manifests and lockfiles, agent configuration, and back-end code that renders nothing.
- **A file on both lists is not a front-end UI change,** except the Tailwind configuration, which the frontend surface already names.
- **Read the file list from `files[]`** of the `skills/code-review-github/scripts/load-issue.sh` document of the merged pull request (step 1), never from the working tree.
- **File the issue through `@skills/create-issue/SKILL.md`** with the title and body the project's rule defines, and record an `external-write` line in the run's audit ledger (`@rules/compound-engineering/orchestration.md`).
- **Apply the `interactive-testing` label** in addition to the content label `create-issue` selects (`@rules/compound-engineering/tracker.md` *Stay additive*). When the repository has no such label, file the issue without it and say `interactive-testing label missing` in the merge report. The project's rule decides whether the label is created.
