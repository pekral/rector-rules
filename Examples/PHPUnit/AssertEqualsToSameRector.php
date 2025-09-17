<?php

declare(strict_types = 1);

namespace Example\PHPUnit;

use PHPUnit\Framework\TestCase;
use stdClass;

/**
 * Example for AssertEqualsToSameRector
 * 
 * This rule replaces assertEquals() with assertSame() for better identity testing.
 */
final class AssertEqualsToSame extends TestCase
{

    public function before(): void
    {
        $expected = 42;
        $actual = 42;
        
        // Before transformation - assertEquals for primitive types
        $this->assertSame($expected, $actual);
        $this->assertSame(42, $actual);
        $this->assertSame('hello', 'hello');
        $this->assertEquals(true, true);
        $this->assertEquals(null, null);
    }
    
    public function after(): void
    {
        $expected = 42;
        $actual = 42;
        
        // After transformation - assertSame for better testing
        $this->assertSame($expected, $actual);
        $this->assertSame(42, $actual);
        $this->assertSame('hello', 'hello');
        $this->assertTrue(true);
        $this->assertNull(null);
    }
    
    public function complexExample(): void
    {
        $user1 = new stdClass();
        $user1->id = 1;
        $user1->name = 'John';
        
        $user2 = new stdClass();
        $user2->id = 1;
        $user2->name = 'John';
        
        // Before transformation
        $this->assertSame($user1->id, $user2->id);
        $this->assertSame($user1->name, $user2->name);
        
        // After transformation
        $this->assertSame($user1->id, $user2->id);
        $this->assertSame($user1->name, $user2->name);
    }
    
    public function arrayExample(): void
    {
        $expected = [1, 2, 3];
        $actual = [1, 2, 3];
        
        // Before transformation
        $this->assertSame($expected, $actual);
        
        // After transformation
        $this->assertSame($expected, $actual);
    }

}
