# Architecture — key material as data, not configuration

> [Overview](README.md) · [Business need](business-need.md) · **Architecture** · [Guides](guides.md) · [Agent prompt](helix-agent-prompt.md) · [Tests](tests.md) · [API reference](api-reference.md)

---

## What the gateway does here

The gateway keeps a small store of values, one per partner, and reads the right one
on every request. In this package the value is the partner's public encryption
key, and the gateway uses it to encrypt the backend's response to that partner.

There are two routes:

1. **A registration route** (`POST /partners/keys`). An operator sends a partner id
   and a public key. The gateway stores the key under that id. Only your operators
   may call it: the build adds an app-key check and an operators-only product in
   front of it before the first deploy.
2. **A document route** (`GET /partners/documents`). A partner asks for a document.
   The gateway looks up the key stored under the partner's id and encrypts the
   backend's response to it.

Your backend does not change. It returns plain documents, as it always has.

For the full list of fields on every plugin mentioned here, see
[docs.digitalapi.ai/api-gateway](https://docs.digitalapi.ai/api-gateway).

## The model

| Word | What it means here |
|---|---|
| **Partner id** | The value in the `X-Partner-Id` header. It decides which entry is written or read. |
| **Entry** | One stored value, under one key. Here: one partner's armored public key. |
| **Reference** | A template such as `$request.headers.x-partner-id` that the gateway fills in from the request at the moment it runs. |
| **Namespace** | Where fetched values are kept for the rest of the request: `ctx.helix.key_value_map` by default. |
| **Operator** | Whoever registers partners' keys. They call the registration route with their app's key in the `X-Admin-Key` header. |
| **Operators product** | A product that includes this API and that only operator apps subscribe to. It is what turns away every other app's key on the registration route. |

## How a request flows

```mermaid
sequenceDiagram
    autonumber
    participant OP as Operator
    participant P as Partner
    participant GW as Gateway
    participant KV as Key store
    participant UP as Backend

    Note over OP,KV: Registration — once per partner, and again on rotation
    OP->>GW: POST /partners/keys<br/>X-Admin-Key: the operator app's key<br/>X-Partner-Id: acme-bank<br/>{"public_key": "-----BEGIN…"}
    Note over GW: helix-auth + api-product-enforcer (the protection you add)<br/>no key or unknown key: 401 · not an operator app: 403<br/>either way, nothing is stored
    Note over GW: key-value-map insert<br/>key: $request.headers.x-partner-id<br/>value: $request.body.public_key
    GW->>KV: store (replaces any previous value)

    Note over P,UP: Every document request
    P->>GW: GET /partners/documents<br/>X-Partner-Id: acme-bank
    Note over GW: key-value-map fetch (priority 3001)
    GW->>KV: read acme-bank
    alt a key is stored
        KV-->>GW: the partner's public key
        GW->>UP: GET /json
        UP-->>GW: 200 plaintext document
        Note over GW: pgp-crypto (priority 898)<br/>resolves the SAME reference
        GW-->>P: 200 text/plain, base64( armored PGP )
    else nothing stored
        GW--xP: 500 — no document, in any form
    end
```

**The two plugins agree because they use the identical reference.** On the
document route, `$request.headers.x-partner-id` appears twice: once to tell
`key-value-map` which entry to fetch, and once to tell `pgp-crypto` which entry to
read. That shared string is the whole connection between them, and it is also the
thing that breaks with no error if one copy is edited.

## The reference grammar

References are filled in from the request (or response) at run time:

| Reference | Resolves to |
|---|---|
| `$request.headers.<name>` | the value of that request header |
| `$request.query.<name>` | the value of that query parameter |
| `$request.body.<dotted.path>` | a value from the JSON request body |
| `$response.headers.<name>` · `$response.body.<path>` | the same, on the response |
| `$consumer.<suffix>` | `"<consumer_name>.<suffix>"` — the authenticated caller |
| `$ctx.<path>` | a walk of the request context itself |

**It is `headers`, plural.** `$request.header.x-partner-id` resolves to nothing,
with no error. The only symptom is the encryption failing, which looks exactly like
"no key registered".

`$consumer.<suffix>` is the one to use once authentication is in front of the
document route. It keys entries on the authenticated caller rather than on a
header the caller chooses. See [Guides → Variations](guides.md#variations).

## Where stored values land

When `key-value-map` runs, it publishes values into the namespace for later
plugins to read:

```
fetched   ->  ctx.helix.<ctx_namespace>.<key>            flat
inserted  ->  ctx.helix.<ctx_namespace>.inserted.<key>   one level down
```

`alias` on a fetched key renames the published field, which is how a value fetched
under a changing key (a partner id) gets a fixed name a template can refer to.
[Solution 12](../12-key-value-store/) relies on that. This package's spec does not
need it, because `pgp-crypto` resolves the same reference itself. A build that
does name an alias on the fetch, and points `pgp-crypto`'s `public_key` at
`$ctx.helix.key_value_map.<alias>`, works too.

## Reading a response

| Request | Status | Body | What it means |
|---|---|---|---|
| Document, partner never registered | **500** | `{"message":"no usable key is registered for this partner"}` | No entry. Nothing is sent in the clear. |
| Document, partner registered with a key that has **no encryption subkey** | **200** | *the same error body* | The key is stored but cannot encrypt. See below. |
| Document, partner registered with a usable key | **200** | base64 of an armored PGP message, `text/plain` | Working as designed. |
| Registration, operator's key | **200** | the upstream's echo of what was posted | Not proof the value was stored. See below. |
| Registration, no key or a key that belongs to no app | **401** | a short JSON message | Turned away by `helix-auth`. Nothing was stored. |
| Registration, an app that isn't on the operators product | **403** | a short JSON message | Turned away by `api-product-enforcer`. Nothing was stored. |
| Registration | **503** | — | The store could not be written. `fail_action: close` means nothing was saved. |

**A registered key can be unusable, and the status will not tell you.** The
configured error status (500) is used only when the store has **no** entry. When
the store returns a key the encryption cannot use, the failure goes out as a 200
with the error message in the body. Neither the status nor the message tells
"wrong kind of key" apart from "no key". It is easy to end up with such a key:
`gpg --quick-generate-key <uid> rsa3072`, or the same command with any other named
algorithm, makes a primary key with no encryption subkey. The bare command, or
`default default` in place of the algorithm, adds one. So **in your own checks,
look at the body, never only the status.** How to check and repair a key:
[Guides → See it work](guides.md#see-it-work).

**A registration's status belongs to the upstream, not the store.** The value is
written before the request is passed on, so a 2xx does not prove it landed and a
5xx does not prove it failed. Read the value back by fetching a document.

## Execution order

Plugins run phase by phase, and within a phase in **priority order**, not the
order they appear in the file. Every plugin in the rewrite phase runs before any
plugin in the access phase.

| Order | Plugin | Route | What it does |
|---|---|---|---|
| 1 | `helix-auth` (rewrite phase, 2450) | registration, added by the protection step | Checks the key in `X-Admin-Key` belongs to an app. No key, or an unknown one: 401. |
| 2 | `api-product-enforcer` (access phase, raised to 3100) | registration, added by the protection step | Lets through only apps on a product that includes this API: anything else gets 403. Each call uses one request of that product's quota. |
| 3 | `key-value-map` (access phase, 3001) | both | Registration: writes the key from the request body. Document: fetches the partner's key into the namespace. |
| 4 | `pgp-crypto` (898) | document | Resolves the same reference against the namespace and encrypts the response to that key. |
| — | `proxy-rewrite` | both | Rewrites the path to the backend's (`/post`, `/json`). |
| — | `request-id` | API-wide | Adds `X-Request-Id`, the handle for a disputed failure, since crypto errors are deliberately vague. |

**Why the enforcer's priority is raised.** At its own priority, 2399, the enforcer
runs in the access phase *after* `key-value-map` (3001). An app that isn't on the
operators product would then get its 403 only after its key had already been
stored. Setting `_meta.priority` to `3100` on the enforcer makes the check come
first. `helix-auth` needs no change: it runs in the earlier rewrite phase.

## Where a missing value is decided

`key-value-map` treats a miss as an ordinary outcome: it cannot know whether the
caller needed that value. Its `fail_action` covers failures of the **store** (it
could not be reached, or a write failed), not a missing key.

So "what does an unregistered partner get?" is answered by the **consuming**
plugin, `pgp-crypto`, through its `fail_policy`. It must be `fail-close`.
`fail-open` would return the backend's document **unencrypted** to a caller who
was meant to receive ciphertext. One of the automated tests checks the error status
for exactly that reason.

## Which plugins can use a stored value

Seeing a stored value and using it on a real request are different jobs.

- **To see one**, `mocking` reads `ctx.helix.key_value_map` directly, on any plan,
  with no encryption. That is [solution 12](../12-key-value-store/). But `mocking`
  answers the request itself, so it can never pass a stored value on to your
  backend.
- **To use one on a proxied call**, the consumers are `pgp-crypto` and
  `lua-callout`: the only plugins that resolve a store reference themselves.
  `lua-callout` is refused at import **on a free-trial organisation**, which is why
  this package uses `pgp-crypto` and runs anywhere. On an organisation that is not
  on a free trial, `lua-callout` imports and deploys and becomes a second option.
  Test the import rather than the catalogue flag, which does not change between
  plans.

## No custom code needed

Nothing is built: configured plugins and the gateway's own store do the whole job.
The real choice is where each partner's key lives.

| | Key in the route ([13](../13-pgp-encryption/)) | Key in the store (this) |
|---|---|---|
| Routes | One per partner | One for all of them |
| Key material in configuration | In every document you import and every revision you read back | None |
| Adding a partner | A new route, a review, a deploy | A write |
| Rotation | A release, as a hard cutover, on the partner's timetable | A write, effective on the next request |
| A change to the route's shape | One edit per partner, and the last one gets missed | One edit |
| Plugins | One | Two, plus two more that protect the registration route |
| Write path to protect | None | One, for your operators only |
| Ways it can fail | Encryption only | Encryption, plus a reference that silently resolves to nothing |

What it costs. Either of these is enough to decide against it for a single
partner:

- **A write path you have to protect.** There is no control-plane API for these
  entries on this build, so the only way in is a route. That route writes key
  material, so it is an admin route, and an open write to your key store is worse
  than a key in a configuration document. Protecting it is a required build step,
  before the first deploy: [Guides](guides.md#build-it-in-the-ui).
- **A second moving part.** Two plugins, a store, and a reference that fails
  silently when it is wrong. `header` instead of `headers` produces no error
  anywhere and looks exactly like "no key registered".

The turning point is the second partner. Starting here when you can see one coming
is less work than moving many routes over later. What it does not buy you (access
control on documents, key history, a check of what you store) is under
[What this does not do](#what-this-does-not-do).

A third option, calling an external secret manager on every request, is
[solution 11](../11-service-callout/)'s shape. It swaps a store for a network call
in the request path.

## When to use this

Use this solution when:

- you have more than one partner, or expect to,
- key material must not live in configuration documents,
- partners rotate keys on their own schedule and you do not want a release each
  time, or
- you need the same treatment for other per-caller values. The store is generic;
  keys are simply the case where a mistake costs most.

Do not use it when:

- **you have exactly one long-lived partner.** [Solution 13](../13-pgp-encryption/)
  is one plugin instead of two, with nothing extra to protect.
- **the value is static configuration.** A per-request lookup of something that
  changes yearly is cost without benefit.
- **you cannot protect the registration route.** An open write path to your key
  store is worse than a key in a configuration document.
- **the answer belongs to another service** rather than a store —
  [solution 11](../11-service-callout/).

## Prerequisites

- An environment where the gateway's key-value store is available.
- An upstream bound to the revision. The spec uses the public `httpbin.org`, whose
  `/post` echoes what it receives.
- An armored OpenPGP public key **with an encryption subkey** to register.
- `helix-auth` and `api-product-enforcer` in your org, an operators-only product
  that includes this API, and an app for each operator. The registration route
  is protected with them before the first deploy
  ([Guides](guides.md#build-it-in-the-ui)).

## What this does not do

- **There is no control-plane API for these entries** on this build. The plugin's
  own `inserts` is the only write path, which is why a registration route exists.
- **The spec and the agent prompt leave the registration route open.** Anybody who
  can reach an open one can register *their* key under *any* partner id, and that
  partner's documents are then encrypted to them. That is why every build path
  adds the protection before the first deploy.
- **The protection counts products per API, not per route.** An app on any
  product that includes this API gets through the registration route's check. Keep
  this API in the operators product only. If partners need apps for the document
  route, move the registration route into an API of its own first.
- **It is not access control on documents.** The partner id comes from a header
  the caller controls, so any caller can ask for any partner's document. They
  receive something encrypted to that partner's key and cannot read it, but that
  is not the same as being refused. Bind the id to an authenticated identity.
- **It does not keep history.** Registration replaces the entry, so a bad write
  destroys the previous value, and a new key is live on the next request. There is
  no versioning and no staged rollout.
- **It does not check what you store.** A wrong key is accepted and only found when
  a partner cannot read a document.
- **`$request.body.<path>` needs a JSON body**, read at request time.
- **Entries are encrypted at rest and scoped per environment.** That protects the
  store; it says nothing about how a value reached the gateway.
- **Everything about the encryption itself** — the wire format, the vague errors,
  the body-size limit — is the same as in [solution 13](../13-pgp-encryption/).
