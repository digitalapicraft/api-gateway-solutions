# Guides — API Products with enforced quota

> [Overview](README.md) · [Business need](business-need.md) · [Architecture](architecture.md) · **Guides** · [Agent prompt](helix-agent-prompt.md) · [Tests](tests.md) · [API reference](api-reference.md)

---

Three ways to build the same thing, then how to see it work. Whichever way you
pick, the result is one API with two pricing tiers, Free (5 requests a minute)
and Pro (1,000 a minute), and two apps that prove one tier never blocks the other.

## Pick your path

| | Choose this if you… | Go to |
|---|---|---|
| **1. Helix Agent** | want the quickest result and are happy to paste a prompt | [Build it with the Helix Agent](#build-it-with-the-helix-agent) |
| **2. Helix control plane** | prefer clicking through screens and want to see every setting | [Build it in the UI](#build-it-in-the-ui) |
| **3. API script** | are scripting this, or wiring it into a pipeline | [Install it directly](#install-it-directly) |

Then, for everyone: [See it work](#see-it-work) · [Variations](#variations) ·
[Configuration reference](#configuration-reference) · [Troubleshooting](#troubleshooting)

## Build it with the Helix Agent

The fastest path, and it works on a **fresh, empty org**. One prompt does the
whole build — the API, both tiers, the plugins, and two apps that prove
isolation. [`helix-agent-prompt.md`](helix-agent-prompt.md) has it as three
numbered steps: paste the whole thing as one message, or one step at a time if
the run ends early.

See [AGENT-GUIDE.md](../../AGENT-GUIDE.md) for the ground rules these prompts
assume.

## Build it in the UI

Screen and button names below are the real ones. The API lives under
**API Gateway** in the left sidebar; developers, products and apps live under
**API Distribution**.

**Before you start:**

- **You have an account.** If you don't, register for a free trial at
  [trial.digitalapi.ai](https://trial.digitalapi.ai/). A new trial org comes
  with a `test` environment, which is all this walkthrough needs.
- **You can create APIs, products and apps.** If you don't see an **Add API**,
  **Add API Product** or **Add App** button, ask your org admin.
- **An environment exists** (for example `test`). Environments are created under
  **Admin → Orgs → (your org) → Environments**, not from the API Gateway sidebar,
  and need a Gateway to attach to. Ask your admin if you're not sure.

**1. Import the API**
1. Go to **API Gateway → APIs**, click **Add API** (or **Create your first API**).
2. Set **Method** to **Import an OpenAPI spec**.
3. Drag in [`example/api-spec.yaml`](example/api-spec.yaml), or paste its
   contents, then click **Import**.

This creates the API and its first revision with routes and plugins included.
It does **not** bind an upstream or deploy, and nothing warns you if you skip
that. The routes just never go live.

**2. Give it an upstream, then deploy it**
1. Go to **API Gateway → Upstreams → Add Upstream**. Name it, pick environment
   `test`, point it at `jsonplaceholder.typicode.com` (or your own host), then
   **Create Upstream**.
2. Back on the API's page, click **Deploy** on the revision. The dialog asks you
   to map an upstream for `test`. Pick the one you just created, then **Deploy**.

**3. Create the Free product**
1. Go to **API Distribution → API Products**, click **Add API Product**.
2. Under **Basic Information**, set **Display Name** to `Free`.
3. Under **APIs**, click **Add API**, select your API, then **Continue**.
4. Under **Authentication Methods**, pick a method for apps to use. Left blank,
   it defaults to `helix-auth`.
5. Under **Quota**, turn on **Enable request quota**. Set **Request limit** `5`,
   **Interval** `1`, **Unit** `Minute`.
6. Click **Create API Product**.

**4. Deploy it**
On the product's page, click **Deploy**, pick `test`, then **Deploy** again. The
badge changes from **Not deployed** to **Deployed**. This is a *different* deploy
from step 2. The product needs its own.

**5. Create the Pro product**
Repeat steps 3 and 4 with **Display Name** `Pro` and **Request limit** `1000`.

**6. Create a developer**
Go to **API Distribution → Developers**, click **Add Developer**, fill in the
name and email, then **Add**.

**7. Create two apps for that developer**
Go to **API Distribution → Apps**, click **Add App**. Pick the **Environment**
and the **Developer**, add the **Free** product, pick an authentication method
and let credentials auto-generate, then **Create App**.

Repeat for a second app subscribed to **Pro**. **This must be a second, separate
app**, not a second product on the same app, or the quota will be shared and
isolation will look broken.

**8. Get each app's key**
On each app's page, open **Credentials** and copy the key. That's the value you
send as the `apikey` header. For key-auth it's the client id.

One gap worth knowing: the UI has no field for `quota_key_scope` (pooling a
developer's apps into one budget). That's only settable through the API or the
spec today. See [Variations](#variations).

## Install it directly

If you'd rather script it against the control plane:

```bash
export ORG=<ORG_ID>
export TOKEN=<control-plane bearer token>      # short-lived
export BASE=https://<YOUR_GATEWAY_HOST>/api
H=(-H "authorization: Bearer $TOKEN" -H 'content-type: application/json')

# 1. Import the spec. It carries helix-auth and api-product-enforcer, and the
#    import assigns the route a service_id. Keep both ids the response returns.
curl -s -H "authorization: Bearer $TOKEN" -F "file=@example/api-spec.yaml" \
  "$BASE/orgs/$ORG/apis/from-spec"     # multipart upload, so no JSON content-type
# → {"api":{"id":"<API_ID>", ...}, "revision":{"id":"<REVISION_ID>", ...}}

# 2. Import does NOT make the routes live. Create an upstream, bind it
#    to the revision, then deploy the revision.
curl -s "${H[@]}" -X POST "$BASE/orgs/$ORG/envs/<TEST_ENV_ID>/upstreams" \
  -d '{"name":"posts-upstream","specification":{"scheme":"https","nodes":[{"host":"jsonplaceholder.typicode.com","port":443,"weight":1}]}}'
# → {"id":"<UPSTREAM_ID>", ...}

curl -s "${H[@]}" -X PATCH "$BASE/orgs/$ORG/apis/<API_ID>/revisions/<REVISION_ID>/upstream-bindings/add" \
  -d '{"environmentUpstreams":[{"environmentId":"<TEST_ENV_ID>","upstreamId":"<UPSTREAM_ID>"}]}'
curl -s "${H[@]}" -X POST "$BASE/orgs/$ORG/apis/<API_ID>/revisions/<REVISION_ID>/deploy" \
  -d '{"environmentId":"<TEST_ENV_ID>","force":false}'

# 3. Create the products, then deploy each one. A separate deploy from step 2:
#    the quota isn't enforced until the product is deployed too. Every product
#    needs a quota object. One with none is a 403, not "unlimited".
for p in \
  '{"name":"posts-free","displayName":"Posts API — Free","apiIds":["<API_ID>"],"quota":{"limit":5,"interval":1,"interval_unit":"minute"}}' \
  '{"name":"posts-pro","displayName":"Posts API — Pro","apiIds":["<API_ID>"],"quota":{"limit":1000,"interval":1,"interval_unit":"minute"}}' \
; do
  curl -s "${H[@]}" -X POST "$BASE/orgs/$ORG/products" -d "$p" | jq -r '.id // .message'
done
curl -s "${H[@]}" -X POST "$BASE/orgs/$ORG/envs/<TEST_ENV_ID>/products/<PRODUCT_ID>/deploy"   # once per product

# 4. Create a developer, then TWO apps, each subscribed to one product
#    (products is a {productId: rank} map). developerId and the environment are
#    path segments, not body fields. Each response carries the app's key.
curl -s "${H[@]}" -X POST "$BASE/orgs/$ORG/developers" \
  -d '{"firstName":"<FIRST_NAME>","lastName":"<LAST_NAME>","email":"<EMAIL>"}' \
  | jq -r '.id'                                              # → <DEVELOPER_ID>

curl -s "${H[@]}" -X POST "$BASE/orgs/$ORG/developers/<DEVELOPER_ID>/envs/<TEST_ENV_ID>/apps" \
  -d '{"name":"<FREE_APP_NAME>","products":{"<PRODUCT_ID_FREE>":1},"plugins":{"helix-auth":{}}}'
curl -s "${H[@]}" -X POST "$BASE/orgs/$ORG/developers/<DEVELOPER_ID>/envs/<TEST_ENV_ID>/apps" \
  -d '{"name":"<PRO_APP_NAME>","products":{"<PRODUCT_ID_PRO>":1},"plugins":{"helix-auth":{}}}'

# 5. More than one gateway node? Set quota_policy to redis in
#    plugin_attr.api-product-enforcer in the gateway's config.yaml.
```

`plugins` on an app names the auth method it authenticates with, and an empty
`{"helix-auth":{}}` asks the control plane to generate the key and secret, like
the UI's auto-generate option. Confirm the shape your org's build expects before
scripting this for real.

> Revisions must be **INACTIVE** to accept a spec change. If it's live, undeploy
> first, or clone the revision so you keep a rollback target.

The same calls without narration: [API reference](api-reference.md).

## See it work

With both keys in hand, call the API six times as the Free app, then once as the
Pro app:

```bash
FREE_KEY="<free app client id>"
PRO_KEY="<pro app client id>"

for i in $(seq 1 6); do curl -s -o /dev/null -w "%{http_code}\n" \
  "https://<YOUR_GATEWAY_HOST>/posts" -H "apikey: $FREE_KEY"; done
# 200 200 200 200 200 429  <- blocked on the 6th call

curl -s -o /dev/null -w "%{http_code}\n" \
  "https://<YOUR_GATEWAY_HOST>/posts" -H "apikey: $PRO_KEY"
# 200  <- unaffected: different tier, different budget
```

The blocked call returns:

```http
HTTP/1.1 429 Too Many Requests

{"error":"quota exceeded"}
```

There is no `Retry-After` or `X-RateLimit-*` header, so publish the retry
contract (window length, backoff with jitter) in your own docs, and show
remaining quota in your developer portal or analytics instead. See
[solution 04](../04-analytics/).

To run all five checks as a script, including the isolation case:

```bash
GATEWAY=https://<YOUR_GATEWAY_HOST> \
FREE_KEY=<free app client id> PRO_KEY=<pro app client id> FREE_LIMIT=5 \
./example/verify.sh          # defaults to /posts
```

Exit code 0 means the quota is enforced *and* scoped to the one offending app,
not just that a rate limit exists. What each check proves, plus the manual tests
`verify.sh` can't run for you: [Tests](tests.md).

## Variations

**Pool a developer's apps into one budget.** Add `quota_key_scope` to a product:

```json
{"name":"posts-pro","apiIds":["<API_ID>"],
 "quota":{"limit":1000,"interval":1,"interval_unit":"minute","quota_key_scope":"developer"}}
```

Every app that developer owns now draws from the same budget. That is a
trade-off, not just a tidier default: one misbehaving app can starve the
developer's others.

**Add more tiers.** Enterprise and an unmetered Internal product are two more of
the same call. `limit: -1` means unlimited: still identified and counted in
analytics, never throttled.

```json
{"name":"posts-enterprise","apiIds":["<API_ID>"],"quota":{"limit":10000,"interval":1,"interval_unit":"minute"}}
{"name":"posts-internal","apiIds":["<API_ID>"],"quota":{"limit":-1}}
```

**Require a token instead of a static key.** Compose with
[solution 02](../02-oauth-jwt/): add `POST /oauth/token` using `helix-auth`
generate, switch the protected routes to `validate_auth_type: jwt-auth`, and
leave `api-product-enforcer` exactly as it is.

## Configuration reference

Source of truth: [`example/api-spec.yaml`](example/api-spec.yaml) for the routes
and plugins, plus the two products (Free, Pro) created in the UI or via the API.
[Install it directly](#install-it-directly) has their exact fields. Two plugins
make this a metered product:

```yaml
# identity — checks the key AND looks up the app's product subscriptions
helix-auth:
  mode: validate
  validate_auth_type: key-auth
  apikey:
    source: header
    key: apikey

# enforcement — spends one unit of the resolved product's quota per request
api-product-enforcer:
  error_policy: fail_close
```

| Plugin | Field | Value here | What it means |
|---|---|---|---|
| `helix-auth` | `mode` | `validate` | Checks an existing credential. `generate` (issuing credentials) is not used here. |
| `helix-auth` | `validate_auth_type` | `key-auth` | A mode of `helix-auth`, not a separate plugin. This is what resolves the product subscription. Plain `key-auth` does not. |
| `helix-auth` | `apikey.source` / `apikey.key` | `header` / `apikey` | Where the app's key (its client id) is read from. |
| `api-product-enforcer` | `error_policy` | `fail_close` | Reject requests if the quota store is unreachable. The only other field it accepts is `ctx_namespace`. |

The spec also carries `request-id`, so a disputed 429 has something to search on,
and `cors`, left wide open for the public demo upstream. Tighten `allow_origins`
before pointing this at your own backend.

A product's `quota` accepts `limit`, `interval`, `interval_unit` and, optionally,
`quota_key_scope` (`app` by default; `developer` pools a developer's apps into one
budget). `limit: -1` means unlimited. The quota counts requests, not cost: a cheap
read and a slow report each use one unit.

**Where the count is kept is not in this file.** `local` or `redis` is set in the
gateway's own `config.yaml`, and the default counts per node. On more than one
node, set `quota_policy: redis`. Why: [Architecture](architecture.md#where-the-quota-is-actually-counted).

Placeholders in this package: `<API_ID>`, `<PRODUCT_ID>`, `<ORG_ID>`, `<ENV_ID>`,
`<TEST_ENV_ID>`, `<YOUR_GATEWAY_HOST>`. Replace all of them before you deploy.

Every field of every plugin: [docs.digitalapi.ai — Traffic plugins](https://docs.digitalapi.ai/api-gateway/plugin-reference/plugins-traffic),
and the wider product docs at [docs.digitalapi.ai/api-gateway](https://docs.digitalapi.ai/api-gateway).

## Troubleshooting

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
