# You already have analytics. It just can't answer the question.

Here's a conversation I've had more than once.

*"Do you have API analytics?"*

Yes. Every request is captured. Nice dashboard. 4.2 million calls last month, 1.8%
failed.

*"At 3am on Tuesday something hammered your orders endpoint. Which integration was
it?"*

...

Forty minutes of on-call time. The dashboard showed a spike — a beautiful, clear,
completely useless spike. Every row was an IP address, and the partners share NAT
gateways, run in clouds, and rotate egress addresses. So the spike was real and
un-actionable, and the incident got resolved the way these usually do: by guessing,
then calling someone.

**Nothing was broken.** Every one of those requests was captured faithfully. That's
what makes this problem interesting, and different from every other solution in this
library — there's no feature to enable, no plugin to add, nothing to buy.

The data can't answer you because of decisions made on the request path months before
anyone opened a dashboard.

## The thing you don't do

Let's get this out of the way, because it's the first instinct and it's wrong.

**You do not add an analytics plugin.** Analytics is enabled globally on the platform.
Every request through every API is already being captured, right now, including the
ones made while you read this.

There is deliberately no `helix-analytics` block anywhere in
[the spec](./gateway/api-spec.yaml). If an agent proposes one — and it will, because on
most platforms observability *is* a plugin you enable — that's the thing to correct.

So if it's already on, what's left to do?

## Analytics can only group by what the gateway knew

That's the whole insight. Everything else follows from it.

When a request completes, the platform writes a row. Something like:

```
route        /orders/{orderId}
app          partner-b-prod
developer    Partner B
status       200
latency      41ms
request_id   7f3c…
```

Six fields. **Three of them are only meaningful because of a decision made earlier in
the request path** — and those three are exactly the difference between a queryable
dataset and a pile of counters.

Analytics runs in the log phase. Last. It records what the earlier phases established.
It is a recorder, not an investigator, and it has no ability to enrich a row with
information nobody resolved.

### Decision one: identity

Without `helix-auth` resolving the caller, `app` and `developer` are absent and the row
attributes to a source IP.

| Question | No identity | Identity resolved |
|---|---|---|
| "Which integration caused the spike?" | An IP address | An app and a developer, by name |
| "Who should we bill?" | Unanswerable | Per-app request counts |
| "Whose integration broke?" | Unanswerable | An app failing every call since 02:14 |

This single decision is the difference between analytics you *query* and analytics you
*scroll*.

### Decision two: path templating

`/orders/{orderId}` declared as a path parameter is **one row**: one latency
distribution, one error rate, one count you can trend.

Declared as literal paths, you get **one row per order.**

Your top-routes chart becomes a list of individual customer orders. Per-route p99
becomes meaningless because every row has exactly one sample. Cardinality grows with
your order volume, forever.

And here's the part that makes it nasty: **the API works identically either way.**
Nothing warns you. Nothing degrades. You find out the first time you try to ask a
route-level question, which for most teams is during an incident.

### Decision three: a correlation id

Aggregates tell you *what* happened. `X-Request-Id` is how you get from a row in a
chart to the specific request — and, because the header is forwarded upstream, to the
matching line in **your backend's own logs**.

One caveat worth more than the config: **ask your teams to log it.** The gateway
generates and records it regardless, but if nobody downstream writes it down, you can
correlate the gateway with itself and nothing else. It's the cheapest observability
work available and it's skipped constantly.

## Why this is urgent rather than tidy

All three decisions share a property:

> **They must be true *before* the data you want to query is generated.**

Analytics cannot retroactively attribute traffic captured without identity. It cannot
collapse literal paths into a template after the fact. Yesterday's anonymous rows stay
anonymous forever.

So this isn't a backlog item that gets cheaper later. It's one of the few configuration
decisions where **delay has a permanent cost** — every day you wait is a day of data
you can never ask questions of.

The corresponding good news, and it's genuinely good: fixing the configuration fixes
things going forward *immediately*. No migration, no backfill. Just a line under the
old data.

## What the configuration looks like

The API-wide block, in full. The notable thing is the absence:

```yaml
x-helix-gateway:
  plugins:
    request-id:
      algorithm: uuid
      header_name: X-Request-Id

    cors:
      allow_origins: "*"
      allow_methods: "GET,POST,OPTIONS"
      allow_headers: "authorization,content-type"
      allow_credential: false

    # NO helix-analytics BLOCK. It's global.
```

Plus `helix-auth` per route, and templated paths — which aren't a plugin at all, just
correct OpenAPI.

Ask for it like this:

```text
I want the platform's analytics to be able to answer per-app and per-route questions
about my Orders API. Analytics is already enabled globally, so do NOT add an analytics
plugin — instead make sure the request path is shaped so the captured data is useful.

1. Confirm identity is resolved on every route, so calls attribute to the calling app
   rather than a source IP. Tell me explicitly if any route is unauthenticated — those
   rows will never be attributable and no later query recovers it.

2. Review my OpenAPI paths for templating. Any route where a segment is really an
   identifier must be a path parameter, not a literal. Tell me if you find one that
   would produce an analytics row per entity.

3. Add request-id (uuid, X-Request-Id) API-wide, and confirm it's forwarded upstream so
   my backend can log the same id.

Then show me the spec, dry-run it, and wait for my confirmation.
```

Notice it asks the agent to **report** on identity coverage rather than fix it. Making a
route authenticated might be a product decision you don't want made for you — but you
absolutely need to know which rows will never be attributable.

