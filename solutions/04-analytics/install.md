# Install — Solution 04 — Analytics: read what your gateway already captured

[Overview](readme.md) · [Business need](business-need.md) · [How it works](how-it-works.md) · **Install** · [Query catalogue](charts.md) · [Changelog](changelog.md)

---

## Read it with the Helix Agent

Recommended path — no queries to hand-write. Ask the agent in plain English and it
pulls the numbers and **renders a chart in the chat** (it calls its `get_metrics`
tool for you; read-only, nothing added to your APIs). Full set of prompts:
[`helix-agent-prompt.md`](helix-agent-prompt.md).

```text
Show me requests to all my APIs in the last hour, broken down by API and sorted
busiest first.
```

More of the everyday questions, each a plain-English prompt:

```text
Show me requests in the last hour grouped by app.
Which of my APIs were slowest in the last hour, by average response time?
Show me requests in the last 24 hours grouped by API and status code (4xx vs 5xx).
Plot total requests per hour for the last 24 hours.
```

Keep asks inside what analytics supports — **average/max, not percentiles**; a
**count of 429s**, not "% of quota used"; an aggregate slice, not a single-request
lookup. See [`helix-agent-prompt.md`](helix-agent-prompt.md) for why, and
[AGENT-GUIDE.md](../../AGENT-GUIDE.md) for the general pattern.

## Run it from the CLI

Prefer a script? [`scripts/query-analytics.sh`](scripts/query-analytics.sh) prints the
headline views for the last hour — same metrics API, no agent:

```bash
CP=https://<YOUR_CONTROL_PLANE_HOST> \
ORG=<YOUR_ORG_ID> \
TOKEN=<control-plane bearer token> \
./scripts/query-analytics.sh
```

Sample output (last hour):

```
Requests by API
  orders-api                                 17
  checkout-api                                9
  partners-api                                9

Requests by app
  (unattributed)                             18
  partner-b-prod                              9
  partner-c-batch                             8

Slowest APIs (AVG response time, ms)
  reporting-api                             812.0
  orders-api                                41.0
  checkout-api                              28.0

Requests by status code
  200                                        30
  429                                         4
  401                                         1
```

Filter to one API with `API_NAME=<name>`, or widen the window with
`WINDOW_HOURS=24`. The full catalogue — every metric, dimension, filter, and the
exact request bodies — is in [`charts.md`](charts.md).

## Getting a token

The analytics API uses a control-plane bearer token, the same one the portal uses.
Get it from the portal (browser DevTools → any request's `Authorization` header),
or from your own login flow. Everything here only **reads** — it changes nothing.

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
resolve identity ([solution 02](../02-oauth-jwt/) / [solution 01](../01-api-products/));
anonymous traffic shows up unattributed.

## Follow-ups in the same session

1. `Filter that to just the checkout API and re-draw it.`
2. `Same chart, but for the last 7 days by day instead of the last hour.`
3. `Now show average and max response time side by side for those APIs.`
4. `Which apps sent the most requests to that API this week?`

## When it goes wrong

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
