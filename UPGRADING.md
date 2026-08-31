# Upgrading

Upgrading this package changes what Rector rewrites in your code. A release that adds rules makes Rector touch
files it previously left alone. This document is the routine that keeps that upgrade boring.

## What a new version can change

The set has grown in most releases so far — 0.4.1 and 0.4.3 added rules, 0.4.3 added 46 of them, and 0.5 added
41 and removed 20. Releases have also raised the `rector/rector` constraint (0.5 moved from `^2.3.6` to
`^2.6.5`) and the supported PHP version (0.4.8 added PHP 8.5).

**Treat every upgrade as one that can change the set.** Run the dry run first; do not assume from the version
number alone that nothing moved. Each release documents what actually changed in
[CHANGELOG.md](CHANGELOG.md) and on the
[Releases page](https://github.com/pekral/rector-rules/releases).

## The routine

1. **Upgrade on its own**, with nothing else in the same commit.

   ```bash
   composer update pekral/rector-rules
   ```

2. **Look before applying.** The dry run lists every file that would change and the rule that would change it.

   ```bash
   vendor/bin/rector process --dry-run
   ```

3. **Read the diff by rule, not by file.** A newly enabled rule that fires in 200 files is one decision, not
   200.

4. **Skip what you do not want**, in your own `rector.php` — never by editing the package:

   ```php
   ->withSkip([
       Rector\CodeQuality\Rector\FuncCall\CompactToVariablesRector::class,
   ])
   ```

5. **Apply, then run your test suite.** Rector's rules are meant to preserve behaviour; your tests are what
   proves it for your code.

   ```bash
   vendor/bin/rector process
   ```

6. **Commit the rewrite separately** from the dependency bump, so a reviewer can read one without the other.

## When a rule rewrote something it should not have

Two independent options, and they do not compete:

- **Local:** add the rule to `withSkip()` in your `rector.php`. Immediate, needs nobody's approval.
- **Upstream:** if the rule is wrong for everyone, open a
  [Disable a rule](https://github.com/pekral/rector-rules/issues/new?template=disable-rule.yml) issue with the
  before/after. A rule that produces broken code is a bug in
  [Rector itself](https://github.com/rectorphp/rector/issues) — this package only chooses which rules run.

## 0.4.x → 0.5

- **No configuration change and no new PHP requirement.** The package still requires PHP `^8.4`.
- `rector/rector` moved to `^2.6.5` from `^2.3.6`.
- Three rules were removed because Rector deprecated them: `CombineIfRector`, `ShortenElseIfRector`,
  `SimplifyIfElseToTernaryRector`. They printed a deprecation warning on every run. If your `rector.php`
  skips any of them, those entries are now redundant; leaving them costs nothing.
- 41 rules were added and 20 removed, so expect a larger dry-run diff than usual — mostly type declarations
  and removal of docblocks that a native type already states.
