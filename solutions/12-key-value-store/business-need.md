# A per-partner sandbox from the gateway's key-value store

> [Overview](README.md) · **Business need** · [Architecture](architecture.md) · [Guides](guides.md) · [Agent prompt](helix-agent-prompt.md) · [Tests](tests.md) · [API reference](api-reference.md)

---

> Every partner integrating with us hits the sandbox first, and every one gets the
> same fixture back. The partner on a legacy settlement account and the one on a
> tier with different limits both integrate fine against it, then fail in
> production. Making the sandbox dynamic always meant a service: an app, a
> datastore, a pipeline and a pager, for something that exists so other people can
> test.
>
> **Keep each partner's values in the gateway's store and answer from them; no
> service behind the endpoint.**

- **What a partner sees: the same fixture as everyone → its own values.**
  Integration bugs surface in the sandbox, not in production.
- **Adding or correcting a partner: a code change and a deploy → one request.**
  It takes effect on the next call.
- **Services to run for the sandbox: one → none.** The gateway answers every route
  itself.

The store can show a value to the caller, or hand it to your backend, and those
are different packages:

| You need the stored value to | Use |
|---|---|
| come back in the response: a sandbox, a demo, a per-consumer test double | this package |
| reach a real backend call: per-partner keys, per-tenant settings | [14 — Per-partner PGP keys](../14-per-partner-pgp-keys/) |

It ships with the registration route unauthenticated, and any stored value is
readable by anyone who sends the matching partner id, so nothing confidential
belongs in it. Values expire, and there is no schema or audit trail.
[Before/after](README.md#what-a-key-value-store-gives-you), [the one thing to get
right](architecture.md#the-two-template-syntaxes), and [what this does not buy
you](architecture.md#what-this-does-not-do) are on the Overview and Architecture
pages.

*Also searched as: key-value store at the API gateway · per-partner sandbox ·
dynamic mock responses per caller · mock API that differs per client · partner
sandbox without a backend · store and read values at the gateway · per-tenant test
data without a deploy.*
