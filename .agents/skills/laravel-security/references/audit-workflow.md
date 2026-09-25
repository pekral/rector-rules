# Laravel Security Audit Workflow

A defensive security auditor in an authorized environment. The goal is to find and report weaknesses and to propose a fix plus a regression test — **never to exploit them**.

## Severity scale

Audit reporting uses five levels; the repository's convergence gate (CR) maps them onto three (High and Medium collapse into Moderate, Low and Info into Minor):

| Audit severity | CR severity | Blocks convergence? |
|------------------|-------------|----------------------|
| Critical         | Critical    | YES                  |
| High             | Moderate    | YES                  |
| Medium           | Moderate    | YES                  |
| Low              | Minor       | NO                   |
| Info             | Minor       | NO                   |

The `leonardo.md` pins (`Critical` / `Moderate` / `Minor`) are unchanged — the audit severity is a reporting layer above them.

## Every confirmed finding carries

1. **The area** (1–7 below) and the **severity** (Critical / High / Medium / Low / Info).
2. **The concrete file and line** (or the search pattern).
3. **The proposed fix** — as a reference to the matching section of `@skills/laravel-security/SKILL.md`.
4. **A regression-test sketch** (Pest / PHPUnit) — the auditor sketches the test that would catch the finding; `donatello` implements the application fix.

## The seven audit areas

### 1. Authorization — IDOR/BOLA

**What to look for:**

- A missing `$this->authorize()` / `Gate::authorize()` / `@can` in controllers and Livewire components — every resource endpoint needs a policy or a gate.
- Direct queries not scoped to the current user: `Post::find($id)` instead of `auth()->user()->posts()->findOrFail($id)`.
- Route model binding without a policy: the controller accepts `{post}` and never verifies ownership.
- Tenant isolation: a multi-tenant app with no global scope and no `tenant_id` filtering.
- Role bypass: an admin route group with no `role:admin` middleware; a Filament panel with no `canAccessPanel()`.
- Livewire actions: a mounted component is not an authorization boundary — every action must call authorize again.

**Grep patterns:**

```bash
grep -rn "::find\(\|::findOrFail\(\|::firstOrFail\(" app/Http/Controllers/
grep -rn "->authorize\|Gate::authorize\|@can" app/ --include="*.php" --include="*.blade.php"
```

**Reference fix:** the *Authorization* section of `@skills/laravel-security/SKILL.md`.

**Regression-test example:**

```php
it('prevents accessing another user post', function (): void {
    $owner = User::factory()->create();
    $attacker = User::factory()->create();
    $post = Post::factory()->for($owner)->create();

    $response = actingAs($attacker)->get("/posts/{$post->id}");

    $response->assertForbidden(); // or assertNotFound(), depending on the chosen strategy
});
```

---

### 2. Authentication

**What to look for:**

- Missing rate limiting on `/login`, `/forgot-password`, `/register` — see the *API Security* section (RateLimiter).
- Session fixation: `$request->session()->regenerate()` is missing after a successful login.
- Logout: the session is not invalidated (`invalidate()` plus `regenerateToken()`), or the token is not revoked.
- Deactivated users still get in: `Authenticatable::banned` / `is_active` is not checked after login (the `Authenticated` event or an `EnsureUserIsActive` middleware).
- Password reset: token validity — tokens are not single-use, or they expire far too late.

**Grep patterns:**

```bash
grep -rn "session()->regenerate\b" app/
grep -rn "throttle:" routes/ app/
```

**Reference fix:** the *Authentication* and *API Security* sections of `@skills/laravel-security/SKILL.md`.

**Regression-test example:**

```php
it('regenerates session on login', function (): void {
    $user = User::factory()->create();
    $this->get('/login');
    $guestToken = $this->app['session']->token();

    $this->post('/login', ['email' => $user->email, 'password' => 'password']);

    expect($this->app['session']->token())->not->toBe($guestToken);
});
```

---

### 3. Validation and requests

**What to look for:**

- A missing FormRequest — an inline `$request->validate()` in several places, or no validation at all.
- `authorize()` returns a hardcoded `true`, or carries no logic — a FormRequest must actually authorize.
- Mass assignment: `$request->all()` or `$request->except(...)` passed into `create()` / `fill()`; the model declares no `$fillable`.
- Unvalidated parameters: a query string or route parameter used in a query without sanitization.
- `DB::raw` or `whereRaw` with interpolation: `DB::select("... '{$input}'")`; `orderByRaw($request->sort)`.

**Grep patterns:**

```bash
grep -rn "request()->all()\|->all()" app/Http/Controllers/
grep -rn "DB::raw\|whereRaw\|orderByRaw\|selectRaw" app/ --include="*.php"
grep -rn "return true;" app/Http/Requests/ --include="*.php"
```

**Reference fix:** the *Eloquent Security* and *Input Validation* sections of `@skills/laravel-security/SKILL.md`.

**Regression-test example:**

```php
it('rejects unvalidated sort parameter', function (): void {
    $response = get('/posts?sort=malicious_sql_fragment--');
    $response->assertUnprocessable(); // or assertBadRequest()
});
```

---

### 4. XSS

**What to look for:**

- `{!! $variable !!}` in Blade templates — check whether the variable comes from user input.
- `innerHTML` or `x-html` in Alpine.js without sanitization.
- Markdown rendered without HTML purification (unpurified output in `{!! Str::markdown($input) !!}`).
- Livewire / Inertia: database-sourced props rendered without escaping in Vue or React.
- `@json($data)` carrying sensitive or user data — verify what is being serialized.

**Grep patterns:**

```bash
grep -rn "{!!" resources/views/ --include="*.blade.php"
grep -rn "x-html\|innerHTML" resources/
grep -rn "Str::markdown\|commonmark" app/ resources/
```

