# Analytics query catalogue — read what your gateway already captured

Analytics is captured for **every** request through **every** API, automatically —
you add nothing to your APIs. This file is the practical part: the queries that
answer the common questions, each one a real request against the analytics metrics
API, plus what the API can and cannot do.

> **How you read analytics: the metrics API, or the portal.** It is a structured
> API, not a natural-language prompt — the agent builds APIs, it does not read
> charts. The runnable [`scripts/query-analytics.sh`](scripts/query-analytics.sh)
> prints the headline views for the last hour; everything below is the same API it
> calls. All queries here were run against a live gateway.

---

## The query shape

Every query is one POST:

```
POST /api/orgs/{orgId}/analytics/metrics/{metric}
Authorization: Bearer <control-plane token>
content-type: application/json

{
  "startTime": "2026-01-01T00:00:00Z",
  "endTime":   "2026-01-01T01:00:00Z",       // last hour = now-1h .. now
  "dimensions": ["api_name"],                // group by these
  "filters":    [                            // optional, AND-combined
    { "column": "api_name", "operator": "EQ", "value": ["my-api"] }
  ],
  "aggregation": "AVG",                       // size/time metrics only (see below)
  "excludeTimeUnit": true,                    // one total per group; omit + set
                                              // timeUnit for a time series
  "pageRequest": { "page": 1, "size": 20,
                   "sort": { "field": "value", "order": "DESC" } }  // top-N
}
```

Response: `{ value, timeRange, groupedResults[], meta }`, each `groupedResults`
row `{ dimensions:{…}, value }` (or `{ timeBucket, value }` for a time series).

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
(multiple filters AND together).

---

## The everyday questions

### Requests in the last hour — by API

```json
POST /api/orgs/{orgId}/analytics/metrics/requests-count
{ "startTime":"<now-1h>", "endTime":"<now>",
  "dimensions":["api_name"], "excludeTimeUnit":true,
  "pageRequest":{ "page":1, "size":20, "sort":{ "field":"value", "order":"DESC" } } }
```

One row per API, busiest first. Swap `api_name` for **`app_name`** to see it by app,
or **`product_name`** to see it by product. Rows with no identity (unauthenticated
traffic) come back with an empty value — the "unattributed" bucket.

### Requests in the last hour — for one specific API / product / app

Add a filter and it applies to any view:

```json
{ "startTime":"<now-1h>", "endTime":"<now>",
  "filters":[{ "column":"api_name", "operator":"EQ", "value":["my-api"] }],
  "dimensions":["app_name"], "excludeTimeUnit":true }
```

("Who called *my-api* in the last hour.") Filter on `product_name` or `app_name`
the same way.

### Slowest / fastest performing API

```json
POST /api/orgs/{orgId}/analytics/metrics/response-time
{ "startTime":"<now-1h>", "endTime":"<now>",
  "dimensions":["api_name"], "aggregation":"AVG", "excludeTimeUnit":true,
  "pageRequest":{ "page":1, "size":20, "sort":{ "field":"value", "order":"DESC" } } }
```

Slowest APIs first (average response time, ms). Flip `order` to `ASC` for fastest.
Run it again with `"aggregation":"MAX"` to see worst-case latency, and query
`upstream-response-time` to see how much of it is your backend versus the edge.

### Error rate — by API and status

```json
POST /api/orgs/{orgId}/analytics/metrics/requests-count
{ "startTime":"<now-1h>", "endTime":"<now>",
  "dimensions":["api_name","response_status_code"], "excludeTimeUnit":true }
```

Counts per API × status; compute the rate client-side (errors ÷ total per API).
Keep 4xx and 5xx separate — 5xx is your problem, 4xx is usually the caller's. Add
`{"column":"response_status_code","operator":"IN","value":["500","502","503","504"]}`
to see only server errors, or `["429"]` to see who is being throttled.

### Traffic over time

```json
POST /api/orgs/{orgId}/analytics/metrics/requests-count
{ "startTime":"<now-24h>", "endTime":"<now>", "timeUnit":"HOURS" }
```

Returns one `{timeBucket, value}` per hour (drop `excludeTimeUnit`, set `timeUnit`
to `SECONDS`/`MINUTES`/`HOURS`/`DAYS`). Overlay the error count (same query, filter
status ≥ 400) to tell a capacity problem (errors rise *with* traffic) from a
deploy/dependency one (errors rise *without* it).

### Data transferred

```json
POST /api/orgs/{orgId}/analytics/metrics/total-transfer-size
{ "startTime":"<now-24h>", "endTime":"<now>",
  "dimensions":["api_name"], "aggregation":"SUM", "excludeTimeUnit":true }
```

Bytes moved, by API — the endpoints driving egress cost. `request-size` /
`response-size` split it by direction.

---

## What analytics CANNOT do — don't build a report on these

- **No percentiles.** `response-time` supports `AVG`/`MIN`/`MAX`/`SUM` only — no
  p50/p95/p99. `MAX` well above `AVG` is your tail signal.
- **No quota-usage metric.** You can count 429s (`requests-count` filtered on
  `response_status_code = 429`), but "app X is at 80% of its limit" is not
  available here — that lives on the products/subscription side.
- **No per-request lookup.** `X-Request-Id` is not a dimension. Narrow analytics to
  a slice, then match the id in **your own logs**.
- **No request/response bodies.** Analytics sees metadata (who, which route,
  status, latency, size), never payloads — by design.

## What makes attribution work

You add nothing to your APIs for analytics — but two properties of how an API is
*already* built decide how useful its rows are:

- **Per-app / per-developer / per-product breakdowns need identity resolved on the
  API.** If an API authenticates callers (`helix-auth`), its rows carry
  `app_name` / `developer` / `product_name`; if it's anonymous, that traffic is the
  "unattributed" bucket. (Adding auth is [solution 01](../01-oauth-jwt/) /
  [solution 03](../03-api-products/) — not something you do for analytics.)
- **Group route-level views by `route_id`, not `api_path`.** `route_id` collapses a
  templated route (`/orders/{id}`) to one row; `api_path` gives one row per concrete
  id.

## Getting a token

The analytics API uses a control-plane bearer token — the same session token the
portal uses. Grab one from the portal (browser DevTools → any request's
`Authorization` header), then run
[`scripts/query-analytics.sh`](scripts/query-analytics.sh), or POST the queries
above yourself.
