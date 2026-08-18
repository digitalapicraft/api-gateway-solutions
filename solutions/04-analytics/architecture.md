# Architecture — analytics that can answer a question

Analytics is not something this solution turns on. It is already on: `helix-analytics`
is enabled globally on the platform, and every request through every API is being
captured right now.

What this solution does is make the capture **useful**. That is a request-path concern,
not an observability concern, and the distinction is the whole architecture.

---

## Where the data comes from

This solution's API is deliberately minimal — two routes returning a standard
response via the `mocking` plugin, no auth. Analytics still captures every call; the
only question is how usefully. Here is a call to the templated route:

```
┌────────┐   ┌───────────────────────────────────────────────┐
│ Client │   │                   Gateway                     │
└───┬────┘   │                                               │
    │ GET /orders/ord_1a2b3c                                 │
    ├────────►│  ┌──────────── rewrite phase ─────────────┐  │
    │        │  │ request-id → X-Request-Id: 7f3c…        │  │
    │        │  └──────────────┬─────────────────────────┘  │
    │        │  ┌──────────── (mocking) ──────────────────┐  │
    │  200   │  │ returns the standard response           │  │
    │◄───────┼──┴─────────────────────────────────────────┘  │
    │        │  ┌──────────── log phase ──────────────────┐  │
    │        │  │ helix-analytics  (GLOBAL — NOT in your   │  │
    │        │  │                   API's spec)            │  │
    │        │  │ writes one row:                          │  │
    │        │  │   route      /orders/{orderId}  ← templated (group by route_id)
    │        │  │   api_path   /orders/ord_1a2b3c ← the concrete path
    │        │  │   status     200                         │  │
    │        │  │   latency    2ms                         │  │
    │        │  │   request_id 7f3c…             ← correlation (log-side)
    │        │  │   app        (none) ── a SOURCE IP unless you add identity
    │        │  └─────────────────┬───────────────────────┘  │
    └────────┴────────────────────┼──────────────────────────┘
                                 ▼
                    ┌────────────────────────┐
                    │   analytics store      │ ──► portal
                    │   (platform-managed)   │ ──► the agent / metrics API
                    └────────────────────────┘
```

Two fields in that row are useful *because of a request-path choice* baked into this
API: **route** is templated (group by the `route_id` dimension and `/orders/{orderId}`
collapses to one row), and **request_id** is a correlation handle you match in your own
logs. A third — **who called** — is a *source IP* here, because the API has no identity.
Add `helix-auth` ([solution 01](../01-oauth-jwt/)) and that same row carries the app and
developer instead; you change nothing on the analytics side.

## The fields that matter, and where they come from

| Field in the row | Comes from | Without it |
|---|---|---|
| `route` (by `route_id`) | The **templated** OpenAPI path `/orders/{orderId}` | Group by `api_path` and you get one row per order id — a per-route breakdown that is a list of individual records, with per-route p99 from one sample each. |
| `request_id` | `request-id`, forwarded upstream | You can see 3% of calls failed but cannot reach the failing request, or the matching line in your backend's logs. |
| `app` / `developer` *(compose-in)* | `helix-auth` ([solution 01](../01-oauth-jwt/)) resolving identity | Not present on this minimal API — the row attributes to a source IP. Add solution 01 when you need per-app numbers. |
Templating and correlation are baked into this minimal API; identity is the one you
add ([solution 01](../01-oauth-jwt/)) when per-app numbers matter. There is no analytics
configuration in the spec at all, and there should not be.

## The property that makes this urgent

**Templating and identity must be in place *before* the data you want to query is
generated.**

This is the structural fact that justifies a gateway configuration in a solution about
reading charts:

- Analytics **cannot retroactively attribute** traffic captured without identity. The
  gateway didn't know who was calling; nothing recovers that later.
- Analytics **cannot collapse** literal paths into a template after the fact. A year of
  `/orders/ord_1a2b3c` rows stays a year of individual rows.
- A correlation id **not written down by your backend** cannot be reconstructed.

So the failure mode isn't "the dashboard is missing a feature". It's "the question was
made unanswerable months ago, by a decision nobody framed as an observability
decision."

The one piece of good news: fixing the configuration fixes it *going forward*
immediately. There's no migration, no backfill — just a line under the old data.

## Execution order

| Order | Plugin / step | Phase | Contributes to the row |
|---|---|---|---|
| 1 | `helix-auth` (validate) | access | `app`, `developer` — and gates everything after it |
| 2 | `request-id` | rewrite | `request_id`, also sent upstream |
| 3 | *(upstream call)* | — | `status`, `latency` |
| 4 | `helix-analytics` **(global)** | log | writes the row |

The dependency that matters: **analytics runs in the log phase, last.** It records
whatever the earlier phases established. It has no ability to enrich a row with
information that was never resolved — it is a recorder, not an investigator.

That's why identity has to be step 1 rather than an afterthought, and why an
unauthenticated route produces a permanently anonymous row.

## Route design is an analytics decision

