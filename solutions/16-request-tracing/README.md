# Solution 16 — Request tracing: find out why a live API call failed

> **Overview** · [Business need](business-need.md) · [Architecture](architecture.md) · [Guides](guides.md) · [Agent prompt](helix-agent-prompt.md) · [Tests](tests.md) · [API reference](api-reference.md)

**In short:** turn on a trace for a deployed API, let the failing call happen
again, and read exactly what the gateway did with it: which rule answered, what
reached your backend, and where the time went. No redeploy, no extra logging.

| | |
|---|---|
| **Time to try it** | About 15 minutes |
| **Difficulty** | 🟢 Beginner — no coding needed |
| **What you'll need** | A free test account and one deployed API. This package includes one to deploy. |

---

## What is a trace session?

A **trace session** is a short recording window on one deployed API in one
environment. While it is open, the gateway writes a detailed record of every
request that passes through: the request as it arrived, every plugin that ran
and what it changed, the request as your backend received it, the backend's
answer, and how long each step took.

It works like a flight recorder you switch on for five minutes. The plane flies
exactly the same. Afterwards, you can replay every decision it made.

## The use case

> *"A partner says our API returns 400 on calls that look fine. Our logs show a
> 400 and nothing else. Was it the gateway or our backend? Which rule? What did
> the backend actually receive?"*

Every team running an API gateway gets this ticket. Without a trace, each guess
costs a round-trip:

- **Ask the partner for the exact request**, and wait for them to dig it out.
- **Add logging and redeploy**, which is itself a production change.
- **Wait for it to happen again**, then find out the logging missed the part
  you needed.

## What a trace session gives you

- **Who answered.** Every record says whether a gateway plugin stopped the
  request (and names it) or your backend returned the error.
- **What changed in flight.** Each plugin lists the headers, variables and body
  it changed, so "the backend never got that header" is answerable in seconds.
- **Where the time went.** Gateway phases and the backend hop are timed
  separately, so "is it us or them?" has a number attached.
- **No change to the API.** Tracing is switched on from the console. The
  response your caller gets is identical, and the session ends by itself.

## Benefits

- **Shorter incidents.** One reproduction instead of several redeploy-and-wait
  cycles.
- **Clear ownership.** "Gateway plugin said no" and "backend said no" route to
  different teams. The record settles it.
- **Safe to use on a live API.** A session records at most a handful of requests
  and expires on its own. It can be limited to failures only, or to a header only
  your test sends.
- **Evidence you can share.** The record is concrete. Paste it into the ticket
  instead of a theory.

## Example

The sample API in this package has three routes that fail or behave in three
different ways. One trace session shows all three:

| Call | What the caller sees | What the trace says |
|---|---|---|
| `POST /posts` with no title | `400` | Outcome **Upstream not called**: the `request-validation` plugin answered. The backend was never called. |
| `GET /posts/1` | `200` | `proxy-rewrite` **added** `X-Partner-Channel: api` before the backend saw it. About 35 ms of the 43 ms total was the backend. |
| `GET /posts/999999` | `404` | No plugin said no. The backend's own status was `404`. |

The first and last rows look identical to the partner ("I got an error"). The
trace shows they belong to different teams.

**In the UI it takes four steps:** deploy the sample API, open
**Observability → Traces**, click **Start tracing session** and pick the API,
then send the calls, click **Refresh**, and click a row's path to inspect it.
[Full walkthrough →](guides.md#start-a-trace-session)

[Build it any of three ways, then see it work →](guides.md)

## Where to go next

- **Want the business case first?** [Business need](business-need.md) explains why
  this matters, in plain terms.
- **Want to understand how it works?** [Architecture](architecture.md) covers what
  a record contains and how to read one.
- **Ready to try it?** [Guides](guides.md) walks you through it step by step.
- **Want the full product documentation?** Every plugin, screen and API call is
  covered at [docs.digitalapi.ai/api-gateway](https://docs.digitalapi.ai/api-gateway).

## Related solutions

- **[04 — Analytics](../04-analytics/)** — trends across all your traffic. A trace
  is the opposite: every detail of a few requests.
- **[01 — API Products](../01-api-products/)** — trace a `401`, `403` or `429`
  to see which plugin answered it, instead of guessing from the status code.
- **[11 — Service callout](../11-service-callout/)** — a trace shows the values a
  callout fetched, which is how you debug an enrichment header that came out
  empty.
