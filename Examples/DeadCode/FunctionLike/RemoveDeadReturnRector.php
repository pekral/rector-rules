<?php

declare(strict_types = 1);

namespace Example\DeadCode;

use InvalidArgumentException;

/**
 * Example for RemoveDeadReturnRector
 * 
 * This rule removes unreachable return statements.
 */
final class RemoveDeadReturn
{

    public function before(): void
    {
        $value = 5;
        
        if ($value > 10) {
            return "Greater than 10";
        }
        
        // This return is unreachable, protože předchozí if vždy vrátí hodnotu
        return "This will never be reached";
    }
    
    public function after(): void
    {
        $value = 5;

        if ($value > 10) {
            return "Greater than 10";
        }

        // Unreachable return was removed
    }
    
    public function complexExample(): void
    {
        $user = null;
        
        // Before transformation
        if ($user === null) {
            throw new InvalidArgumentException("User cannot be null");
        }
        
        if ($user->isActive()) {
            return "User is active";
        }
        
        return "User is inactive";
    }
    
    public function complexExampleAfter(): void
    {
        $user = null;
        
        // After transformation
        if ($user === null) {
            throw new InvalidArgumentException("User cannot be null");
            // Unreachable return was removed
        }
        
        if ($user->isActive()) {
            return "User is active";
            // Unreachable code was removed
        }
        
        return "User is inactive";
    }

}
