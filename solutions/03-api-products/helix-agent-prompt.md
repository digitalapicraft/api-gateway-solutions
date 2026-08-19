# Agent-mode prompt — rate limiting with an API Product quota

Paste this into **Helix Agent Mode**. It works from a **fresh, empty org**: the
agent *creates* the API on a public upstream, creates the tier products, applies
`helix-auth` + `api-product-enforcer`, dry-runs, deploys, and hands you two app
keys so you can prove the limit is scoped per app.

Rate limiting here is the **product quota** — a `quota` field on the product. That
is the platform-native way to do it; there is no separate rate-limit plugin to
reach for. Replace the `<<...>>` values. Read [AGENT-GUIDE.md](../../AGENT-GUIDE.md)
first if you haven't.

---

## The prompt

```text
Create a new REST API and rate-limit it per calling app using an API Product
quota. This is a fresh org — I have no existing API, so create one.

CONTEXT
- API name: <<Posts API>>
- Upstream: https://jsonplaceholder.typicode.com   (public, returns real data with
  no backend of my own; I'll swap in my real upstream later)
- Environment: test   (my free-trial org's default)

WHAT I WANT

1. Create the API with GET /posts and GET /posts/{postId}, proxying the upstream
   (route paths match the upstream, so no path rewrite is needed). Confirm the
   route has a service_id — without one api-product-enforcer returns 403. Deploy
   to the "test" environment.

2. Identify the caller.
   Add helix-auth in validate mode with validate_auth_type key-auth, reading the
   credential key from the "apikey" header. Requests with no key or an unknown key
   must be rejected at the gateway. Use helix-auth (key-auth is one of its
   validate_auth_type values, not a standalone plugin) — I want the app's product
   subscription resolved, not just a static key checked.

3. Rate-limit via product quota.
   Create two API Products bundling this API, each with a quota:
     - "<<Posts API>> — Free"  5 requests per 1 minute
     - "<<Posts API>> — Pro"   1000 requests per 1 minute
   Every product MUST carry a quota object — a product without one is a 403, not
   "unlimited" (use limit -1 for unlimited). Deploy both products to "test".
   Add api-product-enforcer to the API with error_policy fail_close. This IS the
   rate limiter — do not add any other rate-limit plugin.

4. Add request-id (uuid, X-Request-Id) so a disputed 429 has something to search
   on, and cors allowing apikey + content-type with allow_credential false.

CONSTRAINTS — known platform behaviour
- Rate limiting is the product quota, counted per app (the credential). Do NOT key
  any limit-count on consumer_name, and do NOT add a separate rate-limit plugin —
  the product quota is the mechanism.
- Do NOT put Redis settings in api-product-enforcer — it accepts only error_policy
  and ctx_namespace. quota_policy and the Redis connection live in
  plugin_attr.api-product-enforcer in the gateway config.yaml. Tell me in your
  summary that on more than one gateway node this MUST be redis, or each node
  counts separately.
- Check get_plugin_config for each plugin before writing config. Only schema
  fields plus _meta are legal.

BEFORE YOU DEPLOY
- Show me the full spec and the products you are about to create, and wait for my
  confirmation. Run validate_route and dry_run_deploy first; on failure show me
  the error and your fix rather than retrying blindly.

AFTER YOU DEPLOY
- Create a test developer with TWO SEPARATE APPS — one subscribed to Free, one to
  Pro — and give me both app keys. They must be different apps: two keys on the
  same app share one quota bucket and would not prove isolation.
- Give me a curl loop showing the Free app getting 429 {"error":"quota exceeded"}
  after 5 requests while the Pro app still gets 200s with real data in the same
  window.
- Tell me plainly what the 429 does and does not contain (no Retry-After, no
  X-RateLimit-* headers), so I can write the developer docs.

If anything is ambiguous — the environment, the upstream, whether Redis is
configured — ask me instead of guessing.
```

---

## Why the prompt is shaped this way

| Block | Why it's there |
|---|---|
| **"This is a fresh org — create one"** | A new org has no API to meter; the agent must create it (with the public upstream so you get real data). |
| **"Environment: test"** | Free-trial orgs deploy to a default `test` environment. |
| **"Rate-limit via product quota … do not add a separate rate-limit plugin"** | The whole point: rate limiting on this platform is the product's `quota` field enforced by `api-product-enforcer`, not a generic limiter. |
| **"Use helix-auth (key-auth is a validate_auth_type, not a standalone plugin)"** | The most likely wrong turn. A bare key check resolves no product, so the enforcer 403s everything. |
| **"Every product MUST carry a quota"** | A product with no `quota` is a 403, not unlimited. `-1` is unlimited. |
| **"Confirm the route has a service_id"** | No service id → 403 before quota is even considered. Import assigns one, but confirm it. |
| **"Do NOT key on consumer_name / Do NOT put Redis in the enforcer"** | The two generic-gateway reflexes that break this. |
| **"tell me … on more than one node this MUST be redis"** | The most common silent failure — per-node counting serves N× the quota. Force it into the summary. |
| **"TWO SEPARATE APPS"** | Quota is per app; two keys on one app share a bucket and make correct isolation look broken. |

## Tweak knobs

**Pool a developer's apps into one bucket**
```text
Quota should be per developer, not per app — a customer's apps should share one
budget. Set quota_key_scope to developer on each product, and tell me what that
changes about blast radius.
```

**Point at my real upstream**
```text
Rebind the upstream to <<https://my-backend.internal>> and keep the quota exactly
as is. If my paths differ from the routes, add a proxy-rewrite; otherwise proxy
straight through.
```

**Add more tiers / unlimited internal**
```text
Add an "Enterprise" product at 10000/min and an "Internal" product with limit -1
(unlimited but still authenticated and attributed). Every product must carry a
quota object.
```

**Require a token instead of a static key**
```text
Callers should exchange a client id and secret for a short-lived token. Add a
POST /oauth/token with helix-auth generate and switch the protected routes to
validate with validate_auth_type jwt-auth, keeping api-product-enforcer behind it.
```
(That's [solution 01](../01-oauth-jwt/) composed with this one.)

## Known failure modes when running this prompt

- **The agent looks for an existing API.** Remind it: fresh org, create the API on
  the jsonplaceholder upstream.
- **Everything 403s.** The app isn't subscribed to a product covering this API, or
  the route has no service_id, or `helix-auth` wasn't used (a bare key check
  resolves no subscription). Ask the agent to `get_app` and check the products map.
- **Everything 401s.** You're sending the app's secret instead of its key (client id).
- **No 429 ever arrives.** The quota is higher than you think, or `quota_policy` is
  `local` on a multi-node gateway (each node counts separately).
- **Isolation looks broken (both apps 429).** They aren't two separate apps, or
  they share a product. Two keys on one app share a bucket.
- **The agent adds a `limit-count` or keys on `consumer_name`.** Reply: rate
  limiting is the product quota, counted per app — remove that limiter.
- **The agent adds `policy: redis` to api-product-enforcer.** Reply: that field
  isn't in the enforcer's schema — the quota backend is in plugin_attr, not on the
  route.

## Related

- **[Solution 01 — OAuth 2.0 with JWT](../01-oauth-jwt/helix-agent-prompt.md)** —
  swap the static key for a token flow; keep the quota behind it.
- **[Solution 04 — Analytics](../04-analytics/charts.md)** — see who is
  approaching a limit and who got 429s.
