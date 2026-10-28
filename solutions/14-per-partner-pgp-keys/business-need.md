# Per-partner encryption keys without a deploy per partner

> [Overview](README.md) · **Business need** · [Architecture](architecture.md) · [Guides](guides.md) · [Agent prompt](helix-agent-prompt.md) · [Tests](tests.md) · [API reference](api-reference.md)

---

> Fourteen partners means fourteen routes that differ by one key, fourteen keys in
> configuration documents somebody could commit, and a change request every time a
> partner rotates on their own schedule.
>
> **All three costs grow with every partner you add.**

- **One route serves every partner.** The partner id on the request picks the key,
  so adding a partner is a write, not a new route and a deploy.
- **Rotation is a write**, effective on the next request. The partner's schedule
  stops being your release schedule.
- **No key material in the configuration.** The key arrives in a request body, so
  there is nothing in the spec to leak.

It is not free, and the trade-off decides when to adopt it:

| | Key in the route ([13](../13-pgp-encryption/)) | Key in the store (this) |
|---|---|---|
| Partners per route | One | Many |
| Rotation | Edit, review, deploy, hard cutover | One request |
| Extra thing to protect | Nothing | A registration route that writes keys |

For one long-lived partner, the simpler shape wins. The turning point is the
second partner, and it is worth starting here if you can see one coming: moving
many routes over later is more work than starting with one. What this does not
protect, including the open registration route, is covered in
[Architecture](architecture.md#what-this-does-not-do).

*Also searched as: per-tenant encryption keys · key rotation without deploy ·
multi-tenant PGP · dynamic key lookup at the gateway · partner key registry ·
gateway key-value store · secrets out of API config.*
