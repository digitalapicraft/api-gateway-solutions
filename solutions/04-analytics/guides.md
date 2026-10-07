# Guides — read what your gateway already captured

> [Overview](README.md) · [Business need](business-need.md) · [Architecture](architecture.md) · **Guides** · [Agent prompt](helix-agent-prompt.md) · [Tests](tests.md) · [API reference](api-reference.md)

---

Three ways to read the same data, then what to do when an answer looks wrong.
There is nothing to build: analytics is already recording every request, and
everything on this page only reads. Nothing is added to your APIs and nothing is
changed.

## Pick your path

| | Choose this if you… | Go to |
|---|---|---|
| **1. Helix Agent** | want an answer and a chart without writing a query | [Ask the Helix Agent](#ask-the-helix-agent) |
| **2. Command line** | want the headline views printed in a terminal | [Run the script](#run-the-script) |
| **3. Metrics API** | are building your own report, dashboard or pipeline | [Call the metrics API directly](#call-the-metrics-api-directly) |

Then, for everyone: [Variations](#variations) ·
[Configuration reference](#configuration-reference) · [Troubleshooting](#troubleshooting)

There is no click-through walkthrough here: nothing needs creating or deploying, so
there are no screens to go through.

## Ask the Helix Agent

The quickest path, with no queries to write. Ask in plain English and the agent
pulls the numbers and **draws a chart in the chat** — it calls its `get_metrics`
tool for you. Every question in
[`helix-agent-prompt.md`](helix-agent-prompt.md) works on its own; paste any one.
Start here:

```text
Show me requests to all my APIs in the last hour, broken down by API and sorted
busiest first.
```

### Keep the ask inside what analytics supports

The agent maps your words onto the metrics API, so a question it can't answer
comes back empty or quietly approximated rather than as an error:

| Ask for… | Not… | Because |
|---|---|---|
| **average / min / max** response time | p95 / p99 / percentiles | The metric supports AVG, MIN, MAX and SUM only. `MAX` is the worst-case signal. |
| a **count of 429s** | "percent of quota used" | There is no quota-usage metric; you can count rejections, not remaining headroom. |
| an **aggregate slice** (by API, app, status, time) | "show me *that one* request" | Looking up a single request means matching its `X-Request-Id` in your own logs. |
| grouping by **`route_id`** | expecting one row per URL | A templated route is one row under `route_id`; `api_path` gives one row per concrete id. |

[AGENT-GUIDE.md](../../AGENT-GUIDE.md) has the general pattern.

## Run the script

Prefer a terminal? [`scripts/query-analytics.sh`](scripts/query-analytics.sh)
prints the headline views for the last hour — the same metrics API, no agent.

**Before you start: get a token.** The analytics API uses a control-plane bearer
token, the same one the portal uses. Get it from the portal (your browser's
developer tools → any request's `Authorization` header), or from your own sign-in
flow. The script needs `curl` and `python3`.

```bash
CP=https://<YOUR_CONTROL_PLANE_HOST> \
ORG=<YOUR_ORG_ID> \
TOKEN=<control-plane bearer token> \
./scripts/query-analytics.sh
```

It prints six views: requests by API, by app, by product and by status code, then
the slowest and the fastest APIs by average response time. See the
[Overview](README.md#example) for sample output.

Filter every view to one API with `API_NAME=<name>`, widen the window with
`WINDOW_HOURS=24`, or change how many rows each view shows with `TOP` (default 20).

## Call the metrics API directly

Every query is one `POST` with the same token:

```bash
curl -s -X POST "https://<YOUR_CONTROL_PLANE_HOST>/api/orgs/<YOUR_ORG_ID>/analytics/metrics/requests-count" \
  -H "authorization: Bearer <control-plane bearer token>" \
  -H 'content-type: application/json' \
  -d '{"startTime":"<now-1h>","endTime":"<now>",
       "dimensions":["api_name"],"excludeTimeUnit":true,
       "pageRequest":{"page":1,"size":20,"sort":{"field":"value","order":"DESC"}}}'
```

That returns one row per API, busiest first. Times are UTC, written like
`2026-01-01T00:00:00Z`. The response is
`{ value, timeRange, groupedResults[], meta }`, with each row
`{ dimensions:{…}, value }` — or `{ timeBucket, value }` for a series over time.

The exact request for every everyday question — by app or product, slowest and
fastest, errors by status, traffic over time, data transferred — is in the
[query catalogue](charts.md). Each call in one table:
[API reference](api-reference.md).

## Variations

**Follow-ups in the same agent session.** Each one refines the previous answer
rather than starting again:

```text
Filter that to just the {{api_name}} and re-draw it.
```
```text
Same chart, but for the last 7 days by day instead of the last hour.
```
```text
Now show average and max response time side by side for those APIs.
```
```text
Which apps sent the most requests to that API this week?
```

**Narrow any query to one API, product or app.** Add a filter — it works on every
view:

```json
{ "startTime":"<now-1h>", "endTime":"<now>",
  "filters":[{ "column":"api_name", "operator":"EQ", "value":["my-api"] }],
  "dimensions":["app_name"], "excludeTimeUnit":true }
```

**Only server errors, or only throttled calls.** Filter `response_status_code` with
`IN` and `["500","502","503","504"]`, or `["429"]` to see who is hitting a usage
limit.

**A series over time instead of a total.** Drop `excludeTimeUnit` and set
`timeUnit` to `SECONDS`, `MINUTES`, `HOURS` or `DAYS`.

## Configuration reference

There is no gateway configuration: nothing is added to any API. What you can set is
how you read.

**The script** — set as environment variables:

| Setting | Required | Default | What it does |
|---|---|---|---|
| `CP` | yes | — | The control-plane base URL, e.g. `https://<YOUR_CONTROL_PLANE_HOST>` |
| `ORG` | yes | — | Your org id |
| `TOKEN` | yes | — | A control-plane bearer token |
| `WINDOW_HOURS` | no | `1` | How far back to look, in hours |
| `API_NAME` | no | — | If set, every view is filtered to this one API |
| `TOP` | no | `20` | Maximum rows per view |

**A query** — the body of `POST /api/orgs/{orgId}/analytics/metrics/{metric}`:

| Field | What it does |
|---|---|
| `startTime`, `endTime` | The window, in UTC (`2026-01-01T00:00:00Z`) |
| `dimensions` | What to group by — e.g. `api_name`, `app_name`, `product_name`, `response_status_code` |
| `filters` | `{column, operator, value[]}` entries, all combined with AND |
| `aggregation` | `AVG`, `MIN`, `MAX` or `SUM` — time and size metrics only |
| `excludeTimeUnit` | `true` for one total per group; leave it out and set `timeUnit` for a series |
| `timeUnit` | `SECONDS`, `MINUTES`, `HOURS` or `DAYS` |
| `pageRequest` | `page`, `size`, and `sort: {field: "value", order: "ASC" or "DESC"}` for a top-N list |

The full list of metrics and dimensions is on
[Architecture](architecture.md#the-read-api). Placeholders on this page:
`<YOUR_CONTROL_PLANE_HOST>`, `<YOUR_ORG_ID>`. Replace them, and never commit a
token.

## Troubleshooting

- **A breakdown comes back "unattributed".** That API doesn't identify its callers,
  so analytics has no app or developer to put on the rows. It is a property of the
  API, not of the query — see
  [Architecture](architecture.md#two-things-about-attribution).
- **An empty result.** Either there was no traffic in the window, or you've asked
  for further back than the data is kept. Widen the range and ask again.
- **The script prints `(no data in the window)` for every view.** It prints that
  for any answer that carries no rows — including an error from the API. Check
  there was traffic in the window, and that your token hasn't expired.
- **You asked for a percentile and got an average.** Analytics has no percentiles.
  Ask for `max` as the worst-case signal instead, or use a tracing stack.
- **You can't find one particular request.** `X-Request-Id` isn't something
  analytics can group or filter by. Narrow analytics to the right slice, then find
  the id in your own logs.
- **A route shows up as dozens of rows.** You grouped by `api_path`, which gives
  one row per concrete id. Group by `route_id` instead.
- **You want "% of quota used".** There is no such metric. Count the 429s instead;
  remaining headroom lives with the product's settings.
