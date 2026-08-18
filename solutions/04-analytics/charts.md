# The analytics catalogue — what you can ask, and how

Analytics is already capturing every request. This file is the part that matters:
**which questions the analytics API can actually answer, the exact query for each,
and — just as important — the ones it cannot.**

> **How you query analytics: the metrics API, or the portal.** You do **not** ask
> analytics in natural language, and the agent does not run analytics queries — it
> builds APIs, it doesn't read charts. Analytics is a structured API (and the portal
> UI over it). Everything below is a real request against that API.

---

## The building blocks

Every query is one POST:

```
POST /api/orgs/{orgId}/analytics/metrics/{metric}
Authorization: Bearer <token>
content-type: application/json

{
  "startTime": "2026-01-01T00:00:00Z",
  "endTime":   "2026-01-02T00:00:00Z",
  "dimensions": ["route_id"],            // group by these (0..n)
  "filters":    [                        // AND-combined
    { "column": "api_name", "operator": "EQ", "value": ["orders-api"] }
  ],
  "aggregation": "AVG",                  // size/time metrics only (see below)
  "timeUnit": "HOURS",                   // bucket over time; omit + excludeTimeUnit:true for a single total
  "excludeTimeUnit": true,
  "pageRequest": { "page": 1, "size": 100 }
}
```

The response is `{ value, timeRange, groupedResults[], meta }`, where each
`groupedResults` row is either `{ dimensions:{…}, value }` (grouped) or
`{ timeBucket, value }` (time series).

**Metrics** (the `{metric}` path segment):

| Metric (path) | What it is | Aggregation |
|---|---|---|
| `requests-count` | number of requests | none (it's a count) |
| `requests-per-second` | request rate | none |
| `response-time` | latency, ms | `AVG` · `MIN` · `MAX` · `SUM` |
| `upstream-response-time` | time spent in the upstream, ms | `AVG` · `MIN` · `MAX` · `SUM` |
| `request-size` / `response-size` / `total-transfer-size` | bytes | `AVG` · `MIN` · `MAX` · `SUM` |

**Dimensions** (group or filter by any): `env_name`, `app_id`, `app_name`,
`product_name`, `api_name`, `route_id`, `route_name`, `api_path`, `request_method`,
`response_status_code`, `upstream_path`, `developer`.

**Filter operators**: `EQ` `NEQ` `GT` `GTE` `LT` `LTE` `IN` `LIKE` `NOT_LIKE`
(multiple filters are AND-combined).

Two rules carry most of the value:

- **Group route-level charts by `route_id`, not `api_path`.** `route_id` collapses a
  templated route (`/orders/{orderId}`) to one row; `api_path` gives one row per
  concrete path — a "top routes" chart that is really a list of individual records.
- **Attribution needs identity.** `app_name` / `developer` / `product_name` are only
  populated when the route resolved identity (add `helix-auth`,
  [solution 01](../01-oauth-jwt/)). Without it those dimensions are empty and traffic
  groups by IP-level fields only.

---

## What analytics CANNOT do — read this before promising a chart

These are real limits of the metrics API, confirmed against the platform. Don't build
a report around them:

- **No percentiles.** `response-time` supports `AVG`, `MIN`, `MAX`, `SUM` only —
  there is **no p50/p95/p99**. Use `MAX` as a coarse tail signal and `AVG` for the
  body; if you truly need percentiles, that's a separate telemetry pipeline
  (e.g. Prometheus/OpenTelemetry), not this API.
- **No quota-consumption metric.** There is no "percent of quota used" or "remaining
  quota" metric. You can *count 429s* (`requests-count` filtered on
  `response_status_code = 429`), but "apps at 80% of their limit" is **not**
  answerable here — that lives in the products/subscription side, not analytics.
- **No per-request lookup.** `X-Request-Id` is **not** a dimension. Narrow analytics
  to a slice, then match the id in **your own logs** — analytics gives you the
  aggregate, your logs give you the instance.
- **No request/response bodies.** Analytics sees metadata (who, which route, status,
  latency, size), never payloads — by design.
- **Latency is edge-measured.** `response-time` is the gateway's view;
  `upstream-response-time` isolates the backend's share, but neither breaks down your
  internal hops.

---

## Recipes that work on this minimal API

Group by route/status/method — no identity required.

### 1. Traffic over time

```json
POST /api/orgs/{orgId}/analytics/metrics/requests-count
{ "startTime":"…","endTime":"…",
  "filters":[{"column":"api_name","operator":"EQ","value":["orders-api"]}],
  "timeUnit":"HOURS" }
```

