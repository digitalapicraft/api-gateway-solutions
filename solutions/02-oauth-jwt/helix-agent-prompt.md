# Agent-mode prompt — OAuth 2.0 with gateway-issued JWTs

Three steps to an API behind a token exchange: the protected routes, then the
token endpoint, then an app to test with. Replace the `<<...>>` values.
[AGENT-GUIDE.md](../../AGENT-GUIDE.md) carries the standing rules these prompts
assume.

**The token route is its own step on purpose.** All four routes in one write puts
two `helix-auth` configurations in a single route array, which is deep enough to
trip the agent's argument-serialisation defect: the run ends `stream closed with
reason: error` and nothing is written. Verified twice against a clean org; two
smaller writes both land.

---

## Step 1 — the API and the protected routes

```text
Create a REST API "<<Posts API>>" on upstream https://jsonplaceholder.typicode.com,
environment test. Routes GET /posts, GET /posts/{postId} and POST /posts, proxied
straight through.

Protect all three with helix-auth validate, jwt-auth, signing_secret
<<JWT_SIGNING_SECRET>> verbatim.

Put helix-auth on each route and NOT in the service spec. A service-spec block
applies to every route including the token endpoint I add next, and a caller with
no token could then never get one.

Plugins go in a top-level "plugins" map on the route object, each under its own
plugin name, with no "x-helix-gateway" wrapper.

Show me the spec and the stored revision. Do not deploy.
```

## Step 2 — the token endpoint

```text
On the "<<Posts API>>" API, add POST /oauth/token with helix-auth generate,
token_ttl 900, signing_secret <<JWT_SIGNING_SECRET>> — the same value the other
routes use. generate only, no validate block on this route.

Leave the three existing routes unchanged.

Show me the stored revision. Do not deploy.
```

## Step 3 — an app to test with

```text
Create a developer "<<Partner Integrations>>" with an app subscribed to the
"<<Posts API>>" API, and give me the client id and secret.

Then curl commands showing, in order: no token -> 401; client credentials -> 200
with an access_token; that token -> 200 on /posts; a garbage token -> 401; and the
CORRECT client id with a WRONG secret -> 401.
```

That last call is the one people skip, and the only one that proves the secret is
verified rather than decorative.

---

## Why it's shaped this way

- **`helix-auth` generate and validate, not a `jwt-auth` plugin.** `jwt-auth` is a
  `validate_auth_type` here, not a standalone plugin — and it still means "a JWT
  this gateway signed". An external issuer is [solution 05](../05-okta-jwt/).
- **Every step names the API.** A step that says "the routes you just wrote"
  depends on conversation context; resumed in a session whose active API is
  something else, the agent edits that one instead. Naming it is enough — the
  agent finds it and asks when the name is ambiguous, unprompted.
- **"NOT in the service spec", not "not API-wide".** The abstract phrasing was
  tested and failed: told "per route, not API-wide", the agent wrote the routes
  correctly *and* added `helix-auth` validate to the service spec, which covers
  the token endpoint and locks everyone out. Naming the artifact, with the
  consequence, is what holds. It is the one piece of reasoning in this prompt
  that earns its line.
- **The token route is written second.** Four routes and two `helix-auth`
  configurations in one write trips the serialisation defect reproducibly — two
  clean-org runs, `stream closed with reason: error`, nothing written. Split, both
  writes land.
- **The same signing secret in both places.** A mismatch rejects every freshly
  issued token, and neither side's config hints that the value is shared.
- **`validate` per route.** An agent tidying up will hoist it to the document
  root, which protects `/oauth/token` and 401s the request that issues tokens.
- **The secret is a literal.** This build does not resolve `<ENV:...>` or `${...}`.
  Ship the placeholder and the placeholder *is* your signing key.
- **Read the revision back.** Three of the four known agent-mode defects report
  success at every step the agent shows you; the read-back is what catches them.

## Tweak knobs

**An external identity provider already issues the tokens**
```text
Our tokens come from <<Keycloak>>, not the gateway. Drop /oauth/token and switch
the protected routes to openid-connect against that issuer's discovery document,
bearer_only true, unauth_action deny. Not helix-auth — it only verifies tokens it
minted itself, and it has no JWKS, issuer or audience field.
```

**Point at my real upstream**
```text
Rebind the upstream to <<https://my-backend.internal>> and keep everything else.
Add a proxy-rewrite if my backend's paths differ from the route paths.
```

**Shorter tokens for a high-value path**
```text
Reduce the token lifetime to 300 seconds, then tell me what that does to token
endpoint traffic at 50 calls/min and what caching behaviour I should document.
```

**Layer metering on top**
```text
Now meter these callers. Add api-product-enforcer behind the helix-auth block on
the protected routes, create products for the tiers I sell, and confirm the route
has a service_id. No limit-count keyed on consumer_name — the product quota
already counts per app.
```
(That's [solution 01](../01-api-products/).)

## When it goes wrong

| Symptom | Cause |
|---|---|
| Every call 401s, including with a fresh token | The signing secret differs between the issue and validate routes. |
| Every call 401s including `/oauth/token` | `validate` was applied API-wide. Move it to the protected routes only. |
| The token endpoint 401s on credentials you're sure are right | You're sending the app's secret where its client id belongs. |
| The agent reaches for a `jwt-auth` plugin | Reply: `jwt-auth` is a `validate_auth_type` of `helix-auth`, not a plugin. |
| The agent writes `<ENV:JWT_SIGNING_SECRET>` | Reply: this build uses `signing_secret` verbatim — put a real secret and keep it out of git. |
| `stream closed with reason: error`, and the revision has 0 routes | The write was too deep for the agent's serialiser and never reached the control plane. Keep the steps split; don't fold step 2 back into step 1. |
| Deploy fails: `Only INACTIVE revisions can be updated` | Clone the revision or undeploy, then apply. |

## Related

- **[Solution 03 — SOAP to REST](../03-soap-to-rest/helix-agent-prompt.md)** — the
  same auth steps, with protocol mediation in front.
- **[Solution 01 — API Products](../01-api-products/helix-agent-prompt.md)** —
  metering the callers this solution identifies.
- **[Solution 04 — Analytics](../04-analytics/charts.md)** — the usage
  questions you can ask once identity is resolved here.
