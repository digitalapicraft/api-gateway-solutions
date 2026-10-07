# Guides — checking Okta-issued tokens at the gateway

> [Overview](README.md) · [Business need](business-need.md) · [Architecture](architecture.md) · **Guides** · [Agent prompt](helix-agent-prompt.md) · [Tests](tests.md) · [API reference](api-reference.md)

---

Three ways to build the same thing, then how to see it work. Whichever way you
pick, the result is one API with three routes (`GET /posts`, `GET /posts/{postId}`
and `POST /posts`) that accept only access tokens your Okta issued, in front of a
public test service.

**Check this first, whatever path you pick:** your org must include the
`openid-connect` plugin. Not every org does. See
[Install it directly](#install-it-directly) for the one call that tells you, or
ask the Helix Agent (Step 1 of the prompt does this for you).

## Pick your path

| | Choose this if you… | Go to |
|---|---|---|
| **1. Helix Agent** | want the quickest result and are happy to paste a prompt | [Build it with the Helix Agent](#build-it-with-the-helix-agent) |
| **2. Helix control plane** | prefer clicking through screens and want to see every setting | [Build it in the UI](#build-it-in-the-ui) |
| **3. API script** | are scripting this, or wiring it into a pipeline | [Install it directly](#install-it-directly) |

Then, for everyone: [See it work](#see-it-work) · [Variations](#variations) ·
[Configuration reference](#configuration-reference) · [Troubleshooting](#troubleshooting)

## Build it with the Helix Agent

Works on a **fresh org**, as long as it includes `openid-connect`.
[`helix-agent-prompt.md`](helix-agent-prompt.md) has two steps. **Paste Step 1,
check what it shows you, then paste Step 2.** A single large prompt pushes the
agent into an oversized tool call, and the fields it drops are the hardening ones.

**This is the one prompt in the library that names fields.** The configuration has
fourteen of them, four override defaults you would not guess, and one is missing
from the published schema. Asked for as a single outcome, the agent drops exactly
the hardening fields, because they come last. Here is why each instruction is
there:

- **"Confirm the plugin exists; do not substitute."** `openid-connect` is missing
  from some orgs. Without this line the agent reaches for `helix-auth` and builds
  something that looks right and cannot work.
- **`use_jwks: true`, flagged as missing from the schema.** The most important
  line. The agent won't find it in the plugin schema and will drop it as a mistake
  unless told not to. The result imports, dry-runs and deploys cleanly, then
  rejects every token.
- **`unauth_action: deny`, with what breaks without it.** Explaining the login
  redirect is what makes the agent keep the field when it starts trimming.
- **The defaults worth overriding.** `ssl_verify` defaults to false;
  `accept_unsupported_alg` defaults to true and its own description is "ignore the
  signature"; `set_userinfo_header` adds a call to Okta on every request; and
  without `valid_issuers` any issuer the plugin can reach is trusted.
- **API level, not per route.** The opposite of [solution 02](../02-oauth-jwt/)'s
  rule. An agent that has seen that one will attach the check route by route out
  of habit. Here there is no token endpoint to leave open.
- **Step 2 at all.** It makes the agent review its own work against your org's
  live schema, which is what catches dropped fields.

**Before you trust a run, read the stored revision back.** The agent's own summary
is not enough: a field can be dropped while every step reports success. Check that
`openid-connect` is present with `use_jwks: true` and `bearer_only: true`, and
that there is no `helix-auth` anywhere. Then test with no token first: it must
return 401, not a redirect.

See [AGENT-GUIDE.md](../../AGENT-GUIDE.md) for the ground rules these prompts
assume, and [Troubleshooting](#troubleshooting) if the agent takes a wrong turn.

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

**1. Fill in your Okta values**

Download [`example/api-spec.yaml`](example/api-spec.yaml) and replace the four
`<OKTA_...>` placeholders in a local copy. They are plain values: the gateway does
not resolve `<ENV:...>` or `${...}`, so whatever you type is used exactly as
written. Keep the completed copy out of version control.

**2. Import the API**
1. Go to **API Gateway → APIs**, click **Add API** (or **Create your first API**).
2. Set **Method** to **Import an OpenAPI spec**.
3. Drag in your completed copy of the spec, or paste its contents, then click
   **Import**.

The imported spec already carries the `openid-connect` plugin, with every setting
in the [Configuration reference](#configuration-reference), plus `request-id` and
`cors`. There is no separate screen to set these up; they come in with the spec.
Import creates the API and its first revision. It does **not** bind an upstream or
deploy, and nothing warns you if you skip that.

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
  -d '{"name":"posts-upstream","specification":{"scheme":"https","nodes":[{"host":"jsonplaceholder.typicode.com","port":443,"weight":1}]}}'
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

curl -s -o /dev/null -w "%{http_code}\n" "https://<YOUR_GATEWAY_HOST>/posts"
# 401  <- no token, and NOT a redirect to Okta's login page

curl -s -o /dev/null -w "%{http_code}\n" "https://<YOUR_GATEWAY_HOST>/posts" \
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
Add required_scopes so only tokens carrying "{{required_scope}}" are accepted, and
tell me what a token without it now returns.
```

A token without the scope returns 403 (tested).

**Point at your real upstream.**

```text
Change the upstream to {{upstream_url}} and re-run the
dry-run. Leave the auth configuration untouched.
```

**Your authorization server issues opaque tokens, not JWTs.**

```text
This Okta authorization server issues opaque access tokens, so there is no
signature to verify locally. Reconfigure openid-connect to use
introspection_endpoint instead, and tell me what that changes about latency and
what happens when Okta is unreachable.
```

That puts Okta on the request path, and changes how fast and how available your
API is. It is a different design from the one this package validates.

**Use the org authorization server instead of a custom one.**

```text
Switch discovery to https://{{okta_domain}}/.well-known/openid-configuration
and update valid_issuers to match the issuer that document reports.
```

**Other identity providers.** Entra ID, Auth0 and Keycloak work the same way:
change `discovery` and `valid_issuers` to that provider's values.

## Configuration reference

Source of truth: [`example/api-spec.yaml`](example/api-spec.yaml). One block,
applied API-wide at the top of the spec, does the work:

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

### When the agent takes a wrong turn

| Symptom | Cause |
|---|---|
| Every token 401s, though the spec deployed cleanly | `use_jwks` was dropped. Tell the agent it's missing from the schema but accepted and saved, put it back, and redeploy. |
| The API redirects instead of refusing | The plugin is still set up for browser sign-in. Always test with no token first. |
| The proposed spec has `discovery`, `client_id`, `client_secret` and nothing else | The hardening fields were dropped. Step 2's field-by-field check is what catches this. |
| The agent reaches for `helix-auth` | Tell it: `helix-auth` has no JWKS URL, issuer or audience field and its schema forbids extra fields. Re-read the `openid-connect` schema. |
| The agent proposes `jwt-auth` as a standalone plugin | It isn't one here. It is only a `validate_auth_type` of `helix-auth`, and it means a token *this* gateway signed. |
| The agent invents an `audience` field with an expected value | There isn't one. `claim_validator.audience` has `required`, `claim` and `match_with_client_id`. |
