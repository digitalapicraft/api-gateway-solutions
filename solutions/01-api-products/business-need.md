# Business need — API Products with enforced quota

> [Overview](README.md) · **Business need** · [Architecture](architecture.md) · [Guides](guides.md) · [Examples](examples.md) · [Agent prompt](helix-agent-prompt.md) · [Tests](tests.md) · [Configuration reference](configuration-reference.md) · [API reference](api-reference.md)

---

## The problem in one sentence

Today every caller shares one pool of capacity, and the gateway does not know
who is calling or which plan they are on.

That one gap shows up in two very different places:

- **Reliability.** If one partner's app starts calling far too often, it can
  use up the capacity meant for everyone. Nobody can say what that app's
  limit should have been, because there was no limit.
- **Pricing.** If your Enterprise plan promises more capacity than Free, but
  nothing checks that, then a Free customer can use exactly as much as your
  best-paying one. The difference between the plans exists only on paper.

There are smaller costs too. You size your servers for a guess instead of a
known total. Support cannot tell a customer what their limit is. Finding out
which partner caused a spike means searching through logs. And you cannot
bill anyone for the load they create.

## What this solution changes

A quota is attached to **the product you sell**, and it is counted **per
app**. Each app gets its own budget. When an app uses up its budget, the
gateway answers its requests with HTTP 429 ("too many requests") until the
budget resets. Every other app keeps working.

| | Without product quota | With this solution |
|---|---|---|
| **One app misbehaves** | Everyone is affected | Only that app is affected |
| **What "Enterprise" means** | A line in a contract | A real, enforced difference |
| **How you size capacity** | Guess the worst case | Add up what you have sold |
| **Who caused the spike?** | An IP address in a log | The app name, on every request |
| **Billing by usage** | Not possible | Request counts per app |

## Why this is different from a simple rate limit

A plain rate limit protects your backend by rejecting requests once the total
gets too high. It does not care who is calling. So when one partner has a
bug, everyone gets some rejections, and the partner who caused it is not
the only one who suffers.

A product quota does the opposite. The app that caused the problem runs out
of its own budget and gets 429s. Nobody else notices.

## Two things worth knowing before you rely on it

**Capacity planning gets simpler, with one check.** Once every app has a
limit, you can plan for the sum of what you have sold instead of the worst
thing any caller might do. Add up your plan tiers and make sure that total is
below what your backend can handle. If you have sold more than you can serve,
the quota turns an outage into 429s. That is better, but it is still worth
knowing.

**A limit is also a sales signal.** An app that keeps hitting its Free limit
is a customer who needs more. The quota turns "you are at your limit" into
an upgrade conversation with real numbers behind it. [Solution 04](../04-analytics/)
shows how to find those apps.

How to choose the numbers for each tier: [Architecture](architecture.md#tier-design-that-works).
What this solution does not cover: [Configuration reference](configuration-reference.md).

## What you get

- **Uptime no longer depends on your least careful partner.** A problem
  becomes one app getting 429s, which you can act on.
- **Plans become worth paying for**, because the difference between them is
  enforced.
- **Capacity is planned from commitments**, not guesses.
- **Upgrade conversations come with data.**
- **Finding the cause of a spike takes seconds**, not hours.
- **Usage-based billing becomes possible**, and so does a marketplace, because
  the product is the thing a partner subscribes to.

## How you know it is working

- One app that is deliberately calling too often gets 429s, and **every other
  app keeps working**. The example script [`example/verify.sh`](example/verify.sh)
  checks this in case 5. Case 4 only shows that a limit exists. Case 5 shows the
  limit stays with the app that broke it, which is the point.
- Support can state a customer's limit, and it matches what the gateway
  enforces.
- Capacity is planned from the sum of committed quotas, checked against what
  your backend can handle.
- "Which app caused the spike?" can be answered in seconds.
- If the gateway runs on more than one node, you have **confirmed** that
  `quota_policy` is set to `redis`, not assumed it. See [Guides](guides.md).
