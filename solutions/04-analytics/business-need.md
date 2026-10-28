# API analytics and traffic attribution from the gateway you already run

> [Overview](README.md) · **Business need** · [Architecture](architecture.md) · [Guides](guides.md) · [Agent prompt](helix-agent-prompt.md) · [Tests](tests.md) · [API reference](api-reference.md)

---

> *"At 3am something hammered one of our APIs. On-call spent forty minutes working
> out which integration it was. We could see a spike; we couldn't see whose."*
>
> **The data was already there. The gap was knowing how to ask.**

- **Finding the caller behind an incident: a log search → one query.** Name the
  API, app, developer or status code behind a spike while it is still happening.
- **New systems to run: none.** No separate monitoring, logging or data-warehouse
  stack for the everyday questions — the gateway has recorded every request since
  it went in.
- **Risk of breaking something: none.** You add no plugin and no logger, and you
  change no API. The queries only read.

The whole solution is knowing what the metrics API will answer, because asking for
the wrong thing returns an empty or approximate result rather than an error:

| Ask for | Not | Because |
|---|---|---|
| average / min / **max** response time | p95 / p99 | AVG, MIN, MAX and SUM only. `MAX` is your worst-case signal; percentiles need a tracing stack. |
| a **count of 429s** | "percent of quota used" | There is no quota-usage metric. You can count rejections, not remaining headroom. |
| an **aggregate slice** | "show me *that one* request" | Looking up a single request means matching its `X-Request-Id` in your own logs. |
| grouping by **`route_id`** | grouping by `api_path` | Otherwise a route like `/orders/{id}` splits into one row per id. |

Per-app, per-developer and per-product rows only carry names for APIs that
**identify their callers**; anonymous traffic lands as unattributed. That is a
property of the API — [solution 02](../02-oauth-jwt/) or
[solution 01](../01-api-products/) — not of analytics. [What it can and cannot
tell you, including how far back it goes, is on the Architecture
page](architecture.md#what-analytics-can-and-cant-tell-you).

*Also searched as: API analytics · API traffic monitoring · API usage metrics ·
per-consumer API reporting · API gateway observability · API error rate reporting ·
which app is calling my API.*
