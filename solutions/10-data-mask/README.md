# Solution 10 — Data masking: hide personal data from the screen and from the logs

> **Overview** · [Business need](business-need.md) · [Architecture](architecture.md) · [Guides](guides.md) · [Agent prompt](helix-agent-prompt.md) · [Tests](tests.md) · [API reference](api-reference.md)

**In short:** mask sensitive fields — email, phone number, home coordinates — in
the response your callers see, and separately in what your logs keep, without
changing the backend.

| | |
|---|---|
| **Time to try it** | About 15 minutes |
| **Difficulty** | 🟢 Beginner — no coding needed |
| **What you'll need** | A free test account (its default `test` environment). No backend of your own: the example uses public jsonplaceholder data, whose customer records carry email, phone and precise coordinates. To check the log side too, a logger plugin and a log destination you can read |

---

## What is data masking at the gateway?

Masking means replacing the sensitive part of a value before someone sees it —
for example, turning `Sincere@april.biz` into `***@april.biz`. The gateway does
it on the way out, so the backend keeps returning the full record and nobody
downstream sees it.

There are **two different masks**, for two different audiences, and confusing
them is the most common way this project fails:

| | `response-rewrite` | `log-data-mask` |
|---|---|---|
| **Changes** | What the **caller** receives | What a **logger** writes |
| **Effect on the response** | The point | **None** |
| **Needs a logger on the route?** | No | **Yes.** With none, it does nothing at all |
| **Stops a stolen screenshot** | Yes | No |
| **Stops personal data in the log store** | Usually, as a side effect | Yes, and request headers too |

This package ships both.

## The use case

> *"Audit flagged customer PII in our log aggregator, so we have a ticket to mask
> the logs. While we were reading the sample log lines it became obvious that the
> support console shows agents the same thing — every customer's full email,
> full phone number, and the coordinates of their house. Two hundred agents, a
> contact-centre with turnover, and none of them need any of it. The backend is a
> shared service on a quarterly release train, so 'return less' is not a change we
> can make this year."*

Two exposures — the screen and the logs — with one root cause: the backend
returns one full record and every consumer gets all of it. They are usually
treated as one ticket, so the log mask gets configured first, and the screen keeps
showing everything.

## What this gives you

- **A masked response.** The email's personal part, the whole phone number and the
  coordinates are replaced before the response leaves the gateway.
- **A masked log entry**, configured separately, with the `Authorization` and
  `X-Api-Key` headers removed from what a logger writes.
- **Every record masked, not just the first.** The setting that makes this true
  (`scope: global`) is the one most often missed.
- **The useful half kept.** The email domain stays readable, because support uses
  it to tell which customer organisation someone belongs to.

## Benefits

- **No backend release.** Narrowing the response is a configuration change and a
  revision deploy.
- **One rule for every consumer**, applied at the single point they all pass
  through. A new consumer gets the masked view from day one.
- **Provable to an auditor in one response.** "Is it masked?" is answered by a
  test over every record, not by reading configuration.

## Example

A support agent looks up customers. For the first one in the list:

| Field | The backend returns | The support console receives |
|---|---|---|
| `email` | `Sincere@april.biz` | `***@april.biz` |
| `phone` | the full number | `[redacted]` |
| `address.geo.lat` / `lng` | precise home coordinates | `[redacted]` |
| `name`, `username`, `address.city` | as stored | unchanged |

…and the same for every customer in the list, not only the first.

**Setting this up in the gateway's UI takes two short steps:** import the API,
then give it an upstream and deploy it. Both masks come with the imported spec.
[Full click-by-click walkthrough →](guides.md#build-it-in-the-ui)

[Build it any of three ways, then see it work →](guides.md)

## Where to go next

- **Want the business case first?** [Business need](business-need.md) explains why
  this matters, in plain terms.
- **Want to understand how it works?** [Architecture](architecture.md) covers the
  two masks, the `scope` setting, and where regex masking stops.
- **Ready to build it?** [Guides](guides.md) walks you through it step by step.
- **Want the full product documentation?** Every plugin, screen and API call is
  covered at [docs.digitalapi.ai/api-gateway](https://docs.digitalapi.ai/api-gateway).

## Related solutions

- **[08 — API keys](../08-api-key/)** · **[02 — OAuth 2.0 with JWT](../02-oauth-jwt/)** —
  masking is not access control. Put one of these in front.
- **[09 — XML to JSON](../09-xml-to-json/)** — if you convert on the same route,
  the converter runs first and your patterns must match the converted body.
- **[04 — Analytics](../04-analytics/)** — analytics doesn't pass through the log
  helper, so `log-data-mask` doesn't touch it.
