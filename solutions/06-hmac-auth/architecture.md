# Architecture — HMAC request signing at the edge

The gateway holds a copy of each caller's secret and recomputes the caller's
signature from the request it received. Nothing is looked up in a credential list
and compared for equality; the check is that **two independent computations over
the same inputs agree**. Everything else in this document follows from that.

## The flow

```mermaid
sequenceDiagram
    autonumber
    participant C as Partner client
    participant GW as Gateway (rewrite phase)
    participant UP as Upstream

    Note over C: secret_key is stored here and never sent
    C->>C: canonicalise: keyId, "POST /posts", Date, Digest(body)
    C->>C: signature = base64(HMAC-SHA256(secret_key, base + "\n"))
    C->>GW: POST /posts<br/>Date, Digest, Authorization: Signature keyId=...

    GW->>GW: parse the Authorization envelope
    GW->>GW: every signed_headers entry present in headers= ?
    GW->>GW: Date within clock_skew of now ?
    GW->>GW: look up the credential by key_id
    GW->>GW: rebuild the base, recompute with the stored secret
    GW->>GW: rehash the received body, compare to Digest

    alt all checks hold
        GW->>GW: attach the consumer to the request context
        GW->>UP: POST /posts (Authorization stripped by hide_credentials)
        UP-->>GW: 201
        GW-->>C: 201
    else any check fails
        GW--xC: 401 + WWW-Authenticate: hmac realm="partner-events"
        Note over GW,UP: The upstream is never contacted.<br/>The reason is in the gateway log, not the response.
    end
```

## Execution order

Order here is **phase first, then priority within a phase** — not the order
plugins appear in the document. Listing them differently changes nothing.

| Plugin | Phase | Priority | Runs |
|---|---|---|---|
| `hmac-auth` | rewrite | 2530 | Before anything in the access phase, and before the upstream |
| `request-id` | rewrite | — | Service-scoped; produces the correlation id |

Two consequences worth knowing:

- **Rejection happens early.** A bad signature is refused in the rewrite phase, so
  the upstream is never contacted and nothing appears in your backend logs. Absence
  of a log line downstream is expected, not a symptom.
- **`hmac-auth` reads the request body** when `validate_request_body` is on. That
  matters beyond this solution: a plugin later in the chain that expects the body
  to have been read — a logger with `include_req_body`, for instance — depends on
  *something* having read it in the rewrite phase. See
  [solution 07](../07-http-to-kafka/), where that dependency is the whole design.

### The plugin that cannot sit next to it

`request-validation` also runs in the rewrite phase, at priority **2800** — ahead
of `hmac-auth`. It re-encodes the parsed JSON body with `set_body_data`,
deliberately, as a defence against parser-differential attacks.

`hmac-auth` then hashes the **re-encoded** bytes while the client hashed what it
actually sent. Key order and whitespace differ, so the two digests agree only by
coincidence. Symptom: a bare 401, with `Invalid digest` in the gateway log.

They are mutually exclusive on a route. Pick one:

| You want | Do this |
|---|---|
| Body integrity (the point of signing) | `hmac-auth` with `validate_request_body`. Validate the schema behind the gateway |
| Schema rejection at the edge | `request-validation`, and accept that the signature cannot cover the body |

## Why signing, structurally

A bearer credential and a signature answer the same question with different
mechanics, and the difference is not about strength of algorithm:

| | Bearer credential | Signature |
|---|---|---|
| How possession is proven | By **disclosing** the secret | By **computing a function** of it |
| What the proof covers | Nothing — it is the same string every time | This method, path, body and timestamp |
| Reusable by an observer | Yes, indefinitely | Only as a replay of that exact request, until `clock_skew` |
| Verifier could forge it | Yes (it holds the credential) | Yes (symmetric secret) — so, no non-repudiation |

The last row is the honest limit: this is symmetric. It gives integrity and
authentication, not proof of origin against the verifier.

## Where the secret lives

Nowhere in this repository, and nowhere in the specification — by construction,
not by discipline.

