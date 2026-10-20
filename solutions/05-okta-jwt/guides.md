# Guides — checking Okta-issued tokens at the gateway

> [Overview](README.md) · [Business need](business-need.md) · [Architecture](architecture.md) · **Guides** · [Agent prompt](helix-agent-prompt.md) · [Tests](tests.md) · [API reference](api-reference.md)

---

Three ways to build the same thing, then how to see it work. Whichever way you
pick, the result is one API, "Partner Albums API", with two routes (`GET /albums`
and `POST /albums`) that accept only access tokens your Okta issued, in front of a
public test service.

**Check this first, whatever path you pick:** your org must include the
`openid-connect` plugin. Not every org does. See
[Install it directly](#install-it-directly) for the one call that tells you, or
ask the Helix Agent *"confirm the openid-connect plugin exists in this org"*
before you paste the prompt.

## Pick your path

| | Choose this if you… | Go to |
|---|---|---|
| **1. Helix Agent** | want the quickest result and are happy to paste a prompt | [Build it with the Helix Agent](#build-it-with-the-helix-agent) |
| **2. Helix control plane** | prefer clicking through screens and want to see every setting | [Build it in the UI](#build-it-in-the-ui) |
| **3. API script** | are scripting this, or wiring it into a pipeline | [Install it directly](#install-it-directly) |

Then, for everyone: [See it work](#see-it-work) · [Variations](#variations) ·
[Configuration reference](#configuration-reference) · [Troubleshooting](#troubleshooting)

## Build it with the Helix Agent

Works on a **fresh org**, as long as it includes the `openid-connect` plugin.
[`helix-agent-prompt.md`](helix-agent-prompt.md) has two steps: Step 1 creates the
API and its two routes, Step 2 makes every route accept only your Okta's tokens.
Paste the whole thing as one message, or one step at a time if the run ends early.
There is no developer, product or app step: Okta issues the tokens. When it
finishes, read the revision back and check for `use_jwks: true` — the agent often
leaves it out, and you add it yourself.

See [AGENT-GUIDE.md](../../AGENT-GUIDE.md) for the ground rules these prompts
assume.

## Build it in the UI

Screen and button names below are the real ones. The API lives under
**API Gateway** in the left sidebar.

**Before you start:**

- **Your org includes `openid-connect`.** On the free-trial build the whole
  Authentication category is `helix-auth` alone, so this solution cannot run
  there. There is no screen for this check in this walkthrough. Ask the Helix
  Agent *"confirm the openid-connect plugin exists in this org"*, or use the call
  in [Install it directly](#install-it-directly).
- **You have your four Okta values.** See
  [Configuration reference](#configuration-reference) for where each comes from.
- **You can create APIs.** If you don't see an **Add API** button, ask your org
  admin.

**1. Create the API**

Pick one of the two ways below. Both give you the same thing: an API called
`Partner Albums API` with two routes and no plugins yet.

*Option A — from scratch*
1. Go to **API Gateway → APIs**, click **Add API** (or **Create your first API**).
2. Choose **Create from scratch**. Set **Display name** to `Partner Albums API`,
   then **Save**.
3. On the API's page, open **Configuration → Routes** and add two routes:
   - `GET` `/albums`, the list of albums
   - `POST` `/albums`, create an album

*Option B — from an OpenAPI spec*
1. Go to **API Gateway → APIs**, click **Add API** (or **Create your first API**).
2. Set **Method** to **Import an OpenAPI spec**.
3. Drag in your own OpenAPI 3.0 file, or use our example,
   [`example/api-spec-basic.yaml`](example/api-spec-basic.yaml): the same two
   routes, no plugins. Then click **Import**.

> **A spec can carry the plugins too.** Add an `x-helix-gateway` block that
> lists them. At the top level of the file it covers every route; under one
> path and method it covers that route only. The start of this package's block:
>
> ```yaml
> x-helix-gateway:
>   plugins:
>     openid-connect:
>       discovery: "<OKTA_DISCOVERY_URL>"
>       unauth_action: deny
>       bearer_only: true
>       use_jwks: true
>       # ...and the rest of the settings in step 2
> ```
>
> [`example/api-spec.yaml`](example/api-spec.yaml) is this API with all its
> plugins already in place. Replace its four `<OKTA_...>` placeholders in a
> local copy, import that, and you can skip step 2. Keep the completed copy out
> of version control.

Either way, the API is not live yet: it has no upstream and isn't deployed.
That comes in step 3.

**2. Add the plugins**

One plugin, `openid-connect`, does the job: it checks that each call carries an
access token your Okta issued. Add it **before** you deploy: a live revision
can't be changed.

On the API's page, open **Configuration → Plugins** and click **Configure
plugin**. A short wizard opens:

1. **Plugin** — pick the plugin from the catalog.
2. **Scope** — **Entire Revision** applies it to every route; **Specific
   endpoint** applies it to one route.
3. **Configure** — the JSON editor and the Properties list sit side by side.
   Paste the JSON below, or fill in the fields. Then **Next**.
4. **Review** — shows the configuration before and after. Click **Apply**.

Pick `openid-connect` and choose **Entire Revision**, which is what you want:
there is no route here that must stay open. If `openid-connect` isn't in the
catalog, your org doesn't include it and this solution can't run there. At
**Configure**, paste the settings below into the JSON editor.

**`openid-connect` — accepts only your Okta's tokens.** It reads Okta's public
signing keys, checks each token's signature and issuer, and rejects anything
else with HTTP 401 (not authenticated) before the call reaches your backend.

Replace the four `<OKTA_...>` values with your own. They are plain values: the
gateway does not resolve `<ENV:...>` or `${...}`, so whatever you type is used
exactly as written. [Configuration reference](#configuration-reference) says
where each one comes from.

```json
{
  "discovery": "<OKTA_DISCOVERY_URL>",
  "client_id": "<OKTA_CLIENT_ID>",
  "client_secret": "<OKTA_CLIENT_SECRET>",
  "unauth_action": "deny",
  "bearer_only": true,
  "use_jwks": true,
  "ssl_verify": true,
  "accept_unsupported_alg": false,
  "accept_none_alg": false,
  "token_signing_alg_values_expected": "RS256",
  "claim_validator": {
    "issuer": {"valid_issuers": ["<OKTA_ISSUER_URL>"]},
    "audience": {"required": true, "claim": "aud"}
  },
  "jwk_expires_in": 3600,
  "set_access_token_header": true,
  "set_id_token_header": false,
  "set_userinfo_header": false,
  "set_refresh_token_header": false
}
```

Three of these settings are what make the plugin behave like an API guard
rather than a browser sign-in:

| Field | Value | Why |
|---|---|---|
| **bearer_only** | `true` | Treats every caller as an API client with a token. Without it, the deploy fails asking for a browser-session secret. |
| **unauth_action** | `deny` | Refuse a call with no token instead of sending it to Okta's login page. `bearer_only` already does this; it is set too so the intent is plain to anyone reading. |
| **use_jwks** | `true` | Checks the token's signature here, against Okta's published keys. Without it, every token is refused, even a genuine one. |

Paste the JSON into the JSON editor rather than filling in the **Properties**
list for this plugin: `use_jwks` is not in the plugin's published list of
fields, so the Properties list may not offer it, but the gateway accepts and
keeps it.

The plugin then appears under **Configuration → Plugins**. What every field
means, and the two optional extras (`request-id`, `cors`) the full spec adds:
[Configuration reference](#configuration-reference).

**3. Give it an upstream, then deploy it**
1. Go to **API Gateway → Upstreams → Add Upstream**. Name it, pick your
   environment, point it at `jsonplaceholder.typicode.com` (or your own host), then
   **Create Upstream**.
2. Back on the API's page, click **Deploy** on the revision. The dialog asks you to
   map an upstream for the environment. Pick the one you just created, then
   **Deploy**.

**4. Get a token from Okta and call the API**

There is no developer, product or app to create in the gateway: Okta issues the
tokens. Get one from your Okta authorization server (client credentials), then
follow [See it work](#see-it-work).

## Install it directly

If you'd rather script it against the control plane:

```bash
export ORG=<ORG_ID>
export TOKEN=<control-plane bearer token>      # short-lived
export BASE=https://<YOUR_GATEWAY_HOST>/api
H=(-H "authorization: Bearer $TOKEN" -H 'content-type: application/json')

# 0. Confirm openid-connect is in your org. If it isn't listed, stop here:
#    no spec edit will make this solution deploy.
curl -s "${H[@]}" "$BASE/orgs/$ORG/plugin-schemas?page=1&size=300" | grep -o '"openid-connect"'

# 1. Replace the four <OKTA_...> placeholders in a LOCAL copy of the spec first
#    (see the Configuration reference). Then import it. Keep both ids returned.
curl -s -H "authorization: Bearer $TOKEN" -F "file=@api-spec.filled.yaml" \
  "$BASE/orgs/$ORG/apis/from-spec"     # multipart upload, so no JSON content-type
# → {"api":{"id":"<API_ID>", ...}, "revision":{"id":"<REVISION_ID>", ...}}

# 2. Import does NOT make the routes live. Create an upstream, bind it
#    to the revision, then deploy the revision.
curl -s "${H[@]}" -X POST "$BASE/orgs/$ORG/envs/<ENV_ID>/upstreams" \
  -d '{"name":"albums-upstream","specification":{"scheme":"https","nodes":[{"host":"jsonplaceholder.typicode.com","port":443,"weight":1}]}}'
# → {"id":"<UPSTREAM_ID>", ...}

curl -s "${H[@]}" -X PATCH "$BASE/orgs/$ORG/apis/<API_ID>/revisions/<REVISION_ID>/upstream-bindings/add" \
  -d '{"environmentUpstreams":[{"environmentId":"<ENV_ID>","upstreamId":"<UPSTREAM_ID>"}]}'
curl -s "${H[@]}" -X POST "$BASE/orgs/$ORG/apis/<API_ID>/revisions/<REVISION_ID>/deploy" \
  -d '{"environmentId":"<ENV_ID>","force":false}'
```

That is the whole install: there are no products, developers or apps, because
Okta issues the tokens. Note that the upstream **must** live in the same
environment you bind it for. Upstream bindings are per environment, and binding
one from a different environment fails the deploy with
`Upstream not configured for environment`.

> **`bearer_only` is checked when you deploy, not when you import.** A spec without
> it imports cleanly and then fails to deploy with
> `property "session.secret" is required when "bearer_only" is false`. The shipped
> spec sets it.

> Revisions must be **INACTIVE** to accept a spec change. If it's live, undeploy
> first, or clone the revision so you keep a rollback target.

The same calls without narration: [API reference](api-reference.md).

## See it work

Get a token from Okta, then call the API with it, and without it:

```bash
TOKEN=$(curl -s -X POST "https://<your-okta-domain>/oauth2/<authServerId>/v1/token" \
  -u "<CLIENT_ID>:<CLIENT_SECRET>" \
  -d grant_type=client_credentials -d scope=<scope> | jq -r .access_token)

curl -s -o /dev/null -w "%{http_code}\n" "https://<YOUR_GATEWAY_HOST>/albums"
# 401  <- no token, and NOT a redirect to Okta's login page

curl -s -o /dev/null -w "%{http_code}\n" "https://<YOUR_GATEWAY_HOST>/albums" \
  -H "authorization: Bearer $TOKEN"
# 200  <- the upstream's data, untouched
```

What a caller sees in each situation. Every row was run against a deployed route:

| Situation | Response |
|---|---|
| No `Authorization` header | `401` (**not** a redirect) |
| `Bearer` prefix missing | **`400`** — rejected while reading the header, before the plugin runs |
| Not a JWT at all | `401` |
| Signature doesn't verify | `401` |
| `alg: none` | `401` |
| Token expired | `401` |
| `iss` from a different tenant | `401` |
| `iss` missing the issuer's trailing slash | `401` |
| `iss` claim absent | `401` |
| `aud` claim absent | **`403`** — note the different code |
| `aud` present but naming an unrelated API | **`200` — accepted.** See [Troubleshooting](#troubleshooting) |
| Valid token | `200`, upstream's body untouched |

Most failures are the same plain `401`. That is correct: telling them apart would
tell an attacker which part they got right. It also makes them hard for an honest
caller to diagnose, so ask them for the `X-Request-Id` from the response.

The upstream receives `X-Access-Token`. It does **not** receive `X-ID-Token` or
`X-Userinfo`: those are for browser sign-in, and `set_userinfo_header` in
particular would add a call to Okta on every request.

To run the checks as a script:

```bash
GATEWAY=https://<YOUR_GATEWAY_HOST> \
OKTA_TOKEN_URL=https://<your-okta-domain>/oauth2/<authServerId>/v1/token \
OKTA_CLIENT_ID=<CLIENT_ID> \
OKTA_CLIENT_SECRET=<CLIENT_SECRET> \
OKTA_SCOPE=<scope> \
./example/verify.sh
```

If your authorization server needs an `audience` parameter to issue a **JWT**
rather than an opaque token (Auth0 always does, and Okta custom authorization
servers usually do), set `TOKEN_AUDIENCE` too. Set `OTHER_ISSUER_TOKEN` to a token
from a second authorization server to run the wrong-issuer check. What each check
proves, and the manual tests the script can't run: [Tests](tests.md).

## Variations

Each of these is a follow-up prompt to paste into the same Helix Agent session
after the build.

**Require a scope, not just a valid token.** This is also how you tell apart
several APIs in one Okta tenant, since the audience is not checked by value.

```text
Only accept tokens that carry the "{{required_scope}}" scope, and tell me what a
token without it now returns.
```

A token without the scope returns 403 (tested).

**Point at your real upstream.**

```text
Point this at {{upstream_url}} instead, and leave the token verification exactly
as it is.
```

**Your authorization server issues opaque tokens, not JWTs.**

```text
This Okta authorization server issues opaque access tokens, so there is no
signature to verify locally. Change verification to ask Okta about each token
instead, and tell me what that does to latency and what happens when Okta is
unreachable.
```

That puts Okta on the request path, and changes how fast and how available your
API is. It is a different design from the one this package validates.

**Use the org authorization server instead of a custom one.**

```text
Switch to the org authorization server, whose discovery document is
{{okta_org_discovery_url}}, and pin the issuer to the one that document reports.
```

**Meter the callers as well.**

```text
I want to sell access to this API in tiers and enforce the limits per caller.
```

Read [solution 01](../01-api-products/) first: its quota counts per app, and a
token Okta issued does not identify a gateway app. Expect the agent to tell you
this.

**Other identity providers.** Entra ID, Auth0 and Keycloak work the same way:
change `discovery` and `valid_issuers` to that provider's values.

## Configuration reference

Source of truth: [`example/api-spec.yaml`](example/api-spec.yaml).
[`example/api-spec-basic.yaml`](example/api-spec-basic.yaml) is the same routes
with no plugins, for adding them yourself. One block, applied API-wide at the top
of the spec, does the work:

```yaml
openid-connect:
  discovery: "<OKTA_DISCOVERY_URL>"
  client_id: "<OKTA_CLIENT_ID>"
  client_secret: "<OKTA_CLIENT_SECRET>"
  unauth_action: deny
  bearer_only: true
  use_jwks: true
  ssl_verify: true
  accept_unsupported_alg: false
  accept_none_alg: false
  token_signing_alg_values_expected: RS256
  claim_validator:
    issuer:
      valid_issuers:
        - "<OKTA_ISSUER_URL>"
    audience:
      required: true
      claim: aud
  jwk_expires_in: 3600
  set_access_token_header: true
  set_id_token_header: false
  set_userinfo_header: false
  set_refresh_token_header: false
```

**This is `openid-connect`, not `helix-auth`.** `helix-auth` only checks tokens
the gateway itself issued, and has no field for a JWKS URL, an issuer or an
audience. See [Architecture](architecture.md#why-helix-auth-cannot-do-this).

| Field | Value here | What it means |
|---|---|---|
| `discovery` | `<OKTA_DISCOVERY_URL>` | Where the plugin finds Okta's issuer name and public keys. Required. |
| `client_id` / `client_secret` | `<OKTA_CLIENT_ID>` / `<OKTA_CLIENT_SECRET>` | Your Okta application. Both required, although local checking never uses the secret. |
| `use_jwks` | `true` | **Required, and not in the published schema.** Checks tokens locally against Okta's keys. Without it every token is rejected. |
| `bearer_only` | `true` | Accept tokens only; never start a browser sign-in. Without it the deploy is rejected. |
| `unauth_action` | `deny` | Refuse rather than redirect. Redundant while `bearer_only` is true (tested), kept for clarity. |
| `ssl_verify` | `true` | Check Okta's TLS certificate when fetching keys. Default is `false`. |
| `accept_unsupported_alg` / `accept_none_alg` | `false` / `false` | Refuse unsigned or unusually signed tokens. The first defaults to `true`. |
| `token_signing_alg_values_expected` | `RS256` | The only signing algorithm accepted. |
| `claim_validator.issuer.valid_issuers` | `[<OKTA_ISSUER_URL>]` | The only issuer trusted. Must match the discovery document exactly. |
| `claim_validator.audience.required` / `.claim` | `true` / `aud` | The token must *have* an audience. Its value is not checked. |
| `jwk_expires_in` | `3600` | How long to cache Okta's keys, in seconds. Default is `86400`. |
| `set_access_token_header` | `true` | Pass the token upstream as `X-Access-Token`. |
| `set_id_token_header` / `set_userinfo_header` / `set_refresh_token_header` | `false` | Browser-flow headers, all off. `set_userinfo_header` would call Okta on every request. |

**The defaults you must change.** The plugin's defaults suit browser sign-in. For
an API, these are wrong, and each fails in a way that does not look like a
configuration error:

| Field | Default | Why it's wrong for an API | Set to |
|---|---|---|---|
| `bearer_only` | `false` | The **deploy** is rejected: `property "session.secret" is required when "bearer_only" is false`. Checked at deploy, not import. | `true` |
| `unauth_action` | `auth` | Means "redirect to sign in". Redundant while `bearer_only: true` is set (tested: no token still returns 401, not 302). | `deny` |
| `ssl_verify` | `false` | Okta's signing keys, the whole basis of trust, are fetched without checking Okta's certificate. | `true` |
| `accept_unsupported_alg` | `true` | Its own description: *"Ignore ID token signature to accept unsupported signature algorithm"*. | `false` |
| `claim_validator` | *(absent)* | Nothing beyond the signature is checked. Any correctly signed token from any issuer the plugin can reach is accepted. | pin `issuer.valid_issuers` |

The spec also carries `request-id` (`X-Request-Id`, so a rejected caller has
something to quote) and `cors` (all origins, `GET,POST,OPTIONS`, with
`authorization` in the allowed headers so browser callers can send a token).

**Placeholders.** The four values are plain text, used exactly as written:

| Placeholder | Where it comes from |
|---|---|
| `<OKTA_DISCOVERY_URL>` | `https://<your-okta-domain>/oauth2/<authServerId>/.well-known/openid-configuration`, or `https://<your-okta-domain>/.well-known/openid-configuration` for the org authorization server |
| `<OKTA_ISSUER_URL>` | the `issuer` value **that discovery document reports**. Fetch it and copy it; do not retype it |
| `<OKTA_CLIENT_ID>` | the Okta application's client id |
| `<OKTA_CLIENT_SECRET>` | its client secret. Required by the plugin even though local checking never uses it |

Install placeholders: `<ORG_ID>`, `<ENV_ID>`, `<API_ID>`, `<REVISION_ID>`,
`<UPSTREAM_ID>`, `<YOUR_GATEWAY_HOST>`. Replace all of them.

Every field of every plugin: [docs.digitalapi.ai/api-gateway](https://docs.digitalapi.ai/api-gateway).

## Troubleshooting

- **Every token is rejected, though the spec deployed cleanly.** `use_jwks: true`
  is missing. The 401 carries `error_description="no endpoint URI for
  introspection"`. Put it back, even though the schema doesn't list it.
- **A token minted seconds ago returns 401.** In order of likelihood:
  `valid_issuers` doesn't exactly match the discovery document's `issuer` (a
  trailing slash, or `/oauth2/default` versus the org server, is enough);
  `discovery` points at a different authorization server than the one that issued
  the token; or Okta rotated its key and the gateway's cache is stale.
- **A valid token returns 403.** The token checked out but a claim check did not:
  either `required_scopes` is set and the token lacks a scope, or the token has no
  `aud` claim.
- **A caller gets 400.** Their `Authorization` header has no `Bearer ` prefix.
- **The audience is not checked against a value.** A token issued for a different
  API in the same tenant is **accepted** (tested: 200). Pin
  `issuer.valid_issuers` and add `required_scopes`. Never describe this setup as
  checking the audience.
- **The API redirects instead of refusing.** The plugin is set up for browser
  sign-in. Check `bearer_only: true`. Always test with no token first.
- **The deploy fails asking for `session.secret`.** `bearer_only` is missing or
  false.
- **Every token started failing at once, and nothing changed on your side.** Okta
  rotated its signing key while the gateway still had the old keys cached. It
  clears when `jwk_expires_in` runs out (3600 seconds in this spec).
- **Your token request to Okta fails.** That is Okta refusing, not the gateway.
  Usually: the app is not enabled for client credentials, the scope is not granted,
  or no audience was sent and the tenant has no default (set `TOKEN_AUDIENCE`).
- **Your authorization server returns opaque tokens.** Local checking can't work.
  See [Variations](#variations).
- **You get 429s while testing.** Your environment may limit requests before auth
  runs: the environment used for testing allowed 10 requests a minute across the
  whole gateway. `verify.sh` waits between calls (`PACE`, default 7 seconds);
  hand-run tests may not.
- **`client_secret` is required but unused.** It is required by the plugin, and
  used only if you switch to introspection. Supply a real one anyway.
- **`openid-connect` is not in your org.** Some builds don't include it. This
  solution cannot be deployed there.
- **The stored config holds `<ENV:...>` instead of your client id and secret.**
  The agent swapped your values for placeholders, and the gateway uses that text
  exactly as written. Keep the prompt's *"use the literal values for the
  configuration"* line, or ask the agent to put the real values in.
- **The proposed spec has `discovery`, `client_id`, `client_secret` and nothing else.** The hardening fields were dropped. Ask the agent to compare what it stored, field by field, against what the prompt asked for.
- **A token from a *different* authorization server returns 200.** No issuer pin. Ask for tokens to be accepted only from the issuer the discovery document reports.
- **The agent reaches for `helix-auth`.** Tell it: `helix-auth` has no JWKS URL, issuer or audience field and its schema forbids extra fields. If `openid-connect` isn't in this org, stop.
- **The agent proposes `jwt-auth` as a standalone plugin.** It isn't one here. It is only a `validate_auth_type` of `helix-auth`, and it means a token *this* gateway signed.
- **The agent invents an `audience` field with an expected value.** There isn't one. `claim_validator.audience` has `required`, `claim` and `match_with_client_id`.
- **The routes exist with **no plugins**, though every step reported success.** The agent wrapped the plugins in `x-helix-gateway` inside the live route, which a live route silently discards. Ask for a plain top-level `plugins` map and read the revision back; if it still won't, import the spec.
- **Deploy fails: `Only INACTIVE revisions can be updated`.** The revision is already live. Clone it or undeploy, then apply.
