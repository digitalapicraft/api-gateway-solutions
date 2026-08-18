# Business need — analytics that answers questions

## The situation

You already have analytics. That's what makes this different from the other solutions
in this library: nothing is missing, nothing needs buying, and the data has been
accumulating faithfully since the day the gateway went in.

And it still can't tell you what you need to know.

> *"At 3am on Tuesday something hammered our orders endpoint. On-call spent forty
> minutes trying to work out which of our 400 integrations it was. The dashboard showed
> a spike. It could not tell us whose spike it was, because every row was an IP address
> — and our partners share NAT gateways, run in clouds, and rotate egress addresses.*
>
> *We have a chart that tells us something happened and no way to act on it."*

The failure isn't a missing feature. Every one of those requests was captured
correctly. The problem is that analytics can only group by what the gateway **knew at
request time**, and nobody had framed "should this route resolve identity?" as an
observability decision.

The costs are the kind that don't appear on a line item:

- **Incident attribution takes people, not queries.** Forty minutes of on-call time per
  incident, at the worst hour, on work that should be a single question.
- **Chargeback is impossible**, so heavy users are subsidised by light ones and nobody
  knows by how much.
- **Upgrade conversations run on hunches.** You suspect a partner has outgrown their
  tier. You cannot show them.
- **Broken partner integrations go unnoticed.** An integration that started failing
  every call at 02:14 will often not be reported until their business hours — and
  sometimes not at all, if the partner quietly deprioritises it.
- **Quiet churn is invisible.** A partner who *stopped* calling doesn't generate an
  alert. It looks like nothing.
- **Nobody trusts the dashboard**, so nobody looks at it, so the one time it would have
  helped, it wasn't open.

## What changes

Not the analytics. **The request path**, so that the analytics already being captured
can answer something.

| Question | Before | After |
|---|---|---|
| "Which integration caused the 3am spike?" | An IP address, and 40 minutes | An app and a developer, by name, in one query |
| "Which partner's integration is broken?" | You find out when they call you | An app failing every call since 02:14 — you call them |
| "Who should we bill for this traffic?" | Unanswerable | Per-app request counts |
| "Has this partner outgrown their tier?" | A hunch | Peak consumption as a percentage of their limit |
| "Is p99 on this route getting worse?" | An API-wide average that describes nothing | Per-route percentiles, with sample counts |
| "Show me *that* failing request" | Not possible | One correlation id, joined to your backend's own logs |
| "Who stopped calling us?" | Silence | A week-on-week diff |

## The mechanism that matters

The whole solution is three configuration decisions, and one property they share.

**Identity resolved** → rows attribute to an app rather than an IP. This single decision
is the difference between analytics you *query* and analytics you *scroll*.

**Paths templated** → `/orders/{orderId}` is one row you can trend, not one row per
order. Get this wrong and a per-route breakdown becomes a list of individual customer
records, per-route p99 is computed from one sample per row, and cardinality grows with
your order volume forever.

**A correlation id, logged downstream** → the bridge from "3% of calls failed" to "*this*
call failed, for *this* partner, at *this* time", and onward into your backend's logs
because the header is forwarded.

And the property that makes this urgent rather than merely tidy:

> **All three must be true before the data you want to query is generated.**

Analytics cannot retroactively attribute traffic captured without identity. It cannot
collapse literal paths into a template after the fact. Yesterday's anonymous rows stay
anonymous forever.

So this isn't a backlog item that gets cheaper to do later. It is one of the few
configuration decisions where **delay has a permanent cost** — every day you wait is a
day of data you can never ask questions of. The corresponding good news: fixing it fixes
things going forward *immediately*, with no migration and no backfill. Just a line under
the old data.

## Business outcomes

**Incident attribution drops from forty minutes to one query.** The direct saving is
on-call time at the worst hour; the real saving is the decisions made faster during an
incident because you know who to call.

**Broken partner integrations get caught before the partner reports them.** An app
failing 100% of calls is visible immediately. Calling a partner to tell them their
integration broke — before they noticed — is a remarkably good customer experience, and
it costs one query.

**Upgrade conversations get evidence.** An app consistently above 80% of its Free or Pro
limit is a qualified lead with a number attached. This is usually the chart that gets
analytics work funded, and it is the argument to lead with. (It needs
[solution 03](../03-api-products/) — quota consumption requires a quota.)

**Under-utilised committed accounts become visible.** An Enterprise account nowhere near
its quota is either over-provisioned or never fully integrated. The first is fragile
revenue at renewal; the second is churn nobody has spotted. Neither shows up in a
revenue report.

**Chargeback becomes possible.** Per-app request counts are the input to attributing
infrastructure cost to the customers generating it.

**Capacity planning gets a real basis.** Peak-to-median traffic ratio, per route, with
the error rate overlaid — so you can tell a capacity problem (errors rise *with* traffic)
from a deployment problem (errors rise *without* it).

**The dashboard becomes something people read.** Five panels that drive decisions beat
twenty that decorate a wall. [`charts.md`](charts.md) proposes the five and argues for
keeping the other seven investigative.

## What this does not buy you

Stated plainly, because the boundary here is easy to assume away:

- **It does not capture request or response bodies.** By design — capturing bodies means
  capturing customer data. You learn which app called what and what came back, never
  what was in the payload.
- **It does not give per-hop latency inside your services.** Latency is measured at the
  edge. It includes your upstream's total time but cannot decompose it. That's
  distributed tracing, and `X-Request-Id` is the thread that joins the two datasets.
- **It is not alerting.** This is query-and-chart. Real-time threshold alerting is a
  different tool.
- **It cannot fix data already captured badly.** The most consequential limitation in the
  package, and the reason this is worth doing before you onboard at scale.
- **It cannot attribute genuinely anonymous traffic.** If a route must stay unauthenticated,
  attribution on it is impossible in principle. Volume, latency and error rate still
  work; per-app charts never will.
- **Retention is finite and is a platform setting.** It bounds which questions are
  answerable at all — confirm your window before building a 30-day report.
- **A chart nobody acts on is an ornament.** No configuration fixes that. The habit worth
  building: when a chart moves, write down what you did about it. A chart with no history
  of action can be deleted.
- **No numbers are claimed here.** The forty-minute attribution and the 400 integrations
  are the *shape* of a common situation, not measurements from your estate. What this
  document quantifies is the mechanism — what becomes answerable, and what stays
  permanently unanswerable if you wait.

## Success criteria

You'd call this done when:

- "Which app caused this?" is a single query, and the answer is a name.
- Every route you care about attributes to an app rather than an IP — and you know
  explicitly which routes don't, because you asked.
- A per-route breakdown shows **routes**, not entity ids. Verified by looking, not
  assumed.
- The same `X-Request-Id` appears in the gateway's data *and* in your backend's logs for
  the same call. This is the half people skip.
- You can name the apps within 10% of their quota, and someone owns following up.
- You can name the apps that stopped calling this week.
- Per-route p99 is a number you'd act on, with a sample count you'd trust.
- Your standing dashboard is five panels, and when one moves, somebody does something —
  and writes down what.
