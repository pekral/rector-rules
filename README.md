# rector-rules

[![Latest Stable Version](https://poser.pugx.org/pekral/rector-rules/v/stable)](https://packagist.org/packages/pekral/rector-rules)
[![Total Downloads](https://poser.pugx.org/pekral/rector-rules/downloads)](https://packagist.org/packages/pekral/rector-rules)
[![License](https://poser.pugx.org/pekral/rector-rules/license)](https://packagist.org/packages/pekral/rector-rules)

A set of custom rules for [Rector](https://github.com/rectorphp/rector) to automate code refactoring and enforce coding standards.

---

## ⚙️ Requirements

- PHP >= 8.4
- [Rector](https://github.com/rectorphp/rector) >= 2.1.2

## 📦 Installation

```bash
composer require --dev pekral/rector-rules
```

## 🚀 Usage

Add to your `rector.php` configuration file:

```php
<?php
return static function (Rector\Config\RectorConfig $rectorConfig): void {
    $rectorConfig->import(__DIR__ . '/vendor/pekral/rector-rules/rector.php');
};
```

## 📝 Example

Run Rector with your custom rules:

```bash
vendor/bin/rector process src
```

## 🤝 Contributing

Contributions, issues and feature requests are welcome! Feel free to check [issues page](https://github.com/pekral/rector-rules/issues).

## 🪪 License

This project is licensed under the MIT License - see the [LICENSE](LICENSE) file for details.

## ℹ️ About

[rector-rules](https://github.com/pekral/rector-rules) is maintained by [Petr Král](mailto:kral.petr.88@gmail.com).

- [Packagist: pekral/rector-rules](https://packagist.org/packages/pekral/rector-rules)
- [Rector](https://github.com/rectorphp/rector)