# Contributing

This package ships **no rules of its own**. It is a list of rule class names that Rector already provides:
`rules/rules.php` returns a plain array, and `rector.php` registers every entry in it. Almost every
contribution is therefore a decision about a single rule — enable it, or leave it out.

## How the two files work

| File | Role |
| --- | --- |
| [`rules/rules.php`](../rules/rules.php) | The rules that ship. `rector.php` loops over this array. |
| `build/ignored-rules.php` | Rules the guard should not complain about (development only, not distributed). |

`composer check:missing-rules` walks `vendor/rector/rector/rules`, collects every class whose path contains
`/Rector/`, ends in `Rector`, and does not contain `Abstract`, then fails if a rule appears in **neither**
file. It does not reject a rule listed in both — the ignore list's own docblock names *"duplicate in
rules.php"* as one of its cases.

That guard is the point of the whole setup: when Rector releases new rules, `composer check` fails until
someone decides about each one. Nothing is silently skipped.

## Why a rule ends up in the ignore list

The reasons already in `build/ignored-rules.php`, in its own words:

- **Deprecated in `rector/rector`** — the largest group. Registering a deprecated rule prints a warning on
  every run, and some fail outright.
- **Waiting on PHP 8.5** — pipe-operator rules and the JMS Serializer property rules, marked
  *"Enable after PHP 8.5 support enabled"*.
- **Not available in the current Rector version.**
- **Experimental**, or not useful for the example checking the list was originally written for.

If you propose leaving a rule out for a reason that is not on this list, say what the reason is — the list is
the record of every decision made so far, and a new kind of reason should be visible in it.

## Proposing a change

Open an issue first — [Enable a rule](https://github.com/pekral/rector-rules/issues/new?template=enable-rule.yml)
or [Disable a rule](https://github.com/pekral/rector-rules/issues/new?template=disable-rule.yml). Both ask for
the rule's page in the [Rector rule catalog](https://getrector.com/find-rule) and a before/after example,
because that is what the decision is made on.

A rule that produces broken code is a bug in [Rector itself](https://github.com/rectorphp/rector/issues).
This repository only chooses which of its rules run.

## Development setup

```bash
composer install
```

Contributing needs **PHP 8.5+** — the development dependencies require it. Using the package only needs 8.4.

| Command | What it does |
| --- | --- |
| `composer check` | Code style, Rector dry-run on this repository's own sources, and the missing-rule guard |
| `composer fix` | Apply Rector and code-style fixes |
| `composer check:missing-rules` | Report rules that are in neither file |

## Pull requests

1. Add the class to `rules/rules.php`, or to `build/ignored-rules.php` under the group that states why.
2. Run `composer check` and make it pass.
3. Update the rule count in `README.md` if it changed.
4. Use [Conventional Commits](https://www.conventionalcommits.org/) — `feat:`, `fix:`, `docs:`, `chore:`.
   Commit subjects are written in English.
5. Open the pull request against `master`.

Adding or removing a rule changes what Rector rewrites in every project that imports this set. Say so in the
pull request description, so the release notes can carry it.

## Reporting a security issue

Do not open a public issue. See [SECURITY.md](SECURITY.md).
