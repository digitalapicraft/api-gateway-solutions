# Guides — OAuth 2.0 with gateway-issued JWTs

> [Overview](README.md) · [Business need](business-need.md) · [Architecture](architecture.md) · **Guides** · [Agent prompt](helix-agent-prompt.md) · [Tests](tests.md) · [API reference](api-reference.md)

---

Three ways to build the same thing, then how to see it work. Whichever way you
pick, the result is one API with a token endpoint, `POST /oauth/token`, and three
protected routes — `GET /posts`, `GET /posts/{postId}` and `POST /posts` — that
accept only a token the gateway issued, plus one app with a client id and secret
to test with.

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
whole build — the API, the token endpoint, token checks on the protected routes,
and a developer, product and app with working credentials.
[`helix-agent-prompt.md`](helix-agent-prompt.md) has it as three numbered steps:
paste the whole thing as one message, or one step at a time if the run ends early.

See [AGENT-GUIDE.md](../../AGENT-GUIDE.md) for the ground rules these prompts
assume.

## Build it in the UI

Screen and button names below are the real ones. The API lives under
**API Gateway** in the left sidebar; developers, products and apps live under
**API Distribution**.

**Before you start:**

- **You have an account.** If you don't, register for a free trial at
  [trial.digitalapi.ai](https://trial.digitalapi.ai/). A new trial org comes with a
  `test` environment, which is all this walkthrough needs.
- **You can create APIs, products and apps.** If you don't see an **Add API**,
  **Add API Product** or **Add App** button, ask your org admin.
- **You have a signing secret ready** — a long random value, for example from a
  password generator. You paste it into the plugin settings in step 2.

**1. Create the API**

Pick one of the two ways below. Both give you the same thing: an API called
`Posts API` with four routes and no plugins yet.

*Option A — from scratch*
1. Go to **API Gateway → APIs**, click **Add API** (or **Create your first API**).
2. Choose **Create from scratch**. Set **Display name** to `Posts API`, then
   **Save**.
3. On the API's page, open **Configuration → Routes** and add four routes:
   - `POST` `/oauth/token`, the token endpoint
   - `GET` `/posts`, the list of posts
   - `POST` `/posts`, create a post
   - `GET` `/posts/:postId`, one post. The gateway writes a path parameter as
     `:postId`, not `{postId}`.

*Option B — from an OpenAPI spec*
1. Go to **API Gateway → APIs**, click **Add API** (or **Create your first API**).
2. Set **Method** to **Import an OpenAPI spec**.
3. Drag in your own OpenAPI 3.0 file, or use our example,
   [`example/api-spec-basic.yaml`](example/api-spec-basic.yaml): the same four
   routes, no plugins. Then click **Import**.

> **A spec can carry the plugins too.** Add an `x-helix-gateway` block under a
> path and method, and it covers that route only. This one goes on the token
> route; the three `/posts` routes get the same block with `mode: validate`:
>
> ```yaml
> /oauth/token:
>   post:
>     x-helix-gateway:
>       plugins:
>         helix-auth:
>           mode: generate
>           token_ttl: 900
>           signing_secret: "<YOUR_JWT_SIGNING_SECRET>"
> ```
>
> [`example/api-spec.yaml`](example/api-spec.yaml) is this API with all its
> plugins already in place. Replace its four `<YOUR_JWT_SIGNING_SECRET>`
> placeholders with your secret, import it, and you can skip step 2. Keep that
> filled-in copy out of version control.

Either way, the API is not live yet: it has no upstream and isn't deployed.
That comes in step 3.

**2. Add the plugins**

One plugin, `helix-auth`, does the whole job, set up two ways: on the token
route it hands out tokens, and on the three `/posts` routes it checks them. Add
it **before** you deploy: a live revision can't be changed.

On the API's page, open **Configuration → Plugins** and click **Configure
plugin**. A short wizard opens:

1. **Plugin** — pick the plugin from the catalog.
2. **Scope** — **Entire Revision** applies it to every route; **Specific
   endpoint** applies it to one route.
3. **Configure** — the JSON editor and the Properties list sit side by side.
   Paste the JSON below, or fill in the fields. Then **Next**.
4. **Review** — shows the configuration before and after. Click **Apply**.

Add it **on each route, never across the whole API**: choose **Specific
endpoint** and pick the route, and run the wizard once per route, four times in
all. (**Entire Revision** would cover every route, including `/oauth/token`, and
then no caller could ever get a first token.)

**About the signing secret.** Where you see `<YOUR_JWT_SIGNING_SECRET>` below,
type your own long random value instead. It must be **exactly the same on all
four routes**: the token route signs with it, and the other three check with it.
The gateway uses the text exactly as written, so if you leave the placeholder in,
anyone who has read this page can make tokens your API accepts. Never save the
real value anywhere it could be shared, such as a code repository.

1. **On `POST /oauth/token` (Scope: Specific endpoint): `helix-auth` hands out
   tokens.** It checks the
   app's client id **and** secret, then signs a token that lasts 900 seconds
   (15 minutes). This route must stay reachable without a token, since a caller
   has none yet.

   | Field | Value |
   |---|---|
   | **mode** | `generate` |
   | **token_ttl** | `900` |
   | **signing_secret** | `<YOUR_JWT_SIGNING_SECRET>` |

   ```json
   {"mode":"generate","token_ttl":900,"signing_secret":"<YOUR_JWT_SIGNING_SECRET>"}
   ```

2. **On `GET /posts`, `POST /posts` and `GET /posts/:postId` (Scope: Specific
   endpoint, once for each): `helix-auth` checks the token.** A call with no
   token, an expired one, or one this gateway didn't sign gets HTTP 401 (not
   authenticated), and never reaches your backend. Add the same settings on each
   of the three routes.

   | Field | Value |
   |---|---|
   | **mode** | `validate` |
   | **validate_auth_type** | `jwt-auth` |
   | **signing_secret** | `<YOUR_JWT_SIGNING_SECRET>` |

   ```json
   {"mode":"validate","validate_auth_type":"jwt-auth","signing_secret":"<YOUR_JWT_SIGNING_SECRET>"}
   ```

