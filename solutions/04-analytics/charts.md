# The chart catalogue — what to ask, and what the answer is worth

Analytics is already capturing every request. This file is the part that actually
matters: **which questions are worth asking, how to ask them, and what to do with the
answer.**

Each entry below gives you:

- **The question**, in the form you'd say it out loud
- **The agent prompt** — paste it into Agent Mode as written
- **What you get**, and the shape it should be in
- **What it's for** — the decision the chart informs. A chart nobody acts on is a
  dashboard ornament.
- **What breaks it** — the configuration mistake that makes the answer useless

> **On the sample API vs. these charts.** The API shipped with this solution is
> deliberately minimal (two routes, no auth), so charts that group by app or that need
> quota only return useful data once you compose in identity ([solution 01](../01-oauth-jwt/))
> and/or API Products ([solution 03](../03-api-products/)). Charts that group by route,
> status or latency work as-is. Each chart notes what it needs.

Two things are assumed throughout, and both come from
[`gateway/api-spec.yaml`](gateway/api-spec.yaml): **identity is resolved** (so rows
attribute to an app, not an IP) and **paths are templated** (so a route is one row).
Where a chart needs more than that, it says so.

> **The concrete backing for these charts** (the control-plane analytics API): `POST /api/orgs/{orgId}/analytics/metrics/*`
> (requests-count, response-time, sizes, rps, upstream-time) taking
> `{startTime, endTime, filters[], dimensions[], aggregation, timeUnit}`. The
> available **dimensions** are: `env_name`, `app_id`, `app_name`, `product_name`,
> `api_name`, `route_id`, `route_name`, `api_path`, `request_method`,
> `response_status_code`, `upstream_path`, `developer`. **Group route-level charts
> by `route_id`, not `api_path`** — `route_id` collapses `/orders/{orderId}` to one
> row, `api_path` gives one row per concrete id. Note `X-Request-Id` is
> **not** a dimension; see chart 4.

> **On the exact query syntax.** The prompts below are how you ask the *agent*, and
> that's deliberate — it knows your org's schema and can pull the data directly.
> The portal exposes the same underlying data through its own filters; where a field
> name matters, ask the agent to show you the field it filtered on rather than
> guessing. Field names vary by build.

---

## Tier 1 — the four that earn their place immediately

If you only ever look at four things, look at these.

### 1. Traffic by app

> *"Show me calls to Orders API in the last 24 hours, broken down by app, and tell me
> which app sent the most."*

```text
Show me calls to <<Orders API>> in the last 24 hours, broken down by app. Give me the
call count per app, sorted descending, and tell me what percentage of total traffic
the top app represents.
```

**What you get:** a ranked list of apps with call counts. The top app's share of total
traffic is the number that matters.

**What it's for:** this is your baseline. You cannot recognise an anomaly without
knowing what normal looks like, and "one app is 60% of our traffic" is a fact worth
knowing *before* it becomes an incident. It's also the input to any chargeback
conversation.

**What breaks it:** no identity resolution. Without `helix-auth`, this is a list of IP
addresses, and partners share NAT gateways and rotate egress addresses — so the rows
don't correspond to anything you can act on.

---

### 2. Error rate by route and status

> *"Which routes returned 4xx or 5xx yesterday, and what was the error rate on each?"*

```text
Which routes on <<Orders API>> returned 4xx or 5xx yesterday? For each route give me
the count by status code and the error rate as a percentage of that route's total
calls. Separate 4xx from 5xx — I care about them differently.
```

**What you get:** per-route error counts and rates, split by status class.

**What it's for:** the split is the whole value. **5xx is your problem. 4xx is usually
your partner's problem — or your documentation's.** Conflating them into one "error
rate" produces a number that can't drive an action: a rising 5xx rate is an
engineering escalation, a rising 401 rate on one app is a support conversation, and a
rising 400 rate across many apps means your request contract is unclear.

**What breaks it:** grouping by `api_path` instead of `route_id`. `api_path` records
the concrete path, so `/orders/{orderId}` fragments into one row per id and no route
shows a meaningful rate. Group by `route_id` (verified: it collapses to one row per
configured route).

---

### 3. Latency percentiles by route

> *"What's the p50, p95 and p99 latency per route on Orders API this week?"*

```text
Give me p50, p95 and p99 latency per route on <<Orders API>> for the last 7 days.
Include the call count per route so I can see which percentiles are backed by enough
samples to trust. Flag any route where p99 is more than 10x its p50.
```

**What you get:** a latency distribution per route, with sample counts.