`hmac-auth`'s route schema is exactly `allowed_algorithms`, `clock_skew`,
`signed_headers`, `validate_request_body`, `hide_credentials`,
`anonymous_consumer`, `realm` and `_meta`. **There is no secret field.** There is
nothing to accidentally commit.

The secret is on the **app credential**, which the control plane owns:

```mermaid
flowchart LR
    P["Product<br/>authMethods: [hmac-auth]"] --> A
    D["Developer<br/>(the partner)"] --> A
    A["App<br/>plugins: {hmac-auth: {}}"] -->|"control plane generates"| C["Credential<br/>key_id + secret_key"]
    C -->|"returned ONCE<br/>secret_key stored encrypted"| O["Your partner's config"]
    C -.->|"gateway resolves by key_id<br/>at request time"| GW["hmac-auth on the route"]
```

- `authMethods` on the product **must** name `hmac-auth`; it defaults to
  `helix-auth`, and an app under a product that does not name it is rejected.
- `{"hmac-auth": {}}` — an empty config — is the instruction to generate both
  values. Supply them explicitly instead to match a secret a partner already holds.
- `secret_key` is an encrypted field. It is returned in the create response and
  never again.
- Rotation regenerates both values together. There is no previous-secret grace
  period, so rotation is a cutover.

Contrast [solution 01](../01-oauth-jwt/), where `signing_secret` is a **literal in
the spec** and shipping the placeholder publishes your signing key. That failure
mode does not exist here.

## Route shaping

The signed set is a property of the route, not of the API, because what there is
to sign differs per route:

| Route | `signed_headers` | `validate_request_body` |
|---|---|---|
| `POST /posts` | `@request-target`, `date`, `digest` | `true` |
| `GET /posts/{postId}` | `@request-target`, `date` | `false` |

`hmac-auth` is therefore applied **per route**. The trade is explicit: a route
added later without an `x-helix-gateway` block is unauthenticated. The fail-safe
alternative is a single root-level block with the `POST` configuration, at the
cost of making bodyless callers send `SHA-256=47DEQpj8HBSa+/TImW+5JCeuQeRkm5NMpJWZG3hSuFU=`
— the digest of the empty string.

`@request-target` expands to `<METHOD> <request_uri>`, and `request_uri`
**includes the query string**. Any intermediary that normalises, reorders or
appends query parameters invalidates every signature it touches.

## Native vs custom

No custom code. `hmac-auth` is a stock plugin; the only implementation work is on
the **client** side, and that is unavoidable — signing is by definition something
the caller does.

What was deliberately *not* built:

- **A nonce cache via `lua-callout`.** It would close the replay window, and it
  needs shared storage with a consistency story of its own. Out of scope here;
  idempotency upstream is the cheaper answer for most endpoints.
- **`request-validation` alongside it.** Incompatible, as above.
- **Custom header parsing.** The envelope is fixed by the plugin.

## Prerequisites

- An org whose build includes `hmac-auth` — confirm with
  `GET /api/orgs/{orgId}/plugin-schemas?page=1&size=300`.
- An upstream bound to the service. The spec ships pointed at public
  jsonplaceholder so it works on a fresh org.
- A product with `authMethods: ["hmac-auth"]`, a developer, and one app per
  integration.
- Callers with a clock accurate to within `clock_skew` (300s here). A device fleet
  without NTP will generate 401s that look like credential failures.

## Failure behaviour

| Condition | Result |
|---|---|
| No `Authorization` header | 401, with the reason in the body |
| Malformed envelope | 401, with the reason in the body |
| Bad signature, bad digest, stale `Date`, unknown `key_id`, weak signed set | 401, body says only `client request can't be validated` |
| Signature valid, request replayed inside `clock_skew` | **Accepted.** No nonce exists |
| Upstream down | Normal upstream failure — authentication already succeeded |

The split between explained and unexplained 401s is deliberate: parsing errors
help an honest integrator, validation errors must not help an attacker
distinguish which check failed. The detail is in the gateway log, correlated by
the `X-Request-Id` the response carries.
