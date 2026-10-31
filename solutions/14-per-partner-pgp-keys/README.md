# Solution 14 — Per-partner PGP keys: keep each partner's key as data, not configuration

> **Overview** · [Business need](business-need.md) · [Architecture](architecture.md) · [Guides](guides.md) · [Agent prompt](helix-agent-prompt.md) · [Tests](tests.md) · [API reference](api-reference.md)

**In short:** serve many partners from one route, each with their own encryption
key, and add or rotate a partner's key with a single request instead of a deploy.

| | |
|---|---|
| **Time to try it** | About 30 minutes |
| **Difficulty** | 🟡 Intermediate — two plugins, and a write path you have to protect |
| **What you'll need** | A free test account (its default `test` environment) and an OpenPGP public key to register. Nothing in the spec needs filling in: no key material appears in it, which is the point. You also create one app for your operators, so that only they can register keys. |

---

## What is a key-value map?

A **key-value map** is a small store that lives inside the gateway. A route can
write a value into it, and another route can read that value back on a later
request, picking the entry from something on the request, such as a partner id
in a header.

Think of a hotel's key rack. The front desk does not cut a new door for each
guest. It hangs each guest's key on a numbered hook, and hands over whichever key
matches the room number you give. Here the "hook number" is the partner id, and
the "key" is that partner's public encryption key.

This package combines two earlier ones.
[Solution 12](../12-key-value-store/) is the gateway's key-value store: it keeps a
value per caller, picks it from something on the request, and replaces it without
a deploy. [Solution 13](../13-pgp-encryption/) is PGP encryption with the key
written into the route. Here each partner's PGP key lives in the store, so one
route serves every partner and a rotation is a write. Read 12 for the store and 13
for the encryption; these pages cover what the combination adds.

The one difference from 13, in a line: **13 writes the key into the route; this
package fetches it on every request.**

## The use case

> *"We started with one settlement partner, so the key went in the route. We're at
> fourteen now. That's fourteen routes that are identical except for a key, every
> one of those keys is in a configuration document somebody could commit, and when
> a partner rotates — which they do, on their schedule, not ours — it's a change
> request, a review and a deploy. Last month one of them rotated on a Friday
> afternoon and we found out because their file started failing."*

Writing a partner's key into a route works for the first partner. After that:

- **You get one route per partner**, identical except for the key, so any change
  to the route's shape has to be made many times.
- **Every key sits in a configuration document**, where it can end up in a code
  repository.
- **Every rotation is a release**, on the partner's timetable rather than yours,
  and the old and new keys cannot both be live on one route.

## What a key-value map gives you

- **One route for every partner.** The partner id on the request picks the key.
- **Adding a partner is a write.** One request to a registration route. No new
  route, no review, no deploy.
- **Rotating a key is the same write.** The next request uses the new key.
- **No key material in the configuration.** The registration route takes the key
  from the request body, so the spec you import and the revision you read back
  contain no keys.

## Benefits

- **Partner onboarding stops waiting for a release.** It becomes data entry.
- **Partner rotations stop being your emergency.** Their schedule and your release
  schedule are no longer tied together.
- **Less to leak.** There is no key in any document that could be committed.
- **A shape change is one edit**, not one edit per partner.

## Example

Say you send statements to partners, each encrypted to that partner's own key:

| Step | Request | What comes back |
|---|---|---|
| Partner `acme-bank` has not registered yet | `GET /partners/documents` with `X-Partner-Id: acme-bank` | **HTTP 500 (server error)**, and no document in any form |
| An operator registers `acme-bank`'s public key | `POST /partners/keys` with the key in the body and the operator's app key in `X-Admin-Key` | Stored |
| Someone without an operator's key tries the same | `POST /partners/keys` | **HTTP 401 (not signed in)** or **HTTP 403 (not allowed)**, and nothing is stored |
| `acme-bank` asks again | `GET /partners/documents` | HTTP 200 (OK), the document encrypted to `acme-bank`'s key |
| `acme-bank` rotates, and the operator registers the new key | `POST /partners/keys` again | Stored, replacing the old key |
| `acme-bank` asks again | `GET /partners/documents` | Encrypted to the **new** key. The old key can no longer read it. |

No revision, no route change and no deploy at any step.

**Setting this up in the gateway's UI takes seven short steps:** create the API
(from scratch, or from an OpenAPI spec), add the plugins that store each partner's
key and encrypt each document to it, protect the registration route so only your
operators can write keys, give the API an upstream and deploy it, create an
operators-only product, give your operators an app and its key, then register
each partner's key with one request. **The protection step is required, and it
comes before the deploy.** The spec and the agent prompt leave the registration
route open, and anyone who can reach an open one can register their own key
under any partner's id.
[Full click-by-click walkthrough →](guides.md#build-it-in-the-ui)

[Build it any of three ways, then see it work →](guides.md)

## Where to go next

- **Want the business case first?** [Business need](business-need.md) explains why
  this matters, in plain terms.
- **Want to understand how it works?** [Architecture](architecture.md) covers the
  two routes, how the store and the encryption agree on a key, and what this does
  not protect.
- **Ready to build it?** [Guides](guides.md) walks you through it step by step.
- **Want the full product documentation?** Every plugin, screen and API call is
  covered at [docs.digitalapi.ai/api-gateway](https://docs.digitalapi.ai/api-gateway).

## Related solutions

- **[13 — PGP encryption](../13-pgp-encryption/)** — the same encryption with the
  key written into the route. Go there for the encryption itself, or if you have
  exactly one partner.
- **[12 — Key-value store](../12-key-value-store/)** — the quickest way to see the store
  work: it reads stored values back with no encryption at all.
- **[11 — Service callout](../11-service-callout/)** — when the per-request value
  comes from another service rather than a store.
- **[08 — API keys](../08-api-key/)** — app keys at the gateway, the kind that
  protects the registration route here, and how to key entries on an
  authenticated caller instead of a header.
- **[01 — API Products](../01-api-products/)** — how a product decides which apps
  get through, which is what limits the registration route to your operators.
