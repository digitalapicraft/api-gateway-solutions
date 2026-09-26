# Configuration — Solution 11 — the lookup every service re-implements, done once at the edge

[Overview](readme.md) · [Business need](business-need.md) · [How it works](how-it-works.md) · [Install](install.md) · **Configuration** · [Test & verify](testing.md) · [Changelog](changelog.md)

---

## `set`, never `add`

```yaml
headers:
  set:
    X-Tenant-Plan: "${ctx.helix.service_callout.tenant_plan}"
```

`set` **replaces** a header the client sent. `add` would leave the client's value
in place alongside the gateway's.

Verified: a client sending `X-Tenant-Plan: Enterprise-Unlimited` had it overwritten
with the callout's real value. With `add`, that caller would have asserted its own
plan — and this solution would have become a privilege-escalation path rather than
an enrichment one. `verify.sh` asserts it for exactly that reason.

## Failure policy is a decision, per route

The shipped spec makes opposite choices on the two routes, on purpose:

| Route | Policy | Why |
|---|---|---|
| `GET /storefront/orders` | `fail-open` | A read that proceeds without the tenant's plan is survivable. Verified: 200, and the headers absent. |
| `POST /storefront/checkout` | `fail-close` | Taking money without knowing the account's status is worse than failing. Verified: 503 with the configured message, and the backend never called. |

**Under `fail-open` the headers are absent, not empty.** Your backend must treat
them as optional and decide explicitly what to do when they are missing. A backend
that assumes the header is always present fails in a way that looks like a gateway
bug.

`log-only` is the third policy: log and continue, without even recording the error
in the context.