**What it's for:** the p99/p50 ratio is the interesting signal, not the absolute
numbers. A route where p50 is 40ms and p99 is 4 seconds has a *tail* problem —
something is occasionally slow, and averages hide it completely. That's usually a cold
cache, a lock, or one pathological input.

**Why you asked for sample counts:** a p99 computed from 12 requests is noise. Ask for
the count or you'll chase a phantom.

**What breaks it:** mixing fast and slow routes under one path pattern. This is why
[the spec](gateway/api-spec.yaml) keeps `POST /orders/report` separate — blending a
30-second report into a 40ms lookup produces an average that describes neither.

---

### 4. A single request, end to end

> *"Here's a request id from a customer complaint. Show me that request."*

```text
Find the request with X-Request-Id <<7f3c…>> on <<Orders API>>. Show me the route,
the calling app, the status, the latency, and the timestamp.
```

**What you get:** one row. That's the point.

**What it's for:** this is the bridge from "3% of calls failed" to "*this* call
failed, for *this* partner, at *this* time" — and then to your backend's own logs for
the same call, because `request-id` is forwarded upstream.

**What breaks it:** your backend not logging `X-Request-Id`. The gateway generates and
records it either way, but if nobody downstream writes it down, you can correlate the
gateway with itself and nothing else. **Ask your teams to log it.** It is the cheapest
observability work available to you and it is routinely skipped.

---

## Tier 2 — the commercial questions

These are the ones that get analytics funded. They need
[solution 03](../03-api-products/) deployed, because a quota has to exist before
quota consumption means anything.

### 5. Quota consumption per app

> *"Which apps came within 10% of their product quota this week?"*

```text
For <<Orders API>>, show me each app's peak quota consumption as a percentage of its
product's limit over the last 7 days. List any app that exceeded 80% at any point,
with the product it is subscribed to and the peak percentage.
```

**What you get:** apps ranked by how close they came to their ceiling.

**What it's for:** **this is a sales pipeline, not an ops chart.** An app consistently
above 80% of a Free or Pro limit is a qualified upgrade lead with a number attached —
you can open that conversation with evidence rather than a hunch. It's also your early
warning: an app about to start hitting 429s is a support ticket you can pre-empt.

**Requires:** `api-product-enforcer` deployed and products with quotas. See
[solution 03](../03-api-products/).

---

### 6. Who is being throttled

> *"Which apps hit their quota in the last hour, and by how much did they go over?"*

```text
Show me every app that received a 429 on <<Orders API>> in the last hour. For each,
give me the count of 429s, the count of successful calls in the same window, and the
product it is subscribed to.
```

**What you get:** throttled apps with their success/rejection ratio.

**What it's for:** the ratio distinguishes two very different situations. **A few 429s
at a peak means the tier is correctly sized and occasionally binding — that's the
system working.** An app whose calls are 90% 429s is broken: it's either retrying
without backoff (making things worse for itself) or genuinely outgrew its tier weeks
ago. The first needs a documentation conversation, the second needs a sales one.

**Requires:** solution 03. Also worth remembering that the 429 carries no
`Retry-After`, so a client with no backoff logic will hammer you — this chart is how
you find those clients.

---

### 7. Under-utilised committed accounts

> *"Which Enterprise accounts are nowhere near their quota?"*

```text
List apps subscribed to <<Orders API — Enterprise>> whose peak consumption over the
last 30 days was below 20% of their limit. Include the peak percentage and total call
volume.
```

**What you get:** committed accounts using far less than they pay for.

**What it's for:** two possible readings, and you need to know which. Either the
account is **over-provisioned** — you sold them more than they need, which is fine
revenue but fragile at renewal — or they **never fully integrated**, which is a churn
risk nobody has noticed. Both are worth a conversation, and neither shows up in a
revenue report.

**Requires:** solution 03.

---

## Tier 3 — the operational questions

### 8. Traffic over time, with the shape visible

> *"Plot Orders API calls per hour for the last 7 days."*

```text
Plot calls to <<Orders API>> per hour for the last 7 days. Overlay the error rate.
Tell me the peak hour and how it compares with the median hour.
```

**What you get:** a time series with the error rate alongside.

**What it's for:** peak-to-median ratio is your capacity planning input, and the
overlay is what makes it diagnostic: **errors rising *with* traffic means a capacity
problem; errors rising *without* traffic means a deployment or a dependency.** That
distinction is worth more than either line alone, and it's why you overlay rather than
looking at two charts.

---

### 9. Authentication failures by app

> *"Which apps are getting 401s, and are they failing every call or some?"*

