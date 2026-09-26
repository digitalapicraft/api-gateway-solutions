# Install — Solution 01 — API Products: sell tiers you can actually enforce

[Overview](readme.md) · [Business need](business-need.md) · [How it works](how-it-works.md) · **Install** · [Configuration](configuration.md) · [Test & verify](testing.md) · [Changelog](changelog.md)

---

## Build it with the Helix Agent

Recommended path, and it works on a **fresh org**. Two steps — paste the first,
confirm, then the second. Full prompt with the reasoning, tweak knobs and failure
modes: [`helix-agent-prompt.md`](helix-agent-prompt.md).

```text
Create a REST API "<<Posts API>>" on upstream https://jsonplaceholder.typicode.com,
environment test, with routes GET /posts and GET /posts/{postId} proxied straight
through. Fresh org — nothing exists yet. Confirm the route has a service_id.

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

Then the part that makes it demonstrable:

```text
Create a developer with TWO SEPARATE apps, one subscribed to Free and one to Pro,
and give me both keys. Two keys on one app share a bucket and would prove nothing.

Then give me a curl loop showing the Free app getting 429 after 5 requests while
the Pro app still gets 200s in the same window.
```

See [AGENT-GUIDE.md](../../AGENT-GUIDE.md) for what to say if the agent reaches
for a `limit-count` on `consumer_name` — the generic reflex this platform doesn't
use.

## Install it directly

```bash
export ORG=<ORG_ID>
export TOKEN=<control-plane bearer token>      # short-lived
export BASE=https://<YOUR_GATEWAY_HOST>/api
H=(-H "authorization: Bearer $TOKEN" -H 'content-type: application/json')

# 1. Import gateway/api-spec.yaml (OpenAPI import, or Agent Mode). It carries
#    helix-auth + api-product-enforcer. Bind the upstream
#    https://jsonplaceholder.typicode.com (swap in your own later). CONFIRM THE
#    ROUTE HAS A service_id — without one the enforcer 403s regardless of
#    subscription (import assigns one automatically).

# 2. Create the products, then deploy each one to the environment.
jq -c '.products[]' gateway/products.json | while read -r p; do
  curl -s "${H[@]}" -X POST "$BASE/orgs/$ORG/products" -d "$p" | jq -r '.id // .message'
done
curl -s "${H[@]}" -X POST "$BASE/orgs/$ORG/envs/<TEST_ENV_ID>/products/<PRODUCT_ID>/deploy"   # test env

# 3. Create a developer, then TWO apps, each subscribing to one product
#    (products is a {productId: rank} map). Keep both app keys.

# 4. If the gateway runs more than one node, set quota_policy to redis in
#    plugin_attr.api-product-enforcer in the gateway's config.yaml. This is NOT
#    in the route config and nothing here will remind you.

# 5. Prove it — including isolation
GATEWAY=https://<YOUR_GATEWAY_HOST> \
FREE_KEY=<free app client id> PRO_KEY=<pro app client id> FREE_LIMIT=5 \
./gateway/verify.sh          # defaults to /posts
```

> Revisions must be **INACTIVE** to accept a spec change. If it's live: undeploy
> first, or clone the revision so you keep a rollback target.

## Step 1 — the API and the tier quotas

```text
Create a REST API "<<Posts API>>" on upstream https://jsonplaceholder.typicode.com,
environment test, with routes GET /posts and GET /posts/{postId} proxied straight
through. Fresh org — nothing exists yet. Confirm the route has a service_id.

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

## Step 2 — two apps that prove the isolation

```text
Create a developer with TWO SEPARATE apps, one subscribed to Free and one to Pro,
and give me both keys. Two keys on one app share a bucket and would prove nothing.

Then give me a curl loop showing the Free app getting 429 after 5 requests while
the Pro app still gets 200s in the same window.
```

---

## Why it's shaped this way

- **`helix-auth`, not a bare key check.** `key-auth` is a `validate_auth_type` of
  `helix-auth` here, not a standalone plugin. A bare key check authenticates but
  resolves no subscription, so the enforcer 403s everything.
- **Every product carries a quota.** No quota object is a 403. Unlimited is `-1`.
- **Two separate apps.** Quota is counted per app (the credential). Two keys on one
  app share a bucket and make correct isolation look broken.
- **No Redis on the enforcer.** It accepts `error_policy` and `ctx_namespace` only.
  The quota backend lives in `plugin_attr`, and on more than one node it must be
  redis or each node counts separately.
- **Read the revision back.** Three of the four known agent-mode defects report
  success at every step the agent shows you; the read-back is what catches them.

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
(That's [solution 02](../02-oauth-jwt/) composed with this one.)

## When it goes wrong

| Symptom | Cause |
|---|---|
| Everything 403s | The app isn't subscribed to a product covering this API, the route has no `service_id`, or a bare key check replaced `helix-auth`. Ask for `get_app` and check the products map. |
| Everything 401s | You're sending the app's secret where its key (client id) belongs. |
| No 429 ever arrives | The quota is higher than you think, or `quota_policy` is `local` on a multi-node gateway. |
| Both apps 429 | They aren't two separate apps, or they share a product. |
| The agent adds a `limit-count`, or keys on `consumer_name` | Reply: rate limiting is the product quota, counted per app — remove that limiter. |
| The agent puts `policy: redis` on the enforcer | Reply: not in its schema — the quota backend is in `plugin_attr`, not on the route. |

## Related

- **[Solution 02 — OAuth 2.0 with JWT](../02-oauth-jwt/install.md)** —
  swap the static key for a token flow; keep the quota behind it.
- **[Solution 04 — Analytics](../04-analytics/charts.md)** — see who is
  approaching a limit and who got 429s.
