# Guides — Keep a supplier's API key at the gateway

> [Overview](README.md) · [Business need](business-need.md) · [Architecture](architecture.md) · **Guides** · [Agent prompt](helix-agent-prompt.md) · [Tests](tests.md) · [API reference](api-reference.md)

---

Three ways to build the same thing, then how to see it work. Whichever way you
pick, you get one API with one route, `GET /forecast`, that accepts a call only
with a known app's key in the `X-Api-Key` header (a named value sent with the
request). On the way to the supplier, the gateway adds the supplier's key in
`X-Supplier-Key` and removes `X-Api-Key`. You also get a product (a bundle of
APIs that apps sign up to), a developer (the owner of the apps), and one app (one
client) whose key you test with.

**You need the supplier's key first.** To try it with postman-echo.com, use a
made-up test value, such as `test-supplier-key`. postman-echo is public and
echoes every header back, so only a test value goes to it; the real key goes in
once the upstream points at your supplier. Never commit a real key to a
repository.

## Pick your path

| | Choose this if you… | Go to |
|---|---|---|
| **1. Helix Agent** | want the quickest result and are happy to paste a prompt | [Build it with the Helix Agent](#build-it-with-the-helix-agent) |
| **2. Helix control plane** | prefer clicking through screens and want to see every setting | [Build it in the UI](#build-it-in-the-ui) |
| **3. API script** | want to script it, or add it to an automated build pipeline | [Install it directly](#install-it-directly) |

Then, for everyone: [See it work](#see-it-work) · [Variations](#variations) ·
[Configuration reference](#configuration-reference) · [Troubleshooting](#troubleshooting)

## Build it with the Helix Agent

Works on a **new org**. [`helix-agent-prompt.md`](helix-agent-prompt.md) has one
prompt in three steps: create the API, add the key handling and deploy it, then
create the product, developer and app and hand you the app's key. Paste it as
one message. The agent asks you to confirm before it deploys: answer yes. When it
finishes, read the revision back as the prompt page says.

The supplier key you paste goes into the chat. If you'd rather it didn't, give
the agent a test value and change it afterwards (**Changing it later**, in
[step 3 of Build it in the UI](#build-it-in-the-ui)).

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
`Weather API` with one route and no plugins yet.

*Option A — from scratch*
1. Go to **API Gateway → APIs**, click **Add API** (or **Create your first API**).
2. Choose **Create from scratch**. Set **Display name** to `Weather API`, then
   **Create**.
3. On the API's page, open **Configuration → Routes** and add one route:
   `GET /forecast`, where a client asks for the forecast.

   The route form opens already filled in with the name *New* and the path
   `/new-route`. Clear both fields first, then type your own.

*Option B — from an OpenAPI spec*
1. Go to **API Gateway → APIs**, click **Add API** (or **Create your first API**).
2. Set **Method** to **Import an OpenAPI spec**.
3. Drag in your own OpenAPI 3.0 file, or use our example,
   [`example/api-spec-basic.yaml`](example/api-spec-basic.yaml): the same route,
   no plugins. Then click **Import**.

> **A spec can carry the plugins too.** Add an `x-helix-gateway` block that
> lists them. At the top level of the file it covers every route; under one
> path and method it covers that route only:
>
> ```yaml
> paths:
>   /forecast:
>     get:
>       x-helix-gateway:
>         plugins:
>           proxy-rewrite:
>             uri: /get
>             headers: { set: { X-Supplier-Key: "<SUPPLIER_API_KEY>" }, remove: [X-Api-Key] }
> ```
>
> [`example/api-spec.yaml`](example/api-spec.yaml) is this API with all its
> plugins already in place. Replace `<SUPPLIER_API_KEY>` in your copy, import
> it, and you can skip step 2.

Either way, the API is not live yet: it has no upstream and isn't deployed.
That comes in step 3.

**2. Add the plugins**

Two plugins do the job: one checks the client's key, the other swaps it for the
supplier's key. A third, optional one gives every call an id. Add them
**before** you deploy: a live revision can't be changed.

On the API's page, open **Configuration → Plugins** and click **Configure
plugin**. A short wizard opens:

1. **Plugin** — pick the plugin from the catalog.
2. **Scope** — **Entire Revision** applies it to every route; **Specific
   endpoint** applies it to one route.
3. **Configure** — the JSON editor and the Properties list sit side by side.
   Paste the JSON below, or fill in the fields. Then **Next**.
4. **Review** — shows the configuration before and after. Click **Apply**.

Run the wizard once per plugin:

1. **`helix-auth` — checks the client's own key.** Scope **Entire Revision**, so
   every route needs a key, including routes you add later. No key, or a key
   that belongs to no app, gets HTTP 401 (not authenticated) and never reaches
   the supplier.

   ```json
   {"mode":"validate","validate_auth_type":"key-auth","apikey":{"source":"header","key":"X-Api-Key"}}
   ```

   **apikey → source** is required. Until it is filled in, the wizard shows
   `apikey.source: Missing required field`. There is no key to type here: the
   keys live on the apps you create in step 6.

2. **`proxy-rewrite` — swaps the client's key for the supplier's.** Scope
   **Specific endpoint**, route `GET /forecast`. Replace `<SUPPLIER_API_KEY>`
   **before** you click **Apply**. postman-echo.com is a public test service
   that echoes every header it receives, this key included, back to the caller.
   Use a test value with it; put your real key in only after the upstream points
   at your supplier.

   ```json
   {"uri":"/get","headers":{"set":{"X-Supplier-Key":"<SUPPLIER_API_KEY>"},"remove":["X-Api-Key"]}}
   ```

   `uri` is the supplier's path (`/get` on postman-echo.com). `set` adds the
   supplier key and replaces any value a client sends in that header. `remove`
   stops the client's own key going on to the supplier. Type the key itself.
   `<ENV:SUPPLIER_KEY>` is sent as that text. `${SUPPLIER_KEY}` is read as a
   gateway variable, so no header is sent at all. If your real key contains a
   `$`, try a made-up key with a `$` in the same place against postman-echo
   first: `ab$cd` arrives as `ab`. The key is stored as plain text in the API's
   configuration.

3. **`request-id` (optional) — gives every call an id.** Scope **Entire
   Revision**. It adds an `X-Request-Id` header to every response, so a client's
   report can be matched to the gateway's record of the call.

   ```json
   {"algorithm":"uuid","header_name":"X-Request-Id"}
   ```

What every field means: [Configuration reference](#configuration-reference).

**3. Give it an upstream, then deploy it**
1. Go to **API Gateway → Upstreams → Add Upstream**. Name it, pick environment
   `test`, and add a node at `postman-echo.com`, port `443`, scheme HTTPS (or
   your supplier's host). If you switch the scheme to HTTP, the port stays at
   `443`: change it to `80` by hand.
2. **Pass Host** is set to **Rewrite**, which makes **Upstream Host** required.
   It fills in from the node's host; check it reads `postman-echo.com`.
3. Click **Next** through the remaining tabs, then **Add Upstream**.
4. Back on the API's page, click **Deploy** on the revision. The dialog asks you
   to map an upstream for `test`. Pick the one you just created, then click
   **Map & Deploy**. (The button reads **Map & Deploy** while no upstream is
   mapped yet, and **Deploy** once one is.)

**Changing it later.** A change to the upstream's host or port applies to the
live API straight away, with no new deploy. A change to its scheme does not:
undeploy the revision and deploy it again. A change to routes or plugins,
**including a new supplier key**, does need one, because a live revision can't
be edited: use **Clone Revision**, make your change on the copy, then **Force
Deploy** it. No client changes when the supplier key does. If your supplier lets
two keys work at once, switch the gateway to the new key before the old one is
retired, so there is no gap. Rolling back needs no copy: click **Deploy**, pick the older
revision (for example `r1`), and click **Force Deploy**.

**4. Create a product, and deploy it**
1. Go to **API Distribution → API Products**, click **Add API Product**, and set
   a **Display Name**, for example `Weather API`.
2. Under **APIs**, click **Add API**, tick your API, then click **Add (1)**.
   Leave **Authentication Methods** blank: it defaults to `helix-auth`.
3. Under **Quota**, leave **Enable request quota** on (don't click the switch:
   every product needs a quota). This solution doesn't enforce it, so the
   default is fine. Leave **Quota scope** on **App level**, then click
   **Create API Product**.
4. On the product's page, click **Deploy**, pick `test`, then **Deploy** again.
   This is a different deploy from step 3, and an app can only pick a product
   that is already deployed.

**5. Create a developer**
Go to **API Distribution → Developers**, click **Add Developer**, fill in the
name and email, then **Add**.

**6. Create one app per client**
Go to **API Distribution → Apps**, click **Add App**. Fill in **Display Name**,
for example `mobile-app`. Pick the **Environment** and the **Developer**, add the
product, pick an authentication method and let credentials auto-generate, then
**Create App**. If the product list says **No products found.**, the product isn't
deployed yet: go back to step 4. Repeat for each client: the mobile app, the web
app and each partner get **one app each**, so each can be switched off on its
own.

**7. Get each app's key**
On each app's **Overview** tab, find the **Authentication** card. It shows
`helix-auth` with a key and a secret, both hidden, each with a show and a copy
button. Copy the **key**: that's what the client sends in `X-Api-Key`. Not the
app's id and not its secret.

## Install it directly

To script it, call the control plane instead. `BASE` is the API address the
portal calls (it usually starts with `api-`), not the portal page and not the
gateway's address:

```bash
export ORG=<ORG_ID> ENV_ID=<TEST_ENV_ID>
export TOKEN=<control-plane bearer token>      # short-lived
export BASE=https://<YOUR_CONTROL_PLANE_API>/api
H=(-H "authorization: Bearer $TOKEN" -H 'content-type: application/json')

# 1. Put the supplier key into a local copy of the spec. Never commit the copy.
#    The upstream below is postman-echo.com, which echoes it back: type a test
#    value here, not the real key. (If the key contains |, & or \, edit the
#    copy by hand instead.)
printf 'Supplier key: '; IFS= read -rs SUPPLIER_KEY; echo
sed "s|<SUPPLIER_API_KEY>|$SUPPLIER_KEY|" example/api-spec.yaml > weather-api.local.yaml

# 2. Import it. Keep both ids the response returns. Then delete the copy.
curl -s -H "authorization: Bearer $TOKEN" -F "file=@weather-api.local.yaml" \
  "$BASE/orgs/$ORG/apis/from-spec"     # multipart upload, so no JSON content-type
# → {"api":{"id":"<API_ID>", ...}, "revision":{"id":"<REVISION_ID>", ...}}
rm weather-api.local.yaml

# 3. Create an upstream for the supplier, link it, deploy the revision.
#    pass_host + upstream_host: without them the supplier gets the gateway's
#    host name and every call returns 502.
curl -s "${H[@]}" -X POST "$BASE/orgs/$ORG/envs/$ENV_ID/upstreams" \
  -d '{"name":"weather-supplier","specification":{"scheme":"https","pass_host":"rewrite","upstream_host":"postman-echo.com","nodes":[{"host":"postman-echo.com","port":443,"weight":1}]}}'
# → {"id":"<UPSTREAM_ID>", ...}
curl -s "${H[@]}" -X PUT "$BASE/orgs/$ORG/apis/<API_ID>/revisions/<REVISION_ID>/envs/$ENV_ID/bind-upstream" \
  -d '{"upstreamId":"<UPSTREAM_ID>"}'
curl -s "${H[@]}" -X POST "$BASE/orgs/$ORG/apis/<API_ID>/revisions/<REVISION_ID>/envs/$ENV_ID/deploy" \
  -d '{"force":false}'

# 4. A product with this API, deployed. Its quota isn't enforced here.
curl -s "${H[@]}" -X POST "$BASE/orgs/$ORG/products" \
  -d '{"name":"weather-api","displayName":"Weather API","apiIds":["<API_ID>"],"quota":{"limit":10000,"interval":1,"interval_unit":"minute"}}' \
  | jq -r '.id'                                              # → <PRODUCT_ID>
curl -s "${H[@]}" -X POST "$BASE/orgs/$ORG/envs/$ENV_ID/products/<PRODUCT_ID>/deploy"

# 5. A developer, then ONE APP PER CLIENT. The response carries the app's key.
curl -s "${H[@]}" -X POST "$BASE/orgs/$ORG/developers" \
  -d '{"firstName":"<FIRST_NAME>","lastName":"<LAST_NAME>","email":"<EMAIL>"}' \
  | jq -r '.id'                                              # → <DEVELOPER_ID>
curl -s "${H[@]}" -X POST "$BASE/orgs/$ORG/developers/<DEVELOPER_ID>/envs/$ENV_ID/apps" \
  -d '{"name":"mobile-app","displayName":"mobile-app","products":{"<PRODUCT_ID>":1},"plugins":{"helix-auth":{}}}' \
  | jq -r '.credential.plugins["helix-auth"].key'           # → the app's key
```

The same calls without narration: [API reference](api-reference.md).

## See it work

With an app's key in hand, and postman-echo.com as the upstream:

```bash
KEY="<the app's key>"
GW="https://<YOUR_GATEWAY_HOST>"

curl -s "$GW/forecast?city=London" -H "X-Api-Key: $KEY" | jq '{args, headers}'
# {
#   "args": { "city": "London" },
#   "headers": {
#     "host": "postman-echo.com",
#     "x-supplier-key": "<SUPPLIER_API_KEY>",       <- the value you configured
#     "x-credential-identifier": "<APP_ID>",
#     "x-consumer-username": "<CONSUMER_ID>",
#     ...                                            <- and no x-api-key
#   }
# }
```

postman-echo.com answers with the request it received, so the `headers` above
are what the supplier saw. The two ids the gateway adds name the calling app;
see [Variations](#variations) to remove them too. Because the echo puts the
supplier key in the response body, a client of **this test setup** can read it.
A real supplier doesn't send its key back.

To run all seven checks as a script:

```bash
GATEWAY=https://<YOUR_GATEWAY_HOST> \
API_KEY=<APP_API_KEY> SUPPLIER_KEY=<SUPPLIER_API_KEY> \
./example/verify.sh
```

Exit code 0 means clients are checked with their own keys, the supplier gets only
its own key, and no client key reaches it. Run it against the echo upstream: it
reads the echoed headers. What each check proves: [Tests](tests.md).

## Variations

**Hide which app called, too.** The gateway adds `X-Consumer-Username` and
`X-Credential-Identifier` to the request. They aren't secrets, but they tell the
supplier which of your apps called. Add them to the same `remove` list:

```json
{"uri":"/get","headers":{"set":{"X-Supplier-Key":"<SUPPLIER_API_KEY>"},"remove":["X-Api-Key","X-Consumer-Username","X-Credential-Identifier"]}}
```

The key check still works: it runs before the headers are removed.

**Use your real supplier.** Change the upstream's node to the supplier's host,
and `uri` to the supplier's forecast path. If the supplier names its key header
differently, use that name in `set`. Run `verify.sh` against postman-echo.com
first, with a test value as the key, while you can still see what is sent.
Then, on a cloned revision, switch the upstream and put the real key in
together: postman-echo echoes every header it receives.

**Let in only this API's product, with a usage limit per client.** Add
`api-product-enforcer` to the route, as in [solution 01](../01-api-products/).
A key from an app on another product then gets HTTP 403 (forbidden), and an app
over its product's limit gets HTTP 429 (too many requests). That also stops one
client from using up your whole allowance with the supplier.

## Configuration reference

Source of truth: [`example/api-spec.yaml`](example/api-spec.yaml). `helix-auth`
and `request-id` cover the whole API; `proxy-rewrite` is on `GET /forecast`.

| Plugin | Field | Value here | What it means |
|---|---|---|---|
| `helix-auth` | `mode` | `validate` | Check a key the client already has. |
| `helix-auth` | `validate_auth_type` | `key-auth` | A setting of `helix-auth`, not a separate plugin. Finds the app the key belongs to. |
| `helix-auth` | `apikey.source` / `apikey.key` | `header` / `X-Api-Key` | Where the client's key is read from. **Required.** |
| `proxy-rewrite` | `uri` | `/get` | The supplier's path for this route. Query strings are passed on. |
| `proxy-rewrite` | `headers.set` | `X-Supplier-Key: <SUPPLIER_API_KEY>` | Adds the supplier's key, replacing any value a client sent. **Replace the placeholder before you deploy**: a test value while the upstream is postman-echo, the real key once it is your supplier. It is sent as written, except that a `$` starts a gateway variable. |
| `proxy-rewrite` | `headers.remove` | `[X-Api-Key]` | Stops the client's own key reaching the supplier. `helix-auth` can't do this itself. |
| `request-id` | `algorithm` / `header_name` | `uuid` / `X-Request-Id` | API-wide. An id on every response. |

`helix-auth` runs before `proxy-rewrite` (priority 2450, then 1008), so the key is
checked before it is removed. [Architecture](architecture.md#execution-order)
has the full order.

[`example/api-spec-basic.yaml`](example/api-spec-basic.yaml) is the same routes
with no plugins, for adding them yourself.

Placeholders in this package: `<SUPPLIER_API_KEY>`, `<APP_API_KEY>`,
`<ORG_ID>`, `<TEST_ENV_ID>`, `<API_ID>`, `<REVISION_ID>`, `<UPSTREAM_ID>`,
`<PRODUCT_ID>`, `<DEVELOPER_ID>`, `<YOUR_CONTROL_PLANE_API>`,
`<YOUR_GATEWAY_HOST>`. The spec has one: `<SUPPLIER_API_KEY>`.

Every field of every plugin: [docs.digitalapi.ai/api-gateway](https://docs.digitalapi.ai/api-gateway).

## Troubleshooting

- **The supplier rejects every call, often with 401 or 403.** It didn't get its
  real key. Read the deployed revision back: `X-Supplier-Key` must hold the
  literal key. `<SUPPLIER_API_KEY>` and `<ENV:...>` are sent as that text;
  `${...}` is read as a gateway variable, so no header arrives at all. The Helix
  Agent can write such a reference on its own, so check after every agent build.
- **The supplier rejects a key that contains `$`.** The gateway reads `$` and
  the letters after it as a variable, so `ab$cd` arrives as `ab`. To see it,
  run `verify.sh` against postman-echo with a made-up key of the same shape:
  case 4 shows the value received. Never send the real key there.
- **The supplier's logs show your clients' keys.** `X-Api-Key` is missing from
  `remove`. Add it on every route that calls the supplier.
- ***Missing API key in request* on every call.** The key is in another header,
  or in the URL. It must be in `X-Api-Key`. ***Invalid API key in request*** means
  the value isn't an app's key: usually its id or secret was sent instead.
- **A client can see the supplier key in the response.** With postman-echo.com
  that's expected: it echoes the request. A real supplier doesn't send its key
  back.
- **A new route doesn't send the supplier key.** The key check covers the whole
  API, but `proxy-rewrite` is set per route. Give the new route its own, with the
  same `headers` block.
- **A client's own `X-Supplier-Key` reaches the supplier.** The route uses `add`
  instead of `set`. Use `set`, which replaces the client's value.
- **A key from an app on a different product gets in.** The key check doesn't
  look at products. See [Variations](#variations).
- **Use the trace inspector to see each step.** On the API's page, open the
  **Observability** tab and click **Start trace session**. It shows the headers
  each plugin changes and the request body at every stage, which is the fastest
  way to see what each plugin did to a call. A session stops after 10 requests,
  so use **Advanced: filter which requests to capture** to record only the ones
  you care about (skipped requests don't count). The list doesn't refresh by
  itself: click **Refresh**. The **Inspector** shows API keys, the supplier key
  included, and cookies in plain text, so don't share your screen or paste a
  trace into a ticket without removing them. A compressed response, which
  browsers always ask for, is unreadable in the **Response** tab, so call the
  API with curl to read it. The **Upstream** tab's **Total** adds connect time to
  response time, so it can be larger than the request's own total.
- **See what changed, and when, in Audit Logs.** **Observability → Audit Logs**
  lists every clone, plugin change and deploy. Its times are in your local time,
  while analytics uses UTC. Anything done with your token, including scripts and
  the Helix Agent, appears under your name.
