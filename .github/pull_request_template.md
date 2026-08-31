## What does this change?

<!-- One or two sentences. Link the issue it resolves: Closes #123 -->

## Rule changes

<!-- Delete this section if the pull request touches no rule. -->

| Rule class | Added to | Reason |
| --- | --- | --- |
|  | `rules/rules.php` / `build/ignored-rules.php` |  |

## Checklist

- [ ] `composer check` passes.
- [ ] A rule left out of `rules/rules.php` is in `build/ignored-rules.php`, under the group that states why.
- [ ] The rule count in `README.md` matches `rules/rules.php`, if it changed.
- [ ] The commit subject follows Conventional Commits and is written in English.
- [ ] The description says what Rector will now rewrite differently in consuming projects, if anything.
