# rector-rules

[![Checks](https://github.com/pekral/rector-rules/actions/workflows/pr.yml/badge.svg)](https://github.com/pekral/rector-rules/actions/workflows/pr.yml)
[![Latest Stable Version](https://poser.pugx.org/pekral/rector-rules/v/stable)](https://packagist.org/packages/pekral/rector-rules)
[![Total Downloads](https://poser.pugx.org/pekral/rector-rules/downloads)](https://packagist.org/packages/pekral/rector-rules)
[![License](https://poser.pugx.org/pekral/rector-rules/license)](https://packagist.org/packages/pekral/rector-rules)

A curated, ready-to-use [Rector](https://github.com/rectorphp/rector) rule set for PHP 8.4+ projects.

Rector ships over 500 rules. Picking the useful ones — and re-checking them on every Rector release — is a
recurring chore. This package does that curation for you: **one import, 236 hand-picked rules**, with every
rule Rector offers explicitly either enabled or documented as deliberately skipped.

---

## Installation

```bash
composer require --dev pekral/rector-rules
```

---

## Usage

Import the package's `rector.php` into your own configuration. Both Rector config styles work:

**Rector 2 builder style**

```php
<?php

declare(strict_types=1);

use Rector\Config\RectorConfig;

return RectorConfig::configure()
    ->withPaths([__DIR__ . '/src'])
    ->withSets([__DIR__ . '/vendor/pekral/rector-rules/rector.php']);
```

**Closure style**

```php
<?php

declare(strict_types=1);

use Rector\Config\RectorConfig;

return static function (RectorConfig $rectorConfig): void {
    $rectorConfig->import(__DIR__ . '/vendor/pekral/rector-rules/rector.php');
    $rectorConfig->paths([__DIR__ . '/src']);
};
```

Then run Rector:

```bash
# Preview the changes without touching a file
vendor/bin/rector process --dry-run

# Apply them
vendor/bin/rector process
```

### Skipping a rule you disagree with

The set is opinionated. Turn off anything that does not fit your codebase:

```php
return RectorConfig::configure()
    ->withPaths([__DIR__ . '/src'])
    ->withSets([__DIR__ . '/vendor/pekral/rector-rules/rector.php'])
    ->withSkip([
        // Disable a rule everywhere
        Rector\CodeQuality\Rector\FuncCall\CompactToVariablesRector::class,

        // …or only in specific paths
        Rector\Php80\Rector\Class_\ClassPropertyAssignToConstructorPromotionRector::class => [
            __DIR__ . '/src/Legacy',
        ],
    ]);
```

---

## What is in the set

236 rules, grouped by what they do:

| Area | Rules | What it covers |
| --- | ---: | --- |
| `TypeDeclaration` | 57 | Infer and add native parameter, property, and return types |
| `CodeQuality` | 50 | Simplify conditions, loops, and expressions |
| `DeadCode` | 44 | Remove unreachable code, unused variables, and redundant docblocks |
| `PHPUnit` | 22 | Modernise test syntax, attributes, and assertions |
| `TypeDeclarationDocblocks` | 14 | Narrow `array` docblocks that no native type can express |
| `Php53` – `Php86` | 35 | Upgrade syntax to newer PHP versions |
| Other | 14 | `Privatization`, `CodingStyle`, `EarlyReturn`, `Renaming`, `Unambiguous` |

The authoritative list is [`rules/rules.php`](rules/rules.php) — a plain array of rule class names.

### Curation model

| File | Role |
| --- | --- |
| [`rector.php`](rector.php) | Entry point — registers every rule from `rules/rules.php` |
| [`rules/rules.php`](rules/rules.php) | The 236 enabled rules (shipped) |
| `build/ignored-rules.php` | Rules deliberately **not** enabled, with the reason grouped inline (development only) |
| `build/find-missing-rules.php` | CI guard: fails if a rule is neither enabled nor listed as ignored (development only) |

Because of that guard, every rule Rector adds in a new release shows up as a build failure until someone
decides about it. Nothing is silently ignored.

`build/`, `.github/`, and the dotfiles are marked `export-ignore`, so `composer require` pulls down only
`rector.php`, `rules/`, `composer.json`, `README.md`, and `LICENSE`.

---

## Requirements

| | Version |
| --- | --- |
| PHP | `^8.4` |
| `rector/rector` | `^2.6.5` |

Contributing to this repository needs **PHP 8.5+**, because the development dependencies require it. Using
the package only needs 8.4.

---

## Development

```bash
composer install
```

| Command | What it does |
| --- | --- |
| `composer check` | Full check: code style, Rector dry-run, missing-rule guard |
| `composer fix` | Apply Rector and code-style fixes |
| `composer build` | `fix`, then `check`, then reinstall the AI agent rules |
| `composer phpcs` / `composer phpcs:fix` | Code style only |
| `composer rector` / `composer rector:fix` | Rector on this repository's own sources |
| `composer check:missing-rules` | Report rules that are neither enabled nor ignored |
| `composer ai-olympus:install` | Reinstall [pekral/ai-olympus](https://github.com/pekral/ai-olympus) agent rules and skills |

### Adding a rule

1. Add the class to `rules/rules.php`, or to `build/ignored-rules.php` if it should stay off.
2. Run `composer check`.

`composer check:missing-rules` fails when a rule is in neither file, so every rule Rector ships has to be
decided about.

See [CONTRIBUTING.md](.github/CONTRIBUTING.md) for how the guard works and the reasons rules are left out.

### CI

Pull requests run the same `composer check` steps plus a `composer audit`, and separately lint the shipped
sources on the declared minimum PHP 8.4. A weekly job refreshes dependencies and opens a PR; another audits
dependencies for known vulnerabilities.

---

## FAQ

**How do I preview what would change?**
`vendor/bin/rector process --dry-run`.

**How do I disable a single rule?**
Use `withSkip()` — see [Skipping a rule you disagree with](#skipping-a-rule-you-disagree-with).

**Can I combine this with Rector's own sets?**
Yes. Add `->withPhpSets()` or any other set alongside `withSets()`; Rector deduplicates rules registered twice.

**Why is rule X not included?**
Check `build/ignored-rules.php` in the repository — every excluded rule is listed there, grouped by reason
(deprecated upstream, too context-dependent, conflicts with another rule).

**What happens when I upgrade?**
A minor release adds or removes rules, so Rector will rewrite more of your code. Run `--dry-run` first and
read [UPGRADING.md](UPGRADING.md). A patch release never changes the set.

**How do I contribute?**
Open an [Enable a rule](https://github.com/pekral/rector-rules/issues/new?template=enable-rule.yml) or
[Disable a rule](https://github.com/pekral/rector-rules/issues/new?template=disable-rule.yml) issue, ask in
[Discussions](https://github.com/pekral/rector-rules/discussions), or send a pull request — see
[CONTRIBUTING.md](.github/CONTRIBUTING.md).

---

## Links

* [Packagist](https://packagist.org/packages/pekral/rector-rules)
* [Changelog](CHANGELOG.md) · [Upgrade guide](UPGRADING.md) · [Contributing](.github/CONTRIBUTING.md) · [Security policy](.github/SECURITY.md)
* [Discussions](https://github.com/pekral/rector-rules/discussions)
* [Rector documentation](https://getrector.com/)
* [Rector rule catalog](https://getrector.com/find-rule)

---

## License

MIT — see [LICENSE](LICENSE).

Maintained by [Petr Král](https://github.com/pekral).
