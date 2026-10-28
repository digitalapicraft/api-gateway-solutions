# Per-partner keys in a gateway key-value store, not in the config

> [Overview](README.md) · **Business need** · [Architecture](architecture.md) · [Guides](guides.md) · [Agent prompt](helix-agent-prompt.md) · [Tests](tests.md) · [API reference](api-reference.md)

---

> We started with one settlement partner, so the key went in the route. We're at
> fourteen now: fourteen routes identical except for a key, each key in a
> configuration document somebody could commit, and every rotation a change
> request, a review and a deploy. Last month a partner rotated on a Friday
> afternoon, and we found out because their file started failing.
>
> **Store each partner's key at the gateway and fetch it per request; the route
> stays the same for every partner.**

- **Routes per partner: one each → one for all of them.** A change to the route's
  shape is one edit, not fourteen.
- **Keys in configuration: one per partner → none.** The spec holds a reference to
  where the key lives, never the key.
- **A rotation: a release, as a hard cutover → a write.** The partner's next
  request uses the new key, with no deploy.

The cost of moving keys out of the config is a registration route that writes to
the store, and someone has to protect it:

| You have | Use |
|---|---|
| one long-lived counterparty | the key in the route: [13 — PGP encryption](../13-pgp-encryption/) |
| a second counterparty, or rotations on someone else's timetable | this package, with the registration route behind identity |

It ships with the registration route and the partner id both unauthenticated, so
as shipped anyone who can reach the route can register a key under any partner.
The store itself is [solution 12](../12-key-value-store/), and PGP with the key
in the route is [solution 13](../13-pgp-encryption/); this combines them.
[Before/after, what it costs, and what this does not buy you are in
Architecture](architecture.md#no-custom-code-needed).

*Also searched as: key-value store at the API gateway · per-tenant configuration
without redeploy · store partner PGP keys at the gateway · dynamic key lookup per
request · rotate keys without a deploy · per-client encryption keys · move secrets
out of gateway config.*
