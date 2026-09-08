---
name: machine-payments-protocol
description: "Use when implementing, designing, or reviewing the Machine Payments Protocol (MPP) HTTP 402 payment flow in a Laravel/PHP application — middleware placement, payment verification, provider abstraction, pricing, and MCP tool billing. Separates protocol-normative behavior (cited from the IETF draft and its reference implementations) from illustrative naming and generic API-security hardening."
license: MIT
metadata:
  author: "Petr Král (pekral.cz)"
---

## Constraints
- Apply `@rules/php/core-standards.md` when generated code is PHP — `final` classes, `declare(strict_types=1)`, typed signatures.
- If the project uses Laravel, also apply `@rules/laravel/laravel.md` and `@rules/laravel/architecture.md` — payment verification is a service, not controller logic.
- Defer to, never restate, `rules/security/backend.md` and `@skills/laravel-security/SKILL.md` for generic secure coding, secret handling, rate limiting, and error-message hygiene; this skill states only the MPP-specific additions.
- Never invent a protocol detail. Every concrete claim below is labeled **Spec** (cited, with retrieval date), **Package** (a real third-party Laravel package, not the spec), or **Illustrative** (this skill's / the requesting issue's own example naming — never protocol vocabulary). Full source table: `references/protocol-sourcing.md`.
- The spec is an individual IETF Internet-Draft (`draft-ryan-httpauth-payment-01`), not a ratified standard — no working-group adoption, expires 2026-09-19. Treat every **Spec** claim as a moving target and re-verify before relying on it long-term.
- Do not cite `https://www.machinepaymentsprotocol.org/` — it does not resolve.
- Adopting `square1/laravel-mpp` (or any other MPP package) is a Composer dependency decision — apply `@rules/php/dependency-selection.md` (Activity + Compatibility gates, selection note) before proposing it in generated code.
- Hard limits: this file stays <= 500 lines and <= 5000 tokens.

## Modes

This skill runs in one of two modes, selected by the caller via `MODE` (default `implement`):

- **`implement` (default)** — full MPP work: the payment middleware, the verification service and its provider abstraction, `config/mpp.php`, pricing, and MCP tool billing. Every section below behaves as written unless it is explicitly flagged for `MODE=cr`.
- **`cr` (read-only lens — invoked by `@skills/code-review/SKILL.md`, `code-review-github`, `code-review-jira`, and `code-review-bugsnag` when the diff touches an MPP payment surface on a project that implements MPP)** — **never modify a middleware, a service, a route, a configuration file, or any other project file, never author a test, never stage / commit / push, never run fixers or checkers, and never chain a follow-up review.** Scope the analysis to the lines added or modified by the PR diff and return the findings as markdown only, carrying the reproducer fields the CR folds into its standard Critical / Moderate / Minor buckets. Every instruction below that would touch a file is emitted as a written proposal, never applied to the project.

> **What this lens owns in a CR:** protocol conformance — challenge and receipt shape, single-use proof, request and body binding, expiry, no side effect before payment, idempotent settlement, server-side pricing, RFC 9457 problem bodies — each reported at the **Spec** / **Package** / **Illustrative** label `references/protocol-sourcing.md` gives it, never above it.
> It **defers the generic HTTP contract of the gated endpoint** — status choice outside the `402` challenge, response envelope, versioning, idempotency-key mechanics — to `@skills/api-review/SKILL.md`, and **defers generic secure coding** — secrets, rate limiting, transport, error-message hygiene — to `@rules/security/backend.md` and `@skills/security-review/SKILL.md`, as the Constraints above already require. It never raises a finding one of those owns.
> Those boundaries divide the *dimensions* of a payment change, never its lines: a middleware that both settles before verifying the body digest and leaks provider internals into `detail` carries one protocol finding here and one safe-error-message finding from the security owner — two different defects.
> **The lens never proposes adopting MPP.** A project that does not implement MPP is not reviewed by it at all, and a `402` for an exceeded quota or a lapsed plan there is not an MPP defect.

