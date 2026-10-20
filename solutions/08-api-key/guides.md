# Guides — API-key identity at the edge

> [Overview](README.md) · [Business need](business-need.md) · [Architecture](architecture.md) · **Guides** · [Agent prompt](helix-agent-prompt.md) · [Tests](tests.md) · [API reference](api-reference.md)

---

Three ways to build the same thing, then how to see it work. Whichever way you
pick, the result is one API with two routes (`GET /fleet/price-list` and
`POST /fleet/takings`) that only accept a known app's key in the `X-Device-Key`
header, plus a product, a developer and one app whose key you test with.

## Pick your path

| | Choose this if you… | Go to |
|---|---|---|
| **1. Helix Agent** | want the quickest result and are happy to paste a prompt | [Build it with the Helix Agent](#build-it-with-the-helix-agent) |
| **2. Helix control plane** | prefer clicking through screens and want to see every setting | [Build it in the UI](#build-it-in-the-ui) |
| **3. API script** | are scripting this, or wiring it into a pipeline | [Install it directly](#install-it-directly) |

Then, for everyone: [See it work](#see-it-work) · [Variations](#variations) ·
[Configuration reference](#configuration-reference) · [Troubleshooting](#troubleshooting)

## Build it with the Helix Agent

Works on a **fresh org**. [`helix-agent-prompt.md`](helix-agent-prompt.md) has two
steps: Step 1 creates and protects the API, Step 2 issues a key and gives you the
calls that test it. **Paste one step at a time and confirm between them**, in the
same chat.

See [AGENT-GUIDE.md](../../AGENT-GUIDE.md) for the ground rules these prompts
assume.

## Build it in the UI

Screen and button names below are the real ones. The API lives under
**API Gateway** in the left sidebar; developers, products and apps live under
**API Distribution**.

**Before you start:**

- **You have an account.** If you don't, register for a free trial at
  [trial.digitalapi.ai](https://trial.digitalapi.ai/). A new trial org comes with
  a `test` environment, which is all this walkthrough needs.
- **You can create APIs, products and apps.** If you don't see an **Add API**,
  **Add API Product** or **Add App** button, ask your org admin.

**1. Create the API**

Pick one of the two ways below. Both give you the same thing: an API called
`Terminal API` with two routes and no plugins yet.

*Option A — from scratch*
1. Go to **API Gateway → APIs**, click **Add API** (or **Create your first API**).
2. Choose **Create from scratch**. Set **Display name** to `Terminal API`, then
   **Save**.
3. On the API's page, open **Configuration → Routes** and add two routes:
   - `GET /fleet/price-list`, where a terminal fetches its price list
   - `POST /fleet/takings`, where a terminal sends in its takings

*Option B — from an OpenAPI spec*
1. Go to **API Gateway → APIs**, click **Add API** (or **Create your first API**).
2. Set **Method** to **Import an OpenAPI spec**.
3. Drag in your own OpenAPI 3.0 file, or use our example,
   [`example/api-spec-basic.yaml`](example/api-spec-basic.yaml): the same two
   routes, no plugins. Then click **Import**.

> **A spec can carry the plugins too.** Add an `x-helix-gateway` block that
> lists them. At the top level of the file it covers every route; under one
> path and method it covers that route only:
>
> ```yaml
> paths:
>   /fleet/price-list:
>     get:
>       x-helix-gateway:
>         plugins:
>           helix-auth:
>             mode: validate
>             validate_auth_type: key-auth
>             apikey: { source: header, key: X-Device-Key }
> ```
>
> [`example/api-spec.yaml`](example/api-spec.yaml) is this API with all its
> plugins already in place, on both routes. It contains no key and no secret.
> Import that instead and you can skip step 2.

Either way, the API is not live yet: it has no upstream and isn't deployed.
That comes in step 3.

**2. Add the plugins**

Two plugins go on each route: one checks the caller's key, the other points the
route at the right path on your backend. Add them **before** you deploy: a live
revision can't be changed.

On the API's page, open **Configuration → Plugins** and click **Configure
plugin**. A short wizard opens:

1. **Plugin** — pick the plugin from the catalog.
2. **Scope** — **Entire Revision** applies it to every route; **Specific
   endpoint** applies it to one route.
3. **Configure** — the JSON editor and the Properties list sit side by side.
   Paste the JSON below, or fill in the fields. Then **Next**.
4. **Review** — shows the configuration before and after. Click **Apply**.

Every plugin below goes on **Specific endpoint**, so run the wizard once per
plugin per route: four times in all, picking the route named below each time.

1. **`helix-auth` — checks the caller's key.** It reads the key from the
   `X-Device-Key` header and looks up which app it belongs to. No key, or a key
   that belongs to no app, gets HTTP 401 (not authenticated) and never reaches
   your backend. Add it with the same settings to **both** routes,
   `GET /fleet/price-list` and `POST /fleet/takings`.

   | Field | Value |
   |---|---|
   | **mode** | `validate` |
   | **validate_auth_type** | `key-auth` |
   | **apikey → source** | `header` |
   | **apikey → key** | `X-Device-Key` |

   ```json
   {"mode":"validate","validate_auth_type":"key-auth","apikey":{"source":"header","key":"X-Device-Key"}}
   ```

   Fill in **apikey → source** even if the Properties list shows it as
   optional. Without it
   the deploy is refused.

   There is **no key to type in here**. The keys live on the apps you create in
   step 7.

2. **`proxy-rewrite` — sends the call to the right backend path.** The path a
   terminal calls stays fixed; this changes only the path the gateway forwards
   to. Each route gets its own value:

   | Route | **uri** |
   |---|---|
   | `GET /fleet/price-list` | `/todos/1` |
   | `POST /fleet/takings` | `/posts` |

   On `GET /fleet/price-list`:

   ```json
   {"uri":"/todos/1"}
   ```

   On `POST /fleet/takings`:

   ```json
   {"uri":"/posts"}
   ```

   These paths suit the example backend, `jsonplaceholder.typicode.com`. With
   your own backend, use its paths instead.

Repeat until both routes carry both plugins. What every field means, and the
optional
extra (`request-id`) the full spec adds:
[Configuration reference](#configuration-reference).

**3. Give it an upstream, then deploy it**
1. Go to **API Gateway → Upstreams → Add Upstream**. Name it, pick environment
   `test`, point it at `jsonplaceholder.typicode.com` (or your own host), then
   **Create Upstream**.
2. Back on the API's page, click **Deploy** on the revision. The dialog asks you
   to map an upstream for `test`. Pick the one you just created, then **Deploy**.

**4. Create a product**
1. Go to **API Distribution → API Products**, click **Add API Product**.
2. Under **Basic Information**, set a **Display Name**, for example `Terminal API`.
3. Under **APIs**, click **Add API**, select your API, then **Continue**.
4. Under **Authentication Methods**, leave it blank. It defaults to `helix-auth`,
   which is what this solution uses.
5. Under **Quota**, make sure **Enable request quota** is on. It is by default,
   set to 1000 per 1 hour, so don't click the switch: that turns the quota off.
   Every product needs one, but this solution does not enforce it, so the
   default is fine; raise **Request limit** if you want a more generous one.
6. Leave **Quota scope** on **App level**, so every app gets its own allowance.
7. Click **Create API Product**.

**5. Deploy the product**
On the product's page, click **Deploy**, pick `test`, then **Deploy** again. This
is a different deploy from step 3. The product needs its own; creating it is
not enough.

**6. Create a developer**
Go to **API Distribution → Developers**, click **Add Developer**, fill in the
name and email, then **Add**.

**7. Create one app per caller**
Go to **API Distribution → Apps**, click **Add App**. Pick the **Environment**
and the **Developer**, add the product, pick an authentication method and let
credentials auto-generate, then **Create App**. Repeat for every device or
partner job: **one app each**, so each can be switched off on its own.

**8. Get each app's key**
On each app's **Overview** tab, find the **Authentication** card. It shows
`helix-auth` with a key and a secret, both hidden, each with a show and a copy
button. Copy the **key**: that's the value the caller sends in the
`X-Device-Key` header. It is the credential **key**, not the app's id and not
its secret. **Generate New Credentials**, in the same card, issues a new pair.

## Install it directly

If you'd rather script it against the control plane:

```bash
export ORG=<ORG_ID>
export TOKEN=<control-plane bearer token>      # short-lived
export BASE=https://<YOUR_GATEWAY_HOST>/api
H=(-H "authorization: Bearer $TOKEN" -H 'content-type: application/json')

# 1. Import the spec. Nothing to fill in: it contains no key and no secret.
#    Keep both ids the response returns.
curl -s -H "authorization: Bearer $TOKEN" -F "file=@example/api-spec.yaml" \
  "$BASE/orgs/$ORG/apis/from-spec"     # multipart upload, so no JSON content-type
# → {"api":{"id":"<API_ID>", ...}, "revision":{"id":"<REVISION_ID>", ...}}

# 2. Import does NOT make the routes live. Create an upstream, bind it
#    to the revision, then deploy the revision.
curl -s "${H[@]}" -X POST "$BASE/orgs/$ORG/envs/<TEST_ENV_ID>/upstreams" \
  -d '{"name":"terminal-upstream","specification":{"scheme":"https","nodes":[{"host":"jsonplaceholder.typicode.com","port":443,"weight":1}]}}'
# → {"id":"<UPSTREAM_ID>", ...}

curl -s "${H[@]}" -X PATCH "$BASE/orgs/$ORG/apis/<API_ID>/revisions/<REVISION_ID>/upstream-bindings/add" \
  -d '{"environmentUpstreams":[{"environmentId":"<TEST_ENV_ID>","upstreamId":"<UPSTREAM_ID>"}]}'
curl -s "${H[@]}" -X POST "$BASE/orgs/$ORG/apis/<API_ID>/revisions/<REVISION_ID>/deploy" \
  -d '{"environmentId":"<TEST_ENV_ID>","force":false}'

# 3. Create a product that includes this API, then deploy it. Every product needs
#    a quota object; this solution does not enforce it, so make it generous.
curl -s "${H[@]}" -X POST "$BASE/orgs/$ORG/products" \
  -d '{"name":"terminal-api","displayName":"Terminal API","apiIds":["<API_ID>"],"quota":{"limit":<GENEROUS_LIMIT>,"interval":1,"interval_unit":"minute"}}' \
  | jq -r '.id'                                              # → <PRODUCT_ID>
curl -s "${H[@]}" -X POST "$BASE/orgs/$ORG/envs/<TEST_ENV_ID>/products/<PRODUCT_ID>/deploy"

# 4. Create a developer, then ONE APP PER CALLER, subscribed to that product.
#    The control plane issues each app's key and secret.
curl -s "${H[@]}" -X POST "$BASE/orgs/$ORG/developers" \
  -d '{"firstName":"<FIRST_NAME>","lastName":"<LAST_NAME>","email":"<EMAIL>"}' \
  | jq -r '.id'                                              # → <DEVELOPER_ID>

curl -s "${H[@]}" -X POST "$BASE/orgs/$ORG/developers/<DEVELOPER_ID>/envs/<TEST_ENV_ID>/apps" \
  -d '{"name":"<TERMINAL_APP_NAME>","products":{"<PRODUCT_ID>":1},"plugins":{"helix-auth":{}}}'
```

`plugins` on an app names the auth method it authenticates with, and an empty
`{"helix-auth":{}}` asks the control plane to generate the key and secret, like
the UI's auto-generate option. Confirm the shape your org's build expects before
scripting this for real.

> Revisions must be **INACTIVE** to accept a spec change. An ACTIVE one returns
> `Only INACTIVE revisions can be updated`. Clone the revision (keeping the live
> one as a rollback target) or undeploy first.

The same calls without narration: [API reference](api-reference.md).

## See it work

With an app's key in hand:

```bash
KEY="<the app's credential key>"

curl -s -w "\n%{http_code}\n" "https://<YOUR_GATEWAY_HOST>/fleet/price-list"
# {"message":"Missing API key in request"}
# 401

curl -s -o /dev/null -w "%{http_code}\n" \
  "https://<YOUR_GATEWAY_HOST>/fleet/price-list" -H "X-Device-Key: $KEY"
# 200  <- the upstream's data

curl -s -w "\n%{http_code}\n" \
  "https://<YOUR_GATEWAY_HOST>/fleet/price-list" -H "X-Device-Key: 00000000-not-a-real-key"
# {"message":"Invalid API key in request"}
# 401

curl -s -o /dev/null -w "%{http_code}\n" \
  "https://<YOUR_GATEWAY_HOST>/fleet/price-list?apikey=$KEY"
# 401  <- the right key, in the wrong place
```

To run all seven checks as a script:

```bash
GATEWAY=https://<YOUR_GATEWAY_HOST> \
DEVICE_KEY=<DEVICE_API_KEY> APP_SECRET=<APP_SECRET> \
./example/verify.sh
```

Exit code 0 means the key is required, checked, and accepted only in the one
header the route names. What each check proves, plus the manual tests `verify.sh`
can't run for you (switch-off and rotation): [Tests](tests.md).

## Variations

Each of these is a follow-up prompt to paste into the same Helix Agent session
after the build.

**Your callers can only put the key in the query string.**

```text
Change apikey.source to query on both routes, keeping the name apikey. Then tell
me what that costs me: which logs the key will now appear in, and what
compensating controls you'd put on the route.
```

Use this only as a last resort. A key in a URL lands in every log it passes.

**One key per site rather than per terminal.**

```text
Create one app per SITE instead of per terminal, and tell me what I lose: which
questions I can no longer answer in an incident, and what revoking one app now
takes offline.
```

**Meter these callers.**

```text
Now meter them. The product quota is already counted per app, so set a real limit
on the product rather than adding a limit-count keyed on the caller. Show me what
a caller sees when it goes over.
```

That is [solution 01](../01-api-products/): add `api-product-enforcer` to the
routes and the product's quota becomes enforced per app.

**Move to tokens for the callers that can manage it.**

```text
Some of these callers are partner backends that CAN cache and refresh a token. Add
a second API for them using helix-auth generate + validate as in solution 02, and
leave the device API on key-auth. Don't mix the two on one route.
```

**Rotate a key without downtime.** Create a second app for the same caller, give
it the new key, confirm it returns 200, then delete the first app. Rotating one
app's key in place cuts over immediately.

## Configuration reference

Source of truth: [`example/api-spec.yaml`](example/api-spec.yaml).
[`example/api-spec-basic.yaml`](example/api-spec-basic.yaml) is the same routes
with no plugins, for adding them yourself. One block carries the whole solution,
and it is on every protected route:

```yaml
helix-auth:
  mode: validate
  validate_auth_type: key-auth
  apikey:
    source: header
    key: X-Device-Key
```

| Plugin | Field | Value here | What it means |
|---|---|---|---|
| `helix-auth` | `mode` | `validate` | Check an existing credential. (`generate`, issuing tokens, is not used here.) |
| `helix-auth` | `validate_auth_type` | `key-auth` | A mode of `helix-auth`, not a separate plugin. Finds the app the key belongs to. |
| `helix-auth` | `apikey.source` | `header` | Where the key is read from. **Required in practice**, although the schema marks it optional. `query` is allowed and a bad idea. |
| `helix-auth` | `apikey.key` | `X-Device-Key` | The header name. Any name works; it becomes part of the contract you publish to callers. |
| `proxy-rewrite` | `uri` | `/todos/1` on `GET /fleet/price-list` · `/posts` on `POST /fleet/takings` | Maps your published paths to the upstream's. Swap these when you point at your own backend. |
| `request-id` | `algorithm` / `header_name` | `uuid` / `X-Request-Id` | API-wide. Ties the gateway's record of a refusal to the backend's record of the calls that got through. |

**Read what that block does not contain.** There is no key and no secret. The
route names the *header the key arrives in*; the key itself is issued on the app
by the control plane. Unlike the signing secret in [solution 02](../02-oauth-jwt/),
there is nothing here to fill in and nothing to leak, the same as
[solution 06](../06-hmac-auth/).

**Not in the spec, on purpose:** `secret_validation` (it would let the app's
secret in as an *alternative* to the key), `cors` (devices aren't browsers), and
`api-product-enforcer` (this solution identifies callers; metering is
[solution 01](../01-api-products/)).

`helix-auth` is attached per route rather than API-wide. Both routes need it
identically, so either would work; per route keeps adding an unauthenticated
health-check route later a local change.

Placeholders in this package: `<ORG_ID>`, `<TEST_ENV_ID>`, `<API_ID>`,
`<REVISION_ID>`, `<UPSTREAM_ID>`, `<PRODUCT_ID>`, `<DEVELOPER_ID>`,
`<GENEROUS_LIMIT>`, `<DEVICE_API_KEY>`, `<APP_SECRET>`, `<YOUR_GATEWAY_HOST>`.
The spec itself has none.

Every field of every plugin: [docs.digitalapi.ai/api-gateway](https://docs.digitalapi.ai/api-gateway).

## Troubleshooting

- **The dry-run rejects the config, naming `apikey`.** `apikey.source` is missing.
  It is required on both routes even though the schema says it's optional.
- **Every request gets *Missing API key in request*.** The header on the wire is
  not the one in `apikey.key`, or the key is in the query string while `source` is
  `header`.
- **Every request gets *Invalid API key in request*.** The value is not a
  credential key. Usually the app's id or the app's secret was sent instead. This
  is the most common cause of "401 with a key I'm certain is right".
- **A valid key returns 403, not 200.** The key was recognised, but the app's
  product doesn't include this API. Add the API to the product. A product problem, not a key problem.
- **An unknown key returns 200.** The most serious failure: the route isn't
  checking keys at all and is passing everything through while looking
  configured. Read the deployed revision back.
- **A switched-off caller keeps working for a short while.** The gateway caches
  credential state. That delay is your real revocation time; measure it.
- **Turning on `secret_validation` lets a caller in with only the secret.** That
  is what it does. It is not a second factor. Turn it off.
- **Don't add `limit-count` keyed on the caller to meter these apps.** Per-caller
  metering is the product quota, counted per app. See
  [solution 01](../01-api-products/).
- **Deploy fails with `Only INACTIVE revisions can be updated`.** Clone the
  revision or undeploy, then apply.
- **A valid key returns 403, not 200.** The key was recognised, but the app's product doesn't contain this API.
- **Everything 401s with *Missing API key*.** The header on the wire isn't the one in `apikey.key`, or the key is in the query string.
- **The agent renames the routes to `/todos/1` and `/posts`.** It matched the upstream instead of rewriting to it. Keep your paths; use `proxy-rewrite`.
- **The agent reaches for a `key-auth` plugin.** It's a `validate_auth_type` of `helix-auth` here, not a plugin.
- **The agent puts a key value in the spec.** The route names the header only; the control plane issues the key on the app.
- **`create_api` fails saying the API exists.** A previous run left one behind. Use a free name.
- **You ask the agent to run `validate_route`.** It always fails on this platform, whatever the route says. Ask for `dry_run_deploy` instead.