# Business need — answers from the data you already have

## The situation

The gateway has been recording every request since the day it went in. Nothing is
missing and nothing needs buying — the data is there. The gap is getting an answer
out of it quickly, without standing up a telemetry stack or touching your APIs.

> *"At 3am something hammered one of our APIs. On-call spent forty minutes working
> out which integration it was. We could see a spike; we couldn't see whose."*

That question — and most of the everyday ones — is a single query against the
analytics API. This solution is those queries.

## What it changes

| Question | Before | After |
|---|---|---|
| "How much traffic did each API get this hour?" | Eyeball a dashboard, or guess | One query, grouped by `api_name`, sorted |
| "Which integration is driving the load?" | A log hunt | Group by `app_name` / `developer` |
| "Which API is slowest right now?" | Anecdote | Rank by AVG `response-time` |
| "Where are the errors, and whose?" | Scattered | Counts by `api_name` × `response_status_code` |
| "What's my busiest product?" | Unknown | Group by `product_name` |

All read-only, for any window, with nothing installed and no change to any API.

## Why it's low-cost and low-risk

- **No configuration.** Analytics is global; you don't add a plugin or a logger, and
  you can't break anything — the queries only read.
- **No new system.** You're not running Prometheus, an ELK stack, or a warehouse for
  the everyday questions. The gateway already has the data.
- **Answers in seconds.** Incident triage ("who caused this?"), capacity checks
  ("peak vs median?"), and "is this API getting slower?" become queries, not
  projects.

## Business outcomes

- **Incident attribution drops from a log hunt to a query** — name the API, app, or
  status behind a spike immediately.
- **Chargeback and upgrade conversations get evidence** — per-app and per-product
  request counts, rather than hunches. (These rows require the API to resolve
  identity — see below.)
- **Latency regressions surface early** — rank APIs by response time and compare
  windows before a customer complains.

## What shapes the answers (but isn't yours to add here)

You configure nothing for analytics, yet two properties of how an API is *already*
built decide how useful its rows are:

- **Per-app / per-developer / per-product breakdowns need the API to resolve
  identity.** An authenticated API attributes rows to an app; an anonymous one lands
  in an "unattributed" bucket. Adding identity is
  [solution 01](../01-oauth-jwt/) / [solution 03](../03-api-products/) — a decision
  about the API, not about analytics.
- **Group route-level views by `route_id`, not `api_path`** — else a templated route
  fragments into one row per id.

## What analytics is not

Be clear so nobody builds the wrong report on it:

- **Not percentiles.** Average / min / max only; `MAX` is the tail signal. True
  p95/p99 needs a tracing/metrics pipeline.
- **Not quota accounting.** You can count 429s, not "percent of a limit used."
- **Not per-request tracing.** `X-Request-Id` correlates in your own logs, not in
  analytics.
- **Not request bodies.** Metadata only, by design.
- **Retention is finite.** It bounds how far back a window can reach — confirm yours
  before relying on a long-range report.

## Success criteria

You'd call this done when "how much / how fast / how many errors, by API, product,
or app, in the last hour" is a query anyone on the team can run in seconds — with
nothing installed and no change to a single API.
