# Agent-mode prompt — OAuth 2.0 with gateway-issued JWTs

Two steps, from a **fresh, empty org** to an API behind a token exchange. The
agent creates the API on a public upstream, adds the token endpoint, protects the
other routes, dry-runs, and hands you an app's credentials to test with.

Paste one step at a time and confirm between them; a single mega-prompt pushes a
smaller model into one oversized tool call. Replace the `<<...>>` values.
[AGENT-GUIDE.md](../../AGENT-GUIDE.md) carries the standing rules these prompts
assume.

---

## Step 1 — create and protect the API

```text
Create a REST API "<<Posts API>>" on upstream https://jsonplaceholder.typicode.com,
environment test, with routes GET /posts, GET /posts/{postId} and POST /posts
proxied straight through. Fresh org — nothing exists yet.

Add POST /oauth/token using helix-auth in generate mode: it verifies an app's
client id and secret and issues a signed JWT with a 15-minute lifetime — long
enough to be usable, short enough that a leaked one expires before it's useful.

Protect the /posts routes with helix-auth validate, jwt-auth, referencing the SAME
signing secret. Apply validate PER ROUTE, not API-wide — API-wide would protect
/oauth/token and nobody could get a first token.

The signing secret is a literal on this build: no <ENV:...> resolution, so put one
real high-entropy value in both places and remind me not to commit it.

Plugins go in a top-level "plugins" map on the route object, each under its own
plugin name. No "x-helix-gateway" wrapper — a live route discards it silently and
still reports success.

Show me the spec, run dry_run_deploy, then read the revision back so I can see
which plugins actually landed. Wait before deploying.
```

## Step 2 — an app, and the five calls that prove it

```text
Create a developer "<<Partner Integrations>>" with an app subscribed to this API,
and give me the client id and secret.

Then give me curl commands showing, in order: no token → 401; client credentials
→ 200 with an access_token; that token → 200 on /posts with real data; a garbage
token → 401; and the CORRECT client id with a WRONG secret → 401.
```

That last call is the one people skip, and it is the only one that proves the
secret is verified rather than decorative.

---

## Why it's shaped this way

- **`helix-auth` generate and validate, not a `jwt-auth` plugin.** `jwt-auth` is a
  `validate_auth_type` here, not a standalone plugin — and it still means "a JWT
  this gateway signed". An external issuer is [solution 05](../05-okta-jwt/).
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
| Deploy fails: `Only INACTIVE revisions can be updated` | Clone the revision or undeploy, then apply. |

## Related

- **[Solution 03 — SOAP to REST](../03-soap-to-rest/helix-agent-prompt.md)** — the
  same auth steps, with protocol mediation in front.
- **[Solution 01 — API Products](../01-api-products/helix-agent-prompt.md)** —
  metering the callers this solution identifies.
- **[Solution 04 — Analytics](../04-analytics/charts.md)** — the usage
  questions you can ask once identity is resolved here.
