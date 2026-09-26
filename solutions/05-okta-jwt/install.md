# Install — Solution 05 — OAuth with Okta: verify the token, don't issue it

[Overview](readme.md) · [Business need](business-need.md) · [How it works](how-it-works.md) · **Install** · [Configuration](configuration.md) · [Test & verify](testing.md) · [Changelog](changelog.md)

---

## Build it with the Helix Agent

Recommended path, and it works on a **fresh org**. Two steps — a single
mega-prompt pushes the default agent model into an oversized tool call, and the
fields it drops are the hardening ones. Full prompt, with why each field is there
and what happens without it: [`helix-agent-prompt.md`](helix-agent-prompt.md).

**Step 1 — create the API and verify Okta's tokens on it**

```text
First, confirm the openid-connect plugin exists in this org and show me its
schema. If it is not present, stop and tell me — do not substitute another plugin.

Then create a REST API "<<Partner Posts API>>" on upstream <<UPSTREAM_URL>>, with
routes GET /posts, GET /posts/{postId} and POST /posts proxied straight through,
protected by access tokens issued by Okta. The gateway must only VERIFY these
tokens, never issue any. Not helix-auth — it only verifies tokens it minted
itself, and it has no JWKS, issuer or audience field.

Apply openid-connect at the API level, not per route: every route here needs a
token and there is no token endpoint to leave open.

Configure it with:
  discovery: <<OKTA_DISCOVERY_URL>>
  client_id: <<OKTA_CLIENT_ID>>
  client_secret: <<OKTA_CLIENT_SECRET>>
  bearer_only: true and unauth_action: deny   (unauth_action's default REDIRECTS
    API callers to the IdP's login page instead of refusing them; bearer_only
    cannot be omitted either — the deploy is rejected without it, asking for
    session.secret)
  use_jwks: true   (REQUIRED, and NOT in the published schema — add it anyway, it
    is accepted and persisted. Without it the plugin never checks the JWT against
    the JWKS; it falls back to introspection, the IdP has no introspection
    endpoint, and EVERY token gets a 401.)
  ssl_verify: true
  accept_unsupported_alg: false and accept_none_alg: false
  token_signing_alg_values_expected: RS256
  claim_validator.issuer.valid_issuers: [ <<OKTA_ISSUER_URL>> ]
  claim_validator.audience.required: true
  jwk_expires_in: 3600
  set_id_token_header: false and set_userinfo_header: false

Also add request-id, and cors with authorization in the allowed headers.

Plugins go in a top-level "plugins" map on the route object, each under its own
plugin name. No "x-helix-gateway" wrapper — a live route discards it silently and
still reports success.

Show me the spec, then read the revision back so I can see which plugins actually
landed. Do not deploy yet.
```

**Step 2 — make the agent review its own work, then dry-run**

```text
Before deploying: re-read the openid-connect schema from this org and tell me,
field by field, whether every value I asked for is a real field with a legal
value. Call out anything you had to guess or drop.

use_jwks will NOT be in that schema. Keep it anyway — confirm it is still in the
spec you are about to deploy, and do not "clean it up".

Then bind the upstream and run a dry-run deploy. Report exactly what it returns,
and stop there.
```

The agent fetches the real `openid-connect` schema from your org, proposes the
spec, and stops. See [AGENT-GUIDE.md](../../AGENT-GUIDE.md) for what to do when it
takes a wrong turn.

## Install it directly

1. Import [`gateway/api-spec.yaml`](gateway/api-spec.yaml).
2. Bind an upstream on the revision, per environment.
3. Replace the four `<OKTA_...>` placeholders with real values (see below).
4. Dry-run the deploy, then deploy the revision.
5. Run [`gateway/verify.sh`](gateway/verify.sh).

## Step 1 — create the API and verify Okta's tokens on it

```text
First, confirm the openid-connect plugin exists in this org and show me its
schema. If it is not present, stop and tell me — do not substitute another plugin.

Then create a REST API "<<Partner Posts API>>" on upstream <<UPSTREAM_URL>>, with
routes GET /posts, GET /posts/{postId} and POST /posts proxied straight through,
protected by access tokens issued by Okta. The gateway must only VERIFY these
tokens, never issue any. Not helix-auth — it only verifies tokens it minted
itself, and it has no JWKS, issuer or audience field.

Apply openid-connect at the API level, not per route: every route here needs a
token and there is no token endpoint to leave open.

Configure it with:
  discovery: <<OKTA_DISCOVERY_URL>>
  client_id: <<OKTA_CLIENT_ID>>
  client_secret: <<OKTA_CLIENT_SECRET>>
  bearer_only: true and unauth_action: deny   (unauth_action's default REDIRECTS
    API callers to the IdP's login page instead of refusing them; bearer_only
    cannot be omitted either — the deploy is rejected without it, asking for
    session.secret)
  use_jwks: true   (REQUIRED, and NOT in the published schema — add it anyway, it
    is accepted and persisted. Without it the plugin never checks the JWT against
    the JWKS; it falls back to introspection, the IdP has no introspection
    endpoint, and EVERY token gets a 401.)
  ssl_verify: true
  accept_unsupported_alg: false and accept_none_alg: false
  token_signing_alg_values_expected: RS256
  claim_validator.issuer.valid_issuers: [ <<OKTA_ISSUER_URL>> ]
  claim_validator.audience.required: true
  jwk_expires_in: 3600
  set_id_token_header: false and set_userinfo_header: false

Also add request-id, and cors with authorization in the allowed headers.

Plugins go in a top-level "plugins" map on the route object, each under its own
plugin name. No "x-helix-gateway" wrapper — a live route discards it silently and
still reports success.

Show me the spec, then read the revision back so I can see which plugins actually
landed. Do not deploy yet.
```