## Use when
- Implementing MPP-gated Laravel endpoints ("Implement Machine Payments Protocol in Laravel.", "Protect this endpoint using MPP.")
- Generating a payment-verification middleware or service layer for pay-per-request AI-agent access.
- Deciding whether an endpoint should use MPP, API keys, or OAuth.
- Reviewing an MPP implementation for security issues (replay, idempotency, tampering).
- Adding MPP billing to an MCP server or individual MCP tool.

## Why MPP, and why now
Traditional API monetization (accounts, subscriptions, API keys, invoice/payment pages) assumes a human completes a checkout flow. An autonomous agent cannot click through a payment page, so MPP defines an HTTP-native, per-request payment flow with no human in the loop: **Challenge → Credential → Receipt** (Spec: `draft-ryan-httpauth-payment-01`, `https://mpp.dev/protocol/http-402`, retrieved 2026-08-03).

1. Agent requests a resource with no credential.
2. Server responds `402 Payment Required` with a `WWW-Authenticate: Payment` challenge.
3. Agent settles payment out-of-band with a supported payment method, then retries with `Authorization: Payment <credential>`.
4. Server verifies the credential and, on success, serves the resource and returns a `Payment-Receipt`.

MPP does not replace API keys or OAuth for identity — it adds a payment precondition on top of the existing authorization layer. Prefer MPP when the caller is an autonomous agent transacting per call with no pre-provisioned account, and keep the existing identity/authorization mechanism regardless (see Architecture).

## Detecting monetization opportunities
Good fits share three properties: cost per call is genuinely variable or non-trivial, the caller is plausibly an unattended agent rather than a human filling a checkout form, and per-call granularity beats a subscription for that usage pattern. Typical candidates: AI inference endpoints, OCR/document parsing, search/embeddings/vector search, premium report generation, paid data exports, individually-billed premium MCP tools, and SaaS APIs currently gated by manually-provisioned API keys.

## Laravel implementation patterns

### Middleware
`square1/laravel-mpp` (Package — MIT, 26 GitHub stars at retrieval, PHP 8.4 + Laravel 12/13; a young dependency, review and pin it before adopting) registers exactly the shape a Laravel project would reach for:

```php
Route::middleware(['mpp:0.50,USD'])->get('/paid', PaidResourceController::class);
// optional: 'mpp:0.50,USD,grants=10,scope=report.basic,method=tempo'
```

or, as an attribute: `#[RequiresPayment(amount: '5.00', currency: 'USD', grants: 10, scope: 'report.basic')]`.

Whichever middleware you write or adopt, its responsibilities are fixed regardless of implementation: detect a missing/invalid credential and short-circuit with `402` **before** any side effect runs (Spec: "Servers MUST NOT perform side effects for requests that have not been paid" — see Security); on a present credential, delegate verification to a service, never inline it; on success, let the request continue unchanged so downstream code stays MPP-unaware.

### Configuration
`config/mpp.php`, published via `php artisan vendor:publish --tag=mpp-config` (Package). Typical concerns: enabled payment methods, default currency, per-route/default pricing, the challenge-signing secret, and credential TTL. Package env vars: `MPP_SESSION_DRIVER`, `MPP_ATTRIBUTES_ENABLED`, `MPP_CHALLENGE_SECRET`, `TEMPO_RECIPIENT`. Read every secret from `env()`/config and validate presence at boot — `@skills/laravel-security/SKILL.md` Production Configuration.

### Service layer & contracts
Keep the middleware thin: it detects and delegates, a dedicated service verifies. The names below are **illustrative** — the spec defines no service-layer vocabulary, and the real package uses different names (`Square1\Mpp\Protocol\Challenge`, `Square1\Mpp\Protocol\Credential`, `Square1\Mpp\Settlement\Verifier`, `Square1\Mpp\Settlement\SettlementResult`):

```php
interface PaymentProvider
{
    public function supports(string $method): bool;
    public function challenge(Money $amount, string $intent): PaymentChallenge;
    public function verify(PaymentCredential $credential): SettlementResult;
}
```

A `PricingResolver` (or equivalent) computes the amount server-side per route/request — never trust a client-supplied amount (see Security). Bind concrete providers by config (`config('mpp.providers.default')`), never hardcode one.

