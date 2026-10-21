# Guides — HMAC request signing at the edge

> [Overview](README.md) · [Business need](business-need.md) · [Architecture](architecture.md) · **Guides** · [Agent prompt](helix-agent-prompt.md) · [Tests](tests.md) · [API reference](api-reference.md)

---

Three ways to build the same thing, then how to see it work. Whichever way you
pick, the result is one API, "Partner Albums API", with two signed routes
(`POST /albums`, whose signature also covers the body, and `GET /albums/{albumId}`),
plus one app whose `key_id` and `secret_key` you sign with.

## Pick your path

| | Choose this if you… | Go to |
|---|---|---|
| **1. Helix Agent** | want the quickest result and are happy to paste a prompt | [Build it with the Helix Agent](#build-it-with-the-helix-agent) |
| **2. Helix control plane** | prefer clicking through screens and want to see every setting | [Build it in the UI](#build-it-in-the-ui) |
| **3. API script** | are scripting this, or wiring it into a pipeline | [Install it directly](#install-it-directly) |

Then, for everyone: [See it work](#see-it-work) · [Variations](#variations) ·
[Configuration reference](#configuration-reference) · [Troubleshooting](#troubleshooting)

## Build it with the Helix Agent

Works on a **fresh, empty org**. [`helix-agent-prompt.md`](helix-agent-prompt.md)
has three steps: Step 1 creates the API and its two routes, Step 2 makes both
routes accept only signed requests, and Step 3 creates a developer, a product and
an app, and gives you the app's key id and secret. Paste the whole thing as one
message, or one step at a time if the run ends early. When it finishes, read the
revision back and check each route has its own `signed_headers` — a route without
them still deploys, and is wide open. Then send one signed request using
[See it work](#see-it-work).

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

> **A spec can carry the plugins too.** Add an `x-helix-gateway` block that
> lists them. At the top level of the file it covers every route; under one
> path and method it covers that route only. Signing goes on each route here,
> because each route signs a different set of headers:
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

Either way, the API is not live yet: it has no upstream and isn't deployed.
That comes in step 3.

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
   a fingerprint of the body (the `Digest` header). If any of these was altered
   on the way, or the signature is missing, wrong or too old, the call gets
   HTTP 401 (not authenticated) and never reaches your upstream.

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

Don't leave `signed_headers` out on either route: without it the caller decides
what its own signature covers, and the route is effectively open.

Repeat for the second route. What every field means, and the optional
extra (`request-id`) the full spec adds:
[Configuration reference](#configuration-reference).

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
   to map an upstream for `test`. Pick the one you just created, then **Deploy**.

**Changing it later.** A change to the upstream (host, port, scheme) applies to
the live API straight away, with no new deploy. A change to routes or plugins
does need one, because a live revision can't be edited: use **Clone Revision**,
make your change on the copy, then **Force Deploy** it. The same steps roll you
back: clone the older revision and force-deploy that.

**4. Create the product**
1. Go to **API Distribution → API Products**, click **Add API Product**.
2. Under **Basic Information**, set **Display Name** to `Partner Albums API`.
3. Under **APIs**, click **Add API**, select your API, then **Continue**.
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
Go to **API Distribution → Apps**, click **Add App**. Pick the **Environment** and
the **Developer**, add the product, pick **`hmac-auth`** as the authentication
method and let credentials auto-generate, then **Create App**.

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

## Install it directly

If you'd rather script it against the control plane:

```bash
export ORG=<ORG_ID>
export TOKEN=<control-plane bearer token>      # short-lived
export BASE=https://<YOUR_GATEWAY_HOST>/api
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
curl -s "${H[@]}" -X POST "$BASE/orgs/$ORG/envs/<TEST_ENV_ID>/upstreams" \
  -d '{"name":"albums-upstream","specification":{"scheme":"https","nodes":[{"host":"jsonplaceholder.typicode.com","port":443,"weight":1}]}}'
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
  -d '{"name":"settlement-partner","products":{"<PRODUCT_ID>":1},"plugins":{"hmac-auth":{}}}'
```

To match a secret a partner already holds, put your own `key_id` and `secret_key`
in the `hmac-auth` object instead of leaving it empty. Rotating replaces both; you
cannot rotate one and keep the other.

> Revisions must be **INACTIVE** to accept a spec change. If it's live, undeploy
> first, or clone the revision so you keep a rollback target.

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

What each other rejection looks like, and how to find the real reason in the
gateway log: [Architecture → Reading a rejection](architecture.md#reading-a-rejection).

To run all eight checks as a script:

```bash
GATEWAY=https://<YOUR_GATEWAY_HOST> KEY_ID=<KEY_ID> SECRET_KEY=<SECRET_KEY> \
  ./example/verify.sh
```

[`example/verify.sh`](example/verify.sh) contains the same signing steps as a
reusable shell function, for both the with-digest and no-digest signed sets. Exit
code 0 means all eight held, including the one that proves `signed_headers` is
enforced. What each check proves: [Tests](tests.md).

## Variations

Each of these is a follow-up prompt to paste into the same Helix Agent session
after the build. Paste one only if you want that change.

**Tighter replay window.** Shrinks the replay window fivefold. Only do this if
your callers are servers with accurate clocks.

```text
Cut the allowed clock skew to 60 seconds on both routes. Our callers are servers
with NTP, so a one-minute window is realistic.
```

**Fail safe instead of per route.** Signing moves API-wide with the `POST` rules,
so any route added later is signed by default.

```text
Make signing API-wide with the POST route's rules, so any route I add later is
signed by default. Tell me the exact Digest header my GET callers must now send
for an empty body.
```

The answer should be `SHA-256=47DEQpj8HBSa+/TImW+5JCeuQeRkm5NMpJWZG3hSuFU=`, the
digest of an empty body.

**Meter the partners as well.**

```text
Enforce the product's quota per app on both routes. If the quota can't identify
the app from a signed request, tell me rather than working around it.
```

This combination was tested and works without extra setup: with a 3-a-minute
quota, three signed requests returned 201 and the next three returned
`429 {"error":"quota exceeded"}`. See [solution 01](../01-api-products/).

**Let unsigned reads through, attributed.**

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

Check the script pipes `printf` straight into `openssl`: `$( )` strips the
signing base's final newline, and every request then gets 401 with a signature
that looks right.

**Bring your own secret.** When creating the app, put the partner's existing
`key_id` and `secret_key` in the `hmac-auth` object instead of an empty one.

**Rotate without downtime.** Rotating an app's credential cuts over immediately.
Create a second app for the same partner, move them to it, then delete the first.

## Configuration reference

Source of truth: [`example/api-spec.yaml`](example/api-spec.yaml) for the routes
and plugins, plus the product in [`example/products.json`](example/products.json).
[`example/api-spec-basic.yaml`](example/api-spec-basic.yaml) is the same routes
with no plugins, for adding them yourself. Each route carries its own
`hmac-auth` block:

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
| `validate_request_body` | POST `true` · GET `false` | Compare the body with its `Digest`. Only meaningful because `digest` is in `signed_headers`. |
| `clock_skew` | `300` | How many seconds a request's `Date` may differ from now. Also the replay window. |
| `allowed_algorithms` | `hmac-sha256`, `hmac-sha512` | `hmac-sha1` is in the plugin's default list and is left out on purpose. |
| `hide_credentials` | `true` | Remove the `Authorization` header before forwarding. The upstream has no use for it. |
| `realm` | `partner-events` | Sent as `WWW-Authenticate: hmac realm="partner-events"` on a 401. |

`hmac-auth` accepts only those fields plus `anonymous_consumer` and `_meta`.
**There is no secret field**; the secret lives on the app credential.

The spec also carries `request-id` API-wide (`X-Request-Id`). It matters more than
usual here: most rejections are the same short message, and the request id is the
one thing a caller can quote to have the log line found.

The product, from [`example/products.json`](example/products.json):

| Field | Value | What it means |
|---|---|---|
| `name` / `displayName` | `partner-events` / `Partner Albums API` | — |
| `apiIds` | `["<API_ID>"]` | Fill in from the import response, or `GET /api/orgs/{orgId}/apis`. |
| `authMethods` | `["hmac-auth"]` | **Must** name `hmac-auth`. The default is `["helix-auth"]`. |
| `quota` | `10000` per `1` `hour` | Every product needs one (a product without one is rejected at creation). **Not enforced** here, because no `api-product-enforcer` is on the routes. |

Placeholders in this package: `<API_ID>`, `<PRODUCT_ID>`, `<DEVELOPER_ID>`,
`<ORG_ID>`, `<TEST_ENV_ID>`, `<UPSTREAM_ID>`, `<REVISION_ID>`, `<KEY_ID>`,
`<SECRET_KEY>`, `<YOUR_GATEWAY_HOST>`. The spec itself has none.

Every field of every plugin: [docs.digitalapi.ai/api-gateway](https://docs.digitalapi.ai/api-gateway).

## Troubleshooting

- **A signature that looks right always gets 401.** The signing base lost its
  final newline: `$(...)` strips trailing newlines. Pipe `printf` straight into
  `openssl`; never put the base in a variable first. This is the most common cause.
  Next most likely: the `keyId` line is missing, the `Date` is outside
  `clock_skew` because the caller's clock has drifted, or the credential is from a
  different app.
- **An off-the-shelf HTTP Signatures (draft-cavage) library gets 401.** It signs
  different text: no `keyId` line, no final newline, and lowercase
  `(request-target)`. Each alone changes the signature. Use the worked example.
- **`Invalid digest` in the log after a "hardening" change.** `request-validation`
  was added to the route and re-encoded the body. They cannot share a route. Check
  the schema behind the gateway instead.
- **`Date` can't be set from browser JavaScript.** `fetch` and `XHR` refuse to set
  it, so this can't be driven from a browser as written. That is intended (see
  [Architecture](architecture.md#signature-or-token--decide-this-first)), but it
  surprises people building an admin screen.
- **A header named in `headers=` but not sent is skipped**, not reported as an
  error. `signed_headers` catches the ones you require; anything else listed is up
  to the caller.
- **Signatures break behind a proxy.** `@request-target` includes the query
  string. Anything that reorders, normalises or adds query parameters breaks every
  signature it touches.
- **Bursts of 401s that look like credential problems.** Clock drift. A device
  fleet without time sync drifts outside the 300-second window.
- **A correctly signed request gets 401, but one listing `(request-target)` is
  accepted.** The route's `signed_headers` says `(request-target)`, the older
  draft-cavage spelling. The gateway treats it as an ordinary header that isn't
  there and leaves it out of what is signed, so the method and path are not
  covered at all. Change every entry to `@request-target`, then check that a
  signature for one path is refused on another.
- **The read route returns `404 Route Not Found`.** It was created as
  `/albums/{albumId}`. Routes written directly on the gateway take
  `/albums/:albumId`; importing the spec converts `{albumId}` for you.
- **A request signed over only its `keyId` is accepted.** `signed_headers` is
  missing from the route, so the caller chooses what its signature covers. Set it
  on each route.
- **A `POST` with no body is accepted.** `validate_request_body` checks that the
  body matches its `Digest`, not that there is a body: a `POST` with no body and
  the empty-body digest passes. Requiring a body is a schema check, and
  `request-validation` breaks the digest here (see above).
- **A `GET` caller is asked for a `Digest`.** A bodyless `GET` needs none, unless
  the route's `signed_headers` lists `digest`, or the caller lists it in
  `headers=`. Copying the `POST` signing code to a `GET` is the usual way that
  happens.
- **Every bodyless GET gets 401.** `hmac-auth` was moved API-wide with the POST
  settings, so the GET now needs a digest. Send the empty-body digest or go back
  to per-route blocks.
- **A route added later is open to everyone.** `hmac-auth` is per route here; a
  new route needs its own block.
- **App creation fails on an unsupported auth plugin.** The product's
  `authMethods` is still the `["helix-auth"]` default.
- **You need the secret again.** It is returned once and stored encrypted. Rotate
  instead.
- **Leaving `hmac-sha1` allowed.** It is in the plugin's default list. This spec
  narrows it to SHA-256 and SHA-512; keep it that way.
- **A request signed over only `keyId` is accepted.** `signed_headers` was dropped, so the caller chooses what it signs. Ask for each route to fix what the signature must cover, and read it back.
- **A modified body is accepted.** `validate_request_body` is off on `POST /albums`, or `digest` is missing from its `signed_headers`.
- **A signature that looks correct always 401s.** The signing base lost its final newline: `$( )` strips it. Pipe `printf` straight into `openssl`.
- **Every bodyless GET 401s.** `hmac-auth` was moved to the API level, so the GET now requires a digest.
- **The digest stops matching after a "hardening" change.** `request-validation` landed on the route and re-encoded the body.
- **App creation fails on an unsupported auth plugin.** The product's `authMethods` is still the `["helix-auth"]` default.
- **The agent invents a `secret_key` or `signing_secret` field on the route.** There is none. The credential carries it.
- **The routes exist with **no plugins**, though every step reported success.** The agent wrapped the plugins in `x-helix-gateway` inside the live route, which a live route silently discards. Ask for a plain top-level `plugins` map and read the revision back; if it still won't, import the spec.
- **You need the secret again.** It's returned once and stored encrypted. Rotate instead.
- **The session ends with `stream closed with reason: error` part-way through.** The configuration may already have been saved. Read the revision back to see what landed, then carry on from there.
- **Use the trace inspector to see each step.** On the API's page, open the
  **Observability** tab and click **Start trace session**. It shows the headers each plugin changes and
  the request body at every stage, which is the fastest way to see what each
  plugin did to a call.