## Then ask questions

This is where the value is, and it's why [`charts.md`](./charts.md) is twelve questions
rather than one. A few that earn their place immediately:

**Error rate by route — 4xx split from 5xx.** The split is the whole value. **5xx is your
problem. 4xx is usually your partner's problem, or your documentation's.** Conflating
them into one "error rate" gives you a number you cannot act on: a rising 5xx is an
engineering escalation, a rising 401 on one app is a support call, a rising 400 across
many apps means your request contract is unclear.

**Latency percentiles per route, with sample counts.** The p99/p50 *ratio* is the
signal, not the absolute numbers. A route at p50 40ms and p99 4 seconds has a *tail*
problem — something is occasionally slow and averages hide it completely. Ask for the
count too: a p99 computed from twelve requests is noise presented as precision.

**Apps above 80% of their quota.** This is a **sales pipeline, not an ops chart.** An app
consistently near its Free or Pro ceiling is a qualified upgrade lead with a number
attached — you can open that conversation with evidence instead of a hunch. Usually the
chart that gets analytics work funded. (Needs [solution 03](../03-api-products/), since
quota consumption requires a quota.)

**401s by app — failing *every* call, or *some*?** Every call means broken configuration
and a partner who hasn't told you. Some calls means expired tokens and a client not
refreshing. **Worth running proactively**: a partner whose integration broke at 2am often
won't report it until their business hours, and calling them first is a remarkably good
customer experience.

**Apps that stopped calling.** The signal nobody watches. Churn, a broken integration, or
an expired credential — all three deserve a phone call, and none of them generates an
alert. It looks like nothing.

## Route design is an analytics decision

One route in [the spec](./gateway/api-spec.yaml) exists purely to make a point:
`POST /orders/report` is deliberately kept separate from the fast reads.

If a 30-second report and a 40ms lookup share a path pattern, the per-route latency
distribution describes neither. p50 is dragged up, p99 dragged down, and the number is
*worse* than useless because it looks authoritative.

> **If two routes have wildly different latency profiles, they want separate rows.**

Nobody frames "should these be two routes?" as an observability question. It is one.

## Five panels, not twenty

If you're standing up a permanent dashboard:

| Position | Chart | Why |
|---|---|---|
| Top left | Traffic per hour, error rate overlaid | Most information-dense panel there is. Shape plus health. |
| Top right | Error rate by route, 4xx/5xx split | Where to look when the overlay moves. |
| Middle | p95 per route with call counts | Slower than usual, and whether to trust the number. |
| Bottom left | Top apps by volume | Who's driving the traffic above. |
| Bottom right | Apps above 80% of quota | The one commercial panel that belongs on an ops screen. |

The overlay in the top left is doing more work than it looks like: **errors rising *with*
traffic is a capacity problem; errors rising *without* traffic is a deployment or a
dependency.** That distinction is worth more than either line alone, which is why you
overlay rather than keeping two charts.

Everything else in the catalogue is a question you ask **when something looks wrong** —
investigative, not decorative. Putting all twelve on a wall means ten more things nobody
reads, which makes the two that matter harder to see.

One habit worth building: **when a chart moves, write down what you did about it.** A
chart with no history of action can be deleted, and you'd be surprised how many qualify.

## What it can't tell you

- **Requests, not bodies.** Which app called `POST /orders` and what came back — yes.
  What was in the payload — no, and deliberately: capturing bodies means capturing
  customer data.
- **The gateway's view of latency.** It includes your upstream's total time but can't
  decompose it into your internal hops. That's distributed tracing, and `X-Request-Id` is
  the thread joining the two datasets.
- **Rejected requests attribute only when identity resolved.** A 401 from an unknown key
  has no app. Expect an "unidentified" bucket; don't read it as zero.
- **Retention is finite and platform-set.** It bounds which questions are answerable at
  all. Confirm the window before building a 30-day report.
- **It can't fix data already captured badly.** The one that matters most.

## An honest word about validation

The package is labelled **UNVALIDATED**, and here the labelling is worth reading
carefully rather than skipping.

An earlier internal build did confirm the platform's global analytics captures real
traffic and can be queried per route: a two-request window was retrieved and matched what
had been sent. That establishes **the pipe works.**

It establishes almost nothing about this package's actual claims. Two requests from one
app demonstrates nothing about whether per-app attribution is usable across four hundred
integrations. And path templating — the check that matters most, the one whose failure is
unrecoverable — was never tested at all.

So: the mechanism is sound and the reasoning is, I think, correct. But
[`verify.sh`](./gateway/verify.sh) can only verify the request path and seed a labelled
traffic pattern; it prints the queries to run next and tells you plainly that exit 0 does
not mean analytics is verified. The three checks that matter are manual, because analytics
is capture-then-query and no exit code can stand in for looking.

The [validation record](./validation/gateway-validation.yaml) spells out exactly which is
which. I'd rather you knew.

## Try it

Full package — spec, agent prompt, the twelve-chart catalogue, tests — in
[`solutions/04-analytics/`](./).

Start with [`charts.md`](./charts.md). It's the deliverable; the gateway configuration
exists to make those queries answerable.

Then go and check one thing today, before you read anything else: **ask your analytics
for a per-route breakdown, and look at whether your identifier routes appear as templates
or as a list of individual records.**

If it's a list, you've been accumulating unusable data, and you'll keep accumulating it
until someone changes the spec. Better to know on a Tuesday afternoon than at 3am.
