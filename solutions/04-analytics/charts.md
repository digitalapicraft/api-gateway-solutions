# Analytics query catalogue — read what your gateway already captured

> [Overview](README.md) · [Business need](business-need.md) · [Architecture](architecture.md) · [Guides](guides.md) · [Agent prompt](helix-agent-prompt.md) · [Tests](tests.md) · **API reference**

---

Part of the [API reference](api-reference.md): the full request for each everyday
question. Analytics is captured for **every** request through **every** API,
automatically — you add nothing to your APIs. This page is the practical part: the
queries that answer the common questions, each one a real request against the
analytics metrics API, plus what the API can and cannot do.

> **Three ways to read analytics: ask the agent, run the script, or POST the API.**
> The agent understands plain-English asks, calls this same metrics API for you and
> answers with a table ([agent prompt](helix-agent-prompt.md)); the runnable
> [`scripts/query-analytics.sh`](scripts/query-analytics.sh) prints the headline
> views; and everything below is the raw API.

---

## The query shape

Every query is one POST:

```
POST /api/orgs/{orgId}/analytics/metrics/{metric}
Authorization: Bearer <control-plane token>
content-type: application/json

{
  "startTime": "1h",                         // or "24h", "7d", or a UTC time
  "endTime":   "now",                        //   such as "2026-01-01T00:00:00Z"
  "dimensions": ["api_name"],                // group by these
  "filters":    [                            // optional, AND-combined
    { "column": "api_name", "operator": "EQ", "value": ["posts-api"] }
  ],
  "aggregation": "AVG",                       // size/time metrics only (see below)
  "excludeTimeUnit": true,                    // one total per group; omit + set
                                              // timeUnit for a time series
  "pageRequest": { "page": 1, "size": 20,
                   "sort": { "field": "value", "order": "DESC" } }  // top-N
}
```

**Times.** Short forms work: `24h` or `7d` for the start, `now` for the end. Or
give UTC times written like `2026-01-01T00:00:00Z`.

**Names.** Filter on the short internal name (`posts-api`), not the name shown in
the portal ("Posts API"). The portal name matches nothing.

**Response:** `{ value, timeRange, groupedResults[], meta }`. Each `groupedResults`
row is `{ dimensions:{…}, value }`. For a series over time it is
`{ timeBucket, dimensions:{…}, value }`: a series can also be split by a
dimension, so each time slot has one row per group.

**A second form of the same endpoint.** The portal itself calls
`POST /api/orgs/{orgId}/analytics/metrics` (no metric in the path) and puts the
metric in the body instead, for example `"metricType":"REQUESTS_COUNT"`. The rest
of the body is the same. Use whichever suits you.

**Metrics** (the `{metric}` path segment):

