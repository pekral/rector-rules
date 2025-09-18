<?php

declare(strict_types = 1);

namespace Example\TypeDeclaration;

use Exception;
use stdClass;

/**
 * Example for AddReturnTypeDeclarationRector
 * 
 * This rule automatically adds return type declarations based on code analysis.
 */
final class AddReturnTypeDeclaration
{

    public function before(): string
    {
        return "Hello World";
    }
    
    public function after(): string
    {
        return "Hello World";
    }
    
    public function getNumber(): int
    {
        return 42;
    }
    
    public function getArray(): array
    {
        return [1, 2, 3];
    }
    
    public function getNullableString(): ?string
    {
        return null;
    }
    
    public function getBool(): bool
    {
        return true;
    }
    
    public function getFloat(): float
    {
        return 3.14;
    }
    
    public function getObject(): stdClass
    {
        return new stdClass();
    }
    
    public function getUnionType(): string|int
    {
        $random = rand(0, 1);

        return $random === 0 ? "string" : 123;
    }
    
    public function getVoid(): void
    {
        echo "This method returns nothing";
    }
    
    public function getNever(): never
    {
        throw new Exception("This method never returns normally");
    }

}