Returns one `{timeBucket, value}` per hour. **For:** capacity planning (peak vs
median) and spotting anomalies. Run it again grouped by `response_status_code` to see
whether errors rise *with* traffic (capacity) or *without* it (a deploy/dependency).

### 2. Requests and errors by route and status

```json
POST /api/orgs/{orgId}/analytics/metrics/requests-count
{ "startTime":"…","endTime":"…",
  "filters":[{"column":"api_name","operator":"EQ","value":["orders-api"]}],
  "dimensions":["route_id","response_status_code"],
  "excludeTimeUnit":true }
```

Counts per route × status. Compute the error rate client-side (errors ÷ total per
route). **Keep 4xx and 5xx separate** — 5xx is your problem, 4xx is usually the
caller's or your docs'. Filter to a class with
`{"column":"response_status_code","operator":"IN","value":["500","502","503","504"]}`.
**What breaks it:** grouping by `api_path` instead of `route_id` (one row per id).

### 3. Latency by route (AVG / MAX — not percentiles)

```json
POST /api/orgs/{orgId}/analytics/metrics/response-time
{ "startTime":"…","endTime":"…",
  "filters":[{"column":"api_name","operator":"EQ","value":["orders-api"]}],
  "dimensions":["route_id"], "aggregation":"MAX", "excludeTimeUnit":true }
```

Run once with `AVG` (typical) and once with `MAX` (worst case). A route whose `MAX`
dwarfs its `AVG` has a tail problem — something is occasionally slow. **This is the
percentile substitute; the API has no p95.** Query `upstream-response-time` the same
way to see how much of the latency is your backend versus the edge.

### 4. Data transfer

```json
POST /api/orgs/{orgId}/analytics/metrics/total-transfer-size
{ "startTime":"…","endTime":"…",
  "dimensions":["route_id"], "aggregation":"SUM", "excludeTimeUnit":true }
```

Bytes moved, by route. **For:** finding the endpoints driving egress cost;
`request-size` / `response-size` split it by direction.

### 5. Slow-route drift (two windows)

Run recipe 3 (`response-time`, `AVG`, by `route_id`) for this week and last week and
compare. **For:** catching a route that is 20% slower than it was, while it's still
cheap to investigate. (Client-side comparison — the API returns one window at a time.)

---

## Recipes that need identity (compose in [solution 01](../01-oauth-jwt/))

Add `helix-auth` to the routes and `app_name` / `developer` populate; then:

### 6. Traffic by app

```json
POST /api/orgs/{orgId}/analytics/metrics/requests-count
{ "startTime":"…","endTime":"…",
  "filters":[{"column":"api_name","operator":"EQ","value":["orders-api"]}],
  "dimensions":["app_name"], "excludeTimeUnit":true }
```

Your baseline: who is calling, and how much. Without identity every row is an IP.

### 7. Who is failing auth

`requests-count`, `dimensions:["app_name"]`,
`filters:[…,{"column":"response_status_code","operator":"EQ","value":["401"]}]`.
An app failing *every* call is broken config (often the wrong credential); an app
failing *some* is intermittent (expired tokens). Worth running proactively.

### 8. Who is being throttled (needs [solution 03](../03-api-products/) too)

Same shape, filter `response_status_code = 429`, group by `app_name`. This is the
*only* quota-related view analytics offers — a **count of rejections**, not
consumption. "How close is an app to its limit?" is not answerable here.

### 9. New and disappeared callers (two windows)

`requests-count`, `dimensions:["app_name"]`, for this week and last week; diff the app
lists client-side. An app that **stopped** calling is the signal nobody watches —
churn, a broken integration, or an expired credential.

---

## Not answerable from analytics (don't promise these)

- **"Apps above 80% of quota" / "under-utilised committed accounts."** No quota
  metric — see § *What analytics cannot do*. Approximate abuse with the 429 count
  (recipe 8); for true consumption, use the products/subscription side.
- **"p95/p99 latency."** No percentiles. `MAX` is the closest signal.
- **"Show me that one request."** Not a query — a log-side join on `X-Request-Id`.

---

## Building a dashboard

The portal renders these. A screen people actually read is about five panels:

| Panel | Recipe |
|---|---|
| Traffic per hour, error count overlaid | 1 |
| Requests/errors by route, 4xx vs 5xx | 2 |
| Latency by route, `AVG` and `MAX` | 3 |
| Top routes (or apps, with identity) by volume | 2 / 6 |
| Data transfer by route | 4 |

Everything else in this catalogue is a question you run **when something looks
wrong** — investigative, not a permanent panel. And the honest habit: when a chart
moves, write down what you did about it. A chart with no history of action can be
deleted.
