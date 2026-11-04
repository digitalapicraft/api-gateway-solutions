# Solution 23 — Retire an old API version: tell callers when and where, in headers their code can read

> **Overview** · [Business need](business-need.md) · [Architecture](architecture.md) · [Guides](guides.md) · [Agent prompt](helix-agent-prompt.md) · [Tests](tests.md) · [API reference](api-reference.md)

**In short:** run v1 and v2 side by side, mark v1 as deprecated in standard
response headers, and answer a retired v1 endpoint with HTTP 410 (gone) and the
address of its replacement, instead of a bare 404. Your backend doesn't change.

| | |
|---|---|
| **Time to try it** | About 15 minutes |
| **Difficulty** | 🟢 Beginner — no coding needed |
| **What you'll need** | A free test account. The sample API uses a public test backend. |

---

## What is a staged retirement?

A **staged retirement** takes an API version away in steps, and at each step
tells callers what is happening in a form their code can read:

1. **Announce** the dates to the partners you can reach.
2. **Headers.** v1 keeps working, and every response says it is deprecated, when
   it ends, and where its replacement is.
3. **410.** An endpoint that is gone answers "gone, go here", not "not found".
4. **Remove** the route, once nobody calls it.

It works like a shop that moves to a new street. First a sign in the window
with the date, then a note on the locked door with the new address. Only later
does the old shop front disappear.

## The use case

> *"We shipped v2 six months ago. v1 is still called by partners we can't reach.
> When we removed one v1 endpoint last month, they got a bare 404, assumed an
> outage, and opened priority tickets. We need to retire v1 in stages, and tell
> callers in machine-readable terms."*

An email reaches the people you know. It doesn't reach the contractor who built
the integration, or the job that has run unattended for three years. Their code
reads only what the API returns, and a 404 says nothing about why.

## What the gateway gives you

- **Three standard headers on every v1 answer.** `Deprecation` (since when),
  `Sunset` (until when) and `Link` (where to go), as defined by IETF standards,
  so client libraries and log tools can spot them.
- **A successor address for each call.** The `Link` names the v2 address of the
  **same** product: `/v1/products/42` points to `/v2/products/42`.
- **410 Gone for retired endpoints.** The gateway answers itself, with a short
  JSON body naming the replacement. Your backend is never called.
- **Each stage is one revision.** Deploy it, and roll it back the same way.

## Benefits

- **No more outage tickets for a planned change.** A 410 with a successor says
  "on purpose, go here". A 404 says nothing.
- **Callers you can't email still find out.** Their logs, SDKs or monitoring
  can see the headers months before the end date.
- **No backend release.** v1 code stays as it is until the day you switch it
  off. The gateway carries the message.

## Example

The sample API has four routes on a public test backend, where a product is a
post and a review is a comment:

| Call | Stage | What the caller gets |
|---|---|---|
| `GET /v1/products/1` | deprecated | `200`, the product, plus `Deprecation: @1777593600`, `Sunset: Wed, 31 Mar 2027 23:59:59 GMT`, `Link: </v2/products/1>; rel="successor-version"` |
| `GET /v1/products/1/reviews` | retired | `410`, `{"error":"gone", … "successor":"/v2/products/1/reviews"}`, a past `Sunset` and a `Link` |
| `GET /v2/products/1` | current | `200`, the same product, no deprecation headers |
| `GET /v2/products/1/reviews` | current | `200`, the reviews, no deprecation headers |

**In the UI it takes three steps:** create the API with its four routes, add
four plugins with the **Configure plugin** wizard (a path change, the headers,
the 410 and a request id), then add an upstream and deploy.
[Full walkthrough →](guides.md#build-it-in-the-ui)

[Build it any of three ways, then see it work →](guides.md)

## Where to go next

- **Want the business case first?** [Business need](business-need.md) explains why
  this matters, in plain terms.
- **Want to understand how it works?** [Architecture](architecture.md) covers the
  headers, the four stages, and why 410 rather than 404 or a redirect.
- **Ready to try it?** [Guides](guides.md) walks you through it step by step.
- **Want the full product documentation?** Every plugin, screen and API call is
  covered at [docs.digitalapi.ai/api-gateway](https://docs.digitalapi.ai/api-gateway).

## Related solutions

- **[04 — Analytics](../04-analytics/)** — see who still calls v1, before each
  stage.
- **[08 — API keys](../08-api-key/)** — with an app key on every call, you know
  **which** partner is still on v1.
- **[12 — Key-value store](../12-key-value-store/)** — the same `mocking` plugin,
  answering from stored values.
- **[16 — Request tracing](../16-request-tracing/)** — confirm a 410 never
  reached the backend.
- **[19 — Stable public paths](../19-stable-public-paths/)** — versioned public
  paths in front of a backend, the setup this package retires a version of.
- **[24 — Maintenance mode](../24-maintenance-mode/)** — the same gateway-made
  answer for a whole API, when the backend is down for a while rather than gone.
