# Agent-mode prompt — OAuth 2.0 with gateway-issued JWTs

Paste this into **Helix Agent Mode**. It works from a **fresh, empty org**: the
agent *creates* the API (there's nothing pre-existing to find), binds a public
upstream so you get real data immediately, adds the token endpoint, protects the
other routes, dry-runs, and hands you an app's credentials to test with.

Replace the `<<...>>` values. Everything else is deliberate — the table below
says why each block earns its place. Read [AGENT-GUIDE.md](../../AGENT-GUIDE.md)
first if you haven't.

---

## The prompt

```text
Create a new REST API and protect it with OAuth 2.0 client-credentials
authentication, so callers exchange a client id and secret for a short-lived
token instead of sending a static key on every request.

CONTEXT
- This is a fresh org — I do NOT have an existing API. Create one.
- API name: <<Posts API>>
- Upstream: https://jsonplaceholder.typicode.com   (a public REST service, so the
  API returns real data with no backend of my own; I'll swap in my real upstream
  later)
- Environment: test   (my free-trial org's default environment)
- The gateway is the token issuer. There is no external identity provider.

WHAT I WANT

1. Create the API with these routes, proxying the upstream (the route paths match
   the upstream paths, so no path rewrite is needed):
     - GET  /posts            -> lists posts
     - GET  /posts/{postId}   -> one post
     - POST /posts            -> create a post
   Bind the upstream above and deploy to the "test" environment.

2. A token endpoint: POST /oauth/token
   Use helix-auth in generate mode. It should verify the calling app's client id
   and secret (Authorization: Basic base64(client_id:secret)) and return a signed
   JWT with token_type Bearer and expires_in. Token lifetime 900 seconds — a
   leaked token should be worthless within fifteen minutes, so do not default it
   to an hour.

3. Protect /posts and /posts/{postId} (all methods).
   Use helix-auth in validate mode with validate_auth_type jwt-auth, referencing
   the SAME signing secret. A request with no token, a malformed Authorization
   header, an expired token, or a token this gateway did not sign must be rejected
   at the gateway and never reach the upstream. Apply validate PER ROUTE on the
   protected routes — do NOT apply it API-wide, or it would protect /oauth/token
   too and no caller could ever get a first token.

4. Add request-id (uuid, header X-Request-Id) API-wide, and cors allowing the
   "authorization" and "content-type" headers with allow_credential false.

CONSTRAINTS — known platform behaviour, please respect these
- Use helix-auth in generate mode for issuing and validate mode with
  validate_auth_type jwt-auth for verifying. jwt-auth and key-auth are
  validate_auth_type VALUES of helix-auth, not standalone plugins on this build.
- The signing secret is a LITERAL. This build does NOT resolve <ENV:...> or
  ${...} syntax — the string in signing_secret is used verbatim as the HMAC key.
  Use one real, high-entropy value on the token route and every validate route,
  and do not commit it. If you cannot store a secret for me, use a clear
  placeholder and tell me to replace it before deploy.
- Check get_plugin_config for helix-auth before writing config. Only schema
  fields plus _meta are legal — no invented or commentary fields.
- If you need a conditional match, use filter_func (a Lua expression string),
  not vars — vars fails at deploy time.

BEFORE YOU DEPLOY
- Show me the full spec you are about to apply and wait for my confirmation.
- Run validate_route and dry_run_deploy first. If either fails, show me the error
  and your proposed fix rather than retrying blindly.
- Tell me the execution order of the plugins on a protected route, and confirm
  the rejection happens in the access phase before the upstream is called.

AFTER YOU DEPLOY
- Create a developer "<<Partner Integrations>>" with ONE app subscribed to this
  API, and give me its client id and client secret.
- Give me curl commands that show, in order: no token → 401; client credentials
  → 200 with an access_token; that token → 200 on /posts with real data; a
  garbage token → 401; and the CORRECT client id with a WRONG secret → 401.
- That last one matters: if a wrong secret still issues a token, this is a
  static-key flow wearing a token's clothes, and I want to know now.
- Tell me plainly what a rejected caller sees — status, body, and which headers
  are absent — so I can write the developer documentation.

If anything is ambiguous — the environment, the upstream, whether a signing
secret exists — ask me instead of guessing.
```

---

## Why the prompt is shaped this way

| Block | Why it's there |
|---|---|
| **"This is a fresh org — create one"** | On a new free-trial org there is no API to "find". The agent must create it, or it stalls looking for something that isn't there. |
| **"Upstream: jsonplaceholder … real data with no backend of my own"** | Gives you a working end-to-end result on a fresh org — real responses behind the auth — without standing up a backend. Swap it for your own later. |
| **"Environment: test"** | Free-trial orgs get a `test` environment by default; that's where things deploy. |
| **"route paths match the upstream paths, so no path rewrite is needed"** | `/posts` is forwarded to the upstream's `/posts` unchanged — keeps the spec clean (no `proxy-rewrite`). Verified. |
| **"generate … validate with validate_auth_type jwt-auth; not standalone plugins"** | The most likely wrong turn. A general model reaches for a `jwt-auth` plugin by name — it doesn't exist here; it's a mode of `helix-auth`. |
| **"the signing secret is a LITERAL … no `<ENV:...>` resolution"** | Verified platform behaviour. Left as an env-style placeholder, the literal string becomes your public signing key. |
| **"the SAME signing secret"** | Stated twice on purpose — a mismatch rejects every freshly issued token and neither side's config hints the value is shared. |
| **"Apply validate PER ROUTE — do NOT apply it API-wide"** | An agent tidying up hoists the block to the root, protecting `/oauth/token`; then every request 401s, including the one that issues tokens. |
| **"Token lifetime 900 … do not default to an hour"** | The TTL is the only bound on a leaked token; make it a conscious choice with a reason. |
| **"authorization must be in allow_headers"** | Omit it and browser clients fail at preflight — a CORS error, not a 401, sending people to debug the wrong layer. |
| **"the CORRECT client id with a WRONG secret → 401"** | The one test people skip; it proves the secret is actually verified rather than decorative. |

## Tweak knobs

**An external identity provider already issues the tokens**
```text
Actually, our tokens come from <<Keycloak>>, not the gateway. Drop the
/oauth/token route and switch the protected routes to helix-auth validate with
validate_auth_type jwt-auth, verifying against the issuer's public key or JWKS.
The gateway must be a verifier only — it must not mint tokens that IdP owns.
```

**Point it at my real upstream instead of jsonplaceholder**
```text
Rebind the upstream to <<https://my-backend.internal>> and keep everything else.
If my backend's paths differ from the route paths, add a proxy-rewrite to map
them; otherwise leave the routes proxying straight through.
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
has a service_id. Don't add a limit-count keyed on consumer_name — the product
quota already counts per app.
```
(That's [solution 03](../03-api-products/).)

## Known failure modes when running this prompt

- **The agent looks for an existing API and stalls.** Remind it: this is a fresh
  org, create the API with the jsonplaceholder upstream.
- **Every call returns 401, including with a fresh token.** The signing secret
  differs between the issue and validate routes — make both the same literal
  value.
- **Every call returns 401 including `/oauth/token`.** `validate` got applied
  API-wide. Move it to the protected routes only.
- **The agent reaches for a `jwt-auth` plugin.** Reply: `jwt-auth is a
  validate_auth_type of helix-auth on this build, not a plugin — use helix-auth
  generate to issue and validate to verify.`
- **The agent writes `<ENV:JWT_SIGNING_SECRET>` expecting it to resolve.** Reply:
  `this build uses signing_secret literally — put a real secret and tell me to
  keep it out of git.`
- **The token endpoint 401s with credentials you're sure are right.** You're
  sending the app's *secret* where its *client id* belongs.
- **Deploy fails with `Only INACTIVE revisions can be updated`.** Clone the
  revision or undeploy, then apply.

## Related

- **[Solution 02 — SOAP to REST](../02-soap-to-rest/helix-agent-prompt.md)** — the
  same auth acts, with protocol mediation in front (bring your own SOAP backend).
- **[Solution 03 — API Products](../03-api-products/helix-agent-prompt.md)** —
  metering the callers this solution identifies.
- **[Solution 04 — Analytics](../04-analytics/helix-agent-prompt.md)** — the usage
  questions you can ask once identity is resolved here.
