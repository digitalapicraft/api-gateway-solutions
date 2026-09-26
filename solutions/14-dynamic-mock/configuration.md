# Configuration — Solution 14 — A sandbox that answers every partner with that partner's own values

[Overview](readme.md) · [Business need](business-need.md) · [How it works](how-it-works.md) · [Install](install.md) · **Configuration** · [Test & verify](testing.md) · [Changelog](changelog.md)

---

## Why `alias` is load-bearing

The fetch key here is **dynamic** — `tier:$request.headers.x-partner-id`. Without
an alias, the value would publish under a field named after whatever the caller
sent (`tier:acme-42`), and no static template could name it.

`alias` **renames the published field** to a name you choose:

```yaml
key-value-map:
  fetch:
    keys:
      - key: "tier:$request.headers.x-partner-id"
        alias: tier          # -> $ctx.helix.key_value_map.tier
```

That single line is what turns "a store" into "a per-caller store". It is the
difference between this solution and a slightly fancier static mock.

## Drop the diagnostics route before production

The diagnostics route exists to make the substitution grammar visible while you
are learning it: it prints the namespace and what is currently stored in it.
That is exactly the information you do not want reachable in production, since
it exposes both the grammar and the contents of the store.

It is a teaching aid. Remove it from the spec before you deploy for real.