**Reference fix:** the *XSS Prevention* section of `@skills/laravel-security/SKILL.md`.

**Regression-test example:**

```php
it('escapes user-supplied content in view', function (): void {
    $post = Post::factory()->create(['title' => '<script>alert(1)</script>']);

    $response = get("/posts/{$post->id}");

    $response->assertSee('&lt;script&gt;', false);
    $response->assertDontSee('<script>alert(1)</script>', false);
});
```

---

### 5. File upload

**What to look for:**

- Missing `mimes:` or `extensions:` validation — `.php`, `.html`, `.svg`, and `.phar` can be uploaded.
- Missing `max:` — a DoS through oversized files.
- Stored on the `public` disk with no authorizing serve endpoint — the files are reachable directly, with no auth.
- Path traversal: `$request->file('f')->getClientOriginalName()` used in a path without sanitization.
- SVG upload without sanitization (an SVG can carry `<script>`).

**Grep patterns:**

```bash
grep -rn "->store\|->storeAs" app/ --include="*.php"
grep -rn "getClientOriginalName\|getClientOriginalExtension" app/ --include="*.php"
grep -rn "'public'" app/ --include="*.php"
```

**Reference fix:** the *File Upload Security* section of `@skills/laravel-security/SKILL.md`.

**Regression-test example:**

```php
it('rejects php file upload', function (): void {
    $file = UploadedFile::fake()->create('shell.php', 10, 'application/x-php');

    $response = actingAs(User::factory()->create())
        ->post('/uploads', ['file' => $file]);

    $response->assertUnprocessable();
});
```

---

### 6. Secrets and configuration

**What to look for:**

- `.env` committed to the repository (a missing or wrong `.gitignore`).
- API keys, passwords, or tokens hardcoded in the code or in tests (e.g. `'secret' => 'hardcoded_key'`).
- `APP_DEBUG=true` in `.env.example` or in the production config.
- Credentials in the log: `Log::info('Login', ['password' => $password])`.
- Cookie settings: `Secure`, `HttpOnly`, `SameSite` — see the *Production Configuration* section.

**Grep patterns:**

Reading `.env*` is forbidden by `@rules/compound-engineering/orchestration.md` *Bash capability boundary*, with one named exception — the committed `.env.example` template, which carries placeholder values only and never a real secret. Pattern (a) below is therefore the one place this section reads `.env*` content, and it targets `.env.example` exclusively. Patterns (b) and (c) cover the rest of the claims above (the production config, and `.env` git-tracking) without reading any other `.env*` variant.

```bash
# (a) the template — the only permitted read of .env* content
grep -rn "APP_DEBUG=true" . --include=".env.example"
# (b) the production config — a hardcoded 'debug' => true bypassing env()
grep -rn "'debug'" config/ --include="*.php" | grep -v "env("
# (c) .env git-tracking — reads the list of tracked files, never the content of .env
git ls-files | grep -qx '\.env' && echo "CRITICAL: .env is tracked by git"
grep -rn "password\|secret\|api_key" --include="*.php" app/ config/ | grep -v "env(\|config("
grep -rn "Log::" app/ --include="*.php" | grep -i "password\|secret\|token"
```

**Reference fix:** the *Production Configuration* and *Secrets and Dependencies* sections of `@skills/laravel-security/SKILL.md`, which also cover the production config check in pattern (b) above. For cookies see `@rules/security/backend.md`.

**Regression-test example:**

```php
// Target: the specific Log:: line the grep above reveals, for example:
// Log::info('Auth attempt', ['token' => $request->bearerToken(), 'api_key' => $request->input('api_key')]);
it('does not include secret/token/api_key value in the flagged log call context', function (): void {
    $logs = [];
    Log::listen(static function ($log) use (&$logs): void {
        $logs[] = $log->context;
    });

    $secret = 'supersecret-' . uniqid();
    // Replace this endpoint call with the one where the grep found a Log:: carrying a sensitive key.
    $this->post('/api/example', ['api_key' => $secret]);

    foreach ($logs as $context) {
        expect(json_encode($context))->not->toContain($secret);
    }
});
```

---

### 7. Dependencies

**What to look for:**

- `composer audit` never runs — a CI pipeline with no audit step.
- Outdated packages carrying a CVE in `composer.lock`.
- Frontend: `npm audit` / `yarn audit` when the project ships a `package.json`.
- Dev dependencies installed in production (a missing `--no-dev`).

**Commands:**

```bash
composer audit
# when there is a frontend:
npm audit --audit-level=high
```

**Reference fix:** the *Secrets and Dependencies* section of `@skills/laravel-security/SKILL.md`. For dependency selection see `@rules/php/dependency-selection.md`.

**Regression-test example (CI pin):**

```yaml
# .github/workflows/ci.yml
- name: Security audit
  run: composer audit
```

The PHP regression test: assert that the `composer audit` CI step exists in the pipeline YAML (a content test in the test suite).

---

## Finding output format

```
[Area] [Severity] Description of the finding
Soubor: app/Http/Controllers/PostController.php:42
Fix: see the Authorization section of @skills/laravel-security/SKILL.md
Regression test: <the sketch above>
```

The output is severity-sorted (Critical → High → Medium → Low → Info). Every confirmed finding must carry a regression-test sketch.

## Dedup/gating

When an area is already covered by an existing bullet in `@skills/laravel-security/SKILL.md` or in `@rules/security/backend.md` / `@rules/security/frontend.md`, the audit section references it and adds no duplicate detection logic. New detection in this file covers only the patterns specific to the audit workflow (grep commands, test examples), never the secure-by-default blocks — those live in SKILL.md.
