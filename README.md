# rector-rules

[![Latest Stable Version](https://poser.pugx.org/pekral/rector-rules/v/stable)](https://packagist.org/packages/pekral/rector-rules)
[![Total Downloads](https://poser.pugx.org/pekral/rector-rules/downloads)](https://packagist.org/packages/pekral/rector-rules)
[![License](https://poser.pugx.org/pekral/rector-rules/license)](https://packagist.org/packages/pekral/rector-rules)

Latest Version License Downloads

---

## 🚀 Introduction

**rector-rules** is an extensible package of custom rules for [Rector](https://github.com/rectorphp/rector) to automate code refactoring and enforce coding standards. It helps you maintain consistent code style and high code quality in your PHP projects through automated transformations.

---

## 📦 Installation

```bash
composer require --dev pekral/rector-rules
```

---

## ⚙️ Usage

1. Add to your `rector.php` configuration file:

```php
<?php
return static function (Rector\Config\RectorConfig $rectorConfig): void {
    $rectorConfig->import(__DIR__ . '/vendor/pekral/rector-rules/rector.php');
};
```

2. Run Rector with your custom rules:

```bash
vendor/bin/rector process src
```

---

## 📝 Usage Examples

### Code refactoring

```bash
vendor/bin/rector process src
```

### Dry-run (preview changes)

```bash
vendor/bin/rector process src --dry-run
```

### Example configuration (rector.php)

```php
<?php

declare(strict_types=1);

use Rector\Config\RectorConfig;

return static function (RectorConfig $rectorConfig): void {
    $rectorConfig->import(__DIR__ . '/vendor/pekral/rector-rules/rector.php');
    
    // Your additional rules here
    $rectorConfig->paths([__DIR__ . '/src']);
    $rectorConfig->skip([
        // Skip specific rules if needed
    ]);
};
```

---

## ⚙️ Configuration

* Rules can be extended and customized in your `rector.php` configuration.
* Supports PHP 8.4+. Contributing to this repository requires PHP 8.5+, because the development dependencies do.
* Easy integration with CI/CD (GitHub Actions, GitLab CI, ...).
* Includes comprehensive examples for each rule.

## 📋 Included Rules

This package includes **150+ Rector rules** covering code quality, dead code removal, PHP version upgrades, and more. 

For a complete list of all included rules, see [rules/rules.php](rules/rules.php).

---

## ❓ FAQ

**Q: How do I add a custom rule?**  
A: Add it to your `rector.php` configuration or extend this package.

**Q: How do I run Rector only on specific folders?**  
A: Adjust the path in the Rector command, e.g. `src/`, `app/`.

**Q: How can I contribute?**  
A: Open an issue or pull request on GitHub.

**Q: How do I see what changes Rector would make?**  
A: Use the `--dry-run` flag to preview changes without applying them.

**Q: Can I skip specific rules?**  
A: Yes, use the `skip` configuration in your `rector.php` file.

---

## 🔗 Further Resources

* [Rector](https://github.com/rectorphp/rector)
* [Rector Documentation](https://getrector.com/)
* [PHP 8.4 Features](https://www.php.net/releases/8.4/en.php)

---

## 📝 License

This package is licensed under the MIT License - see the [LICENSE](LICENSE) file for details.

## About

[rector-rules](https://github.com/pekral/rector-rules) is maintained by [Petr Král](mailto:kral.petr.88@gmail.com).

- [Packagist: pekral/rector-rules](https://packagist.org/packages/pekral/rector-rules)
- [Rector](https://github.com/rectorphp/rector)