Repeat until all four routes carry `helix-auth`. What every field means, and
the two optional extras (`request-id`, `cors`) the full spec adds across the API:
[Configuration reference](#configuration-reference).

**3. Give it an upstream, then deploy it**
1. Go to **API Gateway → Upstreams → Add Upstream**. Name it, pick environment
   `test`, point it at `jsonplaceholder.typicode.com` (or your own host), then
   **Create Upstream**.
2. Back on the API's page, click **Deploy** on the revision. The dialog asks you to
   map an upstream for `test`. Pick the one you just created, then **Deploy**.

**4. Create a product**
1. Go to **API Distribution → API Products**, click **Add API Product**.
2. Under **Basic Information**, set a **Display Name**, for example `Posts API`.
3. Under **APIs**, click **Add API**, select your API, then **Continue**.
4. Under **Authentication Methods**, pick a method for apps to use. Left blank, it
   defaults to `helix-auth`.
5. Under **Quota**, make sure **Enable request quota** is on. It is by default,
   set to 1000 per 1 hour, so don't click the switch: that turns the quota off,
   and every product needs one. The default is high enough not to get in your way while testing; raise
   **Request limit** or change **Unit** if it isn't. This solution doesn't meter
   callers; [solution 01](../01-api-products/) is how you sell usage tiers.
6. Leave **Quota scope** on **App level**, so every app gets its own allowance.
7. Click **Create API Product**.

**5. Deploy the product**
On the product's page, click **Deploy**, pick `test`, then **Deploy** again. This
is a *different* deploy from step 3. The product needs its own.

**6. Create a developer**
Go to **API Distribution → Developers**, click **Add Developer**, fill in the name
and email, then **Add**.

**7. Create an app for that developer**
Go to **API Distribution → Apps**, click **Add App**. Pick the **Environment** and
the **Developer**, add the product, pick an authentication method and let
credentials auto-generate, then **Create App**.

**8. Get the app's credentials**
On the app's **Overview** tab, find the **Authentication** card. It shows
`helix-auth` with a key and a secret, both hidden, each with a show and a copy
button. Copy **both**: the key is the **client id**, and with the secret it is
what the app sends to `/oauth/token`. **Generate New Credentials**, in the same
card, issues a new pair.

## Install it directly

If you'd rather script it against the control plane:

```bash
export ORG=<ORG_ID>
export TOKEN=<control-plane bearer token>      # short-lived
export BASE=https://<YOUR_GATEWAY_HOST>/api
H=(-H "authorization: Bearer $TOKEN" -H 'content-type: application/json')

# 1. Replace all four <YOUR_JWT_SIGNING_SECRET> placeholders in the spec with one
#    long random value. It is used AS WRITTEN as the signing key — <ENV:...> is
#    not looked up. Do not commit the filled-in spec.

# 2. Import the spec. It carries helix-auth (generate on /oauth/token, validate on
#    the /posts routes), and the import assigns the routes a service_id. Keep both
#    ids the response returns.
curl -s -H "authorization: Bearer $TOKEN" -F "file=@example/api-spec.yaml" \
  "$BASE/orgs/$ORG/apis/from-spec"
# → {"api":{"id":"<API_ID>", ...}, "revision":{"id":"<REVISION_ID>", ...}}

# 3. Import does NOT make the routes live. Create an upstream, bind it
#    to the revision, then deploy the revision.
curl -s "${H[@]}" -X POST "$BASE/orgs/$ORG/envs/<TEST_ENV_ID>/upstreams" \
  -d '{"name":"posts-upstream","specification":{"scheme":"https","nodes":[{"host":"jsonplaceholder.typicode.com","port":443,"weight":1}]}}'
# → {"id":"<UPSTREAM_ID>", ...}

curl -s "${H[@]}" -X PATCH "$BASE/orgs/$ORG/apis/<API_ID>/revisions/<REVISION_ID>/upstream-bindings/add" \
  -d '{"environmentUpstreams":[{"environmentId":"<TEST_ENV_ID>","upstreamId":"<UPSTREAM_ID>"}]}'
curl -s "${H[@]}" -X POST "$BASE/orgs/$ORG/apis/<API_ID>/revisions/<REVISION_ID>/deploy" \
  -d '{"environmentId":"<TEST_ENV_ID>","force":false}'

# 4. Create a product that includes the API, then deploy it. Every product needs
#    a quota object; limit -1 means unlimited. Metering is solution 01.
curl -s "${H[@]}" -X POST "$BASE/orgs/$ORG/products" \
  -d '{"name":"posts","displayName":"Posts API","apiIds":["<API_ID>"],"quota":{"limit":-1}}' \
  | jq -r '.id'                                              # → <PRODUCT_ID>
curl -s "${H[@]}" -X POST "$BASE/orgs/$ORG/envs/<TEST_ENV_ID>/products/<PRODUCT_ID>/deploy"

# 5. Create a developer and an app subscribed to the product. The control plane
#    issues the app's client id (the credential key) and client secret. Keep both.
curl -s "${H[@]}" -X POST "$BASE/orgs/$ORG/developers" \
  -d '{"firstName":"<FIRST_NAME>","lastName":"<LAST_NAME>","email":"<EMAIL>"}' \
  | jq -r '.id'                                              # → <DEVELOPER_ID>
curl -s "${H[@]}" -X POST "$BASE/orgs/$ORG/developers/<DEVELOPER_ID>/envs/<TEST_ENV_ID>/apps" \
  -d '{"name":"<APP_NAME>","products":{"<PRODUCT_ID>":1},"plugins":{"helix-auth":{}}}'
```

`plugins` on an app names the auth method it uses, and an empty
`{"helix-auth":{}}` asks the control plane to generate the key and secret, like the
UI's auto-generate option. Confirm the shape your org's build expects before
scripting this for real.

> Revisions must be **INACTIVE** to accept a change — otherwise you get `Only
> INACTIVE revisions can be updated`. If it's live, undeploy first, or clone the
> revision so you keep one to roll back to.

The same calls without narration: [API reference](api-reference.md).

## See it work

Exchange the app's credentials for a token:

```http
POST /oauth/token
Authorization: Basic <base64(client_id:client_secret)>

HTTP/1.1 200 OK
content-type: application/json

{"access_token":"eyJhbGciOiJIUzI1NiIs...","token_type":"Bearer","expires_in":900}
```

Then call a protected route with it, and without it:

```bash
TOKEN=$(curl -s -X POST "https://<YOUR_GATEWAY_HOST>/oauth/token" \
  -u "<CLIENT_ID>:<CLIENT_SECRET>" | jq -r .access_token)

curl -s -o /dev/null -w "%{http_code}\n" "https://<YOUR_GATEWAY_HOST>/posts" \
  -H "authorization: Bearer $TOKEN"
# 200  <- a token this gateway issued

curl -s -o /dev/null -w "%{http_code}\n" "https://<YOUR_GATEWAY_HOST>/posts"
# 401  <- no token; your backend never saw the call
```

Every rejection on a protected route is a plain `401`:

```http
HTTP/1.1 401 Unauthorized
```

**All four failure causes look the same to the caller** — no token, no `Bearer `
prefix, an expired token, a token this gateway didn't sign. That is correct for
security and awkward for integrators, so:

- **Document the causes** in your developer docs, since the response won't tell
  them apart: "A 401 means one of: no `Authorization` header, no `Bearer ` prefix,
  an expired token, or a token this gateway didn't sign."
- **Use the request id for support.** `X-Request-Id` is added to every call,
  including the token exchange, so when a partner reports "it just returns 401" you
  have something to search for.

**Tell integrators to keep and reuse the token** until shortly before it expires —
around 80% of its lifetime. A client that asks for a new token on every call turns
the token endpoint into your busiest route and doubles the time every call takes.

To run all six checks as a script:

```bash
GATEWAY=https://<YOUR_GATEWAY_HOST> \
CLIENT_ID=<CLIENT_ID> CLIENT_SECRET=<CLIENT_SECRET> EXPECT_TTL=900 \
./example/verify.sh          # defaults to /posts and /oauth/token
```

Exit code 0 means all six held, including that a wrong secret gets no token and a
forged token is refused. What each check proves, plus the manual tests `verify.sh`
can't run for you: [Tests](tests.md).

## Variations

Follow-ups for the same agent session, once the build is standing. Same style as
the prompt — say what you want to be true, not which fields to set.

**Pin the token lifetime**
```text
Set the token lifetime to 900 seconds, and tell me what that does to token
endpoint traffic at 50 calls/min.
```

**An external identity provider already issues the tokens**
```text
Our tokens come from {{identity_provider}}, not the gateway — it issues them and we just
need to accept them. Drop /oauth/token and verify the incoming tokens against
that issuer instead. Reject unauthenticated callers outright rather than
redirecting them to a login page, since these are API clients.
```
This is a different solution, not a setting: [solution 05](../05-okta-jwt/). The
gateway can only check tokens it signed itself, so an external issuer needs a
different plugin entirely.

**Point at my real upstream**
```text
Point this at {{upstream_url}} instead, and keep everything else
as it is. My backend's paths differ from the route paths, so rewrite them on the
way through.
```

**Meter the callers as well as identify them**
```text
Now meter these callers. I sell a free tier and a paid tier — create a product
for each with its own quota, and enforce it per app on the protected routes.
```
Quota here is counted per app by the product, so it needs no separate rate-limit
plugin. That's [solution 01](../01-api-products/).

## Configuration reference

Source of truth: [`example/api-spec.yaml`](example/api-spec.yaml).
[`example/api-spec-basic.yaml`](example/api-spec-basic.yaml) is the same routes
with no plugins, for adding them yourself. Two blocks carry the whole solution.

On the token endpoint, `POST /oauth/token`:

```yaml
helix-auth:
  mode: generate
  token_ttl: 900
  signing_secret: "<YOUR_JWT_SIGNING_SECRET>"
```

On every protected route — `GET /posts`, `POST /posts`, `GET /posts/{postId}`:

```yaml
helix-auth:
  mode: validate
  validate_auth_type: jwt-auth
  signing_secret: "<YOUR_JWT_SIGNING_SECRET>"
```

| Plugin | Field | Value here | What it means |
|---|---|---|---|
| `helix-auth` (token route) | `mode` | `generate` | Checks the app's client id **and** secret, then signs a token. The only mode that checks the secret. |
| `helix-auth` (token route) | `token_ttl` | `900` | Token lifetime in seconds — 15 minutes. Returned to the caller as `expires_in`. |
| `helix-auth` (both) | `signing_secret` | `<YOUR_JWT_SIGNING_SECRET>` | The signing key, used exactly as written. Must be the same value on all four routes. |
| `helix-auth` (protected routes) | `mode` | `validate` | Checks an existing token. |
| `helix-auth` (protected routes) | `validate_auth_type` | `jwt-auth` | Expect a JWT this gateway signed. A setting of `helix-auth`, not a separate plugin. |
| `request-id` (API-wide) | `algorithm` / `header_name` | `uuid` / `X-Request-Id` | A tracking id on every call, including the token exchange. |
| `cors` (API-wide) | `allow_origins` / `allow_methods` / `allow_headers` / `allow_credential` | `*` / `GET,POST,OPTIONS` / `authorization,content-type` / `false` | Browser access. `authorization` must be listed, or browsers can't send the token. Narrow `allow_origins` before pointing this at your own backend. |

**Note what isn't there.** `validate` is set on each protected route, not across
the whole API. Set API-wide, it would protect `/oauth/token` too — and then no
caller could ever get a first token. The symptom is an API where every request
returns 401, including the one meant to fix that.

**Choosing a token lifetime.** `token_ttl` is the only number here with a real
trade-off. Shorter means a leaked token is useless sooner, and your token endpoint
works harder; past an hour or so you have rebuilt the static API key with extra
steps. The table is on [Business need](business-need.md). This spec ships 900
seconds.

The upstream is not in this file. It is bound to the API when you deploy, so the
same spec works against any backend.

Placeholders in this package: `<YOUR_JWT_SIGNING_SECRET>`, `<ORG_ID>`,
`<TEST_ENV_ID>`, `<API_ID>`, `<REVISION_ID>`, `<UPSTREAM_ID>`, `<PRODUCT_ID>`,
`<DEVELOPER_ID>`, `<CLIENT_ID>`, `<CLIENT_SECRET>`, `<YOUR_GATEWAY_HOST>`. Replace
all of them before you deploy. App client ids and secrets are issued by the
platform and never appear in the spec.

Every field of every plugin, and the wider product docs:
[docs.digitalapi.ai/api-gateway](https://docs.digitalapi.ai/api-gateway).

## Troubleshooting

- **The signing secret must be identical on the token route and every protected
  route.** A mismatch rejects every newly issued token with a plain 401. Both sides
  look correct, and nothing hints that the value is shared.
- **The signing secret is used as written.** The gateway looks up neither
  `<ENV:...>` nor `${...}`; the text in `signing_secret` *is* the key. Replace the
  placeholder before you deploy and keep the filled-in spec out of version control.
  Ship the placeholder and your signing key is public.
- **Never set `validate` API-wide.** Every request returns 401, including the one
  that issues tokens. See [Configuration reference](#configuration-reference).
- **`authorization` must be in `cors.allow_headers`.** Otherwise browser clients
  fail before the request is sent, and you see a CORS error rather than a 401 —
  which points people at the wrong layer.
- **`generate` is the only mode that checks the app's secret.** `key-auth`
  validation goes by the credential's key alone. If you need proof that the caller
  holds the secret, you need this flow, not a static key.
- **The client id is the credential's key, not its secret.** Sending the secret
  where the id belongs is the most common cause of "401 at the token endpoint with
  credentials I'm sure are right".
- **Every protected call returns 403 with a valid token.** The app isn't
  subscribed to a product that includes this API.
- **If *everything* returns 401, including calls with tokens issued moments ago,**
  suspect the signing secret before you suspect the client.
- **Confirm `helix-auth`'s fields in your own org** with `get_plugin_config`
  before deploying. Builds differ, and field names are not worth guessing.
- **`request-id` covers the token route on purpose.** Sign-in failures are exactly
  what you'll be asked to investigate, and the token exchange is half the flow.
