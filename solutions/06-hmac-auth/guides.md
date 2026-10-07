# Guides — HMAC request signing at the edge

> [Overview](README.md) · [Business need](business-need.md) · [Architecture](architecture.md) · **Guides** · [Agent prompt](helix-agent-prompt.md) · [Tests](tests.md) · [API reference](api-reference.md)

---

Three ways to build the same thing, then how to see it work. Whichever way you
pick, the result is one API with two signed routes (`POST /posts`, whose
signature also covers the body, and `GET /posts/{postId}`), plus one app whose
`key_id` and `secret_key` you sign with.

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
has two steps: Step 1 creates the API and signs its routes, Step 2 issues an app
credential and gives you a script that proves it. **Paste one step at a time and
confirm between them.** Below them are four optional follow-ups, each a separate
change; paste one only if you want it (see [Variations](#variations)).

Why the prompt is worded the way it is:

- **`signed_headers` is stated as mandatory.** It has no default, so an agent
  writing "a reasonable `hmac-auth` config" leaves it out. The result passes
  checks, deploys, and is wide open. This is the most damaging wrong turn here.
- **Per route, not API-wide.** The two routes need different signed sets. Move one
  block API-wide and every bodyless GET must send a digest of an empty body or get
  a 401.
- **No `request-validation`.** An agent asked to harden an intake endpoint reaches
  for schema checking. At priority 2800 it re-encodes the body before `hmac-auth`
  hashes it at 2530, and the digest silently stops matching.
- **No secret on the route.** Stops the agent inventing a `secret_key` or
  `signing_secret` field by analogy with `helix-auth`. The route has neither.
- **`authMethods: ["hmac-auth"]`.** It defaults to `["helix-auth"]`, and app
  creation then fails with an unhelpful error about an unsupported auth plugin.
- **`plugins {"hmac-auth": {}}`.** The empty object means "generate the
  credentials". An agent may invent values instead, which works but gives you a
  secret of its choosing.
- **"Pipe printf straight into openssl".** Ordinary bash puts the signing base in
  a variable first; `$( )` then drops the final newline, and every request gets a
  401 with a signature that looks right.
- **The test where `headers=` leaves out `digest`.** It proves `signed_headers` is
  enforced rather than decorative.

**Before you trust a run, read the stored revision back.** The agent's summary is
not enough. Check that each route has `hmac-auth` with its own `signed_headers`
(`digest` on the POST route only) and `validate_request_body: true` on the POST
route, and that there is no `request-validation` and no secret in the route config.

See [AGENT-GUIDE.md](../../AGENT-GUIDE.md) for the ground rules these prompts
assume, and [Troubleshooting](#troubleshooting) if the agent takes a wrong turn.

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

**1. Import the API**
1. Go to **API Gateway → APIs**, click **Add API** (or **Create your first API**).
2. Set **Method** to **Import an OpenAPI spec**.
3. Drag in [`example/api-spec.yaml`](example/api-spec.yaml), or paste its
   contents, then click **Import**.

There is **nothing to fill in first**: the spec contains no secret and no
placeholder. It already carries `hmac-auth` on each route, with the settings in
the [Configuration reference](#configuration-reference), plus `request-id`
API-wide. There is no separate screen to set these up; they come in with the spec.
Import does **not** bind an upstream or deploy, and nothing warns you if you skip
that.

**2. Give it an upstream, then deploy it**
1. Go to **API Gateway → Upstreams → Add Upstream**. Name it, pick environment
   `test`, point it at `jsonplaceholder.typicode.com` (or your own host), then
   **Create Upstream**.
2. Back on the API's page, click **Deploy** on the revision. The dialog asks you
   to map an upstream for `test`. Pick the one you just created, then **Deploy**.

**3. Create the product**
1. Go to **API Distribution → API Products**, click **Add API Product**.
2. Under **Basic Information**, set **Display Name** to `Partner Events API`.
3. Under **APIs**, click **Add API**, select your API, then **Continue**.
4. Under **Authentication Methods**, pick **`hmac-auth`**. Left blank, it defaults
   to `helix-auth`, and the app you create in step 6 is then rejected.
5. Under **Quota**, turn on **Enable request quota** and enter the values from
   [`example/products.json`](example/products.json) (10,000 requests per hour).
   Every product needs a quota, even though this solution does not enforce it.
6. Click **Create API Product**.

The product is here only because it is how an app gets a credential. Its quota is
not enforced unless you add the quota check (see [Variations](#variations)).

**4. Deploy the product**
On the product's page, click **Deploy**, pick `test`, then **Deploy** again. This
is a different deploy from step 2. The product needs its own.

**5. Create a developer**
Go to **API Distribution → Developers**, click **Add Developer**, fill in the
partner's name and email, then **Add**.

**6. Create an app for that developer**
Go to **API Distribution → Apps**, click **Add App**. Pick the **Environment** and
the **Developer**, add the product, pick **`hmac-auth`** as the authentication
method and let credentials auto-generate, then **Create App**.

**7. Get the `key_id` and `secret_key`**
On the app's page, open **Credentials**. The `secret_key` is returned **once**,
when the credentials are generated, and stored encrypted after that. Copy both
values then. If you don't see the secret, create the app through
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
  -d '{"name":"posts-upstream","specification":{"scheme":"https","nodes":[{"host":"jsonplaceholder.typicode.com","port":443,"weight":1}]}}'
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
BODY='{"title":"order-created","body":"sku-1","userId":1}'
DATE=$(LC_ALL=C date -u '+%a, %d %b %Y %H:%M:%S GMT')
DIGEST="SHA-256=$(printf '%s' "$BODY" | openssl dgst -sha256 -binary | openssl base64 -A)"

# printf is piped straight into openssl on purpose: the signing base ends with a
# newline, and $( ) strips trailing newlines. Capturing the base in a variable
# first signs a different string, and every request 401s.
SIGNATURE=$(printf '%s\nPOST /posts\ndate: %s\ndigest: %s\n' \
              "$KEY_ID" "$DATE" "$DIGEST" \
            | openssl dgst -sha256 -hmac "$SECRET_KEY" -binary | openssl base64 -A)

curl -i -X POST "https://<YOUR_GATEWAY_HOST>/posts" \
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

**Optional follow-up prompts.** [`helix-agent-prompt.md`](helix-agent-prompt.md)
carries four, below Steps 1 and 2. Paste one into the same session only if you
want that change:

- **Tighter replay window.** Cuts `clock_skew` to 60 seconds on both routes, which
  shrinks the replay window fivefold. Only do this if your callers are servers
  with accurate clocks.
- **Fail safe instead of per route.** Moves `hmac-auth` API-wide with the `POST`
  settings, so any route added later is signed by default. Callers of bodyless
  routes must then send
  `Digest: SHA-256=47DEQpj8HBSa+/TImW+5JCeuQeRkm5NMpJWZG3hSuFU=`, the digest of an
  empty body.
- **Add per-app quota on top.** Puts `api-product-enforcer` on both routes so the
  product's quota is enforced per app. This combination was tested and works
  without extra setup: with a 3-a-minute quota, three signed requests returned 201
  and the next three returned `429 {"error":"quota exceeded"}`. See
  [solution 01](../01-api-products/).
- **Let unsigned callers through as an anonymous consumer.** Sets
  `anonymous_consumer` on the GET route, so unsigned reads are allowed but still
  attributed, while POST stays strictly signed.

**Bring your own secret.** When creating the app, put the partner's existing
`key_id` and `secret_key` in the `hmac-auth` object instead of an empty one.

**Rotate without downtime.** Rotating an app's credential cuts over immediately.
Create a second app for the same partner, move them to it, then delete the first.

## Configuration reference

Source of truth: [`example/api-spec.yaml`](example/api-spec.yaml) for the routes
and plugins, plus the product in [`example/products.json`](example/products.json).
Each route carries its own `hmac-auth` block:

```yaml
# POST /posts — the signature must also cover the body
hmac-auth:
  signed_headers: ["@request-target", "date", "digest"]
  validate_request_body: true
  clock_skew: 300
  allowed_algorithms: ["hmac-sha256", "hmac-sha512"]
  hide_credentials: true
  realm: partner-events

# GET /posts/{postId} — no body, so no digest
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
| `name` / `displayName` | `partner-events` / `Partner Events API` | — |
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

### When the agent takes a wrong turn

| Symptom | Cause |
|---|---|
| A signature that looks correct always 401s | The signing base lost its final newline: `$( )` strips it. Pipe `printf` straight into `openssl`. |
| Every bodyless GET 401s | `hmac-auth` was moved to the API level, so the GET now requires a digest. |
| The digest stops matching after a "hardening" change | `request-validation` landed on the route and re-encoded the body. |
| App creation fails on an unsupported auth plugin | The product's `authMethods` is still the `["helix-auth"]` default. |
| The agent invents a `secret_key` field on the route | There is none. The credential carries it. |
| You need the secret again | It's returned once and stored encrypted. Rotate instead. |
| The session ends with `"stream closed with reason: error"` part-way through | Seen in testing: the configuration had already landed correctly (both routes, per-route `signed_headers`, `validate_request_body` on the write route) before the session died on a later step. Read the revision back to see what actually landed, then carry on from there. |
