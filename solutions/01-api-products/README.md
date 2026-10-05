# Solution 01 — API Products: give different customers different usage limits

> **Overview** · [Business need](business-need.md) · [Architecture](architecture.md) · [Guides](guides.md) · [Agent prompt](helix-agent-prompt.md) · [Tests](tests.md) · [API reference](api-reference.md)

**In short:** create pricing plans for your API, and automatically stop any one
customer from using more than their plan allows, without affecting anyone else.

| | |
|---|---|
| **Time to try it** | About 20 minutes |
| **Difficulty** | 🟢 Beginner — no coding needed |
| **What you'll need** | A free test account, plus two test apps so you can watch one get blocked while the other keeps working |

---

## What is an API Product?

An **API Product** is a named plan — a bundle of one or more APIs, sold as a unit,
with a usage limit attached. Instead of every customer sharing the same pool of
capacity, each customer's app is subscribed to a specific product, and the gateway
checks and enforces that product's limit on every single request.

It works like a mobile phone plan. The "product" is the plan itself — say, "10GB a
month" — and every customer on that plan is measured against it individually. One
customer using their full 10GB never touches anyone else's data.

## The use case

> *"One partner's retry loop took down our checkout API on Black Friday. Every app
> shares one undifferentiated pool."*

This is the problem API Products exist to solve. You have several customers or
partners calling your API. You may already sell different pricing tiers — Free,
Pro, Enterprise. But nothing actually enforces the difference between them, so:

- **One misbehaving app can affect everyone else**, because all capacity comes
  from the same shared pool.
- **A "premium" plan is just a name.** A Free customer can use exactly as much as
  your best-paying customer, because nothing is checking.

## What an API Product gives you

- **A named plan** that bundles specific APIs together.
- **A usage limit (a quota)** attached to that plan — for example, a number of
  requests allowed per minute.
- **Automatic enforcement.** The gateway checks every request against the calling
  app's plan. You don't write any code for this.
- **Per-app isolation.** One app hitting its limit never affects another app, even
  if they're on the same plan.
- **Attribution.** Every request is tied to the specific app and developer that
  made it.

## Benefits

- **Protects your capacity during a spike.** A misbehaving integration burns
  through only its own budget, not everyone else's.
- **Makes your pricing tiers real.** "Enterprise gets more throughput" becomes
  something you actually enforce, not just a line in a contract.
- **Turns hitting a limit into a sales signal.** An app that keeps maxing out its
  plan is a candidate for an upgrade conversation.
- **Gives you attribution for free.** Every request is tied to an app and a
  developer, which makes incident response and billing easier.

## Example

Say you run a checkout API and want two plans:

| Plan | Limit | Who it's for |
|---|---|---|
| Free | 5 requests a minute | Trying it out |
| Pro | 1,000 requests a minute | Paying customers |

Once this is set up: a Free app that sends 6 requests in one minute gets blocked
on the 6th. A Pro app calling at the exact same moment keeps working, completely
unaffected.

**Setting this up in the gateway's UI takes eight short steps:** import the
API, give it an upstream and deploy it, create the Free product with its
quota, deploy that too, create the Pro product the same way, add a developer,
create two apps for them (one per plan), then grab each app's key.
[Full click-by-click walkthrough →](guides.md#build-it-in-the-ui)

[Build it any of three ways, then see it work →](guides.md)

## Where to go next

- **Want the business case first?** [Business need](business-need.md) explains why
  this matters, in plain terms.
- **Want to understand how it works?** [Architecture](architecture.md) covers the
  moving parts and the vocabulary (what a "Product" or an "App" means here).
- **Ready to build it?** [Guides](guides.md) walks you through it step by step.
- **Want the full product documentation?** Every plugin, screen and API call is
  covered at [docs.digitalapi.ai/api-gateway](https://docs.digitalapi.ai/api-gateway).

## Related solutions

- **[02 — OAuth 2.0 with JWT](../02-oauth-jwt/)** — if you can't yet tell which
  customer is calling your API, start there first.
- **[03 — SOAP to REST](../03-soap-to-rest/)** — put a usage limit on an older,
  legacy system and turn it into a sellable plan.
- **[04 — Analytics](../04-analytics/)** — see which customers are close to their
  limit, and who's been blocked.
