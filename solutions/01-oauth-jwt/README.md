# Solution 01 — OAuth 2.0 with JWT, without touching the backend

**The gateway issues the token and verifies it. Your service never learns that
authentication happened.**

| | |
|---|---|
| **Setup time** | ~15 minutes |
| **Difficulty** | 🟢 Beginner |
| **Needs** | A fresh org (its default **test** environment) · a real signing-secret value to paste into the spec (used literally — see below) · one developer + app to test with. The upstream is public jsonplaceholder, so no backend of your own. |
| **Plugins** | `helix-auth` (generate + validate) · `request-id` · `cors` |
| **Build it with** | 🤖 **[the Helix Agent](helix-agent-prompt.md)** — recommended · or import [`gateway/api-spec.yaml`](gateway/api-spec.yaml) |
| **Assets** | ✅ [Agent prompt](helix-agent-prompt.md) · ✅ [Architecture](architecture.md) · ✅ [Business need](business-need.md) · ✅ [Spec](gateway/) · ✅ [Tests](tests/) · ✅ [Validation](validation/) · ✅ [Infographic](infographic.md) · ✅ [Manifest](solution.yaml) |

---

## The problem

> *"Our partner API has been public since 2019. Everybody knows it needs auth.
> The problem isn't agreement — it's that the service is a shared monolith on a
> quarterly release train, the team that owns it has a roadmap through Q3, and
> 'add OAuth' means a six-week release plus a coordinated migration for eleven
> partners. So it stays public, and we put it on the risk register instead."*

Three things are true at once, which is why this sits still for years:

1. **The API needs authentication.** Anyone with the URL is a caller.
2. **The backend cannot ship it soon.** Auth is cross-cutting, so it touches
   every handler, and the release train is full.
3. **Static API keys aren't enough.** They're long-lived, get emailed, get
   committed, and a leaked one is a leak until somebody notices. Partners with a
   security review will ask for OAuth by name.

**Root cause:** authentication is being treated as application logic when it's
edge logic. Nothing about verifying a caller's identity requires knowledge of
your domain model, so nothing about it needs to live in your domain code.

## Business need

Full version: [`business-need.md`](business-need.md).

| Dimension | Public / static-key API | With gateway-issued JWTs |
|---|---|---|
| **Time to ship auth** | A backend release cycle, plus coordinated partner migration | A configuration change and a revision deploy |
| **Credential exposure window** | A static key is valid until someone revokes it — often years | A token is valid for minutes; the long-lived secret never travels on API calls |
| **Backend blast radius** | Every handler touched; auth bugs become application bugs | Zero backend change; a bad token never reaches your code |
| **Partner security review** | "We use an API key in a header" | Standards-based OAuth 2.0 client credentials |
| **Revocation** | Find every place the key was configured | Disable the app; the next token request fails and existing tokens expire on their own |

The mechanism that matters commercially: **the credential that can be replayed
forever stops travelling on every request.** The long-lived secret is used once
per token lifetime against one endpoint; everything else carries something that
expires on its own.

## Who issues the token — decide this first

This is the fork in the road, and picking wrong means building the wrong half of
the flow.

| Your situation | Use | Why |
|---|---|---|
| **You have no identity provider**, and you want partners to exchange a client id and secret for a token | **`helix-auth` generate + validate** — this solution | The gateway *is* the issuer. It holds the signing secret, verifies the app's credentials, and mints the JWT. |
| **Keycloak / Auth0 / Entra ID / Okta already issues tokens** to your partners | **`helix-auth` validate, `validate_auth_type: jwt-auth`**, pointed at the issuer's key material. Drop the `/oauth/token` route. | The gateway is a *verifier only*. It must not mint tokens a separate IdP is authoritative for. |

`helix-auth` `generate` and `helix-auth` `validate` (jwt-auth) are not
alternatives to each other — they sit on opposite sides of the same boundary.
Verifying your own gateway-issued tokens against an external issuer, or issuing
tokens when an IdP already exists, produces a system with two sources of truth
about identity. (Note: `jwt-auth` is a `validate_auth_type` value of `helix-auth`,
not a standalone plugin on this build.)

Everything below is the first row.

