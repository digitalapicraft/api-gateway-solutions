# Retire an old API version without surprising anyone

> [Overview](README.md) · **Business need** · [Architecture](architecture.md) · [Guides](guides.md) · [Agent prompt](helix-agent-prompt.md) · [Tests](tests.md) · [API reference](api-reference.md)

---

> v2 has been live for six months. v1 still gets calls from partners nobody can
> reach. Last month one v1 endpoint was removed, and the partners using it saw a
> 404, assumed an outage, and opened priority tickets.
>
> **The change was planned. The answer callers got didn't say so.**

- **Callers' code learns the dates.** Before: the retirement lives in an email.
  After: every v1 response carries `Deprecation`, `Sunset` and a link to its
  v2 replacement, in standard headers that tools can read.
- **A retired endpoint explains itself.** Before: a 404, which looks like an
  outage. After: HTTP 410 (gone) with the replacement address, so nobody files
  an outage ticket for a planned change.
- **No backend work.** Before: retiring an endpoint meant a code release. After:
  each stage is a gateway revision, deployed and rolled back in minutes.

| Answer | Use it for |
|---|---|
| Headers on a working v1 | the months between announcing and switching off |
| 410 Gone + successor | an endpoint that is retired |
| 404 | an address that never existed, never a retirement |

The headers inform; they don't force anyone to move. The dates are yours to
set. [The four stages, and why 410 beats a redirect, are in the
architecture page](architecture.md).

*Also searched as: API deprecation header · Sunset header · API versioning
strategy · retire old API version · 410 Gone vs 404 · deprecate API endpoint ·
API version sunset policy · successor-version link.*
