# Changelog

All notable changes to `pekral/rector-rules` are documented here.

The format follows [Keep a Changelog](https://keepachangelog.com/en/1.1.0/). Release notes for each version
are also on the [Releases page](https://github.com/pekral/rector-rules/releases).

Most releases so far have changed the rule set, including patch-level ones. Before upgrading, read the entry
below and run `vendor/bin/rector process --dry-run` — see [UPGRADING.md](UPGRADING.md).

## [Unreleased]

### Added

- `CONTRIBUTING.md`, `SECURITY.md`, and `CODE_OF_CONDUCT.md`.
- Issue forms for proposing that a rule be enabled or disabled, and a pull request template.
- This changelog and `UPGRADING.md`.
- A social preview image in `assets/`, for link previews on GitHub and social networks.

### Changed

- The package description no longer claims the package contains custom rules. It lists rules that Rector
  ships, and `rector.php` registers each one.
- `composer.json` `support` now points at Discussions and the security policy.

## [0.5] - 2026-08-31

### Added

- **236 rules, up from 215** — 41 added, 20 removed. The additions lean on type inference (9 new
  `TypeDeclaration` rules) and dead-code removal (13 new `DeadCode` rules, most pruning docblocks a native
  type already states).
- The `LICENSE` file, declared in `composer.json` since the first release but never committed.

### Changed

- Requires `rector/rector` `^2.6.5`, up from `^2.3.6`. The set was re-curated against every rule the new
  version ships.
- README rewritten: both Rector configuration styles, how to skip a rule, what the set covers, and how the
  curation model works.
- `build/`, `.github/`, and the dotfiles are excluded from the distributed archive, so `composer require`
  pulls 5 files instead of the whole repository.

### Removed

- `CombineIfRector`, `ShortenElseIfRector`, and `SimplifyIfElseToTernaryRector`, deprecated upstream in Rector
  2.6.5. They printed a deprecation warning on every run.

## [0.4.8] - 2026-02-14

### Added

- PHP 8.5 support.

## [0.4.7] - 2026-01-25

### Changed

- Development dependency updates.

## [0.4.6] - 2026-01-10

### Changed

- Development dependency updates.

## [0.4.5] - 2025-11-05

### Changed

- CI workflows for changelog updates, dependency refresh, and stale issue handling.

## [0.4.4.1] - 2025-10-29

Re-tag of 0.4.4. This tag is not valid Semantic Versioning and is kept only for history.

## [0.4.4] - 2025-10-29

## [0.4.3] - 2025-10-19

### Added

- 46 new Rector rules.

### Changed

- Requires `rector/rector` `^2.2.3`, up from `^2.1.7`.

## [0.4.2] - 2025-09-18

### Changed

- Internal tooling, README refresh, and dependency updates.

## [0.4.1] - 2025-07-25

### Added

- More rules.

## [0.4] - 2025-05-04

## [0.3] - 2024-12-26

## [0.2.1] - 2023-08-01

## [0.2] - 2023-08-01

## [0.1.1] - 2023-02-19

## [0.1] - 2023-01-06

First release.

[Unreleased]: https://github.com/pekral/rector-rules/compare/0.5...HEAD
[0.5]: https://github.com/pekral/rector-rules/compare/0.4.8...0.5
[0.4.8]: https://github.com/pekral/rector-rules/compare/0.4.7...0.4.8
[0.4.7]: https://github.com/pekral/rector-rules/compare/0.4.6...0.4.7
[0.4.6]: https://github.com/pekral/rector-rules/compare/0.4.5...0.4.6
[0.4.5]: https://github.com/pekral/rector-rules/compare/0.4.4.1...0.4.5
[0.4.4.1]: https://github.com/pekral/rector-rules/compare/0.4.4...0.4.4.1
[0.4.4]: https://github.com/pekral/rector-rules/compare/0.4.3...0.4.4
[0.4.3]: https://github.com/pekral/rector-rules/compare/0.4.2...0.4.3
[0.4.2]: https://github.com/pekral/rector-rules/compare/0.4.1...0.4.2
[0.4.1]: https://github.com/pekral/rector-rules/compare/0.4...0.4.1
[0.4]: https://github.com/pekral/rector-rules/compare/0.3...0.4
[0.3]: https://github.com/pekral/rector-rules/compare/0.2.1...0.3
[0.2.1]: https://github.com/pekral/rector-rules/compare/0.2...0.2.1
[0.2]: https://github.com/pekral/rector-rules/compare/0.1.1...0.2
[0.1.1]: https://github.com/pekral/rector-rules/compare/0.1...0.1.1
[0.1]: https://github.com/pekral/rector-rules/releases/tag/0.1
