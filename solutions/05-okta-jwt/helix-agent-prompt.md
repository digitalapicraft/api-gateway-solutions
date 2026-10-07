# Agent-mode prompt — checking Okta-issued tokens

> [Overview](README.md) · [Business need](business-need.md) · [Architecture](architecture.md) · [Guides](guides.md) · **Agent prompt** · [Tests](tests.md) · [API reference](api-reference.md)

---

Works from a fresh, empty org, as long as it includes the `openid-connect` plugin.
Replace the `{{...}}` values, then **paste Step 1, check what it shows you, and
paste Step 2**. Before you trust the result, read the deployed revision back and
check `use_jwks: true` and `bearer_only: true` are on `openid-connect`. Why the
prompt is worded this way, and what to do if something looks off, are in
[Guides](guides.md#build-it-with-the-helix-agent).

## Prompt

### Step 1 — create the API and verify Okta's tokens on it

```text
First, confirm the openid-connect plugin exists in this org and show me its
schema. If it is not present, stop and tell me — do not substitute another plugin.

Then create a REST API "{{api_name}}" on upstream {{upstream_url}}, with
routes GET /posts, GET /posts/{postId} and POST /posts proxied straight through,
protected by access tokens issued by Okta. The gateway must only VERIFY these
tokens, never issue any. Not helix-auth — it only verifies tokens it minted
itself, and it has no JWKS, issuer or audience field.

Apply openid-connect at the API level, not per route: every route here needs a
token and there is no token endpoint to leave open.

Configure it with:
  discovery: {{okta_discovery_url}}
  client_id: {{okta_client_id}}
  client_secret: {{okta_client_secret}}
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
  claim_validator.issuer.valid_issuers: [ {{okta_issuer_url}} ]
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

### Step 2 — make the agent review its own work, then dry-run

```text
Before deploying: re-read the openid-connect schema from this org and tell me,
field by field, whether every value I asked for is a real field with a legal
value. Call out anything you had to guess or drop.

use_jwks will NOT be in that schema. Keep it anyway — confirm it is still in the
spec you are about to deploy, and do not "clean it up".

Then bind the upstream and run a dry-run deploy. Report exactly what it returns,
and stop there.
```