## How a request flows

```
─── getting a token ────────────────────────────────────────────────────
Client
  │  POST /oauth/token
  │  Authorization: Basic base64(client_id:client_secret)
  ▼
helix-auth  (mode: generate)
  │  looks up the credential by client_id
  │  verifies client_secret        ← the ONLY mode that checks the secret
  │  signs a JWT with JWT_SIGNING_SECRET, ttl 900s
  ▼
200 { "access_token": "eyJ...", "token_type": "Bearer", "expires_in": 900 }

  bad credentials → 401, and no token is minted


─── calling the API ────────────────────────────────────────────────────
Client
  │  GET /posts
  │  Authorization: Bearer eyJ...
  ▼
helix-auth  (mode: validate, validate_auth_type: jwt-auth)   [access phase]
  │  verifies the signature with the SAME JWT_SIGNING_SECRET
  │  checks expiry
  │  resolves the calling app → identity is available to later plugins
  │
  ├── invalid / missing / expired → 401, request stops here
  ▼
Upstream  ← only ever sees requests that already passed
```

The important structural detail: validation happens in the **access phase**, so a
rejected request costs you nothing downstream. Your backend doesn't see it, your
database doesn't see it, and it doesn't consume a connection from your pool.

## Build it with the Helix Agent

Recommended path, and it works on a **fresh org** — the agent *creates* the API
(nothing to find yet) on a public upstream so you get real data immediately. Full
prompt with all the constraints: [`helix-agent-prompt.md`](helix-agent-prompt.md).

```text
Create a new REST API called "Posts API" and protect it with OAuth 2.0
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

Show me the spec, run validate_route and dry_run_deploy, and wait before deploying.
```

Then, in the same session:

```text
Create a developer "Partner Integrations" with an app subscribed to this API,
and give me the client id and secret so I can test the token exchange.
```

The agent creates the API, fetches the real `helix-auth` schema from your org,
proposes the spec, and stops. See [AGENT-GUIDE.md](../../AGENT-GUIDE.md) for why
the prompt is shaped this way and what to do when the agent takes a wrong turn.

## Install it directly

If you'd rather not go through the agent:

```bash
export ORG=<ORG_ID>
export TOKEN=<control-plane bearer token>      # short-lived
export BASE=https://<YOUR_GATEWAY_HOST>/api
H=(-H "authorization: Bearer $TOKEN" -H 'content-type: application/json')

# 1. Replace <YOUR_JWT_SIGNING_SECRET> in the spec with a real, high-entropy
#    secret. On this build it is used LITERALLY as the HMAC key — <ENV:...>
#    is not resolved. Use the SAME value on the token route and every protected
#    route. Do not commit the filled-in spec.

# 2. Import gateway/api-spec.yaml (OpenAPI import in the portal, or Agent Mode)
#    and bind the upstream https://jsonplaceholder.typicode.com to the service
#    (swap in your own backend later). Importing assigns service_id automatically.

# 3. Deploy the revision to the "test" environment (a free-trial org's default).

# 4. Create a developer and an app. The control plane issues the app's
#    client_id (the credential key) and client_secret. Keep both.

# 5. Prove it
GATEWAY=https://<YOUR_GATEWAY_HOST> \
CLIENT_ID=<CLIENT_ID> CLIENT_SECRET=<CLIENT_SECRET> EXPECT_TTL=900 \
./gateway/verify.sh          # defaults to /posts and /oauth/token
```

> An **ACTIVE** revision will not accept edits — you'll get `Only INACTIVE
> revisions can be updated`. Clone the revision (keeping the live one as a
> rollback target) or undeploy first.

## Configuration

Source of truth: [`gateway/api-spec.yaml`](gateway/api-spec.yaml). Two blocks
carry the whole solution.

On the token endpoint:

```yaml
helix-auth:
  mode: generate
  token_ttl: 900
  signing_secret: "<YOUR_JWT_SIGNING_SECRET>"
```

On every protected route:

```yaml
helix-auth:
  mode: validate
  validate_auth_type: jwt-auth
  signing_secret: "<YOUR_JWT_SIGNING_SECRET>"
