# Solution 18 — Validate the request body: refuse a bad request before it reaches your backend

> **Overview** · [Business need](business-need.md) · [Architecture](architecture.md) · [Guides](guides.md) · [Agent prompt](helix-agent-prompt.md) · [Tests](tests.md) · [API reference](api-reference.md)

**In short:** write down what a good request body looks like, once, at the
gateway. A request that doesn't match gets HTTP 400 (bad request) with a
message naming the field, and your backend never sees it.

| | |
|---|---|
| **Time to try it** | About 15 minutes |
| **Difficulty** | 🟢 Beginner — no coding needed |
| **What you'll need** | A free test account. The sample API uses a public test backend, so you don't need your own. |

---

## What is request validation?

**Request validation** is a check the gateway runs on the body of each request
before passing it on. You describe the body you expect: which fields must be
there, what type each one is, which values are allowed. The gateway compares
every request with that description. A match goes through. Anything else is
answered by the gateway with a 400.

It works like a form that won't submit until every required box is filled in.
The office behind it only ever receives complete forms.

## The use case

> *"Our support-ticket service throws a 500 when `priority` is missing or
> `title` is null. The stack traces wake someone up, the caller learns nothing
> useful, and the fix in the service is weeks away."*

Without a check in front of the service:

- **A bad request looks like an outage.** HTTP 500 (server error) is the
  service's own crash, so it pages the on-call team.
- **The caller can't fix it.** A 500 says nothing about which field was wrong.
- **The real fix is slow.** Changing the service means a release, and every
  team that owns a service has to write the same checks again.

## What request validation gives you

- **The right status.** A bad body is the caller's mistake, and gets a 400.
- **A message that names the field**, such as `property "priority" is
  required`, so the caller can fix the request without asking you.
- **A backend that only sees good bodies.** A refused request is never sent on.
- **One rule per route.** Creating a ticket can require fields that changing
  one doesn't.

## Benefits

- **Fewer false alarms.** Bad input stops showing up as server errors.
- **A fix in minutes, not a release.** The rule is gateway configuration: add
  it today, while the service fix waits its turn.
- **The rule is written down.** It is the same kind of schema an OpenAPI
  document uses, so it doubles as documentation of what the API accepts.
- **No code.** One plugin, configured with JSON.

## Example

The sample API has two routes in front of a public test backend that stands in
for the ticket service:

| Call | What the caller gets |
|---|---|
| `POST /tickets` `{"title":"Printer on fire","priority":"high"}` | `201` from the backend, with the new ticket |
| `POST /tickets` `{"title":"Printer on fire"}` | `400` `property "priority" is required` |
| `POST /tickets` `{"title":null,"priority":"high"}` | `400` naming `title`: it must be a string |
| `POST /tickets` `{"title":"Printer on fire","priority":"urgent"}` | `400` naming `priority`: it must be low, normal or high |
| `POST /tickets` with a body that isn't JSON | `400` with the parser's message |
| `PATCH /tickets/1` `{"priority":"low"}` | `200` from the backend: a change needs no required fields |
| `PATCH /tickets/1` `{"priority":"urgent"}` | `400`: a field that is sent must still follow the rule |

None of the 400s reach the backend.

**In the UI it takes three steps:** create the API with its two routes (from
scratch, or from an OpenAPI spec), add the plugins (the body check on each
route, and a path change so `/tickets` reaches the backend's `/posts`), then
give it an upstream and deploy it.
[Full walkthrough →](guides.md#build-it-in-the-ui)

[Build it any of three ways, then see it work →](guides.md)

## Where to go next

- **Want the business case first?** [Business need](business-need.md) explains why
  this matters, in plain terms.
- **Want to understand how it works?** [Architecture](architecture.md) covers what
  the check does, what the caller sees, and what it doesn't catch.
- **Ready to try it?** [Guides](guides.md) walks you through it step by step.
- **Want the full product documentation?** Every plugin, screen and API call is
  covered at [docs.digitalapi.ai/api-gateway](https://docs.digitalapi.ai/api-gateway).

## Related solutions

- **[16 — Request tracing](../16-request-tracing/)** — see which plugin answered
  a call. A refused body shows there as **Upstream not called**, answered by
  `request-validation`.
- **[09 — XML to JSON](../09-xml-to-json/)** — change the shape of a body on the
  way through, rather than refusing it.
- **[08 — API keys](../08-api-key/)** — check who is calling before you check
  what they sent.
