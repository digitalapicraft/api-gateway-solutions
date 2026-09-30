# Agent-mode prompt — rate limiting with an API Product quota

[Overview](README.md) · [Business need](business-need.md) · [Architecture](architecture.md) ·
[Guides](guides.md) · [Examples](examples.md) · **Agent prompt** ·
[Tests](tests.md) · [Configuration reference](configuration-reference.md) ·
[API reference](api-reference.md)

---

Two prompts, pasted one at a time, on a **fresh, empty org**. The first builds
the API and the two pricing tiers; the second proves one tier's limit never
touches the other's. Paste the first, confirm the result, then paste the
second — a single giant prompt pushes a smaller model into one oversized
tool call, which is where mistakes happen.

Rate limiting here **is** the product quota — a `quota` field on the product.
There's no separate rate-limit plugin to reach for. Replace the `<<...>>`
values with your own; everything else can be pasted as-is.

**No upstream of your own yet?** Use `https://jsonplaceholder.typicode.com` —
a real, public API, so the prompt still runs end to end with no backend to
wire up.

## Prompt 1 — the API and the tier quotas

```text
Create a REST API called "<<Posts API>>" on upstream <<your upstream URL — use
https://jsonplaceholder.typicode.com if you don't have one yet>>, environment
test, with routes GET /posts and GET /posts/{postId} proxied straight through.
Fresh org — nothing exists yet. Confirm the route has a service_id.

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
which plugins actually landed. Wait before deploying.
```

## Prompt 2 — two apps that prove the isolation

```text
Create a developer with TWO SEPARATE apps, one subscribed to Free and one to Pro,
and give me both keys. Two keys on one app share a bucket and would prove nothing.

Then give me a curl loop showing the Free app getting 429 after 5 requests while
the Pro app still gets 200s in the same window.
```

## Why it's shaped this way

- **`helix-auth`, not a bare key check.** A bare key check would authenticate
  the caller but not look up a subscription, so the enforcer would 403
  everything.
- **Every product carries a quota.** No quota object means a 403. Unlimited is
  written as `-1`.
- **Two separate apps.** Quota is counted per app. Two keys on one app share a
  bucket, which would make correct isolation look broken.
- **No Redis on the enforcer.** It only accepts `error_policy` and
  `ctx_namespace`. The quota backend lives elsewhere — see
  [Configuration reference](configuration-reference.md).
- **Read the revision back.** Three of the four known agent-mode defects
  report success at every step the agent shows you; the read-back is what
  actually catches them.

## Tweak knobs

**Pool a developer's apps into one bucket**
```text
Quota should be per developer, not per app. Set quota_key_scope to developer on
each product, and tell me what that changes about blast radius.
```

**Point at my real upstream**
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
(That's [solution 02](../02-oauth-jwt/) combined with this one.)

## When it goes wrong

| Symptom | Likely cause |
|---|---|
| Everything 403s | The app isn't subscribed to a product covering this API, the route has no `service_id`, or a bare key check replaced `helix-auth`. |
| Everything 401s | You're sending the app's secret where its key (client id) belongs. |
| No 429 ever arrives | The quota is higher than you think, or `quota_policy` is `local` on a multi-node gateway. |
| Both apps 429 | They aren't actually two separate apps, or they share a product. |
| The agent adds a `limit-count`, or keys on `consumer_name` | Reply: rate limiting is the product quota, counted per app — remove that limiter. |
| The agent puts `policy: redis` on the enforcer | Reply: that's not in its schema — the quota backend belongs elsewhere, not on the route. |

## Related

- **[Solution 02 — OAuth 2.0 with JWT](../02-oauth-jwt/helix-agent-prompt.md)** —
  swap the static key for a token flow; keep the quota behind it.
- **[Solution 04 — Analytics](../04-analytics/charts.md)** — see who's approaching
  a limit and who's been getting 429s.
