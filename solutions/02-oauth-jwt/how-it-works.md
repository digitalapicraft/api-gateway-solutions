# How it works — OAuth 2.0 with gateway-issued JWTs

[Overview](readme.md) · [Business need](business-need.md) · **How it works** · [Install](install.md) · [Configuration](configuration.md) · [Test & verify](testing.md) · [Changelog](changelog.md)

---

The gateway takes on two roles that used to belong to the application: it is the
**authorization server** (it issues tokens) and the **resource server's policy
enforcement point** (it verifies them). The backend service remains a plain HTTP
service with no concept of authentication.

## Who issues the token — decide this first

This is the fork in the road, and picking wrong means building the wrong half of
the flow.

| Your situation | Use | Why |
|---|---|---|
| **You have no identity provider**, and you want partners to exchange a client id and secret for a token | **`helix-auth` generate + validate** — this solution | The gateway *is* the issuer. It holds the signing secret, verifies the app's credentials, and mints the JWT. |
| **Keycloak / Auth0 / Entra ID / Okta already issues tokens** to your partners | **`openid-connect`** with `discovery` + `bearer_only` — see [solution 05](../05-okta-jwt/). Drop the `/oauth/token` route. **Not `helix-auth`:** it has no JWKS URL, issuer or audience field and its schema is `additionalProperties: false`, so it cannot verify a token it did not mint. | The gateway is a *verifier only*. It must not mint tokens a separate IdP is authoritative for. |

`helix-auth` `generate` and `helix-auth` `validate` (jwt-auth) are not
alternatives to each other — they sit on opposite sides of the same boundary.
Verifying your own gateway-issued tokens against an external issuer, or issuing
tokens when an IdP already exists, produces a system with two sources of truth
about identity. (Note: `jwt-auth` is a `validate_auth_type` value of `helix-auth`,
not a standalone plugin on this build.)

Everything below is the first row.

## The two flows

### Flow 1 — obtaining a token

```
┌────────┐                    ┌──────────────────────────────┐
│ Client │                    │           Gateway            │
└───┬────┘                    │                              │
    │  POST /oauth/token      │  ┌────────────────────────┐  │
    │  Authorization: Basic   │  │ helix-auth             │  │
    │  base64(id:secret)      │  │ mode: generate         │  │
    ├────────────────────────►│  │                        │  │
    │                         │  │ 1. look up credential  │  │
    │                         │  │    by client_id        │  │
    │                         │  │ 2. verify client_secret│  │
    │                         │  │ 3. sign JWT with       │  │
    │                         │  │    signing_secret      │  │
    │                         │  │    exp = now + 900s    │  │
    │  200                    │  └────────────────────────┘  │
    │◄────────────────────────┤                              │
    │  { access_token,        │   The upstream is NEVER       │
    │    token_type: Bearer,  │   contacted for this route.   │
    │    expires_in: 900 }    │                              │
    │                         └──────────────────────────────┘
```

If the `client_id` is unknown, or the `client_secret` doesn't match, the response
is **401** and no token is minted. This is the only mode in which the app's
secret is verified at all.

**This route is deliberately not behind validation.** A caller arriving here has
no token by definition. Protecting it produces a system where obtaining a token
requires already having one.

### Flow 2 — calling the API

```
┌────────┐         ┌──────────────────────────────────────┐      ┌──────────┐
│ Client │         │               Gateway                │      │ Upstream │
└───┬────┘         │                                      │      └────┬─────┘
    │ GET /posts  │  ┌─────────── access phase ────────┐ │           │
    │ Authorization│  │ helix-auth                      │ │           │
    │ Bearer eyJ...│  │ mode: validate                  │ │           │
    ├─────────────►│  │ validate_auth_type: jwt-auth    │ │           │
    │              │  │                                 │ │           │
    │              │  │ • Authorization header present? │ │           │
    │              │  │ • "Bearer " prefix?             │ │           │
    │              │  │ • signature valid under the      │ │           │
    │              │  │   SAME signing_secret?          │ │           │
    │              │  │ • exp in the future?            │ │           │
    │              │  │ • resolves the calling app      │ │           │
    │              │  └──────────────┬──────────────────┘ │           │
    │   401        │      fail       │       pass         │           │
    │◄─────────────┼─────────────────┘                    ├──────────►│
    │              │                                      │           │
    │   200        │  ┌───────────── log phase ─────────┐ │◄──────────┤
    │◄─────────────┼──┤ request-id, analytics (global)   │ │           │
    │              │  └─────────────────────────────────┘ │           │
    └──────────────┴──────────────────────────────────────┘───────────┘
```

The structural point: **rejection happens in the access phase.** A request with a
bad token consumes a small amount of gateway CPU and nothing else. It does not
open a connection to your service, doesn't touch your database, doesn't appear in
your application logs, and doesn't count against your service's capacity.

## Execution order

