# Configuration

The package's [`rector.php`](../rector.php) registers every rule in [`rules/rules.php`](../rules/rules.php)
and raises the Rector parallel process timeout to 180 s. Import it into your own `rector.php`; both Rector
config styles work.

## Builder style

```php
<?php

declare(strict_types=1);

use Rector\Config\RectorConfig;

return RectorConfig::configure()
    ->withPaths([__DIR__ . '/src'])
    ->withSets([__DIR__ . '/vendor/pekral/rector-rules/rector.php']);
```

## Closure style

```php
<?php

declare(strict_types=1);

use Rector\Config\RectorConfig;

return static function (RectorConfig $rectorConfig): void {
    $rectorConfig->import(__DIR__ . '/vendor/pekral/rector-rules/rector.php');
    $rectorConfig->paths([__DIR__ . '/src']);
};
```

## Skipping a rule you disagree with

The set is opinionated. Turn off anything that does not fit your codebase in your own `rector.php` — never by
editing the package:

```php
return RectorConfig::configure()
    ->withPaths([__DIR__ . '/src'])
    ->withSets([__DIR__ . '/vendor/pekral/rector-rules/rector.php'])
    ->withSkip([
        // Disable a rule everywhere
        Rector\CodeQuality\Rector\CallLike\AddNameToBooleanArgumentRector::class,

        // …or only in specific paths
        Rector\Php82\Rector\Class_\ReadOnlyClassRector::class => [
            __DIR__ . '/src/Legacy',
        ],
    ]);
```

## Combining with other sets

Add `->withPhpSets()` or any other Rector set alongside `withSets()`. A rule that ends up registered twice is
not an error.

Rules from another package, for example Laravel, need no change in this package. Install that package and list
its sets next to this one:

```php
use Rector\Config\RectorConfig;
use RectorLaravel\Set\LaravelSetList;

return RectorConfig::configure()
    ->withPaths([__DIR__ . '/app'])
    ->withSets([
        __DIR__ . '/vendor/pekral/rector-rules/rector.php',
        LaravelSetList::LARAVEL_CODE_QUALITY,
        LaravelSetList::LARAVEL_COLLECTION,
    ])
    ->withComposerBased(laravel: true);
```

List only the sets that apply to your code permanently. `driftingly/rector-laravel` also ships per-version
upgrade sets, in `LaravelSetList` and in `LaravelLevelSetList`, and that package deprecates every one of
them. `withComposerBased(laravel: true)` replaces them: it reads the installed `laravel/framework` version
and applies the upgrade rules bound to it.

## Parallel process timeout

`rector.php` raises the parallel process timeout to 180 seconds, so a worker that needs longer than Rector's
120-second default does not kill the run on a slow CI machine. The number of worker processes and the job size
stay at Rector's own defaults.

A project that imports `rector.php` inherits the timeout. In the builder style, `withParallel()` or
`withoutParallel()` overrides it. In the closure style, the override has to come after the `import()` call,
because the last call wins.
