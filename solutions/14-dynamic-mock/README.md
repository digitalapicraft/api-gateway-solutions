# Solution 14 — Dynamic mock: a sandbox that answers each partner with their own data

> **Overview** · [Business need](business-need.md) · [Architecture](architecture.md) · [Guides](guides.md) · [Agent prompt](helix-agent-prompt.md) · [Tests](tests.md) · [API reference](api-reference.md)

**In short:** run a partner sandbox with no backend behind it, where every partner
gets their own answers, and where adding or changing a partner is a single request
instead of a deploy.

| | |
|---|---|
| **Time to try it** | About 15 minutes |
| **Difficulty** | 🟢 Beginner — one API, no backend, no coding |
| **What you'll need** | A free test account whose environment has the gateway's key-value store available. No backend service, no encryption, no paid plan. |

---

## What is a dynamic mock?

A **mock** is a route that answers on its own, without calling a real backend.
Sandboxes often use one so partners have something to integrate against. A plain
mock gives everyone the same fixed answer.

A **dynamic mock** builds its answer per request from stored values. Here the
gateway keeps a small store of values per partner, and the mock reads the calling
partner's values when it builds the response.

Think of a hotel's welcome letter. A plain mock is a printed letter that says
"Dear Guest". A dynamic mock is a mail-merge: the same letter, but each guest's own
name and room number are filled in from the register.

## The use case

> *"Every partner gets the same canned response from our sandbox, so nobody
> catches an integration bug until production."*

A sandbox that returns one fixture to everyone only tests your happy path. The
partner on a legacy settlement account, the one on a tier with different limits,
the one whose id has an unusual shape — none of them finds out until production.

The usual fix is a small sandbox service: an app, a datastore, a deploy pipeline,
and something else to keep running. For an endpoint that exists only so partners
can test against it, that is a lot to operate, so most teams keep the canned
response and absorb the bugs.

## What a dynamic mock gives you

- **Per-partner answers from one route.** The partner id on the request picks the
  values.
- **Onboarding is a request.** An operator registers a partner's values with one
  call to an admin route.
- **Changing data is the same request.** The next call sees the new values. No
  revision, no route change, no deploy.
- **No backend.** The gateway answers every route itself, so there is no service to
  run, patch or monitor.

## Benefits

- **Integration bugs show up in the sandbox**, because the sandbox finally differs
  along the lines that break integrations.
- **Partner onboarding stops waiting for a release.**
- **Bad sandbox data gets fixed in seconds**, rather than waiting for a code change
  and a deploy.
- **Support gets a quick answer.** "What does the sandbox think my tier is?" is one
  call as that partner.

## Example

Register two partners, then ask as each:

| Request | Headers | Response |
|---|---|---|
| `POST /sandbox/partners` | `x-partner-id: acme-42`, `x-tier: gold`, `x-settlement-account: GB29-SANDBOX-0001` | **HTTP 202 (accepted)** `{"registered":true,"stored":{…}}` |
| `GET /sandbox/profile` | `x-partner-id: acme-42` | `{"partner":"acme-42","tier":"gold","settlement":"GB29-SANDBOX-0001"}` |
| `GET /sandbox/profile`, after registering `globex-7` the same way | `x-partner-id: globex-7` | `{"partner":"globex-7","tier":"bronze","settlement":"GB29-SANDBOX-0002"}` |
| `POST /sandbox/partners` | `x-partner-id: acme-42`, `x-tier: platinum`, `x-settlement-account: GB29-SANDBOX-0009` | Stored, replacing acme-42's values |
| `GET /sandbox/profile` | `x-partner-id: acme-42` | `{"partner":"acme-42","tier":"platinum","settlement":"GB29-SANDBOX-0009"}` |

A partner nobody registered gets **HTTP 200 (OK) with empty values**, not an
error. That is a deliberate part of the design; see
[Architecture](architecture.md#what-this-does-not-do).

**Setting this up in the gateway's UI takes two short steps:** import the API, then
give it an upstream (never actually called, but required to deploy) and deploy it.
After that you register partners with one request each. Before you expose it,
protect the registration route.
[Full click-by-click walkthrough →](guides.md#build-it-in-the-ui)

[Build it any of three ways, then see it work →](guides.md)

## Where to go next

- **Want the business case first?** [Business need](business-need.md) explains why
  this matters, in plain terms.
- **Want to understand how it works?** [Architecture](architecture.md) covers the
  store, the one setting that makes it per-partner, and the one syntax detail that
  fails silently.
- **Ready to build it?** [Guides](guides.md) walks you through it step by step.
- **Want the full product documentation?** Every plugin, screen and API call is
  covered at [docs.digitalapi.ai/api-gateway](https://docs.digitalapi.ai/api-gateway).

## Related solutions

- **[12 — Key-value map](../12-key-value-map/)** — the same store, used on a real
  proxied response. Go there when a stored value has to reach your backend, which
  a mock can never do.
- **[08 — API keys](../08-api-key/)** — what belongs in front of the registration
  route, and a way to identify partners by credential rather than by a header.
- **[11 — Service callout](../11-service-callout/)** — when the values should come
  from another service rather than a store.
