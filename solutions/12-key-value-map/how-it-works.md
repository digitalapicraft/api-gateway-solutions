# How it works — Solution 12 — one route, fourteen partners, and rotation without a deploy

[Overview](readme.md) · [Business need](business-need.md) · **How it works** · [Install](install.md) · [Configuration](configuration.md) · [Test & verify](testing.md) · [Changelog](changelog.md)

---

## What this package is about

**The store.** Seeding a per-caller value, resolving it from something on the
request, and replacing it without a deploy. That is the whole subject, and it is
the part that transfers to any value you want to keep out of your configuration.

The crypto is plumbing, not the lesson. A stored value has to be *consumed* by
something for you to see it work, and the choice of consumer turns on one
distinction: **observing** a stored value and **using** one are different jobs.

`mocking` can *observe* a stored value — it reads `ctx.helix.key_value_map`
directly, needs no crypto and no Enterprise plan. That is
[solution 14](../14-dynamic-mock/), and it is the shortest way to see the store
work. But `mocking` short-circuits the request, so it can never put a stored value
into a call that reaches your backend.

This package *uses* one, on a real proxied response, and for that the consumer set
is narrower: `pgp-crypto` and `lua-callout` are the only plugins that resolve a KVM
reference themselves. `lua-callout` carries `enterpriseOnly: true` and is refused
at import **on a free-trial organisation** — which is why this package is built on
`pgp-crypto`, and why it runs anywhere. On an organisation that is not on a free
trial, `lua-callout` imports and deploys normally and becomes a second option;
test the import rather than trusting the catalogue flag, which does not change. If you want to understand the crypto itself, that is
[solution 13](../13-pgp-encryption/) — read it if you need it, skip it if you
don't. Everything below is about the store.

The one difference from 13, in a line: **13 writes the key into the route; this
fetches it per request.**

| | [13 — PGP encryption](../13-pgp-encryption/) | **This one** |
|---|---|---|
| Key location | A literal in the route configuration | An entry in a store, fetched per request |
| Adding a counterparty | A new route, a new key in a document | A write |
| Rotating a key | Edit the route, deploy a revision, hard cutover | A write |
| Key material in git | Possible, and the package warns about it | Nothing to leak — no key is in the spec |
| Complexity | One plugin | Two, plus a registration path you must protect |

Use 13 for one long-lived integration. Come here at the second one — and ideally
before, because migrating N routes later is worse than starting here.

## The reference grammar is the whole mechanism

`key-value-map` resolves templates, and `pgp-crypto` resolves the *same* templates
against the namespace it wrote:

```
$request.headers.<name>    $request.query.<name>    $request.body.<dotted.path>
$response.headers.<name>   $response.body.<dotted.path>
$consumer.<suffix>         →  "<consumer_name>.<suffix>"
$ctx.<path>                walks the request context
```

Two things to know before you write one:

- **It is `headers`, plural.** `$request.header.x-partner-id` resolves to nothing,
  silently. The only symptom is the consuming plugin failing — which looks
  identical to "no key registered".
- **The fetch and the consumer must use the same template.** On the read route
  below, `$request.headers.x-partner-id` appears twice: once to decide what to
  fetch, once to decide what to read. They agree because they are the same string.

## Request path

```
Operator ──▶ Gateway ──▶ Backend            Partner ──▶ Gateway ──▶ Backend
                │                                          │
       key-value-map (3001)                       key-value-map (3001)
         inserts:                                   fetch:
           key:   $request.headers.x-partner-id       key: $request.headers.x-partner-id
           value: $request.body.public_key            -> ctx.helix.key_value_map
                │                                          │
                ▼                                   pgp-crypto (898)
            the store                                 keys_ctx_namespace: key_value_map
                                                      public_key: $request.headers.x-partner-id
```

1. **Registration** — `key-value-map` resolves both templates, then writes the
   value under the resolved key. The value comes from the request body, so nothing
   is in the configuration.
