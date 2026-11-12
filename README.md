# rector-rules

[![Latest Version on Packagist](https://img.shields.io/packagist/v/pekral/rector-rules.svg?style=flat-square)](https://packagist.org/packages/pekral/rector-rules)
[![MIT Licensed](https://img.shields.io/badge/license-MIT-brightgreen.svg?style=flat-square)](LICENSE)
![Checks](https://github.com/pekral/rector-rules/workflows/Checks/badge.svg)
[![Total Downloads](https://img.shields.io/packagist/dt/pekral/rector-rules.svg?style=flat-square)](https://packagist.org/packages/pekral/rector-rules)

A curated [Rector](https://github.com/rectorphp/rector) rule set for PHP 8.4+ projects: one import registers
216 hand-picked rules. Every other rule Rector ships is recorded in this repository as deliberately left out,
and a CI guard fails until someone decides about each rule a new Rector release adds.

## Requirements

| | Version |
| --- | --- |
| PHP | `^8.4` |
| `rector/rector` | `^2.8.4` |

`rector/rector` is the only runtime dependency. Developing this repository needs PHP 8.5+ — see
[Testing](#testing).

## Installation

```bash
composer require --dev pekral/rector-rules
```

## Configuration

Import the package's `rector.php` in your project's `rector.php` and set the paths Rector should process:

```php
<?php

declare(strict_types=1);

use Rector\Config\RectorConfig;

return RectorConfig::configure()
    ->withPaths([__DIR__ . '/src'])
    ->withSets([__DIR__ . '/vendor/pekral/rector-rules/rector.php']);
```

The closure style (`$rectorConfig->import(...)`) works too. The set raises Rector's parallel process timeout
to 180 s and leaves the worker count at Rector's default. Skipping rules, combining this set with other sets,
and overriding the timeout are covered in [docs/configuration.md](docs/configuration.md).

## Quick start

Preview what would change, without touching a file:

```bash
vendor/bin/rector process --dry-run
```

Apply the changes:

```bash
vendor/bin/rector process
```

> [!WARNING]
> `vendor/bin/rector process` rewrites the files under the configured paths in place. Run the dry run first
> and commit your work before applying.

## What it does

216 rules, grouped by what they do:

| Area | Rules | What it covers |
| --- | ---: | --- |
| `TypeDeclaration` | 50 | Infer and add native parameter, property, and return types |
| `CodeQuality` | 44 | Simplify conditions, loops, and expressions |
| `DeadCode` | 42 | Remove unreachable code, unused variables, and redundant docblocks |
| `PHPUnit` | 19 | Modernise test syntax, attributes, and assertions |
| `TypeDeclarationDocblocks` | 14 | Narrow `array` docblocks that no native type can express |
| `Php53` – `Php86` | 36 | Upgrade syntax to newer PHP versions |
| Other | 11 | `Privatization`, `CodingStyle`, `EarlyReturn`, `Visibility` |

The set is opinionated: turn off any rule that does not fit your codebase with `withSkip()`. The
authoritative list is [`rules/rules.php`](rules/rules.php), a plain array of rule class names.

## Documentation

- [Configuration](docs/configuration.md) — closure style, skipping rules, combining with Rector's own and
  third-party sets, the parallel timeout
- [How the set is curated](docs/rule-set.md) — the ignore list, the missing-rule guard, why a rule is not
  included, and which files the package ships
- [Rector documentation](https://getrector.com/) and the [Rector rule catalog](https://getrector.com/find-rule)
- [Discussions](https://github.com/pekral/rector-rules/discussions)

## Testing

Developing this repository needs PHP 8.5+, because the development dependencies require it.

```bash
composer install
composer check
```

`composer check` runs the code style check, a Rector dry run on this repository's own sources, and the
missing-rule guard. The other development commands are listed in [CONTRIBUTING.md](.github/CONTRIBUTING.md).

## Upgrading

Most releases so far have changed the set, patch releases included, so an upgrade can make Rector rewrite
more of your code than before. Run `vendor/bin/rector process --dry-run` after upgrading and read
[UPGRADING.md](UPGRADING.md).

## Changelog

See [CHANGELOG.md](CHANGELOG.md).

## Contributing

To propose a change, open an
[Enable a rule](https://github.com/pekral/rector-rules/issues/new?template=enable-rule.yml) or
[Disable a rule](https://github.com/pekral/rector-rules/issues/new?template=disable-rule.yml) issue, or see
[CONTRIBUTING.md](.github/CONTRIBUTING.md). Participation is governed by the
[code of conduct](.github/CODE_OF_CONDUCT.md).

## Security

See [the security policy](.github/SECURITY.md).

## Credits

Maintained by [Petr Král](https://github.com/pekral).

## License

MIT — see [LICENSE](LICENSE).
