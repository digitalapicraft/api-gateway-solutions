# Guides — Public reads, protected writes

> [Overview](README.md) · [Business need](business-need.md) · [Architecture](architecture.md) · **Guides** · [Agent prompt](helix-agent-prompt.md) · [Tests](tests.md) · [API reference](api-reference.md)

---

Three ways to build the same thing, then how to see it work. Each gives you one
API with two open read routes and three write routes that need a partner's key
in `X-Api-Key`, plus a product, a developer and one partner app to test with.

## Pick your path

| | Choose this if you… | Go to |
|---|---|---|
| **1. Helix Agent** | want the quickest result and are happy to paste a prompt | [Build it with the Helix Agent](#build-it-with-the-helix-agent) |
| **2. Helix control plane** | prefer clicking through screens and want to see every setting | [Build it in the UI](#build-it-in-the-ui) |
| **3. API script** | are scripting this, or wiring it into a pipeline | [Install it directly](#install-it-directly) |

Then, for everyone: [See it work](#see-it-work) · [Variations](#variations) ·
[Configuration reference](#configuration-reference) · [Troubleshooting](#troubleshooting)

## Build it with the Helix Agent

The fastest path, and it works on a **fresh, empty org**. One prompt builds the
API, its plugins, a product, a developer and a partner app, and hands you the
app's key. [`helix-agent-prompt.md`](helix-agent-prompt.md) has it as three
steps: paste the whole thing as one message, or one step at a time if the run
ends early. The agent asks you to confirm before it deploys: answer yes.

The prompt names no plugin. It says what must be true, including that the key
check goes on the write routes and **not** on the whole API. Leave that
sentence out and the agent chooses the placement itself.

**What the agent decides for you.** The prompt leaves these open:

| Choice | What the agent picks | If you want something else |
|---|---|---|
| The path change | One rule on the whole API, `^/catalog/items(.*)$` → `/posts$1`, as in this package | Say which backend paths to use |
| The upstream | Reuses one in the environment that already points at the same host, or creates one | Name the upstream to use |
| The product's quota | None: the product has no limit | Ask for a limit; it is enforced only with the product check in [Variations](#variations) |

**Check the result before you trust it.** Open the revision's **Configuration →
Plugins** and confirm three things: `helix-auth` is on `POST`, `PUT` and
`DELETE` and **not** on the whole API; the two `GET` routes have no plugins of
their own; and the item path reads `/catalog/items/:itemId`, with a colon.
Then run [`verify.sh`](#see-it-work) with the key the agent gave you.

Ground rules for these prompts: [AGENT-GUIDE.md](../../AGENT-GUIDE.md).

## Build it in the UI

Screen and button names below are the real ones. The API lives under
**API Gateway** in the left sidebar; developers, products and apps live under
**API Distribution**.

**Before you start:**

- **You have an account.** A free trial at
  [trial.digitalapi.ai](https://trial.digitalapi.ai/) comes with a `test`
  environment, which is all this walkthrough needs.
- **You can create APIs, products and apps.** If you don't see an **Add API**,
  **Add API Product** or **Add App** button, ask your org admin.

**1. Create the API**

Pick one of the two ways below. Both give you an API called `Catalogue API`
with five routes and no plugins yet.

*Option A — from scratch*
1. Go to **API Gateway → APIs**, click **Add API** (or **Create your first API**).
2. Choose **Create from scratch**. Set **Display name** to `Catalogue API`, then
   **Create**.
3. On the API's page, open **Configuration → Routes** and add five routes:
   `GET /catalog/items`, `GET /catalog/items/:itemId`, `POST /catalog/items`,
   `PUT /catalog/items/:itemId` and `DELETE /catalog/items/:itemId`, writing
   the parameter as `:itemId`, not `{itemId}`. Clear the form's prefilled name
   (*New*) and path (`/new-route`) first.

*Option B — from an OpenAPI spec*
1. Go to **API Gateway → APIs**, click **Add API** (or **Create your first API**).
2. Set **Method** to **Import an OpenAPI spec**.
3. Drag in your own OpenAPI 3.0 file, or use our example,
   [`example/api-spec-basic.yaml`](example/api-spec-basic.yaml): the same five
   routes, no plugins. Then click **Import**.

If the name is taken, the import fails with *API with name '<name>' already
exists*: type another **Display name**, which overrides the spec's, and retry.

> **A spec can carry the plugins too.** An `x-helix-gateway` block at the top
> level of the file covers every route; under one path and method it covers that
> route only, which is where the key check goes.
> [`example/api-spec.yaml`](example/api-spec.yaml) is this API with all its
> plugins in place and no key or secret. Import that and skip step 2.

Either way, the API isn't live until step 3.

**2. Add the plugins**

Add them **before** you deploy: a live revision can't be changed. On the API's
page, open **Configuration → Plugins** and click **Configure plugin**. A short
wizard opens:

1. **Plugin** — pick the plugin from the catalog.
2. **Scope** — **Entire Revision** applies it to every route; **Specific
   endpoint** applies it to one route.
3. **Configure** — the JSON editor and the Properties list sit side by side.
   Paste the JSON below, or fill in the fields. Then **Next**.
4. **Review** — shows the configuration before and after. Click **Apply**.

**The scope is the whole lesson.** The first two plugins go on **Entire
Revision**, once each. The key check goes on **Specific endpoint**, three times,
once per write route. Never on **Entire Revision**: that would lock the reads.

1. **`proxy-rewrite` — sends every route to the right backend path.** Scope:
   **Entire Revision**. The public paths stay `/catalog/items…`; the sample
   backend serves the same data at `/posts…`. One rule covers all five routes:
   `/catalog/items` becomes `/posts`, and `/catalog/items/7` becomes `/posts/7`.
   With your own backend, change `/posts$1` to its path.

   ```json
   {"regex_uri":["^/catalog/items(.*)$","/posts$1"]}
   ```

2. **`request-id` — puts an id on every response.** Scope: **Entire Revision**.
   A partner can quote it when a write fails, so you can find the call.

   ```json
   {"algorithm":"uuid","header_name":"X-Request-Id"}
   ```

3. **`helix-auth` — the key check, on the writes only.** Scope: **Specific
   endpoint**. Add it three times, picking one route each time:
   `POST /catalog/items`, `PUT /catalog/items/:itemId` and
   `DELETE /catalog/items/:itemId`. It reads the key from the `X-Api-Key`
   header and finds the app it belongs to. No key, or a key no app has, gets
   HTTP 401 and never reaches your backend.

   ```json
   {"mode":"validate","validate_auth_type":"key-auth","apikey":{"source":"header","key":"X-Api-Key"}}
   ```

   **apikey → source** is required: until it is filled in, the wizard shows
   `apikey.source: Missing required field`. There is **no key to type in
   here**. The keys live on the apps you create in step 7.

Done: two plugins on the whole API, `helix-auth` on three routes, and nothing
of their own on the two `GET` routes.

**3. Give it an upstream, then deploy it**
1. Go to **API Gateway → Upstreams → Add Upstream**. Name it, pick environment
   `test`, and add a node at `jsonplaceholder.typicode.com`, port `443`, scheme
   HTTPS (or your own host).
2. **Pass Host** is set to **Rewrite**; check **Upstream Host** reads
   `jsonplaceholder.typicode.com`. Click **Next** through the remaining tabs,
   then **Add Upstream**.
3. Back on the API's page, click **Deploy** on the revision, map the upstream
   you just created for `test`, then click **Map & Deploy**.

**Changing it later.** A live revision can't be edited: **Clone Revision**,
change the copy, then **Force Deploy** it.

**4. Create a product**
1. Go to **API Distribution → API Products**, click **Add API Product**.
2. Set a **Display Name**, for example `Catalogue partners`.
3. Under **APIs**, click **Add API**, tick your API, then click **Add (1)**.
4. Leave **Authentication Methods** blank (it defaults to `helix-auth`) and
   **Quota** as it is: this solution doesn't enforce it.
5. Click **Create API Product**.

**5. Deploy the product**
On the product's page, click **Deploy**, pick `test`, then **Deploy** again.
This is a separate deploy from step 3. Do it before step 7: an app can only pick
products that are deployed to its environment.

**6. Create a developer**
Go to **API Distribution → Developers**, click **Add Developer**, fill in the
name and email, then **Add**.

**7. Create one app per partner**
Go to **API Distribution → Apps**, click **Add App**. Fill in **Display Name**,
for example `partner-acme`. Pick the **Environment** and the **Developer**, add
the product, let credentials auto-generate, then **Create App**. If the product
list says **No products found.**, go back to step 5. One app per partner, so
each can be switched off on its own.

**8. Get each app's key**
On the app's **Overview** tab, the **Authentication** card shows `helix-auth`
with a key and a secret, both hidden, each with a copy button. Copy the
**key**. That is what the partner sends in `X-Api-Key`.

## Install it directly

`BASE` is the API address the portal calls (it usually starts with `api-`), not
the portal page and not the gateway's address:

```bash
export ORG=<ORG_ID> ENV_ID=<TEST_ENV_ID>
export TOKEN=<control-plane bearer token>      # short-lived
export BASE=https://<YOUR_CONTROL_PLANE_API>/api
H=(-H "authorization: Bearer $TOKEN" -H 'content-type: application/json')

# 1. Import the spec. Nothing to fill in. Keep both ids the response returns.
curl -s -H "authorization: Bearer $TOKEN" -F "file=@example/api-spec.yaml" \
  "$BASE/orgs/$ORG/apis/from-spec"
# → {"api":{"id":"<API_ID>", ...}, "revision":{"id":"<REVISION_ID>", ...}}

# 2. Create an upstream, bind it to the revision, deploy the revision.
curl -s "${H[@]}" -X POST "$BASE/orgs/$ORG/envs/$ENV_ID/upstreams" \
  -d '{"name":"catalogue-upstream","specification":{"scheme":"https","pass_host":"rewrite","upstream_host":"jsonplaceholder.typicode.com","nodes":[{"host":"jsonplaceholder.typicode.com","port":443,"weight":1}]}}'
# → {"id":"<UPSTREAM_ID>", ...}
curl -s "${H[@]}" -X PATCH "$BASE/orgs/$ORG/apis/<API_ID>/revisions/<REVISION_ID>/upstream-bindings/add" \
  -d '{"environmentUpstreams":[{"environmentId":"'$ENV_ID'","upstreamId":"<UPSTREAM_ID>"}]}'
curl -s "${H[@]}" -X POST "$BASE/orgs/$ORG/apis/<API_ID>/revisions/<REVISION_ID>/deploy" \
  -d '{"environmentId":"'$ENV_ID'","force":false}'

# 3. A product with this API in it, deployed. Every product needs a quota.
curl -s "${H[@]}" -X POST "$BASE/orgs/$ORG/products" \
  -d '{"name":"catalogue-partners","displayName":"Catalogue partners","apiIds":["<API_ID>"],"quota":{"limit":<GENEROUS_LIMIT>,"interval":1,"interval_unit":"minute"}}'
# → {"id":"<PRODUCT_ID>", ...}
curl -s "${H[@]}" -X POST "$BASE/orgs/$ORG/envs/$ENV_ID/products/<PRODUCT_ID>/deploy"

# 4. A developer, then ONE APP PER PARTNER on that product. An app needs
#    displayName as well as name; {"helix-auth":{}} creates its key and secret.
curl -s "${H[@]}" -X POST "$BASE/orgs/$ORG/developers" \
  -d '{"firstName":"<FIRST_NAME>","lastName":"<LAST_NAME>","email":"<EMAIL>"}'
# → {"id":"<DEVELOPER_ID>", ...}
curl -s "${H[@]}" -X POST "$BASE/orgs/$ORG/developers/<DEVELOPER_ID>/envs/$ENV_ID/apps" \
  -d '{"name":"partner-acme","displayName":"partner-acme","products":{"<PRODUCT_ID>":1},"plugins":{"helix-auth":{}}}' \
  | jq -r '.credential.plugins["helix-auth"].key'       # → <PARTNER_API_KEY>
```

The same calls without narration: [API reference](api-reference.md).

## See it work

With a partner app's key in hand:

```bash
G=https://<YOUR_GATEWAY_HOST>

curl -s -o /dev/null -w "%{http_code}\n" $G/catalog/items          # 200, no key needed

curl -s -w "\n%{http_code}\n" -X POST $G/catalog/items \
  -H 'content-type: application/json' -d '{"title":"Trail running shoe"}'
# {"message":"Missing API key in request"}
# 401

curl -s -w "\n%{http_code}\n" -X POST $G/catalog/items -H "X-Api-Key: <PARTNER_API_KEY>" \
  -H 'content-type: application/json' -d '{"title":"Trail running shoe","price":89.5}'
# {"title": "Trail running shoe", "price": 89.5, "id": 101}
# 201
```

A key that belongs to no app gets 401 *Invalid API key in request*. The 401
bodies are JSON sent with the content type `text/plain`. To run all fourteen
checks:

```bash
GATEWAY=https://<YOUR_GATEWAY_HOST> API_KEY=<PARTNER_API_KEY> ./example/verify.sh
```

Exit code 0 means every check held. What each one proves: [Tests](tests.md).

## Variations

Make each change on a cloned revision, or ask the agent in the same session.

**Let in only the apps on this API's product.** The key check accepts a key
from any app in the environment, even one whose product doesn't include this
API. To refuse those with HTTP 403 (forbidden), add `api-product-enforcer` to
the three write routes, as in [solution 01](../01-api-products/). It also turns
on the product's quota for each partner.

```text
Only apps subscribed to this API's product may write. Apps on other products
should get a 403 on the write routes. Reads stay open to everyone.
```

**Keep the key away from your backend.** The gateway passes `X-Api-Key` on to
your backend exactly as the partner sent it, so the key can end up in your
backend's logs. Add a `headers.remove` list to the API-wide `proxy-rewrite`, as
[solution 08](../08-api-key/) does per route. The key is checked before
`proxy-rewrite` runs, so the check still works:

```json
{"regex_uri":["^/catalog/items(.*)$","/posts$1"],"headers":{"remove":["X-Api-Key"]}}
```

**Short-lived tokens instead of keys.** For partners whose systems can fetch and
refresh a token, see [solution 02](../02-oauth-jwt/). The placement doesn't
change: the check goes on the write routes only.

## Configuration reference

Source of truth: [`example/api-spec.yaml`](example/api-spec.yaml)
([`api-spec-basic.yaml`](example/api-spec-basic.yaml) has no plugins).

```yaml
# On POST /catalog/items, PUT and DELETE /catalog/items/{itemId} only.
# The two GET routes carry no plugins of their own.
helix-auth:
  mode: validate              # check a credential the caller already has
  validate_auth_type: key-auth  # a setting of helix-auth, not a separate plugin
  apikey:
    source: header            # required; query (the URL) works but ends up in logs
    key: X-Api-Key            # partners must use exactly this header name

# API-wide: the top-level x-helix-gateway block.
proxy-rewrite:
  regex_uri: ["^/catalog/items(.*)$", "/posts$1"]   # $1 = whatever follows, e.g. /7
request-id:
  algorithm: uuid
  header_name: X-Request-Id
```

**Not in the spec, on purpose:** `helix-auth` in the top-level block (it would
lock the reads), `secret_validation` (it accepts the app's secret as an
*alternative* to the key, see [solution 08](../08-api-key/)), and
`api-product-enforcer` (see [Variations](#variations)).

Placeholders (`<ORG_ID>`, `<API_ID>`, `<PARTNER_API_KEY>`, `<YOUR_GATEWAY_HOST>`
and the rest) appear only in the commands on this page. The spec itself has none.

Every field of every plugin: [docs.digitalapi.ai/api-gateway](https://docs.digitalapi.ai/api-gateway).

## Troubleshooting

- **Reads return 401 *Missing API key in request*.** The key check is on the
  whole API. In **Configuration → Plugins**, `helix-auth` must not have the
  scope **Entire Revision**. Move it to each write route with **Specific
  endpoint**, on a cloned revision. After an agent build, ask the agent to do it.
- **One write works with no key.** That route has no key check of its own.
- **`GET /catalog/items/1` returns `404 Route Not Found`.** The route was stored
  as `/catalog/items/{itemId}`. Change it to `/catalog/items/:itemId` and
  redeploy. The agent can store braces even when the prompt says `:itemId`.
- **A write with a partner's key returns *Invalid API key in request*.** The
  value is not a credential key: usually the app's secret or id was sent. Copy
  the **key** from the app's **Authentication** card.
- **A write returns *Missing API key in request* although a key was sent.** The
  key must be in the `X-Api-Key` header. Another header name, or the URL, counts
  as no key.
- **A key from an app on another product opens the writes.** That's how the key
  check works: it doesn't look at the product. See [Variations](#variations).
- **A `PUT` returns 500.** The sample backend answers 500 for a `PUT` on an id
  above 100. That is the backend, not the gateway.
- **A `HEAD` request returns 404.** The API has `GET` routes, not `HEAD` routes.
- **A partner you switched off can still read.** Expected: reads are public.
- **The agent run ends before anything is created.** Paste the three steps one
  at a time, in the same chat.
- **See what each plugin did to a call.** Start a trace session
  ([solution 16](../16-request-tracing/)): a refused write shows `helix-auth` as
  **Upstream not called**. Keys are recorded as sent, so use a test app's key.
