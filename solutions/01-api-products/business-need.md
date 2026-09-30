# Business need — API Products with enforced quota

[Overview](README.md) · **Business need** · [Architecture](architecture.md) ·
[Guides](guides.md) · [Examples](examples.md) · [Agent prompt](helix-agent-prompt.md) ·
[Tests](tests.md) · [Configuration reference](configuration-reference.md) ·
[API reference](api-reference.md)

---

## Why this matters

Two problems that seem unrelated actually come from the same gap: **every
caller shares one pool, and the gateway doesn't know who's calling or what
they paid for.**

- **It causes outages.** One partner's misbehaving app can use up capacity
  meant for everyone else, and nobody can say what its limit should have been
  until after it's already down.
- **It makes your pricing dishonest.** If "Enterprise" is supposed to get more
  capacity but nothing actually checks that, a Free customer can use exactly
  as much as your best-paying one.

The quieter costs add up too: you provision for a guess instead of a
commitment, support can't tell a customer their real limit, "which partner
caused this?" is a log hunt at 3am, and you can't bill anyone for the load
they actually generate.

## What changes

The quota attaches to **the thing you sell** — a product — and is counted
per app:

| Dimension | Without product quota | With this solution |
|---|---|---|
| **Blast radius of a bad integration** | 100% of your customers | Just the one app |
| **What "Enterprise" means** | A line in a contract | A real, enforced difference |
| **Capacity planning basis** | A guess at the worst case | The sum of what you've sold |
| **Attribution** | An IP address in a log | Every request tied to an app |
| **Chargeback** | Not possible | Per-app request counts |

## The two things that actually change

**The blast radius gets bounded, and stays with whoever caused it.** Not "we
survive the spike" — the offending app runs out of its own budget while every
other caller keeps working. A global rate limit doesn't do this: it protects
the backend by rejecting whoever happens to be calling, so one partner's bug
still becomes everyone's bad day, just a smaller one.

**Capacity planning changes what it's measured against.** Without a
per-caller bound, you provision for what a caller *might* do. With one, you
provision for the sum of what you *sold* — but only if that sum is actually
below what your upstream can handle. Add the tiers up and check that before
you rely on the saving; if you've oversold, the quota turns that into 429s
instead of an outage, which is better, but still worth knowing.

That second point is usually what gets this funded: **a quota turns a
contract line into a real product feature, and a ceiling into an upgrade
conversation.** An app that keeps hitting its Free limit is a qualified lead
with a number attached. See [solution 04](../04-analytics/) for the queries
that surface that.

How to actually size your tiers: [Architecture](architecture.md#tier-design-that-works).
What this doesn't solve, in detail: [Configuration reference](configuration-reference.md).

## The payoff

- **Availability stops depending on your worst-behaved partner.** An outage
  becomes one partner getting 429s — an action item you can actually close.
- **Tiers become sellable**, because the difference between them is real.
- **Capacity is planned from commitments**, not guesses.
- **Upgrade conversations get real data** instead of a hunch.
- **Incident attribution drops from hours to seconds.**
- **Chargeback becomes possible**, and a marketplace becomes reachable — the
  product is the thing a partner subscribes to.

## Done looks like

- A deliberately misbehaving app gets 429s while **every other app keeps
  working** — verified by [`example/verify.sh`](example/verify.sh) case 5,
  not case 4. Proving a limit exists is easy; proving it stays with the
  offender is the point.
- Support can state a customer's limit, and it matches what's enforced.
- Capacity is planned from the sum of committed quotas, checked against what
  your upstream can take.
- "Which app caused the spike?" is answerable in seconds.
- If the gateway runs more than one node, you've **confirmed** `quota_policy`
  is `redis` rather than assumed it.