## Step 2 — make the agent review its own work, then dry-run

```text
Before deploying: re-read the openid-connect schema from this org and tell me,
field by field, whether every value I asked for is a real field with a legal
value. Call out anything you had to guess or drop.

use_jwks will NOT be in that schema. Keep it anyway — confirm it is still in the
spec you are about to deploy, and do not "clean it up".

Then bind the upstream and run a dry-run deploy. Report exactly what it returns,
and stop there.
```

---

## Why it's shaped this way

- **"Confirm the plugin exists, do not substitute."** `openid-connect` is absent
  from some builds. Without this the agent reaches for `helix-auth` and produces
  something that looks right and cannot work.
- **`use_jwks: true`, flagged as schema-absent.** The single most important line.
  The agent won't find it in `get_plugin_config` and will drop it as a mistake
  unless told not to — and the resulting spec imports, dry-runs and deploys
  cleanly, then rejects every token.
- **`unauth_action: deny`, with what breaks.** Explaining the 302 is what makes the
  agent keep the field when it starts trimming.
- **The defaults worth overriding.** `ssl_verify` defaults to false;
  `accept_unsupported_alg` defaults to true and its own description is "ignore the
  signature"; `set_userinfo_header` adds a per-request round trip to Okta; without
  `valid_issuers` any issuer the plugin can reach is trusted.
- **API level, not per route.** The opposite of [solution 02](../02-oauth-jwt/)'s
  rule — an agent that has seen that one will scope per route out of habit. Here
  there is no token endpoint to leave reachable.
- **Step 2 at all.** It turns the agent into its own reviewer against the live
  schema, which is what catches the dropped fields.

## Tweak knobs

**Require a scope, not just a valid token**
```text
Add required_scopes so only tokens carrying "<<orders.read>>" are accepted, and
tell me what a token without it now returns.
```

**Point at my real upstream**
```text
Change the upstream to <<https://api.internal.example.com>> and re-run the
dry-run. Leave the auth configuration untouched.
```

**My authorization server issues opaque tokens, not JWTs**
```text
This Okta authorization server issues opaque access tokens, so there is no
signature to verify locally. Reconfigure openid-connect to use
introspection_endpoint instead, and tell me what that changes about latency and
what happens when Okta is unreachable.
```

**Use the org authorization server instead of a custom one**
```text
Switch discovery to https://<<your-okta-domain>>/.well-known/openid-configuration
and update valid_issuers to match the issuer that document reports.
```

## When it goes wrong

| Symptom | Cause |
|---|---|
| Every token 401s, though the spec deployed cleanly | `use_jwks` was dropped. Reply: it's absent from the schema but accepted and persisted — put it back and redeploy. |
| The API redirects instead of refusing | `unauth_action` is at its default. Always test with no token first. |
| The proposed spec has `discovery`, `client_id`, `client_secret` and nothing else | The hardening fields were dropped. Step 2's field-by-field check is what catches this. |
| The agent reaches for `helix-auth` | Reply: it has no JWKS URL, issuer or audience field and its schema is `additionalProperties: false`. Re-read the `openid-connect` schema. |
| The agent proposes `jwt-auth` as a standalone plugin | It isn't one here — only a `validate_auth_type` of `helix-auth`, and it means a token *this* gateway signed. |
| The agent invents an `audience` field with an expected value | There isn't one. `claim_validator.audience` has `required`, `claim` and `match_with_client_id`. |

## Related

- **[02 — OAuth 2.0 with JWT](../02-oauth-jwt/)** — the gateway as issuer. Read
  the fork in this solution's README before choosing.
- **[01 — API Products](../01-api-products/)** — per-app quotas, and why they do
  not follow automatically from an Okta-issued token.
- **[04 — Analytics](../04-analytics/)** — every call captured regardless of which
  plugin authenticated it.