2. **Use** — `key-value-map` (priority 3001) runs first and fetches into
   `ctx.helix.<ctx_namespace>`. `pgp-crypto` (priority 898) then resolves the
   *same* template, looks the value up in that namespace, and uses it as key
   material instead of a literal.

The two plugins agree because they resolve an identical string. That is the entire
coupling, and it is also the thing that breaks silently when one of them is edited.

## The reference grammar

Owned by `key-value-map`'s resolver and shared by any plugin that accepts a dynamic
key reference:

| Reference | Resolves to |
|---|---|
| `$request.headers.<name>` | the value of that request header |
| `$request.query.<name>` | the value of that query parameter |
| `$request.body.<dotted.path>` | a value from the JSON request body |
| `$response.headers.<name>` · `$response.body.<path>` | the same, on the response |
| `$consumer.<suffix>` / `$user.<suffix>` | `"<consumer_name>.<suffix>"` |
| `$ctx.<path>` | a walk of the request context itself |

`$consumer.<suffix>` is the one to reach for once identity is in front of this: it
keys entries on the authenticated caller rather than on a header the caller
supplies, which is the difference between a lookup and a lookup you can trust.

**It is `headers`, plural.** The singular resolves to nothing, with no error.

## Native vs custom

Native, and the choice is between this and the simpler single-key shape.

| | Key in the route ([13](../13-pgp-encryption/)) | Key in the store (this) |
|---|---|---|
| Plugins | One | Two |
| Counterparties per route | One | Many |
| Rotation | Edit, review, deploy, hard cutover | A write |
| Key material in the document | Yes | No |
| Write path to protect | None | One, and it is administrative |
| Failure modes | Crypto only | Crypto, plus a silent reference miss |

A third option — an external secret manager called per request — is
[solution 11](../11-service-callout/)'s shape, and it trades a store for a network
dependency in the request path.

## Where a missing value is decided

`key-value-map` treats a miss as an ordinary outcome: it has no way to know whether
the caller needed that value. `fail_action` governs failures of the *store* — it
could not be reached, the write failed — not the absence of a key.

So the question "what does an unregistered partner get?" is answered by the
**consuming** plugin. Here that is `pgp-crypto`'s `fail_policy`, and the answer
must be `fail-close`: `fail-open` would return the backend's document in the clear
to a caller who was supposed to receive ciphertext. One of the automated tests
asserts the error status for that reason, which is why a test that looks like it is
checking an error message is actually checking a security property.

## The registration route

There is no control-plane API for these entries on this build, so a route is the
only write path. That has three consequences worth designing around:

- **It is administrative.** It writes key material. Treat it like any other admin
  endpoint: authenticated, restricted to operators, audited.
- **It replaces.** Writing the same id again overwrites. That is what makes
  rotation a write — and it means a bad write destroys the previous value with no
  history to fall back on.
- **It is the thing this package ships unprotected**, deliberately, because every
  package in this library ships with the behaviour under test and nothing else.
  That is a property of the library, not a recommendation.

## When not to use this shape

- **One long-lived counterparty** — [solution 13](../13-pgp-encryption/) is
  simpler and has nothing extra to protect.
- **You cannot protect the write path** — then the key is safer in configuration.
- **The value changes yearly** — a per-request lookup is cost without benefit.
- **The answer belongs to another service** — [solution 11](../11-service-callout/).

## Failure modes and what they look like

| Symptom | Cause |
|---|---|
| Every partner gets the fail-close error | The reference resolves to nothing — usually `header` instead of `headers`, or the client is not sending the id header |
| One partner works, everyone else fails | A fixed string was written where a reference belongs |
| The document comes back readable | `fail_policy` is `fail-open` on the consuming plugin |
| The partner cannot decrypt a well-formed document | The wrong key was stored. Invisible from the gateway; only a round-trip decrypt finds it |
| Registration returns 503 | The store could not be written. `fail_action: close` means nothing was saved — which is the right outcome |
| Rotation appears not to take effect | The write used a different id, so it created a second entry rather than replacing one |
| It worked, then stopped after an edit | `ctx_namespace` and `keys_ctx_namespace` no longer match |
