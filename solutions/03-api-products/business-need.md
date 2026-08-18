# Business need — API Products with enforced quota

## The situation

Two failures that look unrelated are the same failure.

**The first is an outage.** One integration partner's retry loop has no backoff. It
sends 40,000 requests a minute at an endpoint sized for 3,000. Every other customer
gets 503s. You find out from Twitter, and the post-mortem action item is "add rate
limiting", which sits in a backlog because nobody can say what the limit should be.

**The second is a commercial dead end.** You sell an "Enterprise" tier that promises
higher throughput. There is no technical difference between it and the free tier.
Sales knows this. Some customers suspect it. Nobody upgrades for throughput, because
throughput isn't actually what they're buying — and when an Enterprise customer has a
capacity problem, you have no answer that isn't "we'll look into it".

Both come from the same place: **every caller shares one undifferentiated pool, and
the gateway has no idea who is calling or what they bought.**

The consequences compound quietly:

- **You provision for the worst-behaved caller's peak**, because that's the only
  bound that exists. Capacity is sized against a hypothetical, not against
  commitments.
- **The real limit is undocumented**, because it isn't a limit — it's the point where
  the backend falls over. Support can't tell a customer their ceiling. Neither can
  on-call.
- **"Which partner caused this?"** is a log hunt with IP addresses, during an
  incident, at 3am.
- **Chargeback is impossible.** You can't attribute infrastructure cost to the
  customers generating it, so heavy users are subsidised by light ones and nobody
  knows by how much.

## What changes

The quota attaches to **the thing you sell** — a product — and is counted per app.

| Dimension | Without product quota | With this solution |
|---|---|---|
| **Blast radius of a bad integration** | 100% of consumers | The offending app |
| **Revenue-path protection** | Checkout competes with batch and free-tier traffic for one pool | Committed accounts get the throughput they paid for |
| **What "Enterprise" means** | A contract line with no enforcement | An enforced technical difference |
| **Upgrade motivation** | None — the tiers are identical in practice | Hitting the ceiling is the trigger |
| **Capacity planning basis** | The worst caller's hypothetical peak | The sum of committed quotas |
| **Attribution** | An IP in a log | Every request tied to an app and a developer |
| **Support answer to "what's my limit?"** | Nobody knows | A number, in the contract, enforced |
| **Chargeback** | Not possible | Per-app request counts |

## The mechanism that matters

Two things change, and the second is the one people miss.

**First: the blast radius becomes bounded, and bounded to the party responsible.**
Not "we survive the spike" — the offending app exhausts its *own* budget while every
other caller is unaffected. That's a different property from a global rate limit,
which protects the backend by rejecting *whoever happens to be calling*. A global
limit turns one partner's bug into everyone's degraded service, just less severely.

**Second: capacity planning changes basis.**

> Without a per-caller bound, you must provision against what a caller *might* do.
> With one, you provision against the sum of what you *sold*.

That's the cost argument, and it's a real one — but it comes with an arithmetic check
that's easy to skip: **add up the committed quotas across the tiers you have actually
sold, and compare that with what your upstream can take.** If the sum exceeds your
capacity, you have oversold. The quota will surface that as 429s to your customers
rather than as an outage — which is a better failure, but it is still a failure, and
it is better to discover it in a spreadsheet.

And the commercial consequence, which is usually what gets this funded:

> A quota turns a contract line into a product feature, and a ceiling into an upgrade
> conversation.

An app repeatedly hitting its Free limit is a qualified lead with a number attached.
An Enterprise account never approaching its quota is either over-provisioned or not
really integrated yet, and both are worth knowing. Neither signal exists without
metering. See [solution 04](../04-analytics/) for the queries that surface them.

## Tier design is a commercial decision, not a technical one

The numbers matter more than the configuration, and only two rules generalise:

**Free must be unusable for production.** If it's generous enough to build on, nobody
upgrades and you have given the product away. Its job is to let someone *try* the
API, not run on it.

