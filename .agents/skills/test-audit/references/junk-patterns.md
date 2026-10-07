# Junk patterns — one Pest example each

Companion to `@skills/test-audit/SKILL.md` *Junk patterns*. The skill names the patterns and owns the rule; this file shows what each one looks like in a Laravel / Pest suite and what replaces it.

## Contents
- Assertion-free test
- Tautology
- Expected value produced by the system under test
- Implementation-coupled mock
- Reflection on a private member
- Duplicate layer test
- Getter / setter and framework behaviour tests
- Test-only production code
- Coverage-only test
- False negative control
- Misleading test name

## Assertion-free test

**Junk: passes as long as nothing throws**

```php
it('syncs the order', function (): void {
    app(SyncOrder::class)($order);
});
```

**Replacement: assert the observable effect**

```php
it('marks the order as synced', function (): void {
    app(SyncOrder::class)($order);

    expect($order->fresh()->synced_at)->not->toBeNull();
});
```

## Tautology

`expect(true)->toBeTrue()`; `$data = new OrderData(total: 500); expect($data->total)->toBe(500);` with no transformation between; asserting the value a mock was just told to return; asserting that `collect([])` is a `Collection`. None of them can fail.

## Expected value produced by the system under test

**Junk: both sides move together when the formula changes**

```php
$expected = $calculator->calculate($input);
expect($calculator->calculate($input))->toBe($expected);
```

**Replacement: pin the value literally**

```php
expect($calculator->calculate(new Money(10_000)))->toEqual(new Money(12_100));
```

The same applies to an expected string rendered by the renderer under test, or a formula re-computed inline in the test.

## Implementation-coupled mock

**Junk: fails on a behaviour-preserving refactor, passes on a wrong total**

```php
$repository->shouldReceive('findByIds')->once()->with([1, 2])->andReturn($orders);
```

**Replacement: assert what the caller observes**

```php
expect(app(ExportOrders::class)([1, 2]))->toHaveCount(2);
```

A call count or order is legitimate only when it is the contract itself, such as "the payment gateway is charged exactly once".

## Reflection on a private member

`(new ReflectionMethod(Invoice::class, 'roundTotal'))->invoke(...)` reaches a line for coverage and pins the method's shape. Test the rounding through the public method that uses it. The code-review side is `@rules/code-review/core-analysis.md` *Visibility widened for a test*.

## Duplicate layer test

The same "a discount over 100 % is rejected" scenario asserted in `DiscountControllerTest`, `ApplyDiscountActionTest`, and `DiscountServiceTest`. Keep it at the owner (the Action), and keep the HTTP test only for what HTTP adds: the `422` status and the validation message.

## Getter / setter and framework behaviour tests

A test that `$user->getName()` returns the name it was given, that an Eloquent `'datetime'` cast returns a `Carbon`, or that a `required` rule rejects an empty field. The framework already guarantees each one; test the application logic built on top of it.

## Test-only production code

**Junk seam: a branch only tests take**

```php
if (app()->runningUnitTests()) {
    return $this->fakeRates;
}
```

Also a `public` method or getter only a test calls, a `setClockForTesting()` hook, or a config key only the test suite sets. Remove the seam and test through the real boundary with `Http::fake()`, `Carbon::setTestNow()`, or a container binding.

## Coverage-only test

`it('covers the fallback branch')` that forces a branch and asserts nothing about its outcome. Name the behaviour of the branch, or remove the branch.

## False negative control

**Junk: 422 from validation, the policy is never reached**

```php
$this->actingAs($stranger)->patchJson("/orders/{$order->id}", [])->assertStatus(422);
```

**Replacement: a valid payload, so the policy is the only reason to refuse**

```php
$this->actingAs($stranger)->patchJson("/orders/{$order->id}", ['note' => 'x'])->assertForbidden();
```

## Misleading test name

`it('retires the expired window')` over a body that asserts only `expect($window)->not->toBeNull()`. Rename it to what it proves, or assert the retirement.
