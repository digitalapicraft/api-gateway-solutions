# Agent-mode prompt — verifying Okta-issued tokens

Works from a fresh, empty org. Replace the `<<...>>` values with your own before
pasting. The prompts below mirror the ones in the
[README](README.md#build-it-with-the-helix-agent) — that is the copy the harness
runs, so the two are kept identical on purpose.

Background on how agent mode behaves, and what to do when it takes a wrong turn:
[AGENT-GUIDE.md](../../AGENT-GUIDE.md).

---

## The prompt

> **Run it in steps, not as one mega-prompt.** This configuration has fourteen
> fields, four of which override defaults. Asked for in one go, the default agent
> model tends to emit a single oversized tool call and silently drop the fields it
> ran out of room for — and the ones it drops are the hardening ones, because they
> come last.

**Step 1 — create the API and verify Okta's tokens on it**

```text
First, confirm the openid-connect plugin exists in this org and show me its
schema. If it is not present, stop and tell me — do not substitute another plugin.

Then create a new REST API called "<<Partner Posts API>>" and protect it with
access tokens issued by Okta. The gateway must only VERIFY these tokens; it must
not issue any. Do not use helix-auth — it verifies tokens it minted itself and has
no JWKS, issuer or audience field.

Upstream: <<UPSTREAM_URL>>. Routes, paths matching the upstream so no path
rewrite: GET /posts, GET /posts/{postId}, POST /posts.

Apply openid-connect at the API level, not per route — every route here needs a
token and there is no token endpoint to leave open.

Configure it with:
  discovery: <<OKTA_DISCOVERY_URL>>
  client_id: <<OKTA_CLIENT_ID>>
  client_secret: <<OKTA_CLIENT_SECRET>>
  bearer_only: true and unauth_action: deny
  use_jwks: true   (REQUIRED. Without it the plugin does not verify the JWT
    against the JWKS at all — it falls back to token introspection, the IdP has no
    introspection endpoint, and EVERY token gets a 401. It is not in the published
    plugin schema; add it anyway, it is accepted and persisted.)
  ssl_verify: true
  accept_unsupported_alg: false and accept_none_alg: false
  token_signing_alg_values_expected: RS256
  claim_validator.issuer.valid_issuers: [ <<OKTA_ISSUER_URL>> ]
  claim_validator.audience.required: true
  jwk_expires_in: 3600
  set_id_token_header: false and set_userinfo_header: false

Also add request-id, and cors with authorization in the allowed headers.

We are editing a LIVE route object, not authoring an OpenAPI document — so do not
follow the spec-generator examples for plugin placement. Each route object in
routeSpec takes "plugins" as a TOP-LEVEL key, and inside it each plugin is
keyed by its own NAME:
  { "name": ..., "uri": ..., "methods": [...], "service_id": ...,
    "plugins": { "<plugin-name>": { <that plugin's own fields> } } }
Do not promote a plugin's fields into the plugins map: "plugins":
{"response_status": 202, "content_type": ...} is four broken plugins, not one
working one — the plugin name level is mandatory.
There must be no "x-helix-gateway" key anywhere in a route object: a live route
silently discards that wrapper, the write still reports success, and the route
deploys with no plugins at all.

Show me the spec, then call get_revision and show me
the stored routeSpec so I can see the plugins landed. Do not deploy yet.
```

**Step 2 — check it, then dry-run**

```text
Before deploying: re-read the openid-connect schema from this org and tell me,
field by field, whether every value I asked for is a real field with a legal
value. Call out anything you had to guess or drop.

use_jwks will NOT be in that schema. Keep it anyway — confirm it is still present
in the spec you are about to deploy, and do not "clean it up".

Then bind the upstream and run a dry-run deploy. Report exactly what it returns.
Do not deploy the revision — stop after the dry-run.
```

---

## Why the prompt is shaped this way

| Block | Why it's there |
|---|---|
| "confirm the plugin exists … do not substitute" | `openid-connect` is absent from some builds. Without this the agent helpfully reaches for `helix-auth` and produces something that looks right and cannot work |
| "must only VERIFY … must not issue" | States the issuer boundary in the first sentence, before any plugin is named |
| "Do not use helix-auth — it has no JWKS, issuer or audience field" | The single most likely wrong turn, pre-empted with the reason rather than just the instruction |
| "at the API level, not per route" | The opposite of solution 01's rule. An agent that has seen 01 will scope per route out of habit |
| `use_jwks: true`, flagged as required and schema-absent | **The single most important line.** The agent will not find it in `get_plugin_config` and will drop it as a mistake unless told not to. Without it every token 401s |
| `unauth_action: deny` with the 302 explanation | Explaining *what breaks* makes the agent keep the field when it starts trimming |
| `ssl_verify: true` | Overrides a `false` default that no one would guess |
| `accept_unsupported_alg: false` | Overrides a `true` default whose own description is "ignore the signature" |
| `valid_issuers` | Without it, any issuer the plugin can reach is trusted |
| `jwk_expires_in: 3600` with the rotation note | Otherwise dropped as an unimportant tuning value |
| `set_userinfo_header: false` | Silently adds a per-request round trip to Okta if left at its default |
| "Show me the spec and wait" | Keeps a human between the proposal and the deploy |
| Step 2's "field by field … call out anything you had to guess" | Turns the agent into its own reviewer against the live schema, which catches dropped fields |

## Tweak knobs

**Require a scope, not just a valid token**

```text
Add required_scopes to the openid-connect config so that only tokens carrying
the "<<orders.read>>" scope are accepted, and tell me what a token without it
now returns.
```

**Point it at my real upstream instead of jsonplaceholder**

```text
Change the upstream for this API to <<https://api.internal.example.com>> and
re-run the dry-run. Leave the auth configuration untouched.
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
Switch discovery to the org authorization server
(https://<<your-okta-domain>>/.well-known/openid-configuration) and update
valid_issuers to match the issuer that document reports.
```

## Known failure modes when running this prompt

- **The agent reaches for `helix-auth`.** The most common wrong turn, because
  `helix-auth` is the identity plugin in every other solution. Reply: *"helix-auth
  has no JWKS URL, issuer or audience field and its schema is
  additionalProperties: false. Re-read the openid-connect schema and use that."*
- **The agent proposes `jwt-auth` as a standalone plugin.** It is not present on
  these builds; on the ones that have `helix-auth` it exists only as a
  `validate_auth_type` value.
- **The hardening fields get dropped.** Symptom: the proposed spec has
  `discovery`, `client_id`, `client_secret` and nothing else. Step 2's field-by-
  field check is what catches this; run it.
- **`unauth_action` is left at its default.** The spec looks complete and the API
  redirects instead of refusing. Always test with no token first.
- **The agent drops `use_jwks` because the schema doesn't list it.** The most
  damaging failure mode, because the resulting spec imports, dry-runs and deploys
  cleanly — and then rejects every token. If the agent removes it, reply: *"use_jwks
  is absent from the schema but accepted and persisted; put it back and redeploy."*
- **The agent invents an `audience` field with an expected value.** There isn't
  one. `claim_validator.audience` has only `required`, `claim` and
  `match_with_client_id`.
- **The agent applies the plugin per route.** Harmless but noisier, and it
  invites someone to add an unprotected route later.

## Related

- **[01 — OAuth 2.0 with JWT](../01-oauth-jwt/)** — the gateway as issuer. Read
  the fork in this solution's README before choosing.
- **[03 — API Products](../03-api-products/)** — per-app quotas, and why they do
  not follow automatically from an Okta-issued token.
- **[04 — Analytics](../04-analytics/)** — every call captured regardless of which
  plugin authenticated it.