**Enterprise must match a contract.** It's the one tier where the quota is a promise
you've made in writing, and it's the number a customer will quote at you during an
incident. Don't derive it by scaling the tier below.

Everything between those is measurement: roughly 2× a healthy integration's p95 is a
reasonable starting point for a production tier, but use your own numbers.

One choice that trips people up — **the window shapes behaviour as much as the
limit.** A per-minute window *absorbs* bursts; a per-second window *shapes* them.
Contracts written in requests-per-*day* are the worst of both: one app can spend the
entire day's budget in 40 seconds and then go dark until midnight, which is neither
protection nor a usable service.

## Business outcomes

**Availability stops depending on your worst-behaved partner.** The 22-minute outage
class of incident becomes one partner's 429s. That's the outcome you can put in a
post-mortem action item and actually close.

**Tiers become sellable.** "Enterprise gets 10,000 requests a minute" is a
differentiated product with an enforced guarantee. This is the change that makes the
pricing page honest.

**Capacity is provisioned against commitments.** You size for what you sold rather
than for what anyone might do. How much that saves depends entirely on the gap
between your current headroom and your committed quotas — measure it rather than
assuming a multiple.

**Upgrade conversations get data.** Quota consumption per app is a pipeline signal
with a number attached, not a hunch.

**Incident attribution drops from hours to seconds.** Every request is tied to an app
and a developer, so "which integration caused this" is a query.

**Chargeback becomes possible.** Per-app request counts are the input to attributing
infrastructure cost to the customers generating it.

**A marketplace becomes reachable.** The product is the unit a partner subscribes to.
Without products there is nothing to list, nothing to self-serve onto, and no
metering behind the subscription.

## What this does not buy you

Stated plainly, because overclaiming here produces disappointed partners:

- **No budget headers.** `api-product-enforcer` emits no `X-RateLimit-*` and no
  `Retry-After`. A client cannot read its remaining quota from a response. The retry
  contract must live in your developer documentation, and it must specify backoff
  *with jitter* — without it, every client retries at the same instant at the top of
  each window and you've scheduled a thundering herd.
- **It is not per-request pricing.** The quota is a request count. A cheap read and a
  30-second report consume one unit each. If cost varies wildly by endpoint, split
  into separate products per endpoint group or the quota misprices your expensive
  paths.
- **It is not burst shaping.** Quota counts within a window. A caller can spend a
  minute's budget in two seconds unless you choose a shorter window.
- **It doesn't meter your end users.** The unit is the app. If you need per-end-user
  limits, that's application logic.
- **It doesn't fix an oversold capacity model.** See the arithmetic check above. It
  makes overselling visible instead of catastrophic, which is not the same as
  preventing it.
- **On more than one gateway node it silently doesn't work** unless the quota backend
  is Redis. This isn't a limitation of the model, but it is the most common reason
  the promised outcome doesn't materialise, and it's invisible from the route
  configuration.
- **No numbers are claimed here.** The 40,000-requests-a-minute outage is the
  *shape* of a common incident, not a measured figure from your estate, and this
  document deliberately quantifies mechanisms (blast radius, planning basis) rather
  than inventing an ROI multiple. Use your own capacity numbers and your own
  committed quotas.

## Success criteria

You'd call this done when:

- A deliberately misbehaving app receives 429s while **every other app is
  unaffected** — verified by [`gateway/verify.sh`](gateway/verify.sh) case 5, not by
  case 4. Proving a limit exists is easy; proving it's scoped to the offender is the
  point.
- Support can state a customer's throughput limit, and it matches what's enforced.
- Your pricing page's tier differences are technically real.
- Capacity is planned from the sum of committed quotas, and you've checked that sum
  against what the upstream can take.
- "Which app caused the spike?" is answerable in seconds.
- You can list the apps within 10% of their quota — those are your upgrade
  conversations.
- If the gateway runs more than one node, you have confirmed `quota_policy` is
  `redis`, rather than assumed it.
