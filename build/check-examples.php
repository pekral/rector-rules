<?php

declare(strict_types = 1);

require __DIR__ . '/../vendor/autoload.php';
require __DIR__ . '/ignored-rules.php';

/**
 * Script to check for missing example files for Rector rules
 * Dynamically reads rules from vendor/rector directory
 */

/**
 * Check if file is a Rector class
 */
function isRectorClass(string $relativePath): bool
{
    return str_contains($relativePath, '/Rector/') &&
           str_ends_with($relativePath, 'Rector') &&
           !str_contains($relativePath, 'Abstract');
}

/**
 * Convert file path to namespace
 */
function pathToNamespace(string $relativePath): string
{
    return 'Rector\\' . str_replace('/', '\\', $relativePath);
}

/**
 * Dynamically discover all Rector rules from vendor directory
 */
function discoverRectorRules(): array
{
    $vendorRectorPath = __DIR__ . '/../vendor/rector/rector/rules';
    
    if (!is_dir($vendorRectorPath)) {
        echo "Error: vendor/rector/rector/rules directory not found.\n";
        echo "Run 'composer install' first.\n";
        exit(1);
    }
    
    $rules = [];
    $iterator = new RecursiveIteratorIterator(
        new RecursiveDirectoryIterator($vendorRectorPath),
    );
    
    foreach ($iterator as $file) {
        if (!$file->isFile() || $file->getExtension() !== 'php') {
            continue;
        }
        
        $relativePath = str_replace($vendorRectorPath . '/', '', $file->getPathname());
        $relativePath = str_replace('.php', '', $relativePath);
        
        if (isRectorClass($relativePath)) {
            $rules[] = pathToNamespace($relativePath);
        }
    }
    
    return $rules;
}

// Path to examples directory
$examplesDir = __DIR__ . '/../Examples';

// Check if Examples directory exists
if (!is_dir($examplesDir)) {
    echo "Error: Examples directory does not exist.\n";
    echo "Create Examples directory in project root.\n";
    exit(1);
}

/**
 * Determine category from Rector rule namespace for PSR-4 structure
 * Returns category name based on PSR-4 autoload mapping
 */
function getCategoryFromRuleClass(string $ruleClass): string
{
    // Extract namespace parts
    $parts = explode('\\', $ruleClass);
    
    // Find the first Rector namespace part (usually the 2nd part after Rector\)
    foreach ($parts as $part) {
        // phpcs:ignore SlevomatCodingStandard.ControlStructures.RequireSingleLineCondition.RequiredSingleLineCondition,PEAR.ControlStructures.MultiLineCondition.CloseBracketNewLine,PEAR.ControlStructures.MultiLineCondition.CloseBracketNewLine
        if (in_array($part, [
            'CodeQuality', 'CodingStyle', 'DeadCode', 'EarlyReturn', 'Naming',
            'Php52', 'Php53', 'Php54', 'Php55', 'Php56', 'Php70', 'Php71', 'Php72', 'Php73', 'Php74',
            'Php80', 'Php81', 'Php82', 'Php83', 'Php84', 'Php85',
            'PHPUnit', 'Privatization', 'TypeDeclaration',
            'Arguments', 'Assert', 'Carbon', 'Instanceof_', 'NetteUtils', 'Removing', 'Renaming', 'Strict', 'Transform', 'Visibility',
        ], true)
        ) {
            return $part;
        }
    }
    
    // Default fallback
    return 'CodeQuality';
}

// Load rules from rules.php
$rulesFile = __DIR__ . '/../rules/rules.php';

if (!file_exists($rulesFile)) {
    echo "Error: rules.php file not found.\n";
    exit(1);
}

$definedRules = require $rulesFile;

if (!is_array($definedRules)) {
    echo "Error: rules.php does not contain array of rules.\n";
    exit(1);
}

// Discover rules dynamically from vendor directory
$allRules = discoverRectorRules();

$missingExamples = [];

foreach ($allRules as $ruleClass) {
    // Extract class name from full name
    $ruleName = basename(str_replace('\\', '/', $ruleClass));
    
    // Check if rule is defined in rules.php
    if (in_array($ruleClass, $definedRules, true)) {
        continue;
    }
    
    // Check if rule is ignored (compare with full class name)
    if (in_array($ruleClass, IGNORED_RULES, true)) {
        continue;
    }
    
    // Determine category from namespace for PSR-4 structure
    $category = getCategoryFromRuleClass($ruleClass);
    
    // Create path to example file following PSR-4 structure
    // Examples/Category/RectorName.php
    $exampleFile = $examplesDir . '/' . $category . '/' . $ruleName . '.php';
    
    if (!file_exists($exampleFile)) {
        $missingExamples[] = $ruleName;
    }
}

if ($missingExamples !== []) {
    foreach ($missingExamples as $missingExample) {
        echo $missingExample . '.php' . "\n";
    }

    exit(1);
}

exit(0);