Plugins run by **priority**, not in the order they appear in the document. On a
protected route:

| Order | Plugin | Phase | Produces | Consumes |
|---|---|---|---|---|
| 1 | `helix-auth` (validate) | access | the resolved calling app in request context | the `Authorization` header, `signing_secret` |
| 2 | *(any authorization or metering plugin)* | access | — | the identity from step 1 |
| — | `request-id` | rewrite/log | `X-Request-Id` | — |
| — | analytics (platform-global) | log | per-request telemetry | the identity from step 1 |

The dependency that matters: **anything that needs to know who is calling must
run after `helix-auth`.** That's not something you arrange by ordering the YAML —
it follows from plugin priorities. It's why [solution 01](../01-api-products/)'s
quota enforcement works when it sits behind this block and returns 403 for
everything when it doesn't.

It's also why analytics can attribute a call to an app rather than an IP address.
Identity resolved here is what every downstream layer reads. See
[solution 04](../04-analytics/).

## Native vs custom

Everything here is native plugin configuration. **No custom code is required, and
writing any would be a mistake.**

| Requirement | How it's met | Why not custom |
|---|---|---|
| Verify client credentials | `helix-auth` mode `generate` | Credential storage and secret comparison already live in the control plane. Custom code would need its own credential store. |
| Sign a JWT | `helix-auth` mode `generate` | Signing is easy to write and easy to write *insecurely*. Timing-safe comparison, correct `exp` handling and algorithm pinning are solved here. |
| Verify a JWT | `helix-auth` mode `validate`, `validate_auth_type: jwt-auth` | Hand-rolled verification is where `alg: none` and algorithm-confusion bugs come from. |
| Reject before the upstream | The access phase | A custom filter would run in the same phase with more ways to be wrong. |
| Correlate an auth failure | `request-id` | — |

The one thing this solution deliberately does *not* attempt: **scopes and
per-route permissions.** That's authorization, it's genuinely
application-specific, and bolting it into the authentication layer with custom
code produces policy nobody can audit. Keep it separate.

## Where the secret lives

```
The literal string in the spec — replaced before deploy, never committed
   signing_secret: "<YOUR_JWT_SIGNING_SECRET>"   ← used VERBATIM as the HMAC key
            │
            ├──► helix-auth generate  on POST /oauth/token        (signs)
            └──► helix-auth validate  on every protected route    (verifies)

This build resolves neither <ENV:...> nor ${...}. There is no indirection: the
string in the field IS the key. That is why the placeholder must be replaced
before deploy and why the filled-in spec must not be committed.
```

Two properties follow from this being one symmetric secret:

- **Both references must resolve to the same value.** A mismatch rejects every
  freshly issued token, and nothing in either plugin block suggests the value is
  shared.
- **Rotation is a coordinated change.** Tokens signed under the old secret stop
  verifying the moment the new one is live. With a 900-second TTL the exposure is
  bounded to fifteen minutes of 401s if you do it carelessly — which is an
  argument for rotating during a low-traffic window and telling partners in
  advance.

If independent third-party verification is a requirement, symmetric signing can't
give it to you: anyone who can verify can also sign. That needs asymmetric keys
and is out of scope here.

## Prerequisites

- The API exists and is deployed to an environment, with the upstream bound to
  the service.
- The real signing secret has **replaced** `<YOUR_JWT_SIGNING_SECRET>` in the
  spec before the revision is deployed. This build resolves neither `<ENV:...>`
  nor `${...}`, so an unreplaced placeholder deploys cleanly and becomes a
  publicly-known HMAC key.
- `helix-auth` is present in your org, and you've confirmed its schema with
  `get_plugin_config`.
- At least one developer with one app, so you have a `client_id` and
  `client_secret` to exchange.

## Failure behaviour

| Condition | Result | Reaches upstream? |
|---|---|---|
| No `Authorization` header | 401 | No |
| `Authorization` without the `Bearer ` prefix | 401 | No |
| Well-formed JWT, wrong signature | 401 | No |
| Valid signature, `exp` in the past | 401 | No |
| Valid token | passes through | Yes |
| Unknown `client_id` at the token endpoint | 401, no token minted | No |
| Known `client_id`, wrong `client_secret` | 401, no token minted | No |
| Placeholder never replaced, identically on both sides | Tokens issue and verify **normally** — and the key is a published constant anyone can forge with | Yes, including forged tokens |
| Signing secrets differ between issue and validate | 401 on every call, even with a token issued seconds earlier | No |

All four caller-side failures are an indistinguishable 401 by design — a verbose
error tells an attacker which half of their guess was right. The cost is that
integrators can't self-diagnose, so **document the four causes** and give them
`X-Request-Id` to quote in support tickets.

The last two rows are the operator-side failures, and they present identically to
the caller-side ones. If *everything* returns 401 including calls with tokens
issued moments ago, suspect the secret before you suspect the client.
