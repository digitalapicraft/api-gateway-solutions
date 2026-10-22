# Guides — API keys checked at the gateway

> [Overview](README.md) · [Business need](business-need.md) · [Architecture](architecture.md) · **Guides** · [Agent prompt](helix-agent-prompt.md) · [Tests](tests.md) · [API reference](api-reference.md)

---

Three ways to build the same thing, then how to see it work. Whichever way you
pick, you get:

- one API with two routes, `GET /fleet/price-list` and `POST /fleet/takings`.
  They accept a request only if it carries a known app's key in the
  `X-Device-Key` header (a named value sent with the request);
- a product (a bundle of APIs that apps sign up to), a developer (the owner of
  the apps), and one app (one caller) whose key you test with.

## Pick your path

| | Choose this if you… | Go to |
|---|---|---|
| **1. Helix Agent** | want the quickest result and are happy to paste a prompt | [Build it with the Helix Agent](#build-it-with-the-helix-agent) |
| **2. Helix control plane** | prefer clicking through screens and want to see every setting | [Build it in the UI](#build-it-in-the-ui) |
| **3. API script** | want to script it, or add it to an automated build pipeline | [Install it directly](#install-it-directly) |

Then, for everyone: [See it work](#see-it-work) · [Variations](#variations) ·
[Configuration reference](#configuration-reference) · [Troubleshooting](#troubleshooting)

## Build it with the Helix Agent

Works on a **new org**. [`helix-agent-prompt.md`](helix-agent-prompt.md) has two
steps: Step 1 creates and protects the API, Step 2 deploys it, creates a key and
gives you the calls that test it. **Paste one step at a time and confirm between them**, in the
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
   **Create**.
3. On the API's page, open **Configuration → Routes** and add two routes:
   - `GET /fleet/price-list`, where a terminal fetches its price list
   - `POST /fleet/takings`, where a terminal sends in its takings

   The route form opens already filled in with the name *New* and the path
   `/new-route`. Clear both fields first, then type your own.

*Option B — from an OpenAPI spec*
1. Go to **API Gateway → APIs**, click **Add API** (or **Create your first API**).
2. Set **Method** to **Import an OpenAPI spec**.
3. Drag in your own OpenAPI 3.0 file, or use our example,
   [`example/api-spec-basic.yaml`](example/api-spec-basic.yaml): the same two
   routes, no plugins. Then click **Import**.

If an API with the same name already exists in your org, the import fails with
*API with name '<name>' already exists*. Type another name in the form's
**Display name** field, which overrides the name in the spec, and import again.

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
route at the right path on your backend. A third, optional one gives every
request an id. Add them **before** you deploy: a live revision can't be changed.

On the API's page, open **Configuration → Plugins** and click **Configure
plugin**. A short wizard opens:

1. **Plugin** — pick the plugin from the catalog.
2. **Scope** — **Entire Revision** applies it to every route; **Specific
   endpoint** applies it to one route.
3. **Configure** — the JSON editor and the Properties list sit side by side.
   Paste the JSON below, or fill in the fields. Then **Next**.
4. **Review** — shows the configuration before and after. Click **Apply**.

The first two plugins go on **Specific endpoint**, so run the wizard once per
plugin per route: four times, picking the route named below each time. The
third goes on **Entire Revision**, once.

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

   **apikey → source** is required. Until it is filled in, the wizard shows
   `apikey.source: Missing required field` and won't let you continue.

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
   your own backend, use its paths instead. The key in `X-Device-Key` is passed
   on to your backend as sent; to remove it, see
   [Keep the key away from your backend](#variations).

3. **`request-id` (optional) — gives every request an id.** Add it once, with
   **Entire Revision**. It adds an `X-Request-Id` header to every response, so
   you can match the gateway's record of a call with your backend's. The
   solution works without it and `verify.sh` doesn't check for it, but the
   expected result for a valid key,
   [`tests/expected/valid-200.json`](tests/expected/valid-200.json), lists its
   header.

   ```json
   {"algorithm":"uuid","header_name":"X-Request-Id"}
   ```

Repeat until both routes carry both of the first two plugins. What every field
means: [Configuration reference](#configuration-reference).

**3. Give it an upstream, then deploy it**
1. Go to **API Gateway → Upstreams → Add Upstream**. Name it, pick environment
   `test`, and add a node at `jsonplaceholder.typicode.com`, port `443`, scheme
   HTTPS (or your own host). If you switch the scheme to HTTP, the port stays at
   `443`: change it to `80` by hand.
2. **Pass Host** is set to **Rewrite**, which makes **Upstream Host** required.
   It fills in from the node's host; check it reads
   `jsonplaceholder.typicode.com`.
3. Click **Next** through the remaining tabs, then **Add Upstream**.
4. Back on the API's page, click **Deploy** on the revision. The dialog asks you
   to map an upstream for `test`. Pick the one you just created, then click
   **Map & Deploy**. (The button reads **Map & Deploy** while no upstream is
   mapped yet, and **Deploy** once one is.)

**Changing it later.** A change to the upstream (host, port, scheme) applies to
the live API straight away, with no new deploy. A change to routes or plugins
does need one, because a live revision can't be edited: use **Clone Revision**,
make your change on the copy, then **Force Deploy** it. Rolling back needs no
copy: click **Deploy**, pick the older revision (for example `r1`), and click
**Force Deploy**.

**4. Create a product**
1. Go to **API Distribution → API Products**, click **Add API Product**.
2. Under **Basic Information**, set a **Display Name**, for example `Terminal API`.
3. Under **APIs**, click **Add API**. In the **Add APIs** dialog, tick your API,
   then click **Add (1)**.
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
not enough. Do it before step 7: an app can only pick products that are already
deployed to its environment.

**6. Create a developer**
Go to **API Distribution → Developers**, click **Add Developer**, fill in the
name and email, then **Add**.

**7. Create one app per caller**
Go to **API Distribution → Apps**, click **Add App**. Fill in **Display Name**,
for example `terminal-3312`. Pick the **Environment** and the **Developer**, add
the product, pick an authentication method and let credentials auto-generate,
then **Create App**. If the product list says **No products found.**, the
product isn't deployed to that environment yet: go back to step 5. Repeat for
every device or partner job: **one app each**, so each can be switched off on
its own.

**8. Get each app's key**
On each app's **Overview** tab, find the **Authentication** card. It shows
`helix-auth` with a key and a secret, both hidden, each with a show and a copy
button. Copy the **key**: that's the value the caller sends in the
`X-Device-Key` header. It is the credential **key**, not the app's id and not
its secret. **Generate New Credentials**, in the same card, creates a new pair.

**Switching a caller off.** There are two ways, and both stop the old key
within seconds:

- **Keep the app's history: Generate New Credentials** on the app's
  **Overview** tab, in the **Authentication** card. The old key stops working,
  and the app's usage history and analytics stay.
- **Remove the app completely: Delete.** The delete dialog warns that it also
  deletes all usage history and analytics for that app.

## Install it directly

To script it, call the control plane instead. `BASE` is the API address the
portal calls (it usually starts with `api-`), not the portal page and not the
gateway's address:

```bash
export ORG=<ORG_ID>
export TOKEN=<control-plane bearer token>      # short-lived
export BASE=https://<YOUR_CONTROL_PLANE_API>/api
H=(-H "authorization: Bearer $TOKEN" -H 'content-type: application/json')

# 1. Import the spec. Nothing to fill in: it contains no key and no secret.
#    Keep both ids the response returns.
curl -s -H "authorization: Bearer $TOKEN" -F "file=@example/api-spec.yaml" \
  "$BASE/orgs/$ORG/apis/from-spec"     # multipart upload, so no JSON content-type
# → {"api":{"id":"<API_ID>", ...}, "revision":{"id":"<REVISION_ID>", ...}}

# 2. Import does NOT make the routes live. Create an upstream, bind it
#    to the revision, then deploy the revision.
# pass_host + upstream_host: without them the backend gets the gateway's host
# and every call returns 502.
curl -s "${H[@]}" -X POST "$BASE/orgs/$ORG/envs/<TEST_ENV_ID>/upstreams" \
  -d '{"name":"terminal-upstream","specification":{"scheme":"https","pass_host":"rewrite","upstream_host":"jsonplaceholder.typicode.com","nodes":[{"host":"jsonplaceholder.typicode.com","port":443,"weight":1}]}}'
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

On an app, `plugins` names the way the app proves who it is. An empty
`{"helix-auth":{}}` asks the control plane to create the key and secret, like the
UI's auto-generate option. Check the shape your org's version of the gateway
expects before you script this for real.

> A revision can only be changed while it is **INACTIVE**, meaning not deployed.
> A deployed (ACTIVE) one returns `Only INACTIVE revisions can be updated`. Clone the revision first, and keep the
> live one so you can go back to it. Or undeploy first.

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

The 401 messages are JSON, but they come back with the content type
`text/plain`. If your client only reads a JSON body when the content type says
JSON, parse the body yourself.

To run all seven checks as a script:

```bash
GATEWAY=https://<YOUR_GATEWAY_HOST> \
DEVICE_KEY=<DEVICE_API_KEY> APP_SECRET=<APP_SECRET> \
./example/verify.sh
```

Exit code 0 means the key is required, checked, and accepted only in the one
header the route names. What each check proves, plus the manual tests `verify.sh`
can't run for you (switching a caller off, and changing a key): [Tests](tests.md).

## Variations

Most of these are follow-up prompts to paste into the same Helix Agent session
after the build. The first and the last are changes you make yourself.

**Keep the key away from your backend.** The gateway passes `X-Device-Key` on
to your backend exactly as the caller sent it, so the key can end up in your
backend's logs. It also adds two headers of its own: `X-Consumer-Username` and
`X-Credential-Identifier` (the app's id, not its name). `helix-auth` has no
setting to hide the key. To remove it, add a `headers.remove` list to the
`proxy-rewrite` that each route already has. Don't add a second
`proxy-rewrite`. The key is checked before `proxy-rewrite` runs, so the check
still works.

On `GET /fleet/price-list`:

```json
{"uri":"/todos/1","headers":{"remove":["X-Device-Key"]}}
```

On `POST /fleet/takings`:

```json
{"uri":"/posts","headers":{"remove":["X-Device-Key"]}}
```

On an API that's already live, use **Clone Revision**, change `proxy-rewrite`
on both routes with the Configure plugin wizard (**Specific endpoint**), then
**Force Deploy** the copy.

**Your callers can only put the key in the query string.**

```text
Change apikey.source to query on both routes, keeping the name apikey. Then tell
me what that costs me: which logs the key will now appear in, and what
compensating controls you'd put on the route.
```

Use this only as a last resort. A key in a URL is copied into every log it passes through.

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
routes, and the product's quota (usage limit) is then enforced for each app. It
also means only apps on a product that includes this API get in; a key from any
other app gets HTTP 403 (forbidden).

**Move to tokens for the callers that can manage it.**

```text
Some of these callers are partner backends that CAN cache and refresh a token. Add
a second API for them using helix-auth generate + validate as in solution 02, and
leave the device API on key-auth. Don't mix the two on one route.
```

**Change a key without interrupting the caller.** Create a second app for the
same caller. Give the caller the new key and check it returns 200. Then delete the
first app (this also deletes that app's usage history and analytics). Giving one
app a new key in place, with **Generate New Credentials**, cuts over at once: the
old key stops working straight away.

## Configuration reference

Source of truth: [`example/api-spec.yaml`](example/api-spec.yaml).
[`example/api-spec-basic.yaml`](example/api-spec-basic.yaml) is the same routes
with no plugins, for adding them yourself. One block of settings does the whole
job, and it is on every protected route:

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
| `helix-auth` | `mode` | `validate` | Check a credential the caller already has. (`generate`, which creates tokens, is not used here.) |
| `helix-auth` | `validate_auth_type` | `key-auth` | A setting of `helix-auth`, not a separate plugin. Finds the app the key belongs to. |
| `helix-auth` | `apikey.source` | `header` | Where the key is read from. **Required.** `query` (the URL) is allowed, but is a bad idea. |
| `helix-auth` | `apikey.key` | `X-Device-Key` | The header name. Any name works. Callers must use exactly this name, so treat it as fixed once you publish it. |
| `proxy-rewrite` | `uri` | `/todos/1` on `GET /fleet/price-list` · `/posts` on `POST /fleet/takings` | Changes the path callers use into the path on the upstream (your backend). Change these values when you use your own backend. It doesn't remove `X-Device-Key`, so the key reaches your backend; see [Variations](#variations) to remove it. |
| `request-id` | `algorithm` / `header_name` | `uuid` / `X-Request-Id` | On the whole API. Gives each request an id, so you can match the gateway's log of a refused call with your backend's log of the calls that got through. |

**Notice what that block does not contain.** There is no key and no secret. The
route names the *header the key arrives in*. The key itself is created on the app
by the control plane. Unlike the signing secret in [solution 02](../02-oauth-jwt/),
there is nothing here to fill in and nothing to leak, the same as
[solution 06](../06-hmac-auth/).

**Not in the spec, on purpose:** `secret_validation` (it would accept the app's
secret as an *alternative* to the key), `cors` (lets browser pages call the API,
and devices aren't browsers), and `api-product-enforcer` (this solution
identifies callers; usage limits are [solution 01](../01-api-products/)).

`helix-auth` is added to each route, not to the whole API. Both routes need the
same settings, so either way works. Adding it per route means you can later add a
route that needs no key (a health check, for example) without changing the
others.

Placeholders in this package: `<ORG_ID>`, `<TEST_ENV_ID>`, `<API_ID>`,
`<REVISION_ID>`, `<UPSTREAM_ID>`, `<PRODUCT_ID>`, `<DEVELOPER_ID>`,
`<GENEROUS_LIMIT>`, `<DEVICE_API_KEY>`, `<APP_SECRET>`, `<YOUR_CONTROL_PLANE_API>`,
`<YOUR_GATEWAY_HOST>`.
The spec itself has none.

Every field of every plugin: [docs.digitalapi.ai/api-gateway](https://docs.digitalapi.ai/api-gateway).

## Troubleshooting

- **The wizard shows `apikey.source: Missing required field`, or the dry-run
  rejects the config naming `apikey`.** (A dry-run is a test deploy that checks
  the configuration without changing anything live.) `apikey.source` is
  missing. Set it to `header` on both routes.
- **Every request gets *Missing API key in request*.** The header in the request
  is not the one named in `apikey.key`. Or the key is in the query string while
  `source` is `header`.
- **Every request gets *Invalid API key in request*.** The value is not a
  credential key. Usually the app's id or the app's secret was sent instead. This
  is the most common cause of "401 with a key I'm certain is right".
- **A key from an app on a different product still gets in.** That's how this
  setup works: the key check only confirms the key belongs to an app in this
  environment, not which product the app is on. To let in only the apps on a
  product that includes this API, add `api-product-enforcer`
  ([solution 01](../01-api-products/)). Until then there is no HTTP 403
  (forbidden) here.
- **An unknown key returns 200.** This is the most serious failure. The route
  isn't checking keys at all. It lets everything through while looking set up.
  Read the deployed revision back.
- **A switched-off caller keeps working for a short while.** The gateway keeps a
  short-term copy of credential details (a cache). That delay is how long it
  really takes to switch a caller off. Measure it.
- **Turning on `secret_validation` lets a caller in with only the secret.** That
  is what it does, and any app's secret works, not only the caller's own. It is
  not a second check. Turn it off.
- **Your client can't read the 401 message.** The body is JSON, but the
  content type is `text/plain`. Parse the body as JSON yourself.
- **The product can't be undeployed.** Apps still subscribe to it. Remove the
  product from those apps, or delete the apps, then undeploy.
- **Your backend logs show device keys.** The gateway passes `X-Device-Key` on
  as sent. Remove it with `proxy-rewrite`: see [Variations](#variations).
- **You want to limit how often each app calls.** Don't add `limit-count` keyed
  on the caller. Usage limits for each caller come from the product quota, counted
  per app. See [solution 01](../01-api-products/).
- **Deploy fails with `Only INACTIVE revisions can be updated`.** Clone the
  revision or undeploy, then apply.
- **The agent renames the routes to `/todos/1` and `/posts`.** It copied the
  backend's paths instead of changing the forwarded path. Keep your paths, and use
  `proxy-rewrite`.
- **The agent tries to use a `key-auth` plugin.** Here it is a
  `validate_auth_type` setting of `helix-auth`, not a plugin.
- **The agent puts a key value in the spec.** The route names the header only.
  The control plane creates the key on the app.
- **`create_api` fails saying the API exists.** A previous run left one behind.
  Use a name that isn't taken.
- **You ask the agent to run `validate_route`.** It always fails on this
  platform, whatever the route says. Ask for `dry_run_deploy` instead.
- **The agent shows green ticks, but nothing was created.** It can run two
  create steps at once and report both as done when neither stored anything.
  Read the revision back, and if it's empty, paste the step again.
- **The agent panel stops responding after it creates the product.** The
  product exists but isn't deployed. Deploy it yourself, as in
  [step 5 of Build it in the UI](#build-it-in-the-ui), then carry on.
- **Use the trace inspector to see each step.** On the API's page, open the
  **Observability** tab and click **Start trace session**. It shows the headers
  each plugin changes and the request body at every stage, which is the fastest
  way to see what each plugin did to a call. A session stops after 10 requests,
  so use **Advanced: filter which requests to capture** to record only the ones
  you care about (skipped requests don't count). The list doesn't refresh by
  itself: click **Refresh**. The **Inspector** shows API keys and cookies in
  plain text, so don't share your screen or paste a trace into a ticket without
  removing them. A compressed response, which browsers always ask for, is
  unreadable in the **Response** tab, so call the API with curl to read it. The
  **Upstream** tab's **Total** adds connect time to response time, so it can be
  larger than the request's own total.
- **See what changed, and when, in Audit Logs.** **Observability → Audit Logs**
  lists every clone, plugin change and deploy. Its times are in your local time,
  while analytics uses UTC. Anything done with your token, including scripts and
  the Helix Agent, appears under your name.
