# MPP Protocol Sourcing Table

Full verification record backing `SKILL.md`'s Spec / Package / Illustrative labels. Every URL below was fetched and every quoted phrase confirmed on **2026-08-03**. Re-verify before treating a **Spec** row as durable — `draft-ryan-httpauth-payment-01` is an individual IETF Internet-Draft, not a ratified standard, and expires 2026-09-19.

## Primary sources

| Source | URL | Nature |
|---|---|---|
| IETF Internet-Draft (normative) | `https://datatracker.ietf.org/doc/html/draft-ryan-httpauth-payment-01` | "The `Payment` HTTP Authentication Scheme". Authors: Brendan Ryan, Jake Moxey, Tom Meagher (Tempo Labs); Jeff Weinstein, Steve Kaliski (Stripe). Individual submission. |
| Spec repo | `https://github.com/tempoxyz/mpp-specs` | Specs CC0-1.0, tooling Apache-2.0/MIT. Layout: `/specs/core`, `/specs/intents`, `/specs/methods`, `/specs/extensions`. |
| Docs site | `https://mpp.dev/` (+ `/protocol`, `/protocol/http-402`, `/protocol/challenges`, `/protocol/credentials`, `/protocol/receipts`, `/protocol/transports/mcp`, `/guides/monetize-mcp-server`) | Official documentation. |
| Rendered spec index | `https://paymentauth.org/` | Also the canonical problem-type base URI. |
| Stripe implementation docs | `https://docs.stripe.com/payments/machine/mpp` | Stripe's own MPP docs. |
| Stripe announcement | `https://stripe.com/blog/machine-payments-protocol` | 2026-03-18. |
| Laravel package | `https://github.com/square1-io/laravel-mpp` | `square1/laravel-mpp`, MIT, 26 stars, PHP 8.4 + Laravel 12/13. |
| Secondary (conflicts on one point — see below) | `https://www.conroyp.com/articles/practical-guide-machine-payments-protocol` | Paul Conroy, 2026-07-03. Useful for Laravel framing; its `402`-body `accepts` shape is **not** in the primary spec. |
| Dead — never cite | `https://www.machinepaymentsprotocol.org/` | DNS does not resolve. |

## Claim labels used in SKILL.md

- **Spec** — confirmed against the IETF draft and/or `mpp.dev`, cited with URL + retrieval date.
- **Package** — a real behavior of `square1/laravel-mpp`, not a protocol requirement.
- **Illustrative** — the issue's own or this skill's own example naming; appears in no spec, docs page, or package.
- **Out of scope / unverified** — not confirmed by any source fetched for this skill; deliberately not shipped as fact.
- **Not shipped (contradicts primary spec)** — appears in a secondary source but conflicts with the IETF draft; excluded from `SKILL.md` entirely.

## Table

| Claim | Label | Detail |
|---|---|---|
| 402 flow: request → 402 + challenge → pay → retry with credential → 200 | Spec | Official flow name is Challenge → Credential → Receipt. |
| `Authorization: Payment <credential>` header | Spec | Auth scheme is literally `Payment`; value is a single base64url-nopad (RFC 4648 §5) token68 encoding a JSON object. |
| Challenge fields (`id`, `realm`, `method`, `intent`, `request`, `expires`, `description`, `opaque`, `digest`) | Spec | Travel in `WWW-Authenticate: Payment`, not the response body. `request` common members: `amount`, `currency`, `recipient`; anything else is method-specific. `digest` = RFC 9530 content digest. |
| Credential object (`challenge`, `payload`, `source`) | Spec | `payload` carries `type`/`signature`; `source` is payer identity, DID format recommended. |
| Receipt on success (`Payment-Receipt` header) | Spec | Draft members: `status`, `method`, `timestamp`, `reference`; docs additionally show `challengeId`, `settlement`. |
| Error body (RFC 9457 Problem Details) | Spec | `application/problem+json`; `type`, `title`, `status`, `detail`; problem-type base `https://paymentauth.org/problems/`. |
| Endpoint paths defined by the protocol | Out of scope / unverified | The spec defines none; any resource is gatable. |
| Invalid credential → 401 vs 403 "depending on protocol state" | Out of scope / unverified | The draft names error *conditions*, not a normative condition→status-code table. Ship as the issue's own hedge only. |
| `MachinePaymentProvider` as the provider-abstraction name | Illustrative | Not found in any spec, docs page, or package. |
| `PaymentVerifier`, `PaymentCredential`, `PaymentProvider`, `PricingResolver` | Illustrative | Package uses different names — see SKILL.md Service layer & contracts. |
| "Stripe MPP" as a product name | Illustrative (imprecise) | Stripe documents "MPP payments" / "machine payments"; `stripe` is a real Production payment-method identifier, but "Stripe MPP" is third-party shorthand, not Stripe's own product name. |
| "Tempo" as a payment provider | Spec | Real, mainnet live 2026-03-18, MPP co-author, Production payment-method identifier. |
| MPP ↔ MCP integration | Spec (stronger than the issue's claim) | Dedicated transport binding `draft-payment-transport-mcp-00`; JSON-RPC error `-32042`, `error.data.challenges[]`, credential in `params._meta["org.paymentauth/credential"]`. |
| Pricing models: per-token, per-MB, per-request, dynamic | Out of scope / unverified as MPP-specific | No such format in the spec; generic API-billing patterns. Prefer the real registered `intent` values (`charge`, `session`, `subscription`) instead. |
| `Route::middleware(['mpp:0.05,USD'])` | Package | `square1/laravel-mpp` registers this exact alias shape (`mpp:0.50,USD[,grants=…,scope=…,method=…]`), plus `#[RequiresPayment(...)]`. |
| `config/mpp.php` | Package | Exact published config path of the package. |
| `accepts: [...]` array in the 402 body | Not shipped (contradicts primary spec) | Secondary source only; the primary spec puts the challenge in `WWW-Authenticate`, not a body array. |
| `Payment-Session` header / metered `grants` at core-spec level | Out of scope / unverified | Neither term appears anywhere in `draft-ryan-httpauth-payment-01` (re-verified 2026-08-03); `grants`/`scope` ship only as `square1/laravel-mpp` features — see SKILL.md *Middleware*. |
| TLS requirement | Spec | "REQUIRES TLS 1.2 or later... Servers MUST NOT issue Payment challenges over unencrypted HTTP. Clients MUST NOT send Payment credentials over unencrypted HTTP." |
