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

> **Run it in steps, not as one mega-prompt.** These are the exact prompts
> verified on the **default agent model**. Paste **Step 1**, let the agent create
> the API and products and stop at the dry-run; confirm; then paste **Step 2**.
> Folding the whole build into a single prompt pushes a smaller model to attempt
> one oversized change and stall — one bounded ask per step keeps it reliable.
> Replace the `<<...>>` values.

**Step 1 — create the API and the tier quotas**

```text
Create a new REST API called "<<Posts API>>" and rate-limit it per app with a
product quota. This is a fresh org — I have no existing API.

Upstream: https://jsonplaceholder.typicode.com (public, returns real data).
Environment: test. Routes: GET /posts, GET /posts/{postId} (paths match the
upstream, no rewrite). Confirm the route has a service_id.

Identify the caller with helix-auth validate, validate_auth_type key-auth, reading
the credential key from the "apikey" header (key-auth is a value of helix-auth,
not a standalone plugin — I want the product subscription resolved).

Create two products, each with a quota: Free 5/min and Pro 1000/min. Every product
must carry a quota object (a product without one is a 403, not "unlimited"). Deploy
both to test. Add api-product-enforcer with error_policy fail_close — the product
quota IS the rate limiter; do not add any other limiter or key anything on
consumer_name. Do not put Redis settings in the enforcer.

Check get_plugin_config for each plugin before writing config. Show me the spec,
dry-run it, and wait for me to confirm before deploying.
```

**Step 2 — two apps that prove the limit is per-app** (same session)

```text
Create a test developer with TWO SEPARATE APPS — one subscribed to Free, one to Pro
— and give me both keys. They must be different apps: two keys on the same app
share one quota bucket and would not prove isolation.

Then give me a curl loop showing the Free app getting 429 after 5 requests while
the Pro app still gets 200s with real data in the same window.
```

The agent creates the API and products, proposes the spec, and stops for your
confirmation. See [AGENT-GUIDE.md](../../AGENT-GUIDE.md) for what to say if the
agent reaches for a `limit-count` on `consumer_name` — the generic reflex this
platform doesn't use.

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
