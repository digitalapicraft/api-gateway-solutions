# Solution 19 — Stable public paths: rename the backend without breaking a single client

> **Overview** · [Business need](business-need.md) · [Architecture](architecture.md) · [Guides](guides.md) · [Agent prompt](helix-agent-prompt.md) · [Tests](tests.md) · [API reference](api-reference.md)

**In short:** give your API public paths that never change, such as
`/v1/customers`, and let the gateway send each call to wherever the backend
really serves it. When the backend renames or moves a path, you change one
setting on the gateway. Clients don't change at all.

| | |
|---|---|
| **Time to try it** | About 15 minutes |
| **Difficulty** | 🟢 Beginner — no coding needed |
| **What you'll need** | A free test account. The example uses a public test backend, so you don't need one of your own. |

---

## What is a stable public path?

A **public path** is the address your clients call. A **backend path** is the
address your backend actually serves. Usually they are the same thing, so a
client is tied to however the backend happens to be organised today.

A stable public path separates the two. The gateway keeps a short list: "a
call to `/v1/customers/1` goes to `/users/1`". Clients only ever learn the
left-hand side. The right-hand side can change whenever the backend team needs
it to.

## The use case

> *"Our mobile app calls the backend's own paths. Last quarter the backend team
> renamed `/users`, and every client release broke. We want public paths that
> are a contract, and backends free to move behind them."*

Without a gateway in between, a backend rename means one of three things:

- **Every client ships a new release**, and old app versions break anyway.
- **The backend keeps the old paths forever**, next to the new ones.
- **Nobody renames anything**, and the backend's layout freezes.

## What stable public paths give you

- **A contract clients can rely on.** `/v1/customers`, `/v1/customers/:customerId`
  and `/v1/customers/:customerId/orders` don't change when the backend does.
- **Backend paths stay private.** Only the public paths have routes. A call to
  the backend's own `/users/1` gets the gateway's 404, even if a client finds
  out the path.
- **One change per backend move.** A renamed path is one setting on one route.
  A new host is one setting on the upstream.
- **Query strings pass through.** A client's `?_limit=2` reaches the backend
  unchanged, whichever kind of rewrite the route uses.

## Benefits

- **Backend teams move freely.** Renames, new layouts and new hosts no longer
  need a client release.
- **Old app versions keep working.** The paths they call are the same paths.
- **Less to expose.** Clients see only the paths you chose to publish.
- **A test for the contract.** The included script checks every public path
  returns the right record. Run it after each backend change.

## Example

The example API has three public paths on a public test backend, where
customers are its users and orders are its todos:

| Client calls | Gateway sends the backend | Client gets |
|---|---|---|
| `GET /v1/customers?_limit=2` | `GET /users?_limit=2` | `200`, 2 customers |
| `GET /v1/customers/3` | `GET /users/3` | `200`, customer 3 |
| `GET /v1/customers/1/orders` | `GET /users/1/todos` | `200`, customer 1's 20 orders |
| `GET /users/1` | nothing | `404 Route Not Found`, from the gateway |

When the backend later serves orders at `/todos?userId=1` instead, only the
third rewrite changes, and clients get the same responses.
[One thing to watch when that happens →](guides.md#the-backend-moved)

**In the UI it takes three steps:** create the API with its three routes, add
a `proxy-rewrite` plugin to each route, then add an upstream and deploy.
[Full walkthrough →](guides.md#build-it-in-the-ui)

[Build it any of three ways, then see it work →](guides.md)

## Where to go next

- **Want the business case first?** [Business need](business-need.md) explains why
  this matters, in plain terms.
- **Want to understand how it works?** [Architecture](architecture.md) covers the
  two kinds of rewrite and what happens to the query string.
- **Ready to try it?** [Guides](guides.md) walks you through it step by step.
- **Want the full product documentation?** Every plugin, screen and API call is
  covered at [docs.digitalapi.ai/api-gateway](https://docs.digitalapi.ai/api-gateway).

## Related solutions

- **[08 — API key](../08-api-key/)** — add a key to these paths before you
  publish them. Its routes use the same kind of rewrite.
- **[10 — Data masking](../10-data-mask/)** — change what comes back, not just
  where the call goes.
- **[16 — Request tracing](../16-request-tracing/)** — see the exact path the
  gateway sent to your backend, when a rewrite doesn't do what you expected.
- **[23 — Retire an old version](../23-retire-old-version/)** — when the `/v1`
  paths here are replaced by `/v2`, tell callers in headers before you switch v1 off.
