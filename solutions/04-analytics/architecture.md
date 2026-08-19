# Architecture — how analytics is captured, and how you read it

This solution adds nothing to your APIs. Analytics is a platform capability that
records every request as it passes through the gateway; your job is only to query
what's already there. So the "architecture" here is two things: where the data
comes from, and the shape of the read API.

---

## Where the data comes from

```
        every request through any API
                    │
        ┌───────────▼───────────────┐
        │  Gateway (log phase)       │   captured automatically —
        │  records one row per call: │   no plugin, no config on your API
        │   api_name, route_id,      │
        │   app_name, developer,     │
        │   product_name, status,    │
        │   response_time, sizes …   │
        └───────────┬───────────────┘
                    ▼
        ┌───────────────────────────┐        ┌───────── you ──────────┐
        │   analytics store          │◄──────►│  metrics API  /  portal │
        │   (platform-managed)       │  read  │  (read-only queries)    │
        └───────────────────────────┘        └─────────────────────────┘
```

Capture happens in the **log phase**, after the request is served, so it never
affects latency or behaviour — and it happens whether or not you ever look. There
is no "turn on analytics" step and no `helix-analytics` block to add to a spec.

## The read API

One endpoint, one request shape:

```
POST /api/orgs/{orgId}/analytics/metrics/{metric}
{ startTime, endTime, dimensions[], filters[], aggregation, timeUnit, pageRequest }
```

- **metric** (path): `requests-count`, `requests-per-second`, `response-time`,
  `request-size`, `response-size`, `total-transfer-size`, `upstream-response-time`.
  The size/time metrics take an `aggregation` of `AVG`/`MIN`/`MAX`/`SUM`; counts
  and rates take none.
- **dimensions**: group by any of `env_name`, `app_id`, `app_name`, `product_name`,
  `api_name`, `route_id`, `route_name`, `api_path`, `request_method`,
  `response_status_code`, `upstream_path`, `developer`.
- **filters**: `{column, operator, value[]}` with `EQ NEQ GT GTE LT LTE IN LIKE
  NOT_LIKE`, AND-combined — e.g. one API, or only 5xx statuses.
- **pageRequest.sort** on `value` gives you top-N (busiest / slowest); `timeUnit`
  (`SECONDS`/`MINUTES`/`HOURS`/`DAYS`) turns a total into a time series.

The full request bodies for the everyday questions are in
[`charts.md`](charts.md); [`scripts/query-analytics.sh`](scripts/query-analytics.sh)
runs the headline set.

## Two things about attribution

You configure nothing for analytics, but two properties of how an API is *already*
built decide how useful its rows are:

- **Identity → attribution.** An API that resolves the caller (`helix-auth`)
  produces rows carrying `app_name` / `developer` / `product_name`. An anonymous API
  attributes to a source-address bucket ("unattributed"). Adding identity is
  [solution 01](../01-oauth-jwt/) / [solution 03](../03-api-products/) — a decision
  about the API, not about analytics.
- **Templating → one row per route.** Group by `route_id` and a templated route
  (`/orders/{id}`) is one row; group by `api_path` and it fragments into one row per
  concrete id.

## Native vs custom

There is nothing to build. You do not run a telemetry pipeline, add a logger, or
write code. Where custom tooling *would* be justified — and is out of scope here —
is anything the metrics API deliberately doesn't do:

- **Percentiles** (p95/p99): the API gives `AVG`/`MIN`/`MAX` only. True percentiles
  need a tracing/metrics pipeline (Prometheus/OpenTelemetry).
- **Per-request tracing** across your internal hops: analytics is edge-measured;
  `upstream-response-time` isolates the backend's share but not the hops within it.
- **Long-term warehousing** beyond the platform's retention window: export the data.

## When to use this

Use it when you want to see request volume, latency, or errors across your APIs,
products, or apps — for triage, capacity planning, or a quick "who's calling what"
— and you want it now, read-only, with nothing to install.

Don't reach for it when you need **percentile latency**, **per-request traces**, or
**alerting on thresholds** — those are a tracing/metrics/alerting stack, fed by
different data. The metrics API answers aggregate questions, not those.
