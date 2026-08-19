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

> **Run it in steps, not as one mega-prompt.** These are the exact prompts
> verified on the **default agent model**. Paste **Step 1**, let the agent create
> the API and stop at the dry-run; confirm; then paste **Step 2**. Folding the
> whole build into a single prompt pushes a smaller model to attempt one oversized
> change and stall — one bounded ask per step is what keeps it reliable. Replace
> the `<<...>>` values.

**Step 1 — create and protect the API**

```text
Create a new REST API called "<<Posts API>>" and protect it with OAuth 2.0
client-credentials authentication. This is a fresh org — I have no existing API.

Upstream: https://jsonplaceholder.typicode.com (public, so it returns real data;
I'll swap in my own later). Deploy to the "test" environment.

Routes (paths match the upstream, so no path rewrite): GET /posts,
GET /posts/{postId}, POST /posts.

Add POST /oauth/token using helix-auth generate — it verifies an app's client id
and secret and issues a signed JWT, 15-minute lifetime. Protect the /posts routes
with helix-auth validate, validate_auth_type jwt-auth, referencing the SAME
signing secret. Apply validate per route, not API-wide (or /oauth/token would be
protected and nobody could get a first token).

The signing secret is a LITERAL on this build — no <ENV:...> resolution — so use
one real, high-entropy value in both places and don't commit it. jwt-auth is a
validate_auth_type of helix-auth, not a standalone plugin.

Check get_plugin_config for helix-auth before writing config. Show me the spec,
run validate_route and dry_run_deploy, and wait before deploying.
```

**Step 2 — create an app and test it** (same session, after Step 1 deploys)

```text
Create a developer "<<Partner Integrations>>" with an app subscribed to this API,
and give me the client id and secret so I can test the token exchange.

Then give me curl commands that show, in order: no token → 401; client credentials
→ 200 with an access_token; that token → 200 on /posts with real data; a garbage
token → 401; and the CORRECT client id with a WRONG secret → 401. That last one
proves the secret is actually verified rather than decorative.
```

The agent creates the API, fetches the real `helix-auth` schema from your org,
proposes the spec, and stops for your confirmation. See
[AGENT-GUIDE.md](../../AGENT-GUIDE.md) for why the prompt is shaped this way and
what to do when the agent takes a wrong turn.

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
- **[Solution 04 — Analytics](../04-analytics/charts.md)** — the usage
  questions you can ask once identity is resolved here.
