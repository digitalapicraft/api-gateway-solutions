# Guides — API Products with enforced quota

> [Overview](README.md) · [Business need](business-need.md) · [Architecture](architecture.md) · **Guides** · [Examples](examples.md) · [Agent prompt](helix-agent-prompt.md) · [Tests](tests.md) · [Configuration reference](configuration-reference.md) · [API reference](api-reference.md)

---

Three ways to build this, then how to test it and fix it.

## Build it with the Helix Agent

Recommended path, and it works on a **fresh org**. The whole build is **one
prompt** — [`helix-agent-prompt.md`](helix-agent-prompt.md). Paste it as a single
message and replace the `<<...>>` values.

It goes all the way: the API and its routes, key-based identity, the two tier
products with their quotas, then a developer, two apps and the loop that makes the
429 appear. It **deploys**, because step 3 cannot hand you working keys otherwise.

**If the run dies mid-way, paste the three steps one at a time instead.** This
build asks for more in a single turn than most — two products and two apps — and
on 2026-09-30 the whole prompt in one message ended the stream four times running,
while each step pasted on its own completed cleanly. That is a limit on the turn,
not on the wording: the steps are identical either way.
[AGENT-GUIDE.md](../../AGENT-GUIDE.md) carries the standing rules it assumes.

> **Check that the quota is the limiter.** The classic wrong turn here is a
> generic rate-limit plugin — `limit-count`, often keyed on a consumer name —
> sitting alongside or instead of the product quota. It looks right, meters the
> wrong thing, and silently coexists with the quota you actually sell. Read the
> stored revision back: identity and the product enforcer, and **no second
> limiter**. Then confirm each product has a `quota` object, because a product
> without one is a 403 rather than "unlimited".
>
> **And check the enforcer is actually there.** It is usually present; in a handful
> of runs it simply was not. Nothing errors when it is missing: the quota exists,
> nothing reads it, and every call succeeds. Two plugin names is the whole check,
> and they may sit on the API or on each route — either is fine here.
>
> On the agent's normal model this prompt got it right unprompted — no
> `limit-count` anywhere, both products carrying a quota at `scope: app`. On a
> small free-tier model the same prompt added `limit-count` to both routes. Neither
> run is a guarantee for yours; the check is cheap, do it anyway.

### Why the prompt is worded the way it is

It names no plugin and no field. Ask for an outcome and the agent reads the real
schemas your org ships; ask for fields and it pattern-matches them from another
gateway's documentation. Three phrasings are doing real work:

- **"Sell this API in two tiers."** Tiers are what products *are* on this
  platform, so naming the commercial shape is what gets you products with quotas
  rather than a rate-limit plugin bolted onto a route. Rate limiting here **is**
  the product quota; there is no separate limiter to reach for.
- **"Per product."** This names the thing the limit hangs off, and it is the
  phrase that most reliably produces the product enforcer rather than a quota
  sitting on a product that nothing reads. It does not need to say "per app":
  quota counts against the credential by **default**, and the stored quotas come
  back `scope: app` whether or not the prompt asks for it. Say `per developer`
  instead only if you want a developer's apps pooled into one bucket.
- **"Two separate apps."** Two keys on the *same* app share a bucket, so a demo
  built that way shows both keys throttling together and looks like a broken
  quota when it is a correct one.

### What the agent decides for you

| | The prompt says | The agent chose |
|---|---|---|
| Key header | nothing | an `apikey` header |
| Error policy | nothing | `fail_close` on the enforcer, and nothing else in its block |
| Counting scope | nothing | `scope: app` on both product quotas — the platform default, and what the isolation demo needs |
| Placement | nothing | usually identity and the enforcer **API-wide**, which is what this solution ships — but sometimes on each route instead. Across five organisations it went API-wide in four and per-route in one. **Both are correct here**, because every route is metered either way |
| Extras | nothing | `request-id` and `cors`; on a weaker model, sometimes an `OPTIONS` route |

