# Security Policy

## What this package is

`rules/rules.php` is an array of class names. `rector.php` reads it and calls `RectorConfig::rule()` on each
entry. There is no other executable code in the distributed archive, the package is installed with `--dev`,
and it never runs in production.

That shape bounds what a vulnerability here could be. The realistic cases are a malicious rule class name
added to the array, or a compromised release of the one runtime dependency, `rector/rector`.

## Supported versions

Fixes go into the latest release. Older tags are not patched.

## Reporting a vulnerability

Report privately through GitHub's
[**Report a vulnerability**](https://github.com/pekral/rector-rules/security/advisories/new) form, which opens
an advisory visible only to the maintainer. If you cannot use it, e-mail **kral.petr.88@gmail.com** with
`[SECURITY] rector-rules` in the subject.

Include the affected version and the steps to reproduce.

**Do not open a public issue for a vulnerability.** This is a single-maintainer project, so a public report
gives every consumer an exploit before there is a fix.

## Out of scope

- **A vulnerability in `rector/rector`** belongs to
  [the Rector project](https://github.com/rectorphp/rector/security). This repository only selects which of
  its rules run.
- **A rule that rewrites your code incorrectly** is not a vulnerability. Open a
  [Disable a rule](https://github.com/pekral/rector-rules/issues/new?template=disable-rule.yml) issue, or
  report it upstream if the transformation itself is wrong.
- **Development dependencies** (PHPCS, PHPStan, and the tooling in `require-dev`) are not shipped —
  `build/`, `.github/`, and the dotfiles are `export-ignore`. A `composer audit` runs weekly on this
  repository regardless.
