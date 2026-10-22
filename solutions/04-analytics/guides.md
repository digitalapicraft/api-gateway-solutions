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
| **1. Helix Agent** | want an answer without writing a query | [Ask the Helix Agent](#ask-the-helix-agent) |
| **2. Helix control plane** | prefer clicking through screens, or want charts your team can keep and share | [Read it in the UI](#read-it-in-the-ui) |
| **3. Command line** | want the headline views printed in a terminal | [Run the script](#run-the-script) |
| **4. Metrics API** | are building your own report, dashboard or pipeline | [Call the metrics API directly](#call-the-metrics-api-directly) |

Then, for everyone: [Variations](#variations) ·
[Configuration reference](#configuration-reference) · [Troubleshooting](#troubleshooting)

## Names: use the short name, not the one on screen

Analytics stores each API and app under its **short internal name**: lower case,
with hyphens instead of spaces. An API shown in the portal as "Posts API" is
stored as `posts-api`. An app shown as "Free App" is stored as `free-app`.

Use the short name whenever you filter or ask for one API or app. Filtering by
the name shown in the portal returns nothing, with no error.

## Ask the Helix Agent

The quickest path, with no queries to write. Ask in plain English and the agent
pulls the numbers and **answers with a table** in the chat.
[`helix-agent-prompt.md`](helix-agent-prompt.md) has a set of questions — each one
works on its own, so paste any one.

**Tip:** if the agent stops after "Reading analytics fields" without an answer,
type `continue`.

When the agent reports an overall average across several APIs, don't rely on it.
See [Before you trust a number](#before-you-trust-a-number).

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
   - **How to calculate it?** — shown only when there's a choice. The choices
     are **Avg**, **Min**, **Max** and **Sum**.
   - **Group data by** — pick **Time (show trends)** to see how it changes, or a
     category such as **Api Name** to compare APIs side by side.
   - **Chart style** — for example **Area Chart** for a trend, or **Bar Chart**
     to compare.
4. **Grouping & Filters** tab *(optional)*:
   - **Grouping** splits the chart into one line or bar per item. With
     **Grouping Mode** set to **Auto**, pick a **Grouping Dimension**, such as
     **Api Name**.
   - **Filters** narrows what's counted. Click **Add filter** and pick a
     **Dimension**. Each filter has two more settings:
     - **Fixed** or **Dynamic**. **Fixed** always applies the value you set.
       **Dynamic** lets whoever views the report pick the value.
     - The **operator**, which decides how the value is compared: **EQ** (equal
       to), **GTE** (greater than or equal to), **IN** (any of a list), **LIKE**
       (contains a pattern), and more. It starts on **EQ**.

     Then pick a value, or type one and choose **Use "…"**.
5. Click **Next** until the button reads **Save Widget**, then save. The widget
   opens with a time bar (**1h**, **24h**, **7d**, **14d**, **30d** or
   **Custom**) and a **View By** choice to regroup it on the spot.

The same steps answer the other everyday questions:

| Question | What data to show? | Group data by | Filter |
|---|---|---|---|
| How has traffic changed this week? | Requests Count | Time (show trends) | — (pick **7d** on the time bar) |
| Which APIs are slowest? | Response Time | Api Name | status code, operator **LT**, `400` — so blocked calls don't pull the average down |
| Which APIs fail most? | Requests Count | Api Name | status code, operator **GTE**, `500` |
| Who is being turned away for going over their limit? | Requests Count | Api Name, or App Name | status code, operator **EQ**, `429` |
| How much data is moving? | Total Transfer Size | Time (show trends) | — |

For **Which APIs fail most?**, change the operator to **GTE** before you type
`500`. The operator starts on **EQ**, so typing `500` alone counts only 500s and
misses 502, 503 and 504.

The names in **Group data by** and **Dimension** come from your gateway, so the
exact list can vary.

**Split by status family (2xx, 4xx, 5xx).** On the **Grouping & Filters** tab:
1. Set **Grouping Mode** to **Manual**.
2. Set **Group Dimension** to **Response Status Code**. Do this first: the groups
   are matched against this dimension.
3. Click **Add Group** once per family. Set **Match Type** to **Prefix (starts
   with)** and the value to the first digit, such as `4`.

**Built-in widgets.** Widgets marked **Predefined** come with the platform. Open
one and click **Clone** to make your own copy you can change.

If you are a super admin, two extra things apply:
- You also see **Edit** and **Delete** on built-in widgets. These change the
  widget for every organisation. Use **Clone** instead.
- When you create a widget or report you see a **Predefined widget** (or
  **Predefined report**) switch. Turning it on publishes that widget or report to
  every organisation. Leave it off unless that is what you want.

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
3. You are taken straight to the session page. Send some traffic, then click
   **Refresh**: the list does not update by itself. Each request is listed with
   its method, path, status and time taken. Filter by status family or by how
   slow it was.
4. Click a request. **Request chain** shows each plugin that ran and what it
   changed; **Inspector** shows the headers and body of the request and the
   response.

To come back to a session later, open the sessions list (the API's
**Observability** tab, or **Observability → Traces** in the sidebar) and click
**View traces** next to it.

A trace session stops recording after **10 requests**. On a busy API, use
**Advanced: filter which requests to capture** so the session records only the
requests you care about, for example status `429`.

> **Warning: traces show secrets in plain text.** The **Inspector** shows API keys
> and cookies exactly as the caller sent them. Don't share your screen while it is
> open, and remove keys and cookies before you paste a trace into a ticket or chat.

**Calls by app.** **App Name** is in the **Group data by** list. But the UI charts
leave out calls that have no app, without saying so. If an API doesn't check keys,
its calls disappear from a by-app chart instead of showing as "unattributed". To
see those calls, ask the Helix Agent or use the script below; both show them as
"unattributed".

### Before you trust a number

- **Blocked calls look very fast.** A call the gateway turns away (401 for a
  missing key, 429 for a usage limit, and similar) is counted at 0–4 ms. For the
  real speed of your API, filter to status codes below 400.
- **Success plus Failure doesn't add up to Request Count.** The built-in
  **Success Count KPI** and **Failure Count KPI** widgets leave out 3xx codes, such
  as the 304 a browser gets when it refreshes a page. Those calls are in
  **Request Count** but in neither of the other two.
- **"Total Bandwidth" is an average, not a total.** The built-in **Total
  Bandwidth** widget shows the average size of one call, not the total moved.
- **QPS (queries per second) can show decimals.** QPS is the number of requests
  in a time slot divided by the seconds in that slot. Small traffic gives values
  like 0.02, and the value changes when you change the time range. For small
  numbers, use **Requests Count** instead.
- **An overall average across APIs is wrong.** When you group an average (such
  as response time) by API, the single overall figure is the average of the
  per-API averages, not of all calls. In one test it read 310 ms when the real
  average was about 214 ms. Use the per-API rows.

## Run the script

Prefer a terminal? [`scripts/query-analytics.sh`](scripts/query-analytics.sh)
prints the headline views for the last hour — the same metrics API, no agent.

**Before you start: you need three values.**
- **`CP` — your control-plane API address.** This is the address the portal
  itself calls behind the scenes, and it usually begins with `api-`. It is **not**
  the address of the portal page you log in to. To find it, open your browser's
  developer tools on the portal, look at any request, and copy the part before
  `/api/`. With the wrong address the script shows "no data" and no error.
- **`ORG` — your org id.**
- **`TOKEN` — a control-plane bearer token**, the same one the portal uses. Copy
  it from the same request's `Authorization` header, or get one from your own
  sign-in flow. It lasts about 1 hour.

The script needs `curl` and `python3`.

```bash
CP=https://<YOUR_CONTROL_PLANE_API> \
ORG=<YOUR_ORG_ID> \
TOKEN=<control-plane bearer token> \
./scripts/query-analytics.sh
```

It prints six views: requests by API, by app, by product and by status code, then
the slowest and the fastest APIs by average response time. See the
[Overview](README.md#example) for sample output.

Filter every view to one API with `API_NAME=<short name>` (for example
`posts-api`), widen the window with `WINDOW_HOURS=24`, or change how many rows
each view shows with `TOP` (default 20).

## Call the metrics API directly

Every query is one `POST` with the same token:

```bash
curl -s -X POST "https://<YOUR_CONTROL_PLANE_API>/api/orgs/<YOUR_ORG_ID>/analytics/metrics/requests-count" \
  -H "authorization: Bearer <control-plane bearer token>" \
  -H 'content-type: application/json' \
  -d '{"startTime":"1h","endTime":"now",
       "dimensions":["api_name"],"excludeTimeUnit":true,
       "pageRequest":{"page":1,"size":20,"sort":{"field":"value","order":"DESC"}}}'
```

That returns one row per API, busiest first. Times are either short forms such
as `24h`, `7d` and `now`, or UTC timestamps written like `2026-01-01T00:00:00Z`.
The response is `{ value, timeRange, groupedResults[], meta }`, with each row
`{ dimensions:{…}, value }` — or `{ timeBucket, dimensions:{…}, value }` for a
series over time.

The exact request for every everyday question — by app or product, slowest and
fastest, errors by status, traffic over time, data transferred — is in the
[query catalogue](charts.md), along with the cautions about the overall `value`.
Each call in one table: [API reference](api-reference.md).

## Variations

**Follow-ups in the same agent session.** Each one refines the previous answer
rather than starting again:

```text
Filter that to just the {{api_name}} and show it again.
```
```text
Same breakdown, but for the last 7 days by day instead of the last hour.
```
```text
Now show average and max response time side by side for those APIs.
```
```text
Which apps sent the most requests to that API this week?
```

**Narrow any query to one API, product or app.** Add a filter — it works on every
view. Use the short name:

```json
{ "startTime":"1h", "endTime":"now",
  "filters":[{ "column":"api_name", "operator":"EQ", "value":["posts-api"] }],
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
| `CP` | yes | — | Your control-plane **API** address, e.g. `https://<YOUR_CONTROL_PLANE_API>` — the address the portal calls, not the portal page |
| `ORG` | yes | — | Your org id |
| `TOKEN` | yes | — | A control-plane bearer token (lasts about 1 hour) |
| `WINDOW_HOURS` | no | `1` | How far back to look, in hours |
| `API_NAME` | no | — | If set, every view is filtered to this one API (short name, such as `posts-api`) |
| `TOP` | no | `20` | Maximum rows per view |

**A query** — the body of `POST /api/orgs/{orgId}/analytics/metrics/{metric}`:

| Field | What it does |
|---|---|
| `startTime`, `endTime` | The window: short forms (`24h`, `7d`, `now`) or UTC (`2026-01-01T00:00:00Z`) |
| `dimensions` | What to group by — e.g. `api_name`, `app_name`, `product_name`, `response_status_code` |
| `filters` | `{column, operator, value[]}` entries, all combined with AND |
| `aggregation` | `AVG`, `MIN`, `MAX` or `SUM` — time and size metrics only |
| `excludeTimeUnit` | `true` for one total per group; leave it out and set `timeUnit` for a series |
| `timeUnit` | `SECONDS`, `MINUTES`, `HOURS` or `DAYS` |
| `pageRequest` | `page`, `size`, and `sort: {field: "value", order: "ASC" or "DESC"}` for a top-N list |

The full list of metrics and dimensions is on
[Architecture](architecture.md#the-read-api). Placeholders on this page:
`<YOUR_CONTROL_PLANE_API>`, `<YOUR_ORG_ID>`. Replace them, and never commit a
token.

## Troubleshooting

- **An error status, and you want to know where it came from.** Look at the
  backend time for those calls: query `upstream-response-time` filtered to that
  status code.
  - **No backend time:** the gateway answered on its own, so the error came from
    the gateway — a plugin, sign-in, a usage limit, or a fault.
  - **Backend time present:** the call reached your backend, so the error came
    from your backend.
- **A breakdown comes back "unattributed".** That API doesn't identify its callers,
  so analytics has no app or developer to put on the rows. It is a property of the
  API, not of the query — see
  [Architecture](architecture.md#two-things-about-attribution).
- **A filter on one API or app returns nothing.** You probably used the name
  shown in the portal. Use the short name, such as `posts-api` — see
  [Names](#names-use-the-short-name-not-the-one-on-screen).
- **An empty result.** Either there was no traffic in the window, or you've asked
  for further back than the data is kept. Widen the range and ask again.
- **The script prints `(no data in the window)` for every view.** It prints that
  for any answer that carries no rows — including an error from the API. Check
  there was traffic in the window, that `CP` is the control-plane API address
  rather than the portal page, and that your token hasn't expired (it lasts about
  1 hour).
- **Calls to a wrong path are missing.** A call that matches no route (`404 Route
  Not Found`) is never recorded. A 404 that your backend sends is recorded.
- **Query strings are missing from paths.** They are not stored: a call to
  `/posts?try=1` appears as `/posts`.
- **The status code is not what your backend sent.** A gateway plugin can change
  the status code (for example a response rewrite). Analytics records what the
  caller received, not what the backend sent.
- **You asked for a percentile and got an average.** Analytics has no percentiles.
  Ask for `max` as the worst-case signal instead, or use a tracing stack.
- **You can't find one particular request.** `X-Request-Id` isn't something
  analytics can group or filter by. Narrow analytics to the right slice, then find
  the id in your own logs.
- **A route shows up as dozens of rows.** You grouped by `api_path`, which gives
  one row per concrete id. Group by `route_id` instead.
- **You want "% of quota used".** There is no such metric. Count the 429s instead;
  remaining headroom lives with the product's settings.
