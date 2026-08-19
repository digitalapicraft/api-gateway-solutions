# Agent-mode prompt — read your analytics by asking

You don't have to hand-write metrics queries. **Ask the agent in plain English and
it pulls the numbers and renders a chart in the chat** — it calls the analytics
metrics tool for you (`get_analytics_metadata` to learn your org's real
metric/dimension names, then `get_metrics`). Nothing is added to your APIs; this is
read-only.

The prompts below stay inside what the analytics API actually supports. Read
[AGENT-GUIDE.md](../../AGENT-GUIDE.md) if you haven't; the catalogue with the raw
request bodies is [`charts.md`](charts.md).

---

## The everyday prompts

Paste any of these. "Last hour" = a `1h` range; widen it to `24h`, `7d`, etc.

**Requests in the last hour, by API**
```text
Show me requests to all my APIs in the last hour, broken down by API and sorted
busiest first.
```

**By app, or by product**
```text
Show me requests in the last hour grouped by app.
```
```text
Show me requests in the last hour grouped by product.
```

**For one specific API**
```text
For the API <<orders-api>>, show me requests in the last hour broken down by app.
```

**Slowest / fastest performing API**
```text
Which of my APIs were slowest in the last hour? Rank them by average response time,
slowest first.
```
```text
Which APIs were fastest by average response time in the last hour?
```

**Errors, and who's being throttled**
```text
Show me requests in the last 24 hours grouped by API and status code, so I can see
4xx and 5xx per API.
```
```text
Show me 429 responses in the last hour grouped by app.
```

**Traffic over time**
```text
Plot total requests across all my APIs per hour for the last 24 hours.
```

**Data transfer**
```text
Show me total bytes transferred by API over the last 24 hours.
```

---

## Keep the ask inside what analytics supports

The agent maps your words to the metrics API, so phrase requests for things it can
actually return — otherwise you'll get an empty or approximated answer:

| Ask for… | Not… | Because |
|---|---|---|
| **average / max** response time | p95 / p99 / percentiles | The metric supports AVG/MIN/MAX/SUM only — no percentiles. |
| a **count of 429s** | "percent of quota used" | There is no quota-usage metric; you can only count rejections. |
| an **aggregate slice** (by API/app/status/time) | "show me *that one* request" | Single-request lookup is a log-side join on `X-Request-Id`, not an analytics query. |
| grouping by **route** | expecting one row per URL | Group by `route_id` (a templated route is one row), not `api_path`. |

Per-app / per-developer / per-product breakdowns only carry names for APIs that
resolve identity ([solution 01](../01-oauth-jwt/) / [solution 03](../03-api-products/));
anonymous traffic shows up unattributed.

## Follow-ups in the same session

1. `Filter that to just the checkout API and re-draw it.`
2. `Same chart, but for the last 7 days by day instead of the last hour.`
3. `Now show average and max response time side by side for those APIs.`
4. `Which apps sent the most requests to that API this week?`

## Known failure modes

- **You ask for p95/p99.** The agent can only return AVG/MIN/MAX. Ask for max as the
  tail signal, or use a tracing/metrics stack for true percentiles.
- **You ask "how close is app X to its quota".** Not available — ask for its 429
  count instead.
- **A breakdown comes back "unattributed".** That API doesn't resolve identity, so
  analytics has no app/developer to attribute to — that's a property of the API, not
  the query.
- **An empty result.** No traffic in the window, or you're outside the retention
  period — widen the range.

## Prefer the script or raw API?

[`scripts/query-analytics.sh`](scripts/query-analytics.sh) prints the headline views
from the CLI, and [`charts.md`](charts.md) has the exact request bodies if you want
to call the metrics API directly. Same data, three ways in.
