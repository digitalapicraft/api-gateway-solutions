# Solution 04 — Analytics: read what your gateway already captured

**Every request through every API is captured automatically. You add nothing to
your APIs. This is how you pull the answers — requests in the last hour by API,
product, or app; your slowest and fastest APIs; error rates — out of the analytics
API.**

| | |
|---|---|
| **Setup time** | ~5 minutes (nothing to deploy) |
| **Difficulty** | 🟢 Beginner |
| **Needs** | APIs that already receive traffic · a control-plane bearer token (the portal uses the same one) |
| **Changes to your APIs** | **None.** Analytics is global; there is no plugin or config to add. |
| **Run it** | 🤖 [ask the agent](helix-agent-prompt.md) — it charts it for you · 📊 [`scripts/query-analytics.sh`](scripts/query-analytics.sh) — CLI · 📖 [`charts.md`](charts.md) — raw queries |
| **Assets** | ✅ [Agent prompt](helix-agent-prompt.md) · ✅ [Query catalogue](charts.md) · ✅ [Query script](scripts/query-analytics.sh) · ✅ [Architecture](architecture.md) · ✅ [Business need](business-need.md) · ✅ [Infographic](infographic.md) · ✅ [Validation](validation/) · ✅ [Manifest](solution.yaml) |

---

## The point

You don't turn analytics on — it's **already recording every request**. You just
read it, three ways: **ask the agent in plain English** and it pulls the numbers and
draws a chart ([agent prompt](helix-agent-prompt.md)); run
[`scripts/query-analytics.sh`](scripts/query-analytics.sh) from the CLI; or POST the
[metrics-API queries](charts.md) yourself. Nothing is built or configured on your
APIs, and it's all read-only. Verified against a live gateway.

## The questions it answers

All for a chosen window (the last hour by default):

- **How many requests did each API get?** — and each **product**, and each **app**.
- **Which of my APIs is slowest / fastest?** — by average response time.
- **Where are the errors?** — counts by API and status code (4xx vs 5xx), who got 429s.
- **What's the traffic shape over time?** — per-hour (or per-minute/day) buckets.
- **What's driving data transfer / egress?** — bytes by API.

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

## What analytics can and can't tell you

**Can:** requests, response time, sizes, and rates — grouped and filtered by
`api_name`, `product_name`, `app_name`, `developer`, `route_id`, `route_name`,
`api_path`, `request_method`, `response_status_code`, `env_name`, `upstream_path`.

**Can't** (don't build a report on these):

- **No percentiles** — average / min / max only. `MAX` is your tail signal.
- **No quota-usage metric** — you can count 429s, not "% of a limit used."
- **No per-request lookup** — `X-Request-Id` isn't a dimension; match a single
  request in your own logs.
- **No request/response bodies** — metadata only, by design.

## What makes the numbers useful

You add nothing for analytics, but two things about how an API is *already* built
shape its rows:

- **Per-app / per-developer / per-product breakdowns need the API to resolve
  identity.** An API that authenticates callers attributes rows to an app; an
  anonymous one lands in the "unattributed" bucket. (That's how the API is built —
  see [solution 01](../01-oauth-jwt/) / [solution 03](../03-api-products/) — not
  something you do for analytics.)
- **Group route-level views by `route_id`, not `api_path`** — `route_id` collapses
  a templated route to one row; `api_path` gives one row per concrete id.

## Validation status

**Validated against a live gateway.** Every query in [`charts.md`](charts.md) and
[`scripts/query-analytics.sh`](scripts/query-analytics.sh) was run against the real
analytics API and returned the expected shapes — requests by API/app/product,
slowest/fastest by response time, and errors by status. See
[`validation/`](validation/). Point the script at your own org and token to see
your data.

## Related solutions

- **[01 — OAuth 2.0 with JWT](../01-oauth-jwt/)** — resolve identity on an API so
  its analytics attributes per app instead of landing in the unattributed bucket.
- **[03 — API Products](../03-api-products/)** — per-product rows and the 429
  counts come from having products with quotas.
