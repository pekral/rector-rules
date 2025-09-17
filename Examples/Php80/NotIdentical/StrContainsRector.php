<?php

declare(strict_types = 1);

namespace Example\Php80;

/**
 * Example for StrContainsRector rule
 * 
 * This rule replaces strpos() !== false checks with str_contains() function.
 */
final class StrContains
{

    public function before(): void
    {
        $text = "Hello World";
        
        // Before transformation - old way
        if (str_contains($text, 'World')) {
            echo "Text contains 'World'";
        }
        
        // Additional examples
        if (str_contains($text, 'Hello')) {
            echo "Text contains 'Hello'";
        }
        
        if (!str_contains($text, 'PHP')) {
            echo "Text does not contain 'PHP'";
        }
    }
    
    public function after(): void
    {
        $text = "Hello World";
        
        // After transformation - modern way
        if (str_contains($text, 'World')) {
            echo "Text contains 'World'";
        }
        
        // Additional examples
        if (str_contains($text, 'Hello')) {
            echo "Text contains 'Hello'";
        }
        
        if (!str_contains($text, 'PHP')) {
            echo "Text does not contain 'PHP'";
        }
    }
    
    public function complexExample(): void
    {
        $email = "user@example.com";
        $allowedDomains = ['example.com', 'test.com'];
        
        // Before transformation
        $isAllowed = false;

        foreach ($allowedDomains as $domain) {
            if (str_contains($email, $domain)) {
                $isAllowed = true;

                break;
            }
        }
        
        // After transformation
        $isAllowed = false;

        foreach ($allowedDomains as $domain) {
            if (str_contains($email, $domain)) {
                $isAllowed = true;

                break;
            }
        }

        if ($isAllowed) {
            echo "Email is allowed";
        }
    }

}
