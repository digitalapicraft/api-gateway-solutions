# API reference — read what your gateway already captured

> [Overview](README.md) · [Business need](business-need.md) · [Architecture](architecture.md) · [Guides](guides.md) · [Agent prompt](helix-agent-prompt.md) · [Tests](tests.md) · **API reference**

---

The raw calls behind [Call the metrics API directly](guides.md#call-the-metrics-api-directly)
and [`scripts/query-analytics.sh`](scripts/query-analytics.sh), listed for lookup
rather than as a walkthrough. Every call only reads. The full request body for each
everyday question is in the [query catalogue](charts.md); the wider product
documentation is at [docs.digitalapi.ai/api-gateway](https://docs.digitalapi.ai/api-gateway).

All calls are `POST /api/orgs/{orgId}/analytics/metrics/{metric}` with
`Authorization: Bearer <control-plane token>` and `content-type: application/json`.
Send them to your control-plane **API** address — the one the portal calls,
usually beginning with `api-` — not the portal page you log in to. The token lasts
about 1 hour.

The portal uses a second form of the same endpoint:
`POST /api/orgs/{orgId}/analytics/metrics` with the metric in the body, for example
`"metricType":"REQUESTS_COUNT"`. Either form works.

Times can be short forms (`24h`, `7d`, `now`) or UTC (`2026-01-01T00:00:00Z`).
Filter on short internal names such as `posts-api`, not the name shown in the
portal.

| Question | `{metric}` | Body (beyond `startTime`, `endTime`) | Notes |
|---|---|---|---|
| Requests by API | `requests-count` | `"dimensions":["api_name"]`, `"excludeTimeUnit":true`, sort `value` `DESC` | Swap `api_name` for `app_name` or `product_name` to see it by app or product. Rows without identity come back with an empty value — "unattributed". |
| Requests for one API, by app | `requests-count` | add `"filters":[{"column":"api_name","operator":"EQ","value":["<short name>"]}]`, `"dimensions":["app_name"]` | A filter applies to any view. Filter on `product_name` or `app_name` the same way. `LIKE` needs `%` wildcards: `"%post%"`. |
| Slowest / fastest APIs | `response-time` | `"dimensions":["api_name"]`, `"aggregation":"AVG"`, sort `value` `DESC` (or `ASC` for fastest) | Use `"aggregation":"MAX"` for worst case. Average response time is in milliseconds. Filter `response_status_code` `LT` `["400"]`: blocked calls count as 0–4 ms. |
| Backend time | `upstream-response-time` | as above | Your backend's time on its own. Don't subtract it from `response-time`: the two are averaged over different calls, so the backend average can be higher. |
| Errors by API and status | `requests-count` | `"dimensions":["api_name","response_status_code"]` | Work out the error rate yourself: errors ÷ total per API. Keep 4xx and 5xx apart. |
| Only server errors / only throttled calls | `requests-count` | filter `response_status_code` `IN` `["500","502","503","504"]` or `["429"]` | 429 is a caller over its usage limit. |
| Traffic over time | `requests-count` | `"timeUnit":"HOURS"` (no `excludeTimeUnit`) | Returns one `{timeBucket, value}` per bucket. Add `dimensions` to split the series by API, app or status. |
| Data transferred | `total-transfer-size` | `"dimensions":["api_name"]`, `"aggregation":"SUM"` | Each row's `value` is empty. The sizes are inside `dimensions` as `request_size` and `response_size`; add them for the total. `request-size` / `response-size` on their own return the usual `value`. |
| Request rate (QPS — requests per second) | `requests-per-second` | no extra fields needed | Always returns a series with one value per minute: the requests in that minute ÷ 60. Takes no aggregation. Small traffic shows decimals. |

The response is `{ value, timeRange, groupedResults[], meta }`, each row
`{ dimensions:{…}, value }` or, for a series, `{ timeBucket, dimensions:{…}, value }`.

**Read the top-level `value` with care.**
- For an average grouped by a dimension, it is the average of the group averages,
  not of all calls (in one test, 310 ms against a real average of about 214 ms).
  Don't use it as the overall average.
- With `pageRequest`, it covers only the rows on that page.

**Mistakes that fail silently.** A misspelt field name is ignored, and an
`aggregation` sent with a count (`requests-count`, `requests-per-second`) is
accepted. Both change the result with no error. More detail in the
[query catalogue](charts.md#mistakes-the-api-wont-tell-you-about).

What the API cannot do — percentiles, quota usage, single-request lookup, bodies,
wrong-path calls — is on
[Architecture](architecture.md#what-analytics-can-and-cant-tell-you).
