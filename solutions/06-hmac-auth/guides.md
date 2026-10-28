# Guides — HMAC request signing at the gateway

> [Overview](README.md) · [Business need](business-need.md) · [Architecture](architecture.md) · **Guides** · [Agent prompt](helix-agent-prompt.md) · [Tests](tests.md) · [API reference](api-reference.md)

---

There are three ways to build the same thing. After that, this page shows how to
see it work. Whichever way you pick, you end up with:

- one API, "Partner Albums API", with two routes that need a signature:
  `POST /albums`, whose signature also covers the body, and `GET /albums/{albumId}`
- one app, whose `key_id` and `secret_key` you sign requests with.

## Pick your path

| | Choose this if you… | Go to |
|---|---|---|
| **1. Helix Agent** | want the quickest result and are happy to paste a prompt | [Build it with the Helix Agent](#build-it-with-the-helix-agent) |
| **2. Helix control plane** | prefer clicking through the screens where you manage APIs, products and apps, and want to see every setting | [Build it in the UI](#build-it-in-the-ui) |
| **3. API script** | are scripting this, or wiring it into a pipeline | [Install it directly](#install-it-directly) |

Then, for everyone: [See it work](#see-it-work) · [Variations](#variations) ·
[Configuration reference](#configuration-reference) · [Troubleshooting](#troubleshooting)

## Build it with the Helix Agent

This works on a **new, empty org**. [`helix-agent-prompt.md`](helix-agent-prompt.md)
has three steps:

- Step 1 creates the API and its two routes.
- Step 2 makes both routes accept only signed requests.
- Step 3 creates a developer, a product and an app, and gives you the app's key id
  and secret.

Paste the whole prompt as one message. If the run ends early, paste one step at a
time instead. When it finishes, read the revision (the saved version of the API's
configuration) back. Check that each route has its own `signed_headers`. A route
without them still deploys, and is wide open. Then send one signed request, as
shown in [See it work](#see-it-work).

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
- **Your org includes `hmac-auth`.** There is no screen for this check in this
  walkthrough. Ask the Helix Agent *"confirm the hmac-auth plugin exists in this
  org"*, or use the call in [Install it directly](#install-it-directly).
- **You can create APIs, products and apps.** If you don't see an **Add API**,
  **Add API Product** or **Add App** button, ask your org admin.

**1. Create the API**

Pick one of the two ways below. Both give you the same thing: an API called
`Partner Albums API` with two routes and no plugins yet.

*Option A — from scratch*
1. Go to **API Gateway → APIs**, click **Add API** (or **Create your first API**).
2. Choose **Create from scratch**. Set **Display name** to `Partner Albums API`,
   then **Create**.
3. On the API's page, open **Configuration → Routes** and add two routes:
   - `POST /albums`, which sends in an event with a JSON body
   - `GET /albums/:albumId`, which reads one event back. The gateway writes a
     path parameter as `:albumId`, not `{albumId}`.

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
> lists them. At the top level of the file, the block covers every route. Under
> one path and method, it covers only that route. Here, signing goes on each
> route separately, because each route signs a different set of headers:
>
> ```yaml
> paths:
>   /albums:
>     post:
>       x-helix-gateway:
>         plugins:
>           hmac-auth:
>             signed_headers: ["@request-target", "date", "digest"]
>             validate_request_body: true
> ```
>
> [`example/api-spec.yaml`](example/api-spec.yaml) is this API with all its
> plugins already in place, on both routes. It contains no secret and no
> placeholder. Import that instead and you can skip step 2.

Either way, the API is not live yet. It has no upstream (the backend service the
gateway forwards requests to), and it isn't deployed. That comes in step 3.

**2. Add the plugins**

One plugin, `hmac-auth`, makes each route accept only signed requests. Add it
**before** you deploy: a live revision can't be changed.

On the API's page, open **Configuration → Plugins** and click **Configure
plugin**. A short wizard opens:

1. **Plugin** — pick the plugin from the catalog.
2. **Scope** — **Entire Revision** applies it to every route; **Specific
   endpoint** applies it to one route.
3. **Configure** — the JSON editor and the Properties list sit side by side.
   Paste the JSON below, or fill in the fields. Then **Next**.
4. **Review** — shows the configuration before and after. Click **Apply**.

`hmac-auth` goes on **each route separately**, not on the whole API, because
the two routes check different things. Run the wizard twice, choosing
**Specific endpoint** each time and picking the route named below. (**Entire
Revision** would apply one setting to every route.)

There is **no secret to type in here**. The secret lives on the app you create
in step 7, and the gateway looks it up from the key id each request carries.

1. **`hmac-auth` on `POST /albums` — checks the signature, and that the body
   wasn't changed.** The caller signs the method, the path, the `Date` header and
   a fingerprint of the body (the `Digest` header). The call gets HTTP 401 (not
   authenticated) if any of these changed on the way, or if the signature is
   missing, wrong or too old. It then never reaches your backend (the upstream).

   | Field | Value |
   |---|---|
   | **signed_headers** | `@request-target`, `date`, `digest` |
   | **validate_request_body** | `true` |
   | **clock_skew** | `300` |
   | **allowed_algorithms** | `hmac-sha256`, `hmac-sha512` |
   | **hide_credentials** | `true` |
   | **realm** | `partner-events` |

   ```json
   {"signed_headers":["@request-target","date","digest"],"validate_request_body":true,"clock_skew":300,"allowed_algorithms":["hmac-sha256","hmac-sha512"],"hide_credentials":true,"realm":"partner-events"}
   ```

2. **`hmac-auth` on `GET /albums/:albumId` — checks the signature.** A read has
   no body, so the signature covers only the method, the path and the `Date`
   header, and there is no body check.

   | Field | Value |
   |---|---|
   | **signed_headers** | `@request-target`, `date` |
   | **validate_request_body** | `false` |
   | **clock_skew** | `300` |
   | **allowed_algorithms** | `hmac-sha256`, `hmac-sha512` |
   | **hide_credentials** | `true` |
   | **realm** | `partner-events` |

   ```json
   {"signed_headers":["@request-target","date"],"validate_request_body":false,"clock_skew":300,"allowed_algorithms":["hmac-sha256","hmac-sha512"],"hide_credentials":true,"realm":"partner-events"}
   ```

Don't leave out `signed_headers` on either route. Without it, the caller decides
what its own signature covers, and the route is as good as open.

Repeat for the second route. [Configuration reference](#configuration-reference)
explains every field, and the optional extra (`request-id`) that the full spec
adds.

**3. Give it an upstream, then deploy it**
1. Go to **API Gateway → Upstreams → Add Upstream**. Name it, pick environment
   `test`, and add a node at `jsonplaceholder.typicode.com`, port `443`, scheme
   HTTPS (or your own host). If you switch the scheme to HTTP, the port stays at
   `443`: change it to `80` by hand.
2. **Pass Host** is set to **Rewrite**, which makes **Upstream Host** required.
   It fills in from the node's host. Check that it reads
   `jsonplaceholder.typicode.com`.
3. Click **Next** through the remaining tabs, then **Add Upstream**.
4. Back on the API's page, click **Deploy** on the revision. The dialog asks you
   to map an upstream for `test`. Pick the one you just created, then click
   **Map & Deploy**. (The button reads **Map & Deploy** while no upstream is
   mapped yet, and **Deploy** once one is.)

**Changing it later.** A change to the upstream's host or port applies to the
live API straight away, with no new deploy. A change to its scheme does not:
undeploy the revision and deploy it again. A change to routes or plugins does
need a new deploy, because a live revision can't be edited. Use **Clone
Revision**, make your change on the copy, then **Force Deploy** it. Rolling back
needs no copy: click **Deploy**, pick the older revision (for example `r1`), and
click **Force Deploy**.

**4. Create the product**
1. Go to **API Distribution → API Products**, click **Add API Product**.
2. Under **Basic Information**, set **Display Name** to `Partner Albums API`.
3. Under **APIs**, click **Add API**, select your API, then **Add (1)**.
4. Under **Authentication Methods**, pick **`hmac-auth`**. Left blank, it defaults
   to `helix-auth`, and the app you create in step 7 is then rejected.
5. Under **Quota**, make sure **Enable request quota** is on. It is by default,
   set to 1000 per 1 hour, so don't click the switch: that turns the quota off.
   Every product needs a quota, even though this solution does not enforce it.
   Change **Request limit** to `10000`, and keep **Interval** at `1` and **Unit**
   at **Hour**, the values in [`example/products.json`](example/products.json).
   The summary line should read *"Subscribers can make up to 10000 requests per
   1 hour"*.
6. Leave **Quota scope** on **App level**, so every app gets its own allowance.
7. Click **Create API Product**.

The product is here only because it is how an app gets a credential. Its quota is
not enforced unless you add the quota check (see [Variations](#variations)).

**5. Deploy the product**
On the product's page, click **Deploy**, pick `test`, then **Deploy** again. This
is a different deploy from step 3. The product needs its own.

**6. Create a developer**
Go to **API Distribution → Developers**, click **Add Developer**, fill in the
partner's name and email, then **Add**.

**7. Create an app for that developer**
Go to **API Distribution → Apps**, click **Add App**. Fill in **Display Name**,
for example `settlement-partner`. Pick the **Environment** and the
**Developer**, add the product, pick **`hmac-auth`** as the authentication
method and let credentials auto-generate, then **Create App**. If the product
list says **No products found.**, the product isn't deployed to that
environment yet: an app can only pick products that are. Go back to step 5.

**8. Get the `key_id` and `secret_key`**
On the app's **Overview** tab, find the **Authentication** card. It shows
`hmac-auth` with a key and a secret, both hidden, each with a show and a copy
button. The key is the `key_id` and the secret is the `secret_key`; the caller
needs both to sign. The `secret_key` is returned **once**, when the credentials
are generated, and stored encrypted after that, so copy both values then.
**Generate New Credentials**, in the same card, issues a new pair. If you don't
see the secret, create the app through
[Install it directly](#install-it-directly) instead, where it is in the create
response.

**Switching a caller off.** There are two ways, and both stop the old
credentials (the `key_id` and `secret_key`) working within seconds:

- **Keep the app's history: Generate New Credentials** on the app's
  **Overview** tab, in the **Authentication** card. The old credentials stop
  working, and the app's usage history and analytics stay.
- **Remove the app completely: Delete.** The delete dialog warns that it also
  deletes all usage history and analytics for that app.

## Install it directly

If you'd rather script it, call the control plane (where you manage APIs,
products and apps) directly. `BASE` is the API address the portal calls (it
usually starts with `api-`), not the portal page and not the gateway's address:

```bash
export ORG=<ORG_ID>
export TOKEN=<control-plane bearer token>      # short-lived
export BASE=https://<YOUR_CONTROL_PLANE_API>/api
H=(-H "authorization: Bearer $TOKEN" -H 'content-type: application/json')

# 0. Confirm hmac-auth is in your org.
curl -s "${H[@]}" "$BASE/orgs/$ORG/plugin-schemas?page=1&size=300" | grep -o '"hmac-auth"'

# 1. Import the spec. Nothing to fill in first: it has no secret and no
#    placeholder. Keep both ids the response returns.
curl -s -H "authorization: Bearer $TOKEN" -F "file=@example/api-spec.yaml" \
  "$BASE/orgs/$ORG/apis/from-spec"     # multipart upload, so no JSON content-type
# → {"api":{"id":"<API_ID>", ...}, "revision":{"id":"<REVISION_ID>", ...}}

# 2. Import does NOT make the routes live. Create an upstream, bind it
#    to the revision, then deploy the revision.
# pass_host + upstream_host: without them the backend gets the gateway's host
# and every call returns 502.
curl -s "${H[@]}" -X POST "$BASE/orgs/$ORG/envs/<TEST_ENV_ID>/upstreams" \
  -d '{"name":"albums-upstream","specification":{"scheme":"https","pass_host":"rewrite","upstream_host":"jsonplaceholder.typicode.com","nodes":[{"host":"jsonplaceholder.typicode.com","port":443,"weight":1}]}}'
# → {"id":"<UPSTREAM_ID>", ...}

curl -s "${H[@]}" -X PATCH "$BASE/orgs/$ORG/apis/<API_ID>/revisions/<REVISION_ID>/upstream-bindings/add" \
  -d '{"environmentUpstreams":[{"environmentId":"<TEST_ENV_ID>","upstreamId":"<UPSTREAM_ID>"}]}'
curl -s "${H[@]}" -X POST "$BASE/orgs/$ORG/apis/<API_ID>/revisions/<REVISION_ID>/deploy" \
  -d '{"environmentId":"<TEST_ENV_ID>","force":false}'

# 3. Create the product from example/products.json, with your API id filled in,
#    then deploy it. authMethods MUST be ["hmac-auth"] (it defaults to helix-auth).
jq '.products[0] | .apiIds = ["<API_ID>"]' example/products.json \
  | curl -s "${H[@]}" -X POST "$BASE/orgs/$ORG/products" -d @- | jq -r '.id'   # → <PRODUCT_ID>
curl -s "${H[@]}" -X POST "$BASE/orgs/$ORG/envs/<TEST_ENV_ID>/products/<PRODUCT_ID>/deploy"

# 4. Create a developer, then one app per partner integration. An EMPTY
#    {"hmac-auth": {}} tells the control plane to generate key_id and secret_key.
#    They come back ONCE, in this response. Store them now.
curl -s "${H[@]}" -X POST "$BASE/orgs/$ORG/developers" \
  -d '{"firstName":"<FIRST_NAME>","lastName":"<LAST_NAME>","email":"<EMAIL>"}' \
  | jq -r '.id'                                              # → <DEVELOPER_ID>

curl -s "${H[@]}" -X POST "$BASE/orgs/$ORG/developers/<DEVELOPER_ID>/envs/<TEST_ENV_ID>/apps" \
  -d '{"name":"settlement-partner","displayName":"Settlement partner","products":{"<PRODUCT_ID>":1},"plugins":{"hmac-auth":{}}}'
```

To match a secret a partner already holds, put your own `key_id` and `secret_key`
in the `hmac-auth` object instead of leaving it empty. Changing the key replaces
both values. You can't change one and keep the other.

> A revision accepts a spec change only when it is **INACTIVE**. If it's live,
> undeploy it first. Or clone the revision, so you keep the old one to go back to.

The same calls without narration: [API reference](api-reference.md).

## See it work

Sign and send a request. Replace `KEY_ID` and `SECRET_KEY` with your app's values:

```bash
BODY='{"title":"order-created","userId":1}'
DATE=$(LC_ALL=C date -u '+%a, %d %b %Y %H:%M:%S GMT')
DIGEST="SHA-256=$(printf '%s' "$BODY" | openssl dgst -sha256 -binary | openssl base64 -A)"

# printf is piped straight into openssl on purpose: the signing base ends with a
# newline, and $( ) strips trailing newlines. Capturing the base in a variable
# first signs a different string, and every request 401s.
SIGNATURE=$(printf '%s\nPOST /albums\ndate: %s\ndigest: %s\n' \
              "$KEY_ID" "$DATE" "$DIGEST" \
            | openssl dgst -sha256 -hmac "$SECRET_KEY" -binary | openssl base64 -A)

curl -i -X POST "https://<YOUR_GATEWAY_HOST>/albums" \
  -H 'Content-Type: application/json' \
  -H "Date: $DATE" -H "Digest: $DIGEST" \
  -H "Authorization: Signature keyId=\"$KEY_ID\",algorithm=\"hmac-sha256\",headers=\"@request-target date digest\",signature=\"$SIGNATURE\"" \
  -d "$BODY"
# HTTP/1.1 201 Created  <- signed, unchanged, accepted
```

Change one character of `BODY` after computing `DIGEST` and the same call returns
401. Send no `Authorization` header at all and you get:

```http
HTTP/1.1 401 Unauthorized
WWW-Authenticate: hmac realm="partner-events"

{"message":"client request can't be validated: missing Authorization header"}
```

To see what the other rejections look like, and how to find the real reason in
the gateway log, read [Architecture: Reading a rejection](architecture.md#reading-a-rejection).

To run all eight checks as a script:

```bash
GATEWAY=https://<YOUR_GATEWAY_HOST> KEY_ID=<KEY_ID> SECRET_KEY=<SECRET_KEY> \
  ./example/verify.sh
```

[`example/verify.sh`](example/verify.sh) has the same signing steps as a shell
function you can reuse. It covers both kinds of signature: with a body fingerprint
(digest) and without one. Exit code 0 means all eight checks passed, including the
one that proves `signed_headers` is enforced. What each check proves:
[Tests](tests.md).

## Variations

Each of these is a follow-up prompt to paste into the same Helix Agent session
after the build. Paste one only if you want that change.

**A shorter time limit.** Cuts the time in which someone can resend a copied
request from 5 minutes to 1. Only do this if your callers are servers with
accurate clocks.

```text
Cut the allowed clock skew to 60 seconds on both routes. Our callers are servers
with NTP, so a one-minute window is realistic.
```

**Safe by default, instead of per route.** Signing moves to the whole API, using
the `POST` route's rules. Any route you add later then needs a signature by
default.

```text
Make signing API-wide with the POST route's rules, so any route I add later is
signed by default. Tell me the exact Digest header my GET callers must now send
for an empty body.
```

The answer should be `SHA-256=47DEQpj8HBSa+/TImW+5JCeuQeRkm5NMpJWZG3hSuFU=`, the
digest of an empty body.

**Count each partner's usage too.**

```text
Enforce the product's quota per app on both routes. If the quota can't identify
the app from a signed request, tell me rather than working around it.
```

We tested this combination, and it works with no extra setup. With a quota of 3 a
minute, three signed requests returned 201. The next three returned
`429 {"error":"quota exceeded"}` (HTTP 429, too many requests). See
[solution 01](../01-api-products/).

**Let unsigned reads through, counted under one named caller.**

```text
Allow unsigned GET /albums/{albumId} calls, attributed to {{anonymous_consumer_name}},
while POST /albums stays strictly signed.
```

**Prove it with a script.**

```text
Write me a bash script that signs and sends requests with the app's key id and
secret, showing in order: no signature → 401; a correct signature → 201; the same
headers with a modified body → 401; a Date 20 minutes old → 401; a signature that
leaves the digest out of what it covers → 401.
```

Check that the script pipes `printf` straight into `openssl`. `$( )` removes the
final newline from the text to sign. Then every request gets 401, even though the
signature looks right.

**Bring your own secret.** When creating the app, put the partner's existing
`key_id` and `secret_key` in the `hmac-auth` object instead of an empty one.

**Change the key with no downtime.** When you change an app's credential, the old
one stops working at once. Instead, create a second app for the same partner,
move them to it, then delete the first.

## Configuration reference

The files that define this solution are
[`example/api-spec.yaml`](example/api-spec.yaml) for the routes and plugins, and
[`example/products.json`](example/products.json) for the product.
[`example/api-spec-basic.yaml`](example/api-spec-basic.yaml) has the same routes
with no plugins, so you can add them yourself. Each route has its own `hmac-auth`
block:

```yaml
# POST /albums — the signature must also cover the body
hmac-auth:
  signed_headers: ["@request-target", "date", "digest"]
  validate_request_body: true
  clock_skew: 300
  allowed_algorithms: ["hmac-sha256", "hmac-sha512"]
  hide_credentials: true
  realm: partner-events

# GET /albums/{albumId} — no body, so no digest
hmac-auth:
  signed_headers: ["@request-target", "date"]
  validate_request_body: false
  clock_skew: 300
  allowed_algorithms: ["hmac-sha256", "hmac-sha512"]
  hide_credentials: true
  realm: partner-events
```

| Field | Value here | What it means |
|---|---|---|
| `signed_headers` | POST: `@request-target`, `date`, `digest` · GET: `@request-target`, `date` | What every signature on this route **must** cover. **The setting that makes this secure.** No default; without it the caller chooses. |
| `validate_request_body` | POST `true` · GET `false` | Compare the body with its `Digest`. Only useful because `digest` is in `signed_headers`. |
| `clock_skew` | `300` | How many seconds a request's `Date` may differ from now. Also how long someone can resend a copied request. |
| `allowed_algorithms` | `hmac-sha256`, `hmac-sha512` | `hmac-sha1` is in the plugin's default list and is left out on purpose. |
| `hide_credentials` | `true` | Remove the `Authorization` header before forwarding. The backend (upstream) has no use for it. |
| `realm` | `partner-events` | Sent as `WWW-Authenticate: hmac realm="partner-events"` on a 401. |

`hmac-auth` accepts only those fields plus `anonymous_consumer` and `_meta`.
**There is no secret field.** The secret is stored on the app's credential.

The spec also adds `request-id` to the whole API. It puts an `X-Request-Id` header
on each response. That matters more than usual here. Most rejections give the same
short message. The request id is the one thing a caller can quote so that you can
find the log line.

The product, from [`example/products.json`](example/products.json):

| Field | Value | What it means |
|---|---|---|
| `name` / `displayName` | `partner-events` / `Partner Albums API` | — |
| `apiIds` | `["<API_ID>"]` | Fill in from the import response, or `GET /api/orgs/{orgId}/apis`. |
| `authMethods` | `["hmac-auth"]` | **Must** name `hmac-auth`. The default is `["helix-auth"]`. |
| `quota` | `10000` per `1` `hour` | Every product needs one (a product without one is rejected when you create it). **Not enforced** here, because no `api-product-enforcer` is on the routes. |

Placeholders in this package: `<API_ID>`, `<PRODUCT_ID>`, `<DEVELOPER_ID>`,
`<ORG_ID>`, `<TEST_ENV_ID>`, `<UPSTREAM_ID>`, `<REVISION_ID>`, `<KEY_ID>`,
`<SECRET_KEY>`, `<YOUR_GATEWAY_HOST>`. The spec itself has none.

Every field of every plugin: [docs.digitalapi.ai/api-gateway](https://docs.digitalapi.ai/api-gateway).

## Troubleshooting

- **A signature that looks right always gets 401.** The text to sign lost its
  final newline: `$(...)` removes trailing newlines. Pipe `printf` straight into
  `openssl`. Never put the text in a variable first. This is the most common
  cause. The next most likely causes: the `keyId` line is missing; the `Date` is
  outside `clock_skew` because the caller's clock is wrong; or the credential
  belongs to a different app.
- **A ready-made HTTP Signatures (draft-cavage) library gets 401.** It signs
  different text: no `keyId` line, no final newline, and lowercase
  `(request-target)`. Each difference alone changes the signature. Use the worked
  example.
- **The digest stops matching (`Invalid digest` in the log) after a "hardening"
  change.** Someone added `request-validation` to the route, and it re-wrote the
  body. The two plugins can't share a route. Check the schema in your backend,
  behind the gateway, instead.
- **`Date` can't be set from browser JavaScript.** `fetch` and `XHR` refuse to set
  it, so this can't be driven from a browser as written. That is on purpose (see
  [Architecture](architecture.md#signature-or-token--decide-this-first)), but it
  surprises people building an admin screen.
- **A header named in `headers=` but not sent is skipped**, not reported as an
  error. `signed_headers` catches the ones you require. Anything else listed is up
  to the caller.
- **Signatures break behind a proxy.** `@request-target` includes the query
  string. Anything that reorders, tidies up or adds query parameters breaks every
  signature it touches.
- **Bursts of 401s that look like credential problems.** The callers' clocks are
  wrong. Devices that don't keep their clocks in sync drift outside the 300-second
  limit.
- **A correctly signed request gets 401, but one listing `(request-target)` is
  accepted.** The route's `signed_headers` says `(request-target)`, the older
  draft-cavage spelling. The gateway treats it as an ordinary header that isn't
  there, and leaves it out of what is signed. So the method and path are not
  covered at all. Change every entry to `@request-target`. Then check that a
  signature for one path is refused on another.
- **The read route returns `404 Route Not Found`.** It was created as
  `/albums/{albumId}`. Routes written directly on the gateway take
  `/albums/:albumId`. Importing the spec converts `{albumId}` for you.
- **A request signed over only its `keyId` is accepted.** `signed_headers` is
  missing from the route, or was dropped, so the caller chooses what its signature
  covers. Set it on each route. If the agent built the API, ask it to set what the
  signature must cover on each route, and read the revision back.
- **A changed body is accepted.** `validate_request_body` is off on
  `POST /albums`, or `digest` is missing from its `signed_headers`.
- **A `POST` with no body is accepted.** `validate_request_body` checks that the
  body matches its `Digest`. It does not check that there is a body. A `POST` with
  no body and the empty-body digest passes. Requiring a body is a schema check, and
  `request-validation` breaks the digest here (see above).
- **A `GET` caller is asked for a `Digest`.** A `GET` with no body needs none,
  unless the route's `signed_headers` lists `digest`, or the caller lists it in
  `headers=`. This usually happens when someone copies the `POST` signing code to
  a `GET`.
- **Every `GET` with no body gets 401.** `hmac-auth` was moved to the whole API
  with the POST settings, so the GET now needs a digest. Send the empty-body
  digest, or go back to one block per route.
- **A route added later is open to everyone.** `hmac-auth` is set per route here.
  A new route needs its own block.
- **App creation fails on an unsupported auth plugin.** The product's
  `authMethods` is still the `["helix-auth"]` default.
- **The product can't be undeployed.** Apps still subscribe to it. Remove the
  product from those apps, or delete the apps, then undeploy.
- **You need the secret again.** It is returned once and stored encrypted. Create
  a new key instead.
- **Leaving `hmac-sha1` allowed.** It is in the plugin's default list. This spec
  narrows the list to SHA-256 and SHA-512. Keep it that way.
- **The agent invents a `secret_key` or `signing_secret` field on the route.**
  There is none. The credential carries the secret.
- **The routes exist with no plugins, though every step reported success.** The
  agent wrapped the plugins in `x-helix-gateway` inside the live route. A live
  route silently throws that away. Ask for a plain top-level `plugins` map and
  read the revision back. If that still doesn't work, import the spec.
- **The session ends part-way through with `stream closed with reason: error`.**
  The configuration may already be saved. Read the revision back to see what was
  saved, then carry on from there.
- **Use the trace inspector to see each step.** On the API's page, open the
  **Observability** tab and click **Start trace session**. It shows the headers
  each plugin changes, and the request body at every stage. It is the fastest
  way to see what each plugin did to a call. A session stops after 10 requests,
  so use **Advanced: filter which requests to capture** to record only the ones
  you care about (skipped requests don't count). The list doesn't refresh by
  itself: click **Refresh**. The **Inspector** shows API keys and cookies in
  plain text. Don't share your screen, or paste a trace into a ticket, without
  removing them first. A compressed response, which browsers always ask for, is
  unreadable in the **Response** tab, so call the API with curl to read it. The
  **Upstream** tab's **Total** adds connect time to response time, so it can be
  larger than the request's own total.
- **See what changed, and when, in Audit Logs.** **Observability → Audit Logs**
  lists every clone, plugin change and deploy. Its times are in your local time,
  while analytics uses UTC. Anything done with your token, including scripts and
  the Helix Agent, appears under your name.
