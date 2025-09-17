# Rector Rules Examples

This directory contains usage examples for all Rector rules defined in `rules/rules.php`.

## Structure

Examples are organized into categories by transformation type:

- **CodeQuality** - Rules for improving code quality
- **CodingStyle** - Rules for consistent code style
- **DeadCode** - Rules for removing dead code
- **EarlyReturn** - Rules for early return pattern
- **Naming** - Rules for naming conventions
- **Php53-Php84** - Rules specific to PHP versions
- **Privatization** - Rules for privatization
- **TypeDeclaration** - Rules for type declarations
- **PHPUnit** - Rules specific to PHPUnit tests

## Usage

Each example file contains:

1. **Rule description** - What the rule does
2. **Before transformation examples** - Code that will be changed
3. **After transformation examples** - Expected result
4. **Complex examples** - Real use cases

## Checking

To check if all rules have their example files, run:

```bash
php build/check-examples.php
```

## Ignored Rules

Some rules are ignored because of:
- Duplicate definitions in `rules.php`
- Experimental or deprecated rules
- Rules that don't need examples

List of ignored rules can be found in `build/ignored-rules.php`.