```text
Show me 401 responses on <<Orders API>> in the last 24 hours, grouped by app where
identity could be resolved, and separately the count of 401s where no app could be
identified. For apps with 401s, give me the ratio of failed to successful calls.
```

**What you get:** two buckets — identified apps failing, and unidentifiable failures.

**What it's for:** the split matters. An app failing **every** call is broken
configuration, and usually a partner who hasn't told you yet — most likely sending
the app secret where the client id belongs, or a token issued under a rotated signing
secret. An app failing **some** calls is more interesting: probably expired tokens,
meaning they're not refreshing before expiry. The unidentifiable bucket is scanning,
stale credentials, or a decommissioned integration still running somewhere.

**Worth doing proactively.** A partner whose integration broke at 2am will often not
tell you until their business hours. This chart tells you first, and calling them is a
remarkably good customer experience.

---

### 10. Token endpoint abuse

> *"Which apps are requesting tokens more often than they should?"*

```text
On <<Orders API>>, show me token requests per app over the last 24 hours alongside
each app's total API calls. Flag any app whose token requests exceed one per 12
minutes, or whose token-request count is more than 5% of its API call count.
```

**What you get:** token requests per app, relative to actual API usage.

**What it's for:** a client that fetches a fresh token per API call has doubled the
latency of everything it does and made your token endpoint your busiest route. With a
900-second TTL, a well-behaved client requests roughly four tokens an hour regardless
of volume. **Anything approaching one token per call is a client not caching**, and
it's a one-line fix on their side that they don't know they need.

---

### 11. New and disappeared apps

> *"What changed in who's calling us?"*

```text
Compare apps calling <<Orders API>> this week against last week. List apps that
appeared for the first time, and apps that called last week but not this week.
```

**What you get:** the diff in your caller population.

**What it's for:** an app that **stopped** calling is the signal nobody watches. It's
either a partner who churned quietly, an integration that broke and was never fixed,
or a credential that expired — and all three are worth a call. New apps confirm
onboarding is working, and occasionally reveal a partner who went live without telling
anyone.

---

### 12. Slow-route drift

> *"Is anything getting slower?"*

```text
For <<Orders API>>, compare p95 latency per route this week against the same period
last week. List any route where p95 increased by more than 20%, with both values.
```

**What you get:** routes trending slower, with the magnitude.

**What it's for:** degradation is rarely a step change — it's a 15% increase per week
until someone notices a customer complaint. Comparing week-on-week catches the drift
while it's still cheap to investigate, and gives you the change window to look at.

---

## Building a dashboard from these

If you're standing up a permanent view, resist adding everything. A dashboard people
actually read has one screen:

| Position | Chart | Why here |
|---|---|---|
| Top left | Traffic per hour, error rate overlaid (#8) | The single most information-dense panel. Shape plus health. |
| Top right | Error rate by route, 4xx and 5xx split (#2) | Where to look when the overlay moves. |
| Middle | p95 per route with call counts (#3) | Slower than usual, and whether the number is trustworthy. |
| Bottom left | Top apps by volume (#1) | Who is driving the traffic above. |
| Bottom right | Apps above 80% of quota (#5) | The only commercial panel that belongs on an ops screen. |

Everything else in this catalogue is a **question you ask when something looks wrong**,
not a panel you stare at. Charts 4, 9, 10, 11 and 12 are investigative — putting them
on a wall means five more things nobody reads, which makes the two that matter harder
to see.

The one habit worth building: **when a chart moves, write down what you did about
it.** A chart with no history of action is a chart you can delete.

---

## What analytics cannot tell you

Being clear about the boundary, because assuming otherwise wastes an afternoon:

- **It sees requests, not request bodies.** Which app called `POST /orders` and what
  it got back — yes. What was in the payload — no, and that's deliberate: capturing
  bodies means capturing customer data.
- **It sees the gateway's view.** Latency is measured at the edge, which includes your
  upstream's time but cannot break it down into *your* internal hops. For per-hop
  timing you want distributed tracing, and `X-Request-Id` is the thread that connects
  the two.
- **Rejected requests are attributed only when identity resolved.** A 401 from an
  unknown key has no app to attribute to — hence the two buckets in chart 9.
- **It cannot retroactively fix modelling mistakes.** Untemplated paths recorded as
  literal order ids stay that way. So does traffic captured before you resolved
  identity. **The three decisions in the spec have to be made before the data you want
  to query is generated** — which is the real reason this solution has a gateway
  configuration at all.
- **Retention is finite, and it's a platform setting.** Chart 7 asks for 30 days and
  chart 12 compares week-on-week. Confirm your retention window covers the questions
  you intend to ask, before you build a report that silently truncates.