All of that is correct here. The window is the one worth a follow-up if your
contracts are written differently — see [tier design](architecture.md#tier-design-that-works),
and the first entry under [Variations](#variations).

### Variations

Follow-ups for the same session, once the build above is standing. Same register
as the prompt — say what you want to be true, not which fields to set.

**Pool a developer's apps into one bucket**
```text
Count the quota per developer rather than per app, and tell me what that changes
about blast radius when one of their apps misbehaves.
```

**Point at my real upstream**
```text
Point this at <<https://my-backend.internal>> instead and keep the tiers as they
are. My backend's paths differ from the route paths, so rewrite them on the way
through.
```

**More tiers**
```text
Add an Enterprise tier at 10000 a minute, and an Internal tier that is unlimited
but still authenticated and attributed, so I can see its traffic.
```

**Require a token instead of a static key**
```text
Callers should exchange a client id and secret for a short-lived token instead of
sending a static key, and the tier limits should still apply behind it.
```
That's [solution 02](../02-oauth-jwt/) composed with this one.

### When the agent goes wrong

**Read the stored revision before you trust any of it.** Driven against a small
free-tier model, this prompt added `limit-count` to both routes — the wrong turn
the platform is most prone to, from a prompt that asked for nothing of the kind.
On the agent's normal model it did not. Which model is serving decides more here
than the prompt does.

| Symptom | Cause |
|---|---|
| Everything works, every call 200s, **and no 429 ever comes** | `api-product-enforcer` was never added. Identity resolves, the products exist with their quotas, the apps are subscribed — and nothing enforces any of it. This is the quietest failure in the solution: there is no error, the demo looks finished, and the quota you are selling is decorative. Check the API carries the enforcer before you believe any limit. |
| A `limit-count` on the routes, or anything keyed on a consumer name | The generic rate-limit reflex. Rate limiting here is the product quota, counted per app. Tell it to remove the limiter and enforce the tiers through the products instead. |
| Everything 403s | The app isn't subscribed to a product covering this API, the route has no `service_id`, or a bare key check replaced identity that resolves a subscription. Ask for `get_app` and check the products map is non-empty. |
| Everything 401s | You're sending the app's secret where its key (client id) belongs. |
| No 429 ever arrives | First check the enforcer is on the API at all (row 1). Then: the quota is higher than you think, or the quota backend is counting per node — see [the quota backend](configuration-reference.md#the-quota-backend-isnt-in-this-file). |
| Both apps 429 together | They aren't two separate apps, or they share a product. Two keys on one app share a bucket. |
| A product exists but every call 403s | It has no `quota` object. That is a 403, not "unlimited" — unlimited is `-1`. |
| Identity in the service spec, or on each route | Either is fine, and you will see both — this solution meters every route, so the two are equivalent. It only matters if you later add a route that must stay reachable without a key, such as a token endpoint ([solution 02](../02-oauth-jwt/)); then it has to be per-route. |

## Build it in the UI

If you'd rather click through screens than paste a prompt or run curl, here's the
same setup in the gateway's web console. Screen and button names below are the
real ones. The API itself lives under **API Gateway** in the left sidebar; the
developer/product/app screens live under **API Distribution**
(Developers, API Products, Apps).

**Before you start:**

- **You have an account.** If you don't, register for a free trial at
  [trial.digitalapi.ai](https://trial.digitalapi.ai/). A new trial org comes
  with a `test` environment, which is all this walkthrough needs.
- **You have permission to create APIs, products, and apps.** If you don't see
  an **Add API**, **Add API Product**, or **Add App** button, ask your org admin
  — these actions are permission-gated.
- **An environment exists** (e.g. `test`), and you're an **org admin** or know
  one. Environments aren't created from the API Gateway sidebar — that
  Environments screen is read-only. They're created under
  **Admin → Orgs → (your org) → Environments tab → Create environment**, which
  needs an existing Gateway to attach to. Ask your admin if you're not sure one
  exists yet.

**1. Import the API**
1. Go to **API Gateway → APIs**, then click **Add API** (or
   **Create your first API** if the list is empty).
2. Set **Method** to **Import an OpenAPI spec**.
3. Drag in [`example/api-spec.yaml`](example/api-spec.yaml) (or paste its
   contents into the editor tab instead), then click **Import**.

This creates the API and its first revision — routes and plugins included,
straight from the spec — in one step. It does **not** bind an upstream or
deploy the API to an environment, and nothing warns you if you skip that —
the routes just never go live.

**2. Give it an upstream, then deploy it**
1. Go to **API Gateway → Upstreams → Add Upstream**. Name it, pick environment
   `test`, and point it at `jsonplaceholder.typicode.com` (or your own host) —
   **Create Upstream**.
2. Back on the API's detail page, click **Deploy** on the revision. Since
   `test` has no upstream bound yet, the dialog itself asks you to map one
   inline — pick the upstream you just created, then **Deploy**.

**3. Create the Free product**
1. Go to **API Distribution → API Products**, then click **Add API Product** (or
   **Create your first product** if the list is empty).
2. Under **Basic Information**, set **Display Name** to `Free`.
3. Under **APIs**, click **Add API**, select the API you just imported, then
   **Continue**.
4. Under **Authentication Methods**, pick a method for apps to use (leave it
   blank and it silently defaults to `helix-auth`).
5. Under **Quota**, turn on **Enable request quota**, then set **Request limit**
   to `5`, **Interval** to `1`, **Unit** to `Minute`.
6. Click **Create API Product**.

**4. Deploy it**
On the product's page, click **Deploy** in the header, pick your environment
(e.g. `test`), then click **Deploy** again in the dialog. The status badge next
to the product name changes from **Not deployed** to **Deployed**. This is a
*different* deploy from step 2 — the product needs its own.

**5. Create the Pro product**
Repeat step 3 with **Display Name** `Pro` and **Request limit** `1000` (same
interval and unit), then deploy it the same way.

**6. Create a developer**
Go to **API Distribution → Developers**, click **Add Developer**, fill in
**First Name**, **Last Name**, and **Email**, then click **Add**.

**7. Create two apps for that developer**
Go to **API Distribution → Apps**, click **Add App**.
- Pick the **Environment** and the **Developer** you just created.
- Under **Products**, click **Add Product** and choose **Free**.
- Under **Authentication**, pick a method and let credentials auto-generate
  (recommended), or supply your own.
- Click **Create App**.

Repeat, subscribing the second app to **Pro** instead of Free. **This must be a
second, separate app** — not a second product added to the same app — or the
quota will be shared and isolation will look broken.

**8. Get each app's key**
On each app's detail page, open **Credentials** and use the reveal (eye) icon or
**Copy** next to the key field. That's the value you send as the `apikey` header.
(The exact field name shown depends on the authentication method you picked; for
key-auth it's the client id.)

Now call the API with each key: the Free app's calls get blocked after 5 in a
minute, while the Pro app keeps working. See [Tests](tests.md) to check this
with `verify.sh` instead of by hand.

**One gap worth knowing:** the UI doesn't currently have a field for
`quota_key_scope` (pooling a developer's apps into one shared bucket) — that's
only settable through the API or the spec today. See
[Configuration reference](configuration-reference.md).

## Install it directly

If you'd rather script it against the API than click through the UI or paste a
prompt:

```bash
export ORG=<ORG_ID>
export TOKEN=<control-plane bearer token>      # short-lived
export BASE=https://<YOUR_GATEWAY_HOST>/api
H=(-H "authorization: Bearer $TOKEN" -H 'content-type: application/json')

# 1. Import example/api-spec.yaml (OpenAPI import, or Agent Mode). It carries
#    helix-auth + api-product-enforcer. CONFIRM THE ROUTE HAS A service_id —
#    without one the enforcer 403s regardless of subscription (import assigns
#    one automatically). Keep both ids the response returns.
curl -s "${H[@]}" -F "file=@example/api-spec.yaml" "$BASE/orgs/$ORG/apis/from-spec"
# → {"api":{"id":"<API_ID>", ...}, "revision":{"id":"<REVISION_ID>", ...}}

# 2. The import does NOT bind an upstream or deploy the API — nothing fails
#    loudly if you skip this, the routes just never go live. Create an
#    upstream (note: no /api prefix on this one call, that's the platform's
#    own inconsistency), bind it to the revision, THEN deploy the revision.
#    Swap the upstream host for your own once you're past the demo.
curl -s "${H[@]}" -X POST "$BASE/orgs/$ORG/envs/<TEST_ENV_ID>/upstreams" \
  -d '{"name":"posts-upstream","specification":{"scheme":"https","nodes":[{"host":"jsonplaceholder.typicode.com","port":443,"weight":1}]}}'
# → {"id":"<UPSTREAM_ID>", ...}

curl -s "${H[@]}" -X PATCH "$BASE/orgs/$ORG/apis/<API_ID>/revisions/<REVISION_ID>/upstream-bindings/add" \
  -d '{"environmentUpstreams":[{"environmentId":"<TEST_ENV_ID>","upstreamId":"<UPSTREAM_ID>"}]}'
# Only after the bind succeeds:
curl -s "${H[@]}" -X POST "$BASE/orgs/$ORG/apis/<API_ID>/revisions/<REVISION_ID>/deploy" \
  -d '{"environmentId":"<TEST_ENV_ID>","force":false}'

# 3. Create the products, then deploy each one to the environment. This is a
#    SEPARATE deploy from the revision's above — the quota isn't enforced
#    until the product itself is deployed too. Every product needs a quota
#    object — one with none is a 403, not "unlimited".
for p in \
  '{"name":"posts-free","displayName":"Posts API — Free","apiIds":["<API_ID>"],"quota":{"limit":5,"interval":1,"interval_unit":"minute"}}' \
  '{"name":"posts-pro","displayName":"Posts API — Pro","apiIds":["<API_ID>"],"quota":{"limit":1000,"interval":1,"interval_unit":"minute"}}' \
; do
  curl -s "${H[@]}" -X POST "$BASE/orgs/$ORG/products" -d "$p" | jq -r '.id // .message'
done
curl -s "${H[@]}" -X POST "$BASE/orgs/$ORG/envs/<TEST_ENV_ID>/products/<PRODUCT_ID>/deploy"   # once per product

# 4. Create a developer, then TWO apps, each subscribing to one product
#    (products is a {productId: rank} map). Keep both app keys.
curl -s "${H[@]}" -X POST "$BASE/orgs/$ORG/developers" \
  -d '{"firstName":"<FIRST_NAME>","lastName":"<LAST_NAME>","email":"<EMAIL>"}' \
  | jq -r '.id'                                              # → <DEVELOPER_ID>

# developerId and the environment are PATH segments here, not body fields.
curl -s "${H[@]}" -X POST "$BASE/orgs/$ORG/developers/<DEVELOPER_ID>/envs/<TEST_ENV_ID>/apps" \
  -d '{"name":"<FREE_APP_NAME>","products":{"<PRODUCT_ID_FREE>":1},"plugins":{"helix-auth":{}}}'
curl -s "${H[@]}" -X POST "$BASE/orgs/$ORG/developers/<DEVELOPER_ID>/envs/<TEST_ENV_ID>/apps" \
  -d '{"name":"<PRO_APP_NAME>","products":{"<PRODUCT_ID_PRO>":1},"plugins":{"helix-auth":{}}}'
# Each response carries the app's key — keep both.

# 5. If the gateway runs more than one node, set quota_policy to redis in
#    plugin_attr.api-product-enforcer in the gateway's config.yaml. This is NOT
#    in the route config and nothing here will remind you.

# 6. Prove it — including isolation
GATEWAY=https://<YOUR_GATEWAY_HOST> \
FREE_KEY=<free app client id> PRO_KEY=<pro app client id> FREE_LIMIT=5 \
./example/verify.sh          # defaults to /posts
```

> Revisions must be **INACTIVE** to accept a spec change. If it's live: undeploy
> first, or clone the revision so you keep a rollback target.

The raw control-plane calls behind steps 1–4 are also listed in
[API reference](api-reference.md), if you want them without the narration.

## Testing your deployment

```bash
GATEWAY=https://<YOUR_GATEWAY_HOST> \
FREE_KEY=<free app client id> PRO_KEY=<pro app client id> FREE_LIMIT=5 \
./example/verify.sh          # defaults to /posts
```

Exit code 0 means the quota is enforced *and* scoped to the one offending app —
not just that a rate limit exists. Full breakdown of what each check proves, plus
the manual tests `verify.sh` can't run for you: [Tests](tests.md).

## Troubleshooting

- **Every call returns 200 and no 429 ever comes.** `api-product-enforcer` was
  never added. Identity resolves, the products exist with their quotas, the apps
  are subscribed, and nothing enforces any of it. There is no error. Check the
  deployed revision carries the enforcer before you believe any limit.
- **The quota backend isn't on the route.** On more than one node, `quota_policy`
  must be `redis` in `plugin_attr.api-product-enforcer`. The default, `local`,
  counts per node — so an N-node cluster serves roughly N times the quota you sold.
- **The route needs a `service_id`.** No service id means 403, before quota is even
  checked. Nothing in the plugin config tells you this.
- **A product with no `quota` object is a 403**, not "unlimited". Unlimited means
  `limit: -1`.
- **Use `helix-auth`, not raw `key-auth`.** `key-auth` checks the key but doesn't
  resolve a product subscription, so the enforcer 403s every request — it looks
  like a subscription problem, but it's really a plugin choice.
- **Never key a rate limit on `consumer_name`.** Here, per-caller metering is the
  product quota, counted on the credential — there's no separate limiter.
- **`fail_close` is the default**, so a quota-backend outage returns 503. If serving
  unmetered traffic is better for your business than an outage, set `fail_open`
  deliberately, and know that's the trade you're making.
- **Key-auth validate doesn't check the app's secret.** The `apikey` header carries
  the credential's **key** (its client id), not a secret. If you need proof of
  possession, use the client-credentials flow instead — [solution 02](../02-oauth-jwt/).
- **Two keys on one app share one bucket.** A test using two keys from one app will
  look like the quota is broken when it isn't.
- **Only the top-ranked covering product is checked.** If a 429 shows up sooner
  than you expected, check which product actually won — the app may be subscribed
  to something you forgot about, ranked higher.
- **Use `filter_func`, not `vars`,** for conditional route matching. `vars` is typed
  differently between the control plane and the gateway, and deploy will fail.
- **Confirm `api-product-enforcer` exists in your org** with `get_plugin_config`
  before you design around it.
