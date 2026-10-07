# A per-partner sandbox without a sandbox service

> [Overview](README.md) · **Business need** · [Architecture](architecture.md) · [Guides](guides.md) · [Agent prompt](helix-agent-prompt.md) · [Tests](tests.md) · [API reference](api-reference.md)

---

> Every partner gets the same canned response from the sandbox, so the partner
> with an unusual account shape integrates "successfully" and fails in production.
> Making it dynamic has always meant building and running a service.
>
> **Sandbox data should be data, not code.**

- **Integration bugs surface in the sandbox, not production**, because each
  partner finally sees their own values.
- **Onboarding or correcting a partner is one request**, effective on the next
  call — no change request, no review, no deploy.
- **No service to operate.** The gateway answers every route itself: no container,
  no datastore, no patching, no on-call for the sandbox.

The trade-off, stated plainly:

| | A sandbox service | This |
|---|---|---|
| Per-partner answers | Yes | Yes |
| Something to run and patch | An app, a datastore, a pipeline | Nothing beyond the gateway |
| Can pass a value on to your real backend | Yes | **No** — the mock answers the request itself |
| Schema, audit trail, guaranteed persistence | Yours to build | None; values expire after a set time |

That is the right trade for sandbox data and the wrong one for anything else.
Nothing confidential belongs in the store, and the registration route has to be
protected before it is exposed. The full list is in
[Architecture](architecture.md#what-this-does-not-do).

*Also searched as: dynamic API mock · per-tenant sandbox · partner sandbox
environment · mock API with stored data · contract test double per consumer ·
API sandbox without backend · stateful mock at the gateway.*