Two modelling choices in the spec exist purely for observability reasons, and neither
is obvious as such.

**Templating.** `/orders/{orderId}` declared as a parameter is one row. Declared as
literals, it's one row per order. The API behaves identically — this is invisible until
you ask a route-level question.

**Splitting by latency profile.** If you later add routes with very different latency
profiles — say a 30-second report and a 40ms lookup — keep them as separate routes. Sharing
one path pattern gives a per-route latency distribution that describes neither: p50 dragged
up, p99 dragged down, a number worse than useless because it looks authoritative.

> **If two routes have wildly different latency profiles, they want separate rows.**

Nobody frames "should these be two routes?" as an observability question. It is one.

## Native vs custom

There is nothing to build. **No custom code is required, and the analytics capture
itself is not yours to configure.**

| Requirement | How it's met | Note |
|---|---|---|
| Capture every request | `helix-analytics`, **enabled globally by the platform** | Not in your spec. Adding a block is the mistake this solution prevents. |
| Attribute to an app | `helix-auth` in the access phase | The one decision that determines whether per-app anything is possible |
| Group by route | Templated OpenAPI paths | A modelling decision, not a plugin |
| Correlate to one request | `request-id`, forwarded upstream | Half the value is your backend logging it |
| Query it | The portal, or the agent in natural language | See [`charts.md`](charts.md) |

Where custom work **would** be justified, and is out of scope here:

- **Per-hop tracing inside your own services.** Analytics measures at the edge. For
  internal spans you want distributed tracing, and `X-Request-Id` is the thread that
  joins the two datasets.
- **Threshold alerting.** This is query-and-chart. Alerting is a different tool fed by
  different data.
- **Long-term warehousing beyond the platform's retention window.** If you need
  multi-year trend analysis, that's an export pipeline.

## What the data cannot tell you

Worth stating precisely, because assuming otherwise wastes an afternoon:

- **Requests, not bodies.** Which app called `POST /orders` and what status came back —
  yes. What was in the payload — no, and deliberately: capturing bodies means capturing
  customer data.
- **The gateway's view of latency.** It includes your upstream's total time but cannot
  decompose it into your internal hops.
- **Rejected requests attribute only when identity resolved.** A 401 from an unknown key
  has no app. Expect an "unidentified" bucket and don't read it as zero.
- **Retention is finite and is a platform setting.** It bounds which questions are
  answerable at all. Confirm your window before building a 30-day report.

## When to use this

Use it when:

- **You have analytics and cannot get an actionable answer out of it.** The common case,
  and it's a request-path problem wearing a tooling problem's clothes.
- **You're about to onboard partners at scale.** Get these three right before the data
  arrives — two of them are unrecoverable.
- **Incident attribution is slow.** "Which of our 400 integrations caused this" should be
  a query, not forty minutes.
- **You need chargeback or upgrade signals.** Per-app counts are the input to both.

Don't use it when:

- **You need per-hop latency inside your services.** Distributed tracing.
- **You need bodies.** Not captured, by design.
- **You need real-time threshold alerting.** Different tool.
- **Your API is genuinely anonymous and must stay so.** Then attribution is impossible in
  principle. Volume, latency and error rate still work; per-app charts never will.

## Prerequisites

- The API is deployed to an environment.
- For per-app attribution, **identity is resolved** on the routes — see
  [solution 01](../01-oauth-jwt/). Optional here; without it, rows attribute to a source IP.
- Paths are templated wherever a segment is an identifier.
- `request-id` applied API-wide, and ideally your backend teams logging it.
- Traffic actually exists. Analytics is capture-then-query; there is nothing to look at
  until calls have been made. [`gateway/verify.sh`](gateway/verify.sh) seeds a known,
  labelled pattern for exactly this reason.
- For the quota charts (5–7 in [`charts.md`](charts.md)):
  [solution 03](../03-api-products/) deployed, since consumption requires a quota to
  exist.

## Failure behaviour

Analytics has no failure mode that affects the request path — it runs in the log phase
and does not gate traffic. The failures are all *epistemic*: the data is captured
faithfully and cannot answer you.

| Symptom | Cause | Recoverable? |
|---|---|---|
| Every row is an IP address | Identity not resolved on that route | **No** for existing data. Fix the route; future data is fine. |
| One row per order id | Path not templated | **No** for existing data. Fix the spec; future data is fine. |
| `X-Request-Id` found at the gateway but not in backend logs | Your services aren't recording the forwarded header | Yes — ask your teams |
| Per-route p99 looks implausible | Too few samples in that row | Yes — ask for the sample count alongside |
| A route's latency describes nothing | Fast and slow operations share one path pattern | Yes — split the routes |
| Query returns nothing | No traffic yet, or outside the retention window | Yes — seed traffic; check retention |
| A 401 spike attributes to no app | Identity never resolved for those requests — correct behaviour | N/A — expect the unidentified bucket |

The first two rows are the ones worth acting on today, because they are the only two
that get worse the longer you wait.
