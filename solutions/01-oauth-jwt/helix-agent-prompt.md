# Agent-mode prompt — OAuth 2.0 with gateway-issued JWTs

Paste this into **Helix Agent Mode**. It works from a blank organisation: the
agent finds the API, fetches the real `helix-auth` schema from your org, adds a
token endpoint, protects the other routes, dry-runs, and hands you an app's
credentials to test with.

Replace the `<<...>>` values. Everything else is deliberate — the table below
says why each block earns its place.

Read [AGENT-GUIDE.md](../../AGENT-GUIDE.md) first if you haven't. The short
version: prompt at the level of outcomes, keep the confirm gate, and give the
agent the platform's opinions.

---

## The prompt

```text
Add OAuth 2.0 client-credentials authentication to my API, so partners exchange
a client id and secret for a short-lived token instead of sending a static key
on every request. The backend must not change.

CONTEXT
- API to protect: <<Orders API>>   (find it with list_apis; if more than one
  matches, ask me before changing anything)
- Environment: <<staging>>
- The gateway is the token issuer. There is no external identity provider
  involved.
- JWT_SIGNING_SECRET already exists as an environment variable on <<staging>>.
  If it does not, tell me and stop — do not invent a secret and do not write a
  literal one into the spec.

WHAT I WANT

1. A token endpoint: POST /oauth/token
   Use helix-auth in generate mode. It should verify the calling app's client id
   and client secret (sent as Authorization: Basic base64(client_id:secret)) and
   return a signed JWT with token_type Bearer and expires_in.
   Token lifetime: 900 seconds. A leaked token should be worthless within
   fifteen minutes, so do not default this to an hour.
   Reference the signing secret as an environment variable, never a literal.

2. Protect every other endpoint.
   Use helix-auth in validate mode with validate_auth_type jwt-auth, referencing
   the SAME signing secret. A request with no token, a malformed Authorization
   header, an expired token, or a token this gateway did not sign must be
   rejected at the gateway and never reach the upstream.

   Apply validate PER ROUTE on the protected endpoints — do NOT apply it
   API-wide. If it covers /oauth/token as well, no caller can ever obtain a
   first token and every single request returns 401.

3. Add request-id (uuid, header X-Request-Id) API-wide, including on the token
   endpoint. Auth failures are the thing I will be asked to investigate and the
   token exchange is half the flow.

4. Add cors allowing the "authorization" and "content-type" headers, with
   allow_credential false. authorization must be allowed or browser clients fail
   at preflight and I get a CORS error instead of a 401, which sends people
   debugging the wrong layer.

CONSTRAINTS — known platform behaviour, please respect these
- Use helix-auth in generate mode for issuing, NOT the jwt-auth plugin. jwt-auth
  validates tokens an EXTERNAL issuer signed; here the gateway is the issuer. If
  you think an external issuer is involved, ask me rather than assuming.
- The signing secret on the issue route and on every validate route must be the
  same value. A mismatch rejects every freshly issued token with an opaque 401
  and the config looks correct on both sides.
- Secrets never appear in a spec. Use an environment-variable reference for the
  signing secret. The app's client id and secret are provisioned on the
  credential by the control plane — do not write them into config.
- Check get_plugin_config for helix-auth before writing any config and use the
  schema this org actually has. Only schema fields plus _meta are legal — no
  invented or commentary fields in the plugin blocks.
- If you need a conditional match on a header or path, use filter_func (a Lua
  expression string), not vars — vars fails at deploy time.

BEFORE YOU DEPLOY
- Show me the full spec you are about to apply and wait for my confirmation.
- Run validate_route and dry_run_deploy first. If either fails, show me the
  error and your proposed fix rather than retrying blindly.
- Tell me the execution order of the plugins on a protected route, and confirm
  the rejection happens in the access phase before the upstream is called.

AFTER YOU DEPLOY
- Create a developer "<<Partner Integrations>>" with ONE app subscribed to this
  API, and give me its client id and client secret.
- Give me curl commands that show, in order: no token → 401; client credentials
  → 200 with an access_token; that token → 200 on a protected route; a garbage
  token → 401; and the CORRECT client id with a WRONG secret → 401.
- That last one matters: if a wrong secret still issues a token, this is a
  static-key flow wearing a token's clothes, and I want to know now.
- Tell me plainly what a rejected caller sees — status, body, and which headers
  are absent — so I can write the developer documentation.

If anything is ambiguous for my org — the environment, the upstream, whether the
signing secret exists — ask me instead of guessing.
```

---

## Why the prompt is shaped this way

