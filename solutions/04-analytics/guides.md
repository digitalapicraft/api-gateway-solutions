# Guides — read what your gateway already captured

> [Overview](README.md) · [Business need](business-need.md) · [Architecture](architecture.md) · **Guides** · [Agent prompt](helix-agent-prompt.md) · [Tests](tests.md) · [API reference](api-reference.md)

---

Four ways to read the same data, then what to do when an answer looks wrong.
There is nothing to build: analytics is already recording every request, and
everything on this page only reads. Nothing is added to your APIs and nothing is
changed.

## Pick your path

| | Choose this if you… | Go to |
|---|---|---|
| **1. Helix Agent** | want an answer and a chart without writing a query | [Ask the Helix Agent](#ask-the-helix-agent) |
| **2. Helix control plane** | prefer clicking through screens, or want charts your team can keep and share | [Read it in the UI](#read-it-in-the-ui) |
| **3. Command line** | want the headline views printed in a terminal | [Run the script](#run-the-script) |
| **4. Metrics API** | are building your own report, dashboard or pipeline | [Call the metrics API directly](#call-the-metrics-api-directly) |

Then, for everyone: [Variations](#variations) ·
[Configuration reference](#configuration-reference) · [Troubleshooting](#troubleshooting)

## Ask the Helix Agent

The quickest path, with no queries to write. Ask in plain English and the agent
pulls the numbers and **draws a chart in the chat**.
[`helix-agent-prompt.md`](helix-agent-prompt.md) has a set of questions — each one
works on its own, so paste any one.

See [AGENT-GUIDE.md](../../AGENT-GUIDE.md) for the ground rules these prompts
assume.

## Read it in the UI

Analytics has two screens in the left sidebar, under **Analytics**:

- **Widgets** — one chart or one number, built from a single question such as
  "requests per API".
- **Reports** — a page that puts several widgets together, with filters and a
  time range for the whole page.

You build widgets first, then add them to a report. Nothing on these screens
changes your APIs. To look at single requests instead of totals, use a trace
(step 3).

**1. Build a widget: requests by API**
1. Go to **Analytics → Widgets** and click **Create widget**. A preview on the
   right updates as you go.
2. **Overview** tab: set **Widget Name** (for example *Requests by API*), and
   under **What kind of widget?** pick **Chart / Graph**. Pick **Single Number
   (KPI)** instead when you want one big number, such as total requests today.
3. **Metric Config** tab:
   - **What data to show?** — pick **Requests Count**.
   - **How to calculate it?** — shown only when there's a choice, such as a
     total or an average.
   - **Group data by** — pick **Time (show trends)** to see how it changes, or a
     category such as **Api Name** to compare APIs side by side.
   - **Chart style** — for example **Area Chart** for a trend, or **Bar Chart**
     to compare.
4. **Grouping & Filters** tab *(optional)*:
   - **Grouping** splits the chart into one line or bar per item. With
     **Grouping Mode** set to **Auto**, pick a **Grouping Dimension**, such as
     **Api Name**.
   - **Filters** narrows what's counted. Click **Add filter**, pick a
     **Dimension**, then pick a value or type one and choose **Use "…"**.
5. Click **Next** until the button reads **Save Widget**, then save. The widget
   opens with a time bar (**1h**, **24h**, **7d**, **14d**, **30d** or
   **Custom**) and a **View By** choice to regroup it on the spot.

The same steps answer the other everyday questions:

| Question | What data to show? | Group data by | Filter |
|---|---|---|---|
| How has traffic changed this week? | Requests Count | Time (show trends) | — (pick **7d** on the time bar) |
| Which APIs are slowest? | Response Time (average or P99) | Api Name | — |
| Which APIs fail most? | Requests Count | Api Name | status code, `500` and up |
| Who is being turned away for going over their limit? | Requests Count | Api Name, or the app or consumer if offered | status code `429` |
| How much data is moving? | Total Transfer Size | Time (show trends) | — |

The names in **Group data by** and **Dimension** come from your gateway, so the
exact list can vary. To split by status family (2xx, 4xx, 5xx), set **Grouping
Mode** to **Manual**, add one group per family with **Match Type** **Prefix
(starts with)** and a value such as `4`.

Widgets marked **Predefined** come with the platform. Open one and click
**Clone** to make your own copy you can change.

**2. Put widgets together in a report**
1. Go to **Analytics → Reports** and click **Create report**.
2. **Report** tab: give it a **Title** and a **Description**. Under **Report
   Filters**, click **Add filter** to set one for every widget on the page:
   **Always Applied** locks a value (for example one environment), and **User
   Selectable** lets whoever views the report pick a value.
3. **Widgets** tab: click **Add widget** and pick from the widgets you've built.
   Use **Layout** to arrange them, or set each widget's width and height.
4. Click **Create Custom Report**. A report needs at least one widget.

A report opens on the last **14d**. Change it with the time bar, and use the
filters at the top if you added any.

**3. Look at single requests with a trace**

When a widget shows something odd, a trace shows what happened to the requests
behind it.
1. Go to **API Gateway → APIs**, open the API, then the **Observability** tab.
2. Click **Start trace session**. Pick the **Environment**, and under **How long
   should we capture?** pick a length, from **Quick check** (1 minute) to **Long
   capture** (1 hour). Then **Start tracing**.
3. Send some traffic, then open the session with **View traces**. Each request is
   listed with its method, path, status and time taken. Filter by status family
   or by how slow it was.
4. Click a request. **Request chain** shows each plugin that ran and what it
   changed; **Inspector** shows the headers and body of the request and the
   response.

On a busy API, use **Advanced: filter which requests to capture** to record only
the requests you care about, for example status `429`. You can also reach all
trace sessions from **Observability → Traces** in the sidebar.

**Calls by app.** If **Group data by** doesn't list the app or consumer in your
org, ask the Helix Agent or use the script below; both group by app.

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