```

**Note what isn't there.** `validate` is applied per route, not at the document
root. Applying it API-wide would protect `/oauth/token` too — and then no caller
could ever obtain a first token, because getting one would require already having
one. The symptom is an API where literally every request returns 401, including
the one that's supposed to fix that.

## Choosing a token lifetime

`token_ttl` is the only number in this solution with a real trade-off, so choose
it rather than inheriting a default.

| TTL | Buys you | Costs you |
|---|---|---|
| **300s** (5 min) | A leaked token is worthless almost immediately | A token request every five minutes per client; clients that don't cache will hammer the endpoint |
| **900s** (15 min) | Short exposure window, modest token traffic | Reasonable for most partner integrations — this is the default in this spec |
| **3600s** (1 hour) | Minimal token traffic | A leaked token is usable for up to an hour |
| **24h+** | Nothing worth having | You have reinvented the static API key, with extra steps |

The thing to tell integrators: **cache the token and reuse it until shortly
before it expires.** Refresh at around 80% of the lifetime. A client that
requests a fresh token per API call turns your token endpoint into your busiest
route and doubles the latency of everything.

## What the caller actually sees

Be precise about this in your developer docs, because it's what integrators hit.

Successful exchange:

```http
POST /oauth/token
Authorization: Basic <base64(client_id:client_secret)>

HTTP/1.1 200 OK
content-type: application/json

