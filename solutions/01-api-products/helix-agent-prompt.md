# Agent-mode prompt — rate limiting with an API Product quota

> [Overview](README.md) · [Business need](business-need.md) · [Architecture](architecture.md) · [Guides](guides.md) · [Examples](examples.md) · **Agent prompt** · [Tests](tests.md) · [Configuration reference](configuration-reference.md) · [API reference](api-reference.md)

---

Paste one of these into Agent Mode. Replace the `<<...>>` values with your own.

## Short

```text
Create a REST API called "<<Posts API>>" on upstream <<your upstream URL, or
https://jsonplaceholder.typicode.com>>, environment test, with helix-auth
(validate, key-auth, "apikey" header) and api-product-enforcer (fail_close) on its
routes. Create two products on it, Free at 5/min and Pro at 1000/min, and deploy
everything to test. Then create a developer with two separate apps, one on Free and
one on Pro, give me both keys, and show me a curl loop where the Free app gets 429
after 5 requests while the Pro app keeps getting 200s.
```

Filled in with real values, no placeholders: [Examples](examples.md).

## Detailed

```text
Create a REST API called "<<Posts API>>" on upstream <<your upstream URL, or
https://jsonplaceholder.typicode.com>>, environment test, with routes GET /posts
and GET /posts/{postId} proxied straight through. Fresh org — nothing exists yet.
Confirm the route has a service_id.

Identify the caller with helix-auth in validate mode, key-auth, reading the key
from an "apikey" header. I need the app's product subscription resolved, so don't
substitute a bare key check.

Create two products, each with a quota — Free 5/min and Pro 1000/min — and deploy
both to test. A product with no quota object is a 403, not "unlimited".

Put api-product-enforcer on the routes with error_policy fail_close. The product
quota IS the rate limiter: no second limiter, nothing keyed on consumer_name, and
no Redis settings on the enforcer.

Plugins go in a top-level "plugins" map on the route object, each under its own
plugin name. No "x-helix-gateway" wrapper — a live route discards it silently and
still reports success.

Show me the spec, run dry_run_deploy, then read the revision back so I can see
which plugins actually landed. Wait for my go-ahead before deploying.

Once deployed, create a developer with TWO SEPARATE apps, one subscribed to Free
and one to Pro, and give me both keys — two keys on one app would share a bucket
and prove nothing. Then give me a curl loop showing the Free app getting 429 after
5 requests while the Pro app still gets 200s in the same window.
```

## Existing API

```text
I already have an API called "<<Posts API>>" deployed to test. Add helix-auth
(validate, key-auth, reading the key from an "apikey" header) and
api-product-enforcer (error_policy fail_close) to its routes — in the route's
top-level "plugins" map, not under an "x-helix-gateway" wrapper. Show me the
spec and read the revision back before you deploy the change. Then create two
products on it, Free at 5/min and Pro at 1000/min, deploy both to test, and
create a developer with two separate apps, one per product. Give me both keys.
```

## Follow-ups

**Pool a developer's apps into one bucket**
```text
Quota should be per developer, not per app. Set quota_key_scope to developer on
each product, and tell me what that changes about blast radius.
```

**Rebind to a different upstream**
```text
Rebind the upstream to <<https://my-backend.internal>> and keep the quota as is.
Add a proxy-rewrite if my paths differ from the routes.
```

**More tiers**
```text
Add an "Enterprise" product at 10000/min and an "Internal" product at limit -1 —
unlimited, but still authenticated and attributed.
```

**Require a token instead of a static key**
```text
Callers should exchange a client id and secret for a short-lived token. Add a
POST /oauth/token with helix-auth generate, switch the protected routes to
validate with jwt-auth, and keep api-product-enforcer behind it.
```
