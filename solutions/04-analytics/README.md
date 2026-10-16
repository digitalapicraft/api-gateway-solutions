# Solution 04 — Analytics: see who is calling your APIs, how much, and how fast

> **Overview** · [Business need](business-need.md) · [Architecture](architecture.md) · [Guides](guides.md) · [Agent prompt](helix-agent-prompt.md) · [Tests](tests.md) · [API reference](api-reference.md)

**In short:** the gateway already records every request through every API. This
solution shows you how to read that record — requests by API, product or app; the
slowest and fastest APIs; where the errors are — without adding anything to your
APIs.

| | |
|---|---|
| **Time to try it** | About 5 minutes — there is nothing to build or deploy |
| **Difficulty** | 🟢 Beginner — ask in plain English, or run one script |
| **What you'll need** | APIs that already receive traffic, and a control-plane bearer token (the same one the portal uses) |

---

## What is gateway analytics?

Every request that passes through the gateway is recorded: which API and route it
hit, which app and developer sent it (when the API identifies callers), the status
code it got back, how long it took, and how big it was. Nobody has to switch this
on — it is part of the platform, and it happens whether or not you ever look.

**Analytics** is how you read that record back. You ask a question — "which API
was busiest in the last hour?" — and get an answer grouped and filtered the way
you need it.

It works like the itemised bill on a phone contract. The calls were logged as they
happened; the bill just lets you sort them by number, by day, or by cost.

## The use case

> *"At 3am something hammered one of our APIs. On-call spent forty minutes working
> out which integration it was. We could see a spike; we couldn't see whose."*

The data to answer that question was already there. What was missing was knowing
how to ask for it — and knowing which questions the data can't answer, so nobody
builds a report on numbers that don't exist.

## What this solution gives you

- **Three ways to read the same data:** ask the Helix Agent in plain English and
  it draws a chart; run [`scripts/query-analytics.sh`](scripts/query-analytics.sh)
  for a printed summary; or send the metrics API calls yourself.
- **Ready-made questions** for the everyday cases: traffic by API, product or app;
  slowest and fastest APIs; errors by status code; who is being rate-limited;
  traffic over time; data transferred.
- **A clear list of what analytics can't tell you**, so a report is never built on
  a number that isn't there.

## Benefits

- **Find the caller behind a spike while it is still happening.** Name the API,
  app, developer or status code in one query instead of searching logs.
- **No new systems to run.** No separate monitoring stack for the everyday
  questions — the gateway has been recording since it went in.
- **No risk.** You add no plugin and change no API. Every query only reads.

## Example

Run the script against your org and it prints the last hour at a glance:

```
Requests by API
  orders-api                                 17
  checkout-api                                9
  partners-api                                9

Requests by app
  (unattributed)                             18
  partner-b-prod                              9
  partner-c-batch                             8

Slowest APIs (AVG response time, ms)
  reporting-api                             812.0
  orders-api                                41.0
  checkout-api                              28.0

Requests by status code
  200                                        30
  429                                         4
  401                                         1
```

The `(unattributed)` row is traffic from APIs that don't identify their callers —
see [Architecture](architecture.md#two-things-about-attribution) for why, and how
to fix it.

**Reading it takes one step:** paste a question to the Helix Agent, or run the
script with your org id and token. There is nothing to configure first.
[Step by step →](guides.md)

## Where to go next

- **Want the business case first?** [Business need](business-need.md) explains why
  this matters, in plain terms.
- **Want to understand how it works?** [Architecture](architecture.md) covers where
  the data comes from, the read API, and its limits.
- **Ready to try it?** [Guides](guides.md) walks you through all three ways.
- **Want every query, ready to copy?** The [query catalogue](charts.md) has the
  exact request for each everyday question.
- **Want the full product documentation?** Every plugin, screen and API call is
  covered at [docs.digitalapi.ai/api-gateway](https://docs.digitalapi.ai/api-gateway).

## Related solutions

- **[02 — OAuth 2.0 with JWT](../02-oauth-jwt/)** — make an API identify its
  callers, so its traffic is reported per app instead of landing in
  `(unattributed)`.
- **[01 — API Products](../01-api-products/)** — per-product rows and the 429 counts
  come from having products with usage limits.
