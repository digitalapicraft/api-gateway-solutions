# Architecture — OAuth 2.0 with gateway-issued JWTs

The gateway takes on two roles that used to belong to the application: it is the
**authorization server** (it issues tokens) and the **resource server's policy
enforcement point** (it verifies them). The backend service remains a plain HTTP
service with no concept of authentication.

---

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
    │                         │  │    JWT_SIGNING_SECRET  │  │
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
    │              │  │   SAME JWT_SIGNING_SECRET?      │ │           │
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
| 1 | `helix-auth` (validate) | access | the resolved calling app in request context | the `Authorization` header, `JWT_SIGNING_SECRET` |
| 2 | *(any authorization or metering plugin)* | access | — | the identity from step 1 |
| — | `request-id` | rewrite/log | `X-Request-Id` | — |
| — | analytics (platform-global) | log | per-request telemetry | the identity from step 1 |

The dependency that matters: **anything that needs to know who is calling must
run after `helix-auth`.** That's not something you arrange by ordering the YAML —
it follows from plugin priorities. It's why [solution 03](../03-api-products/)'s
quota enforcement works when it sits behind this block and returns 403 for
everything when it doesn't.

It's also why analytics can attribute a call to an app rather than an IP address.
Identity resolved here is what every downstream layer reads. See
[solution 04](../04-analytics/).

## Who issues the token — the design decision

Get this wrong and you build the wrong half of the flow.

```
                      Who signs the tokens?
                              │
            ┌─────────────────┴─────────────────┐
            │                                   │
      The gateway                    An external IdP
      (no IdP exists)                (Keycloak, Auth0,
            │                         Entra ID, Okta)
            ▼                                   ▼
   helix-auth generate              jwt-auth on the routes
   + helix-auth validate            + NO token route here
   (this solution)
            │                                   │
   Gateway is the                    Gateway is a
   AUTHORIZATION SERVER              VERIFIER ONLY
   and the enforcement point         The IdP stays
                                     authoritative
```

These are not interchangeable implementations of the same idea:

- **`helix-auth` generate** makes the gateway the authorization server. It holds
  the signing secret, so it can both mint and verify. Right when there's no IdP
  and you don't want to run one for a partner API.
- **`jwt-auth`** makes the gateway a verifier against someone else's issuer. It
  holds a public key or a JWKS URL, so it can verify but not mint. Right whenever
  an IdP already exists.

The failure mode of choosing wrong is subtle: two systems both believe they're
authoritative about identity, and you find out during an incident.

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
Environment variable on the gateway environment
   JWT_SIGNING_SECRET = <never in this repo, never in the spec>
            │
            ├──► referenced by helix-auth generate  on POST /oauth/token   (signs)
            └──► referenced by helix-auth validate  on every protected route (verifies)
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

## When to use this

Use it when:

- **The backend can't ship auth on your timeline.** This is the common case, and
  it's the whole point: authentication is edge logic being held hostage by a
  release train.
- **Partners are asking for OAuth 2.0 by name**, or a security questionnaire is.
- **You're handing out static keys today.** This shrinks the replay window from
  "until someone notices" to minutes, without asking integrators to re-plumb how
  they store credentials — they still hold an id and a secret.
- **You need attribution as well as authentication.** Identity resolved here is
  what makes per-app analytics and per-app quota possible at all.
- **Multiple services need the same auth.** Configure it once at the edge rather
  than N times in N codebases.

Don't use it when:

- **An IdP already issues tokens to these callers.** Use `jwt-auth` against that
  issuer. Running a second authorization server is a correctness problem, not a
  duplication problem.
- **You need end-user identity or delegated access.** Client credentials
  authenticates the *application*. If the question is "may this user see this
  record", the authorization code flow and an authorization layer are what you
  want.
- **The client can't hold a secret** — a browser SPA or a mobile app. Client
  credentials assumes a confidential client. A secret shipped to a public client
  isn't a secret.
- **You need per-scope route policy.** This solution establishes *who*. It says
  nothing about *what they may do*.
- **Tokens must be revocable immediately.** There's no revocation list; a token
  lives until it expires. Shorten the TTL, or accept the window.

## Prerequisites

- The API exists and is deployed to an environment, with the upstream bound to
  the service.
- `JWT_SIGNING_SECRET` exists as an environment variable **before** the revision
  is deployed. A spec referencing a secret that doesn't exist deploys cleanly and
  fails at request time.
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
| `JWT_SIGNING_SECRET` missing on the environment | 401 on every call | No |
| Signing secrets differ between issue and validate | 401 on every call, even with a token issued seconds earlier | No |

All four caller-side failures are an indistinguishable 401 by design — a verbose
error tells an attacker which half of their guess was right. The cost is that
integrators can't self-diagnose, so **document the four causes** and give them
`X-Request-Id` to quote in support tickets.

The last two rows are the operator-side failures, and they present identically to
the caller-side ones. If *everything* returns 401 including calls with tokens
issued moments ago, suspect the secret before you suspect the client.