| Block | Why it's there |
|---|---|
| **"The gateway is the token issuer. There is no external IdP."** | This is the fork in the road. `helix-auth` generate and `jwt-auth` sit on opposite sides of the issuer boundary, and an agent that guesses wrong builds a verifier with nothing to verify, or an issuer competing with your real IdP. |
| **"Use helix-auth generate, NOT jwt-auth"** | The most likely wrong turn. A general-purpose model associates "JWT" with the `jwt-auth` plugin and will reach for it by name. |
| **"the SAME signing secret"** | Stated twice on purpose. It's the top cause of a deployment that looks perfect and rejects every token, and neither side's config hints that the value is shared. |
| **"Apply validate PER ROUTE — do NOT apply it API-wide"** | An agent optimising for tidiness will hoist the auth block to the document root, which protects the token endpoint. The result is an API where every request 401s, including the one that issues tokens. |
| **"Token lifetime 900 seconds… do not default this to an hour"** | Left unspecified, the agent takes the platform default. The TTL is the *only* bound on a leaked token's usefulness, so it deserves an explicit decision with a reason attached. |
| **"tell me and stop"** on the missing secret | The agent can't set environment secrets. Without this it may write a literal, or deploy a spec referencing a secret that doesn't exist — which deploys cleanly and fails at request time. |
| **"authorization must be in allow_headers"** | Omitting it produces a CORS preflight failure, not a 401. People then debug auth for an hour while the request never arrives. |
| **"Check get_plugin_config"** | Prevents fields invented from another gateway's documentation. One line, most of the schema failures. |
| **BEFORE YOU DEPLOY** | `validate_route` → `dry_run_deploy` → show → confirm → deploy. The confirm gate sits exactly at the step that's hard to undo. |
| **"Tell me the execution order"** | Plugins run by priority, not document order. If the agent can't say which phase rejects the request, the config is probably wrong in a way that only shows up later. |
| **"the CORRECT client id with a WRONG secret → 401"** | The one test people skip, and the one that proves the secret is actually verified rather than decorative. |
| **"what a rejected caller sees"** | Forces the agent to surface that all four failure causes return an indistinguishable 401, before a partner discovers it for you. |

## Tweak knobs

Each is a different piece of content and a different conversation.

**An external identity provider already issues the tokens**
```text
Actually, our tokens come from <<Keycloak>>, not the gateway. Drop the
/oauth/token route entirely and switch the protected routes to the jwt-auth
plugin, verifying against the issuer's public key or JWKS endpoint. The gateway
must be a verifier only — it must never mint tokens that IdP is authoritative
for. Show me how the key is referenced so I can rotate it.
```

**Shorter tokens for a high-value path**
```text
Reduce the token lifetime to 300 seconds. Then tell me what that does to token
endpoint traffic if a client makes 50 calls a minute, and what caching behaviour
I should document for integrators.
```

**Keep static keys working during the migration**
```text
Some partners can't move to OAuth this quarter. Keep the JWT validation on
/orders, but let me nominate specific apps that may still authenticate with a
static key via helix-auth validate key-auth on a parallel route. Tell me what
this weakens and how I'd revoke the static path later.
```

**Layer metering on top**
```text
Now meter these callers. Add api-product-enforcer behind the helix-auth block on
the protected routes, create products for the tiers I sell, and make sure the
route has a service_id. Do not add a limit-count keyed on consumer_name — the
product quota already counts per app.
```
(That's [solution 03](../03-api-products/).)

**Add the SOAP mediation underneath**
```text
The upstream actually speaks SOAP/XML. Keep this auth exactly as it is and add
bidirectional transformation plus a proxy-rewrite to the upstream's real path,
so partners keep sending JSON.
```
(That's [solution 02](../02-soap-to-rest/).)

**Rotate the signing secret without downtime**
```text
I need to rotate JWT_SIGNING_SECRET. Walk me through it, and tell me honestly
whether tokens issued under the old secret will be rejected the moment the new
one is live — and if so, how I sequence it so partners don't see a wall of 401s.
```

## Follow-up prompts for the same session

1. `Show me every request to Orders API in the last hour that returned 401, grouped by app. If an app is failing every call, tell me which of the four causes it looks like.`
2. `A partner says they're getting 401 with credentials they're sure are right. Walk me through what to check, in the order most likely to be the cause.`
3. `Write the developer-portal documentation for this token flow, including the caching guidance and the fact that a 401 doesn't distinguish its cause.`
4. `Which apps are requesting a new token more than once a minute? They aren't caching, and they're making my token endpoint the busiest route on the API.`

## Known failure modes when running this prompt

- **Every call returns 401, including with a token you just got.** The signing
  secrets differ between the issue route and the validate route. Check both
  reference the *same* environment variable, and that it exists on the
  environment you deployed to.
- **Every call returns 401 including `/oauth/token` itself.** `validate` got
  applied API-wide and is now protecting the token endpoint. Reply: `validate is
  covering /oauth/token — move it to the protected routes only, or nobody can
  ever get a first token.`
- **The agent reaches for `jwt-auth` to issue tokens.** Reply: `jwt-auth
  validates tokens an external issuer signed. The gateway is the issuer here —
  use helix-auth in generate mode on the token endpoint.`
- **The agent writes a literal signing secret into the spec.** Reply: `never put
  a secret in a spec. Reference the JWT_SIGNING_SECRET environment variable, and
  tell me if it doesn't exist yet.`
- **The token endpoint 401s with credentials you're certain are correct.** You're
  almost certainly sending the app's *secret* where its *client id* belongs. The
  client id is the credential key.
- **A garbage token returns 200.** The route isn't validating at all — it's
  passing traffic through while looking configured. Ask the agent to show the
  applied plugins on that specific route.
- **Deploy fails with `Only INACTIVE revisions can be updated`.** Tell the agent
  to clone the revision or undeploy, apply, then redeploy.
- **The agent adds a `description` or `note` key inside the plugin block.** Only
  schema fields plus `_meta` are legal. Reply: `move that to a YAML comment —
  commentary keys are rejected.`

## Related

- **[Solution 02 — SOAP to REST](../02-soap-to-rest/helix-agent-prompt.md)** —
  the same auth acts, with protocol mediation added in front.
- **[Solution 03 — API Products](../03-api-products/helix-agent-prompt.md)** —
  metering the callers this solution identified.
- **[Solution 04 — Analytics](../04-analytics/helix-agent-prompt.md)** — the
  usage questions you can only ask because identity was resolved here.
