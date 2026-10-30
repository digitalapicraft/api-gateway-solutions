# Solution 17 — Mock before the backend: a real URL for an endpoint that doesn't exist yet

> **Overview** · [Business need](business-need.md) · [Architecture](architecture.md) · [Guides](guides.md) · [Agent prompt](helix-agent-prompt.md) · [Tests](tests.md) · [API reference](api-reference.md)

**In short:** publish the agreed routes at the gateway today and let it answer
them with sample responses. When the backend ships, remove the mock: the same
URLs reach the backend, and the frontend changes nothing.

| | |
|---|---|
| **Time to try it** | About 15 minutes |
| **Difficulty** | 🟢 Beginner — no coding needed |
| **What you'll need** | A free test account. No backend: the gateway answers every call. |

---

## What is a mock?

A **mock** is a route the gateway answers on its own, with a response you wrote
in advance, instead of passing the call to a backend. To the caller it looks
like the real API: the same host, the same path, a real status code and a real
JSON body.

It works like a film set's shop front. From the street it looks like a shop and
the actors can walk up to it. When the real shop opens, it opens at the same
address.

## The use case

> *"The frontend team is blocked: the shipment-tracking screen needs
> `GET /shipments/:shipmentId` and `POST /shipments`, and the backend team won't
> have them for three weeks. We've agreed the JSON contract. We need a real URL
> returning that contract today."*

Without a mock, the usual workarounds each cost something later:

- **Hard-coded sample data in the frontend**, which someone has to find and take
  out before release.
- **A local mock server on each developer's laptop**, so every developer runs
  something different and nobody can share a link.
- **Waiting**, which turns a three-week backend into a six-week feature.

## What a mock at the gateway gives you

- **A shared URL today.** Everyone, including testers and the demo, calls the
  same host and gets the agreed answer.
- **The contract in one place.** The OpenAPI file holds the routes, the JSON
  shapes and the sample answers.
- **A visible marker.** Every mocked answer carries an `x-mock-by` header, so the
  frontend can tell sample data from real data.
- **A switch-over with no client change.** The backend arrives as a new revision
  of the same API, on the same host and paths.

## Benefits

- **The frontend starts now**, not when the backend is ready.
- **Nothing to clean up in the client.** No sample data to remove, no URL to
  change at release.
- **A safe way back.** If the first backend release misbehaves, deploying the
  mocked revision again puts the sample answers back.
- **Disagreements show up early**, while the contract is still cheap to change.

## Example

| Call | Answer while mocked | Answer after the switch-over |
|---|---|---|
| `GET /shipments/SHP-1001` | HTTP 200 (OK), the sample shipment, `x-mock-by` | the backend's answer |
| `GET /shipments/anything` | the same sample shipment: every id gets one answer | the backend's answer |
| `POST /shipments` | HTTP 201 (created), a sample body, `Location: /shipments/SHP-1001` | the backend's 201 |
| `DELETE /shipments/SHP-1001` | HTTP 404 `Route Not Found`: it isn't in the contract | the same |

The sample package switches over to a public test backend that has no
`/shipments`, so its switched-over version also maps the paths onto that
backend's `/posts`. Your own backend won't need that.

**In the UI it takes four steps:** create the API with its two routes, add the
`mocking` plugin to each route, give it an upstream and deploy it, then, when the
backend is ready, clone the revision without the mock and **Force Deploy** it.
[Full walkthrough →](guides.md#build-it-in-the-ui)

[Build it any of three ways, then see it work →](guides.md)

## Where to go next

- **Want the business case first?** [Business need](business-need.md) explains why
  this matters, in plain terms.
- **Want to understand how it works?** [Architecture](architecture.md) covers the
  mock, the marker header and the switch-over.
- **Ready to try it?** [Guides](guides.md) walks you through it step by step.
- **Want the full product documentation?** Every plugin, screen and API call is
  covered at [docs.digitalapi.ai/api-gateway](https://docs.digitalapi.ai/api-gateway).

## Related solutions

- **[12 — Key-value store](../12-key-value-store/)** — when each caller, or each id,
  needs its own answer. This package's mock gives everyone the same one.
- **[18 — Validate the request body](../18-validate-request-body/)** — turn away
  a create with missing fields at the gateway, before and after the switch-over.
- **[16 — Request tracing](../16-request-tracing/)** — see whether a given call
  was answered by the mock or reached the backend.
- **[24 — Maintenance mode](../24-maintenance-mode/)** — the same kind of
  gateway answer, switched on for a whole API while its backend is down.