## HTTP responses
- **Missing/expired/unrecognized credential → `402 Payment Required`** with a `WWW-Authenticate: Payment` challenge carrying, at minimum, `id`, `realm`, `method`, `intent`, `request` (base64url JSON; documented common members `amount`, `currency`, `recipient` — anything beyond that is payment-method-specific), and optionally `expires`, `description`, `opaque`, `digest` (Spec, retrieved 2026-08-03). The spec defines no endpoint path convention — MPP gates any HTTP-addressable resource; do not present a fixed path as protocol-mandated.
- **Invalid/tampered/replayed credential → the issue's own hedge is `401` or `403` "depending on protocol state"; this is not a spec-confirmed condition-to-status mapping.** Ship it as illustrative guidance, not a normative rule. The safer default when a challenge is expired or already consumed is to re-issue a fresh `402`, rather than asserting a specific 401-vs-403 branch.
- **Successful settlement → continue the original request** and return `Payment-Receipt: <base64url JSON>` alongside the normal response; the draft's receipt carries `status`, `method`, `timestamp`, `reference` (Spec).
- **Any protocol error body → RFC 9457 Problem Details** (`Content-Type: application/problem+json`; `type`, `title`, `status`, `detail`) (Spec). Never leak provider internals in `detail` — `@rules/security/backend.md` *Safe Validation & Error Messages*.

**Example wire exchange (Spec, retrieved 2026-08-03) — the challenge auth-params are comma-separated quoted values on `WWW-Authenticate`, never a JSON body or a JSON-valued header:**

```http
HTTP/1.1 402 Payment Required
WWW-Authenticate: Payment id="abc123", realm="mpp.dev", method="tempo", intent="charge", request="eyJ..."
Content-Type: application/problem+json

GET /paid HTTP/1.1
Authorization: Payment eyJjaGFsbGVuZ2UiOnsiaWQiOiJxQjN3RXJUeVU3aU9wQXNEOWZHaEprIiwi...
```

Do not ship a `402` body with an `accepts: [...]` array — a secondary source uses that shape, but it contradicts the primary spec, which puts the challenge in `WWW-Authenticate`. A `Payment-Session` header is not defined anywhere in the core draft either; treat it as a `square1/laravel-mpp` extension (Package), never as protocol.

## Security considerations
MPP-specific rules are additive on top of this repo's existing security baseline — apply `rules/security/backend.md` and `@skills/laravel-security/SKILL.md` for everything generic; this section states only the MPP-specific additions.

**Spec-normative (`draft-ryan-httpauth-payment-01`, retrieved 2026-08-03) — stronger than "recommended", these are MUSTs (one exception noted below):**
- **Single-use proof / no double-spending.** A payment proof MUST be usable exactly once; persist consumed challenge ids in a durable store, not cache alone.
- **Request binding (SHOULD, not MUST).** The draft states "Servers SHOULD bind the challenge `id` to the challenge parameters ... to prevent request integrity attacks"; recommended construction is HMAC-SHA256 over the fixed slots `realm|method|intent|request|expires|digest|opaque`, so a re-signed challenge is detectable.
- **Body binding.** When a `digest` param is present, recompute the RFC 9530 digest of the current request body and reject on mismatch.
- **Expiry.** Reject a credential for an expired challenge; the spec sets no default TTL (`square1/laravel-mpp` defaults to 5 minutes — a package default, not a spec default).
- **No side effects before payment.** The payment gate runs before any state mutation; the `402` path performs no writes.
- **Idempotent settlement under concurrency.** Concurrent requests carrying the same credential must yield at most one settlement and one resource delivery — an atomic lock keyed on the challenge id, plus an idempotency key on the settlement provider call.
- **Transport.** TLS 1.2+ is REQUIRED; never issue a challenge or accept a credential over plain HTTP.

