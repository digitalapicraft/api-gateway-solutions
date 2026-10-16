# API rate limiting and tiered quotas with API Products

> [Overview](README.md) · **Business need** · [Architecture](architecture.md) · [Guides](guides.md) · [Agent prompt](helix-agent-prompt.md) · [Tests](tests.md) · [API reference](api-reference.md)

---

> One partner's retry loop sends 40,000 requests a minute at an endpoint sized for
> 3,000, and everyone else gets 503s. Meanwhile the "Enterprise" tier you sell is
> a contract line with nothing enforcing it.
>
> **Both are the same bug: one undifferentiated pool, and no idea who is calling.**

- **A problem stays with the one app that caused it.** The quota attaches to the thing you
  sell and is counted per app, so a bad integration throttles itself.
- **"Enterprise" becomes a real difference**, which makes hitting the ceiling the
  thing that triggers an upgrade.
- **Capacity planned against committed quotas**, not the worst caller's
  hypothetical peak — and every request attributable for chargeback.

Picking the numbers is commercial, not technical, and only two rules generalise:

| Tier | The rule |
|---|---|
| Free | must be unusable for production — if you can build on it, nobody upgrades |
| Production | about 2× a healthy integration's p95, measured rather than guessed |
| Enterprise | matches a contract; never derive it by scaling the tier below |

The window matters as much as the limit: per-minute absorbs bursts, per-second
shapes them, and per-day lets one app spend the whole budget in forty seconds and
then go dark. [The full argument, and what this does not buy you, are in the
README](README.md).

*Also searched as: API rate limiting · tiered API pricing · per-consumer quota ·
API monetization tiers · throttle API by customer · freemium API plan · API
product catalog.*
