# Pre-existing issue handling

Referenced from `skills/resolve-issue/SKILL.md` *Pre-existing issue handling*, and from every other skill that reads code outside its own change. The principle has one owner: `@rules/compound-engineering/general.md` *The assignment is the scope*. This file states only the procedure for the one exception, a security vulnerability.

While reading and modifying the files required for the in-scope work, you may encounter a problem that is **unrelated to the current assignment** but was already present in those files.

- **A security vulnerability is fixed in this PR.** `@rules/compound-engineering/general.md` *The assignment is the scope* defines what counts as one and how small the fix is.
- **Every other problem follows the owner.**

Rules for a security vulnerability:

1. **Do not silently ignore** a vulnerability you encountered in a file you had to read for the in-scope work — fix it in this PR.
2. **Do not expand scope** by scanning unrelated files for more. Limit attention to files already touched by the in-scope changes (or their direct dependencies you must read to understand the change).
3. Land the fix in its **own separate commit** inside the same PR:
   - Use a Conventional Commits subject per `@rules/git/general.md`: `fix(<scope>): pre-existing — <description>`.
   - The `pre-existing — ` prefix is mandatory so reviewers can identify the commit at a glance (e.g. `fix(user): pre-existing — authorize the record owner before download`).
   - Add the regression test in the **same commit** as the fix. The test must fail before the fix lands and pass after.
   - The fix follows the same 100% coverage rule on changed lines as the in-scope changes.
4. Commit the fix **before** the in-scope work, so it forms an independently revertable base. A skill that has no in-scope commit of its own (`create-test`, `create-missing-tests-in-pr`, `process-code-review`) commits it as its own commit, distinct from its test or review-fix commits.
5. If the vulnerability is **too large to fix inline** (it needs an architectural decision or reaches shared infrastructure beyond the touched files), do not fix it inline. It is a critical security issue under the filing bar: file it, subject to `agents/leonardo.md` *Never disclose an unfixed vulnerability on a public tracker*, and list it under the PR `## TODO` with the issue URL.
6. **A refactoring-only assignment fixes no vulnerability.** Keep the behaviour unchanged and file it per `@rules/refactoring/general.md` *Behaviour stays identical — bugs included*.
