<?php

declare(strict_types = 1);

namespace Example\CodeQuality;

/**
 * Example for CombineIfRector rule
 * 
 * This rule combines nested if conditions into a single condition with && operator.
 */
final class CombineIf
{

    public function before(): void
    {
        $value = 5;
        
        if ($value <= 0) {
            return;
        }

        if ($value < 10) {
            echo "Value is between 0 and 10";
        }
    }
    
    public function after(): void
    {
        $value = 5;
        
        if ($value > 0 && $value < 10) {
            echo "Value is between 0 and 10";
        }
    }
    
    public function complexExample(): void
    {
        $user = null;
        $isLoggedIn = true;
        
        // Before transformation
        if ($user !== null && $isLoggedIn && $user->isActive()) {
            $user->login();
        }
        
        // After transformation
        if ($user !== null && $isLoggedIn && $user->isActive()) {
            $user->login();
        }
    }

}
