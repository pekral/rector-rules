<?php

declare(strict_types = 1);

require_once __DIR__ . '/../vendor/autoload.php';
require_once __DIR__ . '/ignored-rules.php';

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
 *
 * @return array<string>
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


/**
 * Load defined rules from rules/rules.php
 */
function getDefinedRules(): array
{
    $rulesFile = __DIR__ . '/../rules/rules.php';
    
    if (!file_exists($rulesFile)) {
        echo "Error: rules.php file not found.\n";
        exit(1);
    }
    
    $rules = require $rulesFile;
    
    if (!is_array($rules)) {
        echo "Error: rules.php does not contain array of rules.\n";
        exit(1);
    }
    
    return $rules;
}

/**
 * Main function
 */
function main(): void
{
    $allRules = loadAndDisplayAllRules();
    $definedRules = loadAndDisplayDefinedRules();
    
    $missingRules = findMissingRules($allRules, $definedRules);
    
    if ($missingRules === []) {
        echo "✅ All available Rector rules are already defined in rules/rules.php\n";

        return;
    }
    
    displayMissingRules($missingRules);
    exit(1);
}

/**
 * Load and display all Rector rules
 */
function loadAndDisplayAllRules(): array
{
    echo "Loading all Rector rules from vendor...\n";
    $allRules = discoverRectorRules();
    echo "Found " . count($allRules) . " Rector rules.\n\n";
    
    return $allRules;
}

/**
 * Load and display defined rules
 */
function loadAndDisplayDefinedRules(): array
{
    echo "Loading defined rules from rules/rules.php...\n";
    $definedRules = getDefinedRules();
    echo "Found " . count($definedRules) . " defined rules.\n\n";
    
    return $definedRules;
}

/**
 * Find missing rules
 */
function findMissingRules(array $allRules, array $definedRules): array
{
    $missingRules = [];
    
    foreach ($allRules as $ruleClass) {
        // Check if rule is defined in rules.php
        if (in_array($ruleClass, $definedRules, true)) {
            continue;
        }
        
        // Check if rule is ignored (compare with full class name)
        if (in_array($ruleClass, IGNORED_RULES, true)) {
            continue;
        }
        
        $missingRules[] = $ruleClass;
    }
    
    return $missingRules;
}

/**
 * Display missing rules
 */
function displayMissingRules(array $missingRules): void
{
    echo "❌ Found " . count($missingRules) . " Rector rules that are not defined:\n\n";
    
    $categorizedRules = categorizeRules($missingRules);
    
    foreach ($categorizedRules as $category => $rules) {
        echo "📁 {$category}:\n";

        foreach ($rules as $rule) {
            echo sprintf('  - %s%s', $rule, PHP_EOL);
        }

        echo "\n";
    }
    
    echo "💡 Tip: You can add missing rules to rules/rules.php using:\n";
    echo "use " . implode(";\nuse ", $missingRules) . ";\n";
}

/**
 * Categorize rules by their namespace
 */
function categorizeRules(array $missingRules): array
{
    $categorizedRules = [];

    foreach ($missingRules as $rule) {
        $parts = explode('\\', $rule);

        if (count($parts) >= 3) {
            $category = $parts[2];
            $categorizedRules[$category][] = $rule;
        } else {
            $categorizedRules['Other'][] = $rule;
        }
    }
    
    ksort($categorizedRules);
    
    return $categorizedRules;
}

// Run the script
main();
