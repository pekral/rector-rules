# How the set is curated

This package ships no rules of its own. It is a list of rule class names that Rector already provides, plus a
guard that makes every rule Rector ships an explicit decision.

## Files

| File | Role |
| --- | --- |
| [`rector.php`](../rector.php) | Entry point — registers every rule from `rules/rules.php` and raises the Rector parallel process timeout to 180 s |
| [`rules/rules.php`](../rules/rules.php) | The 216 enabled rules (shipped) |
| `build/ignored-rules.php` | The 221 rules that do not ship (development only). 2 JMS Serializer rules sit under a PHP 8.5 heading; the other 219 are grouped under a plain `// Ignored rules` heading. Rules deprecated in Rector are listed nowhere — they are deleted |
| `build/find-missing-rules.php` | CI guard: fails if a rule is neither enabled nor listed as ignored, or if a deprecated rule is listed in either file (development only) |

Because of that guard, every rule Rector adds in a new release shows up as a build failure until someone
decides about it. Nothing is silently ignored. [CONTRIBUTING.md](../.github/CONTRIBUTING.md) describes how the
guard works in detail.

## Why is rule X not included?

Check `build/ignored-rules.php` in the repository — every rule that does not ship is listed there, except
rules deprecated in Rector. Those are never shipped and never listed. Rules waiting on PHP 8.5 sit under a
heading that says so; the rest are grouped under a plain `// Ignored rules` heading, which records the
decision without a reason.

To change a decision, open an
[Enable a rule](https://github.com/pekral/rector-rules/issues/new?template=enable-rule.yml) or
[Disable a rule](https://github.com/pekral/rector-rules/issues/new?template=disable-rule.yml) issue.

## What the package installs

`build/`, `.github/`, `assets/`, the dotfiles, `CHANGELOG.md`, and `UPGRADING.md` are marked `export-ignore`
in `.gitattributes`. The rule set itself is `rector.php` and `rules/rules.php`; `composer require` also pulls
down `composer.json`, `README.md`, `LICENSE`, this `docs/` directory, and the AI agent files (`AGENTS.md`,
`.agents/`, `.codex/`), which are not marked `export-ignore`.
