<?php

declare(strict_types = 1);

namespace Example\CodeQuality;

/**
 * Example for ConvertStaticToSelfRector
 * 
 * This file contains code examples that are transformed by
 * rule ConvertStaticToSelfRector.
 */
final class ConvertStaticToSelf
{

    private const string CONSTANT = 'value';

    public function example(): void
    {
        // Before transformation
        echo self::CONSTANT;
        echo self::CONSTANT;
        
        // After transformation
        echo self::CONSTANT;
        echo self::CONSTANT;
    }

}