| Metric (path) | What it is | Aggregation |
|---|---|---|
| `requests-count` | number of requests | none (it's a count) |
| `requests-per-second` | request rate (QPS — requests per second) | none |
| `response-time` | latency, ms | `AVG` · `MIN` · `MAX` · `SUM` |
| `upstream-response-time` | time spent in the upstream, ms | `AVG` · `MIN` · `MAX` · `SUM` |
| `request-size` / `response-size` / `total-transfer-size` | bytes | `AVG` · `MIN` · `MAX` · `SUM` |

**Dimensions** (group or filter by any): `env_name`, `env_id`, `api_name`,
`api_id`, `app_id`, `app_name`, `product_name`, `product_id`, `developer`,
`route_id`, `route_name`, `api_path`, `request_method`, `response_status_code`,
`client_ip`, and fields for AI traffic: the model, the provider, token counts,
cost and currency.
`upstream_path` is accepted but not filled in yet, and `client_ip` currently holds
the same internal address on every row — see
[Architecture](architecture.md#the-read-api).

**Filter operators**: `EQ` `NEQ` `GT` `GTE` `LT` `LTE` `IN` `LIKE` `NOT_LIKE`
(multiple filters AND together). `LIKE` needs `%` wildcards: `"%post%"` matches
any value containing `post`; `"post"` alone matches only the exact value.

### Read the overall `value` with care

The top-level `value` is a single figure for the whole answer. Two cautions:

- **For an average, it is wrong.** When you group an average (such as
  `response-time` with `AVG`) by a dimension, `value` is the average of the group
  averages, not the average of all calls. In one test it read 310 ms when the real
  average was about 214 ms. Don't use it as the overall average. To work out the
  real one, weight each group's average by its request count (from
  `requests-count` with the same dimensions).
- **With paging, it covers only that page.** If you send `pageRequest`, `value` is
  worked out from the rows on that page only, not from every row.

### Mistakes the API won't tell you about

The API accepts some mistakes silently and returns a different answer:

- **A misspelt field name** (for example `dimension` instead of `dimensions`) is
  ignored, so the query runs without it.
- **An `aggregation` on a count** (`requests-count`, `requests-per-second`) is
  accepted and changes the result.

Check your spelling against this page, and leave `aggregation` out for counts and
rates.

---

## The everyday questions

### Requests in the last hour — by API

```json
POST /api/orgs/{orgId}/analytics/metrics/requests-count
{ "startTime":"1h", "endTime":"now",
  "dimensions":["api_name"], "excludeTimeUnit":true,
  "pageRequest":{ "page":1, "size":20, "sort":{ "field":"value", "order":"DESC" } } }
```

One row per API, busiest first. Swap `api_name` for **`app_name`** to see it by app,
or **`product_name`** to see it by product. Rows with no identity (unauthenticated
traffic) come back with an empty value — the "unattributed" bucket.

### Requests in the last hour — for one specific API / product / app

Add a filter and it applies to any view:

```json
{ "startTime":"1h", "endTime":"now",
  "filters":[{ "column":"api_name", "operator":"EQ", "value":["posts-api"] }],
  "dimensions":["app_name"], "excludeTimeUnit":true }
```

("Who called *posts-api* in the last hour.") Filter on `product_name` or `app_name`
the same way, using short names such as `free-app`.

### Slowest / fastest performing API

```json
POST /api/orgs/{orgId}/analytics/metrics/response-time
{ "startTime":"1h", "endTime":"now",
  "filters":[{ "column":"response_status_code", "operator":"LT", "value":["400"] }],
  "dimensions":["api_name"], "aggregation":"AVG", "excludeTimeUnit":true,
  "pageRequest":{ "page":1, "size":20, "sort":{ "field":"value", "order":"DESC" } } }
```

Slowest APIs first (average response time, ms). Flip `order` to `ASC` for fastest.
Run it again with `"aggregation":"MAX"` to see worst-case latency.

The filter keeps only calls below 400. Calls the gateway blocks (401, 429 and
similar) are counted at 0–4 ms, so leaving them in makes an API look faster than
it is.

To see your backend's time on its own, query `upstream-response-time` the same
way. Don't subtract it from `response-time` to get the gateway's share: the two
averages are taken over different sets of calls (blocked calls have no backend
time), so the backend average can even be the higher of the two.

### Error rate — by API and status

```json
POST /api/orgs/{orgId}/analytics/metrics/requests-count
{ "startTime":"1h", "endTime":"now",
  "dimensions":["api_name","response_status_code"], "excludeTimeUnit":true }
```

Counts per API × status; compute the rate client-side (errors ÷ total per API).
Keep 4xx and 5xx separate — 5xx is your problem, 4xx is usually the caller's. Add
`{"column":"response_status_code","operator":"IN","value":["500","502","503","504"]}`
to see only server errors, or `["429"]` to see who is being throttled.

### Traffic over time

```json
POST /api/orgs/{orgId}/analytics/metrics/requests-count
{ "startTime":"24h", "endTime":"now", "timeUnit":"HOURS" }
```

Returns one `{timeBucket, value}` per hour (drop `excludeTimeUnit`, set `timeUnit`
to `SECONDS`/`MINUTES`/`HOURS`/`DAYS`). Add `"dimensions":["api_name"]` to split
the series by API: each hour then has one row per API, with the API in
`dimensions`. Overlay the error count (same query, filter status ≥ 400) to tell a
capacity problem (errors rise *with* traffic) from a deploy/dependency one (errors
rise *without* it).

### Requests per second

```json
POST /api/orgs/{orgId}/analytics/metrics/requests-per-second
{ "startTime":"1h", "endTime":"now" }
```

This always returns a series with one value per minute, whatever `timeUnit` or
`excludeTimeUnit` you send. Each value is the requests in that minute divided by
60, so small traffic shows decimals such as 0.02. For small numbers,
`requests-count` is easier to read.

### Data transferred

```json
POST /api/orgs/{orgId}/analytics/metrics/total-transfer-size
{ "startTime":"24h", "endTime":"now",
  "dimensions":["api_name"], "aggregation":"SUM", "excludeTimeUnit":true }
```

Bytes moved, by API — the endpoints driving egress cost. The sizes are **not** in
each row's `value`, which comes back empty. They sit inside `dimensions`, as
`request_size` and `response_size`:

```json
{ "dimensions": { "api_name": "posts-api",
                  "request_size": 1520, "response_size": 284310 },
  "value": null }
```

(The numbers are an illustration.) Add the two together for the total per API.
`request-size` and `response-size` on their own return the usual `value`.

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
- **No wrong-path calls.** A call that matches no route (`404 Route Not Found`) is
  never recorded.

## What makes attribution work

You add nothing to your APIs for analytics — but two properties of how an API is
*already* built decide how useful its rows are:

- **Per-app / per-developer / per-product breakdowns need identity resolved on the
  API.** If an API authenticates callers (`helix-auth`), its rows carry
  `app_name` / `developer` / `product_name`; if it's anonymous, that traffic is the
  "unattributed" bucket. (Adding auth is [solution 02](../02-oauth-jwt/) /
  [solution 01](../01-api-products/) — not something you do for analytics.)
- **Group route-level views by `route_id`, not `api_path`.** `route_id` collapses a
  templated route (`/orders/{id}`) to one row; `api_path` gives one row per concrete
  id.

## Getting a token

The analytics API uses a control-plane bearer token — the same session token the
portal uses, and it lasts about 1 hour. Grab one from the portal (browser
DevTools → any request's `Authorization` header). Send your queries to the
control-plane **API** address the portal calls (usually beginning with `api-`),
not the portal page you log in to. Then run
[`scripts/query-analytics.sh`](scripts/query-analytics.sh), or POST the queries
above yourself.
