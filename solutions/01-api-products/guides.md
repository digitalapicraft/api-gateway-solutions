# Guides — API Products with enforced quota

> [Overview](README.md) · [Business need](business-need.md) · [Architecture](architecture.md) · **Guides** · [Examples](examples.md) · [Agent prompt](helix-agent-prompt.md) · [Tests](tests.md) · [Configuration reference](configuration-reference.md) · [API reference](api-reference.md)

---

Three ways to build this, then how to test it and fix it.

## Build it with the Helix Agent

The fastest path, and it works on a **fresh, empty org**. One prompt does the
whole build — the API, both tiers, the plugins, and two apps that prove
isolation. [`helix-agent-prompt.md`](helix-agent-prompt.md) has three
one-shot versions to pick from: a short one, a detailed one with every
guardrail spelled out, and one for adding tiers to an API you already have.

See [AGENT-GUIDE.md](../../AGENT-GUIDE.md) for the ground rules these prompts
assume.

## Build it in the UI

If you'd rather click through screens than paste a prompt or run curl, here's the
same setup in the gateway's web console. Screen and button names below are the
real ones. The API itself lives under **API Gateway** in the left sidebar; the
developer/product/app screens live under **API Distribution**
(Developers, API Products, Apps).

**Before you start:**

- **You have permission to create APIs, products, and apps.** If you don't see
  an **Add API**, **Add API Product**, or **Add App** button, ask your org admin
  — these actions are permission-gated.
- **An environment exists** (e.g. `test`), and you're an **org admin** or know
  one. Environments aren't created from the API Gateway sidebar — that
  Environments screen is read-only. They're created under
  **Admin → Orgs → (your org) → Environments tab → Create environment**, which
  needs an existing Gateway to attach to. Ask your admin if you're not sure one
  exists yet.
- **You're not on a free trial that's already at its resource limit.** Creating
  an API, product, or app is capped on some plans; the UI tells you if you've
  hit that cap.

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

Each of these has cost somebody an afternoon.

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
