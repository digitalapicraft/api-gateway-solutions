# Keep the catalogue public and the changes private

> [Overview](README.md) · **Business need** · [Architecture](architecture.md) · [Guides](guides.md) · [Agent prompt](helix-agent-prompt.md) · [Tests](tests.md) · [API reference](api-reference.md)

---

> Your catalogue API is how comparison sites, search engines and partners find
> your products. The same API has a route that adds products, and nothing stops
> a stranger who finds it from using it.
>
> **The fix has to close that route without putting a hurdle in front of anyone
> who only reads.**

- **Reads stay free of friction.** Crawlers and comparison sites keep working
  with no key, no sign-up and no change on their side.
- **Writes are partner-only.** A change with no key, or with a key that
  belongs to no app, is refused at the gateway. Your backend never sees it.
- **Every change has a name on it.** Each partner gets its own key, so you know
  who changed what, and you can switch one partner off without touching the
  others.

The one decision is where the key check goes:

| Put the key check on… | Reads | Writes |
|---|---|---|
| The whole API | Refused without a key: the catalogue drops out of search | Partners only |
| **The three write routes** (this solution) | **Open to everyone** | **Partners only** |
| Nothing | Open | Open to anyone who finds them |

No figures here are measured; they are the reasoning behind the design. How
the check works, and what it does not cover, is in the
[architecture page](architecture.md).

*Also searched as: public GET protected POST · API key for write endpoints only ·
read-only public API · protect POST PUT DELETE · per-route authentication ·
anonymous read access API gateway · secure write endpoints · open API with
partner-only updates.*