{"access_token":"eyJhbGciOiJIUzI1NiIs...","token_type":"Bearer","expires_in":900}
```

Every rejection on a protected route is a **401**:

```http
HTTP/1.1 401 Unauthorized
```

**All four failure causes look the same to the caller** — no token, malformed
header, expired token, bad signature. That is correct security behaviour (a
verbose error tells an attacker which half of their guess was right) and it is
genuinely awkward for integrators. Two consequences to design around:

- **Document the causes**, since the response won't distinguish them. "A 401
  means one of: no `Authorization` header, no `Bearer ` prefix, an expired token,
  or a token this gateway didn't sign."
- **Use the correlation id for support.** `X-Request-Id` is stamped on every
  call including the token exchange, so when a partner reports "it just returns
  401" you have something to search on.

## Testing

```bash
GATEWAY=https://<YOUR_GATEWAY_HOST> \
CLIENT_ID=<CLIENT_ID> CLIENT_SECRET=<CLIENT_SECRET> ./gateway/verify.sh
```

Exit 0 means all six cases held:

| # | Case | Expected |
|---|---|---|
| 1 | No token on a protected route | `401` |
| 2 | Valid client credentials at the token endpoint | `200` + a three-segment JWT |
| 3 | Valid Bearer token on a protected route | `200` |
| 4 | Forged token (valid shape, wrong signature) | `401` |
| 5 | **Correct client_id, wrong client_secret** | `401` |
| 6 | Token sent without the `Bearer ` prefix | `401` |

**Case 5 is the one to not skip.** It's what separates a real credentials flow
from a static-key flow in a token's clothing. If a wrong secret still gets you a
token, the secret isn't being checked and the whole design is decorative.

Case 4 matters for the same reason in the other direction: if a garbage token
returns 200, the route isn't validating at all — it's just passing traffic
through while looking configured.

Full plan including expiry (which needs a wait, so it's a manual case):
[`tests/test-plan.yaml`](tests/test-plan.yaml).

## Gotchas

Each of these has cost somebody an afternoon.

- **The signing secret must be identical on the issue route and every validate
  route.** A mismatch means every freshly issued token is rejected with an
  opaque 401 — the config looks correct on both sides, and the failure gives you
  no hint that it's about a *shared* value.
- **Set the environment secret before you deploy.** A spec referencing
  `<ENV:JWT_SIGNING_SECRET>` on an environment where it doesn't exist deploys
  cleanly and then fails at request time.
- **Never apply `validate` API-wide over the token endpoint.** See §
  *Configuration*. Every request 401s, including the one that issues tokens.
- **`authorization` must be in `cors.allow_headers`.** Otherwise browser clients
  fail at preflight and you get a CORS error, not a 401 — which sends people
  debugging the wrong layer for an hour.
- **`generate` is the only mode that checks the app's secret.** `key-auth`
  validate resolves on the credential *key* alone. If you need proof of
  possession, you need this flow, not a static key.
- **The `client_id` is the credential key, not the secret.** Sending the secret
  where the id belongs is the most common cause of "401 on the token endpoint
  with credentials I'm certain are right".
- **Confirm `helix-auth`'s schema in your own org** with `get_plugin_config`
  before deploying. Builds differ, and field names are not worth guessing.
- **`request-id` on the token route is deliberate.** Auth failures are exactly
  the thing you'll be asked to investigate, and the token exchange is half the
  flow.

## When to use it

Use it when:

- Your API needs authentication and the backend can't ship it on your timeline.
- Partners are asking for OAuth 2.0 by name, or a security review is.
- You're handing out static keys today and want to shrink the exposure window
  without asking every integrator to re-plumb their client.
- You want authentication and *attribution* in one step — see
  [solution 04](../04-analytics/), which depends on identity being resolved here.

Don't use it when:

- **An identity provider already issues tokens to these callers.** Use
  `jwt-auth` against that issuer instead. See § *Who issues the token*.
- **You need end-user identity, not app identity.** Client credentials
  authenticates the *application*. Delegated user access is the authorization
  code flow, and this is not it.
- **You need fine-grained scopes and per-scope route policy.** This solution
  proves who is calling. Deciding what they may do is authorization — a separate
  layer.
- **The caller genuinely cannot store a secret** — a public single-page app or a
  mobile client. Client credentials assumes a confidential client.

## Limitations

- **Client credentials authenticates apps, not users.** No end-user identity is
  established, and no consent is involved.
- **No scopes in this configuration.** The token proves identity; it doesn't
  carry per-route permissions. Add authorization on top.
- **No token revocation list.** A token is valid until it expires; disabling an
  app stops *new* tokens. This is why the TTL is the security control — it's the
  only bound on a leaked token's usefulness.
- **No refresh tokens.** Client credentials doesn't use them: the client already
  holds the long-lived secret, so it re-exchanges instead.
- **Symmetric signing.** One shared secret signs and verifies. If a third party
  needs to verify your tokens independently, that requires asymmetric keys.
- **Every 401 looks alike.** Correct, and awkward. See § *What the caller
  actually sees*.

Full list: [`solution.yaml`](solution.yaml) § `limitations`.

## Validation status

**Validated against a gateway — imported, dry-run, deployed, and passed `verify.sh`.**

| Stage | Status | Provenance |
|---|---|---|
| Configuration generated | **YES** | [`gateway/api-spec.yaml`](gateway/api-spec.yaml) |
| Local validation | **PASS** | Structural review — [`validation/local-validation.yaml`](validation/local-validation.yaml) |
| Gateway dry-run | **PASS** | Non-destructive; a missing upstream binding is reported here, before any deploy. |
| Gateway deployed | **DEPLOYED** | Revision ACTIVE in a test environment; `service_id` auto-assigned on import. |
| Functional tests | **PASS (6/6)** | `gateway/verify.sh` exit 0 — including the wrong-secret and forged-token cases. |

Overall: **READY.** The token flow works exactly as documented — three-segment
HS256 JWT, `expires_in` matching `token_ttl`, the client secret genuinely checked,
forged and prefix-less tokens rejected. Full record, including the two repo
corrections this run produced (the `<ENV:...>` finding and the `jwt-auth`
plugin-naming fix), is in
[`validation/gateway-validation.yaml`](validation/gateway-validation.yaml).

**One thing you must do:** replace `<YOUR_JWT_SIGNING_SECRET>` with a real secret.
It is used *literally* as the HMAC key on this build — `<ENV:...>` syntax is not
resolved — so shipping the placeholder makes your signing key a public constant.

## Related solutions

- **[02 — SOAP to REST](../02-soap-to-rest/)** — puts this exact auth layer in
  front of a mediated SOAP backend. The two compose directly.
- **[03 — API Products](../03-api-products/)** — once you know *who* is calling,
  meter them. Add `api-product-enforcer` behind this `helix-auth` block.
- **[04 — Analytics](../04-analytics/)** — analytics attributes calls to an app
  only because this solution resolved identity first.