**Generic hardening that stays correct even if the draft's field names change — the mechanics are `rules/security/backend.md`'s, applied here to the payment gate:**
- Never trust a client-echoed `amount`/`currency` — re-derive the price server-side and verify it against the request binding before settling.
- `hash_equals()` for every HMAC/signature comparison, never `==`.
- Validate `expires` against the server clock with a documented tolerance; reject the credential (fail closed) when `expires` is missing or unparseable rather than treating it as absent.
- Rate-limit the unauthenticated `402` path itself (a free challenge-minting oracle) and failed settlement attempts separately.
- A settled payment proves funds moved, not that the payer may access this resource/tenant — keep the existing authorization layer in force behind the payment gate.
- Fail closed on a provider timeout or unreachable settlement backend.
- Audit-log challenge issuance, settlement attempt, outcome, and receipt reference as structured events with correlation ids; log identifiers, never proofs or secrets.

## Architecture recommendations
Prefer: middleware for detection/short-circuit, a dedicated service class for verification, DI for the provider, an interface (`PaymentProvider` or your own name) so no route depends on one payment method, and configuration-driven provider selection. Avoid: payment logic inside a controller, a static helper class, or duplicated verification per route — the same failure modes `@rules/laravel/architecture.md` already flags for any cross-cutting concern.

## Provider abstraction
The spec defines payment **methods** (registered identifiers, e.g. `tempo`, `stripe`), not a Laravel provider-abstraction name — `MachinePaymentProvider` and similar names are **illustrative**, not protocol vocabulary. Two real, citable payment methods exist today, both Production-status identifiers (retrieved 2026-08-03): `tempo` (Tempo Labs' payments blockchain, mainnet live 2026-03-18 — native stablecoin settlement) and `stripe` (Stripe's MPP payment method — Shared Payment Tokens + PaymentIntents, 0.50 USD card minimum). Design the abstraction so adding a third method is a new class implementing your interface, not a branch in existing code.

## Pricing
The spec carries only `amount` + `currency` in the challenge `request` — there is no protocol-defined per-token/per-MB/dynamic pricing format; treat those as generic API-billing patterns, not MPP vocabulary. What the spec does define is the **intent** axis (Spec, `/specs/intents`, retrieved 2026-08-03): `charge` (one-time, settles immediately), `session` (streaming payment over a payment channel), `subscription` (recurring fixed payment across billing periods). Model pricing strategy around intent first, then compute the amount server-side per request via your own pricing resolver.

## MCP integration
MPP has a dedicated MCP transport binding (Spec: `draft-payment-transport-mcp-00`, `https://mpp.dev/protocol/transports/mcp`, retrieved 2026-08-03) — stronger than a generic "MPP can protect MCP tools" claim: a payment-required tool call returns JSON-RPC error code `-32042` with challenges in `error.data.challenges[]`, and the credential is returned in `params._meta["org.paymentauth/credential"]` on retry. Guide: `https://mpp.dev/guides/monetize-mcp-server`. Use this for a premium MCP server billing tools individually (e.g. a `search_docs()` tool that returns `-32042` until paid) rather than inventing a bespoke MCP payment envelope.

## Best practices
Idempotent settlement (see Security), immutable credentials (never mutate a decoded credential in place — re-derive instead), short-lived challenges, request/body binding via signature, structured audit events, and a retry-safe design where a client retry with the same credential never double-settles. Generate tests for: missing credential → `402`, expired challenge → rejected, replayed credential → rejected, tampered `request`/`digest` → rejected, concurrent settlement → single success.

## Related Skills
- `@skills/laravel-security/SKILL.md` — generic Laravel security building blocks this skill defers to.
- `@skills/security-review/SKILL.md` — audit an existing MPP implementation.
- `@skills/api-review/SKILL.md` — HTTP status-code and contract review for the gated endpoint.

## Done when
- The Challenge → Credential → Receipt flow is implemented with the payment gate running before any side effect.
- Verification lives in a service behind an interface, not in the controller or middleware body.
- Amount/currency are computed server-side, never trusted from the client.
- Every claim labeled Spec/Package/Illustrative in generated code or docs matches `references/protocol-sourcing.md`; nothing beyond it is presented as normative.
- The Security section's spec-normative rules (single-use proof, body binding, no pre-payment side effects, idempotent settlement, TLS — all MUSTs, plus request binding as a SHOULD) are satisfied or consciously deferred to `@skills/laravel-security/SKILL.md`.

## Output Humanization
- Use [blader/humanizer](https://github.com/blader/humanizer) for all skill outputs to keep the text natural and human-friendly.
