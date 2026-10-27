<?php

declare(strict_types = 1);

use Rector\Config\RectorConfig;

return static function (RectorConfig $rectorConfig): void {
    $rectorConfig->parallel(processTimeout: 180, maxNumberOfProcess: 6, jobSize: 60);

    foreach (include(__DIR__ . '/rules/rules.php') as $ruleClassName) {
        $rectorConfig->rule($ruleClassName);
    }
};