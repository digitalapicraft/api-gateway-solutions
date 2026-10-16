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

| Question | `{metric}` | Body (beyond `startTime`, `endTime`) | Notes |
|---|---|---|---|
| Requests by API | `requests-count` | `"dimensions":["api_name"]`, `"excludeTimeUnit":true`, sort `value` `DESC` | Swap `api_name` for `app_name` or `product_name` to see it by app or product. Rows without identity come back with an empty value — "unattributed". |
| Requests for one API, by app | `requests-count` | add `"filters":[{"column":"api_name","operator":"EQ","value":["<name>"]}]`, `"dimensions":["app_name"]` | A filter applies to any view. Filter on `product_name` or `app_name` the same way. |
| Slowest / fastest APIs | `response-time` | `"dimensions":["api_name"]`, `"aggregation":"AVG"`, sort `value` `DESC` (or `ASC` for fastest) | Use `"aggregation":"MAX"` for worst case. Average response time is in milliseconds. |
| How much of the time is the backend | `upstream-response-time` | as above | Separates your backend's share from the gateway's. |
| Errors by API and status | `requests-count` | `"dimensions":["api_name","response_status_code"]` | Work out the error rate yourself: errors ÷ total per API. Keep 4xx and 5xx apart. |
| Only server errors / only throttled calls | `requests-count` | filter `response_status_code` `IN` `["500","502","503","504"]` or `["429"]` | 429 is a caller over its usage limit. |
| Traffic over time | `requests-count` | `"timeUnit":"HOURS"` (no `excludeTimeUnit`) | Returns one `{timeBucket, value}` per bucket. |
| Data transferred | `total-transfer-size` | `"dimensions":["api_name"]`, `"aggregation":"SUM"` | `request-size` / `response-size` split it by direction. |
| Request rate | `requests-per-second` | as for a count | A rate; takes no aggregation. |

The response is `{ value, timeRange, groupedResults[], meta }`, each row
`{ dimensions:{…}, value }` or, for a series, `{ timeBucket, value }`.

What the API cannot do — percentiles, quota usage, single-request lookup, bodies —
is on [Architecture](architecture.md#what-analytics-can-and-cant-tell-you).
