# Your Enterprise tier is a line in a contract

Two problems, and almost nobody notices they're the same problem.

**The first one wakes you up.** On Black Friday your checkout API is down for 22
minutes. It isn't traffic — it's one integration partner whose retry loop has no
backoff, sending 40,000 requests a minute at an endpoint sized for 3,000. Every
other customer gets 503s. You find out from Twitter. The post-mortem action item
says "add rate limiting", and it sits in the backlog for a year because nobody can
say what the limit should be.

**The second one costs you money quietly.** You sell an Enterprise tier that
promises higher throughput. There is no technical difference between it and the free
tier. Sales knows. Some customers suspect. Nobody upgrades *for throughput*, because
throughput isn't really what they're buying — and when an Enterprise customer has a
capacity problem, your answer is "we'll look into it".

Same root cause: **every caller shares one undifferentiated pool, and the gateway has
no idea who is calling or what they bought.**

## Why a global rate limit doesn't fix it

The obvious answer is a rate limit on the endpoint. It doesn't work, and it's worth
being precise about why, because it's the thing most teams try first.

A global limit protects your backend by rejecting *whoever happens to be calling when
the limit is hit.* Your partner's runaway retry loop fills the bucket, and your other
eleven customers get the 429s. You've converted one partner's bug into everyone's
degraded service — less severe than an outage, but the same shape.

What you actually want is for **the offending app to exhaust its own budget** while
everyone else carries on unaffected. That's a different property, and it requires the
gateway to know two things a rate limit doesn't: *which app* is calling, and *what
that app bought.*

## The model, which is where people go wrong

This doesn't transfer from other gateways, so it's worth four lines:

| Concept | What it is |
|---|---|
| **Developer** | The organisation consuming your API |
| **App** | One integration, with its own key and secret |
| **Product** | A bundle of APIs plus a quota — **the thing you sell** |
| **Subscription** | An app subscribes to products, each with a rank |

The load-bearing sentence: **quota lives on the product and is counted per app.**

Not per IP. Not per developer. And *never* keyed on `consumer_name`, which is the
reflex a general-purpose gateway model brings and which meters the wrong thing here.

That the quota lives on the *product* is what makes it a commercial artefact rather
than an operational one. Changing what a tier is worth is a product edit, not a
deployment. That's the whole trick.

One consequence to internalise now, because it will confuse you later: **a developer
with three apps gets three independent buckets.** That's usually right — their staging
integration misbehaving shouldn't spend their production budget. If you want them
pooled, `quota_key_scope: developer` does it, but understand what you're choosing:
pooling means one of their apps *can* starve their own production traffic.

## The configuration is four lines

```yaml
# identity — resolves the app AND its product subscriptions
helix-auth:
  mode: validate
  validate_auth_type: key-auth
  apikey:
    source: header
    key: apikey

# enforcement — meters against whichever product was resolved
api-product-enforcer:
  error_policy: fail_close
```

That's genuinely the entire enforcer configuration. It accepts `error_policy` and
`ctx_namespace`, and nothing else.

Then the products, which is where the interesting decisions live:

| Product | Limit | Who it's for |
|---|---|---|
| Free | 60/min | Evaluation — deliberately unusable for production |
| Pro | 1000/min | Normal production, ~2× a healthy integration's p95 |
| Enterprise | 10000/min | Committed accounts, backed by a contract |
| Internal | −1 | First-party: unmetered, still authenticated and attributed |

Two design rules generalise, and they're commercial rather than technical.

**Free must be unusable for production.** If it's generous enough to build on, nobody
upgrades and you've given the product away. Its job is to let someone *try* the API.

**Enterprise must match a contract.** It's the one tier where the quota is a promise
you made in writing, and it's the number a customer will quote at you during an
incident. Don't derive it by scaling Pro.

And one that trips people up: **the window shapes behaviour as much as the limit.** A
per-minute window *absorbs* bursts; a per-second window *shapes* them. Contracts
written in requests-per-*day* are the worst of both — one app spends the whole day's
budget in 40 seconds and then goes dark until midnight, which is neither protection
nor a usable service.

## Ask for it instead

Describe the outcome and let the agent fetch your org's real schemas:

```text
Set up tiered throughput on my Orders API using API Products, so one partner's app
can never exhaust capacity for the others.

Identify the caller with helix-auth in validate mode, key-auth type, reading the
credential key from the "apikey" header. Use helix-auth, not the raw key-auth plugin
— I want the app's product subscription resolved, not just a static key checked.

Create four API Products bundling this API, each with a quota: Free 60/min, Pro
1000/min, Enterprise 10000/min, Internal with limit -1. Every product must carry a
quota object — a product without one is a 403, not "unlimited".

Enforce it with api-product-enforcer, error_policy fail_close. Confirm the route has
a service_id — without one the enforcer returns 403 regardless of subscription.

Do NOT key any rate limit on consumer_name, and do NOT put Redis settings in the
api-product-enforcer block — that plugin only accepts error_policy and ctx_namespace.

Show me the spec, dry-run it, and wait for me to confirm before deploying.
```

Then the part that makes it demonstrable rather than merely deployed:

```text
Create a test developer with TWO SEPARATE APPS — one subscribed to Free, one to Pro
— and give me both keys. They must be different apps: two keys on the same app share
one quota bucket and would not prove isolation.

Then give me a curl loop showing the Free app getting 429 after 60 requests while the
Pro app still gets 200s in the same window.
```

Those two "do NOT" lines aren't decoration. This solution has more platform-specific
constraints than anything else in the library, precisely because a general-purpose
model brings generic rate-limiting habits and almost every one of them is wrong here.
The [full prompt](./helix-agent-prompt.md) has a table explaining each constraint and
what goes wrong without it.

## The thing that will silently not work

Here is the failure I'd most like you to remember, because it's invisible from the
configuration you just read.

**`api-product-enforcer` does not configure the quota backend.** The `local`-vs-`redis`
choice lives in `plugin_attr.api-product-enforcer` in the *gateway's* `config.yaml`.

The default is `local`, which counts in each node's own memory.

So on a three-node gateway, a product with a 1,000/min quota serves roughly
**3,000/min**. Each node independently believes it's under the limit. Your quota is
off by a factor of your node count, and nothing about it is wrong in the route config.

You will not see this in a single-node test environment. You'll see it in production,
as a quota that "doesn't seem to work", and you'll spend the afternoon reading the
route configuration where the answer isn't.

**More than one node → `quota_policy` must be `redis`.**

There's an infuriating detail that makes this worse: `limit-count`, the other limiter,
*does* take `policy` and `redis_host` on the route. So the instinct to put Redis
settings next to the enforcer is well-founded by analogy, and it's rejected — or
worse, it validates and you've learned nothing.

## Test the case everybody skips

`verify.sh` asserts five things:

1. No key → 401
2. Unknown key → 401
3. Valid Free key → 200
4. Past the window → 429 `{"error":"quota exceeded"}`
5. **A second app on a different product, at that same moment → still 200**

Cases 1–4 prove a rate limit exists. Any limiter does that. **Case 5 proves the limit
is scoped to the offending app rather than to your API**, which is the entire business
case and the only thing distinguishing this from the global limit that doesn't work.

The two keys must come from **two separate apps**. Quota counts per credential, so two
keys on one app share a bucket and correct isolation looks broken. This is the most
common false alarm in the whole solution, which is why
[`verify.sh`](./gateway/verify.sh) refuses to run if you pass the same key twice.

## What your partners will actually see

```http
HTTP/1.1 429 Too Many Requests
content-type: application/json

{"error":"quota exceeded"}
```

That's it. **No `Retry-After`. No `X-RateLimit-*` headers.** Not on the rejection, and
not on successful responses either — so a client cannot track its own consumption from
responses at all.

Two things follow, and both are documentation work rather than configuration:

**Publish the retry contract**, since the response can't carry it. Tell integrators
the window length and tell them to back off exponentially *with jitter*. Without
jitter, every throttled client retries at the same instant at the top of each window,
and you've built a thundering herd on a schedule.

**Surface remaining quota in the portal**, not in headers. The number exists
server-side; it just isn't in the response.

If a partner contract genuinely requires budget headers, that's `limit-count` with
`show_limit_quota_header: true` — a different limiter with a different key. Don't try
to make the product enforcer do it.

## Why there's a second limiter on the search route

The spec puts a `limit-count` of 20/60s keyed on `remote_addr` on `POST /orders/search`,
on top of the product quota. Worth explaining, because the reasoning generalises to any
expensive endpoint.

The product quota is per app, and **it only applies to traffic that authenticated.**
Anything failing auth never reaches the enforcer. So however well-tuned your quota is,
it offers no protection against an unauthenticated flood hitting your reporting store.

The per-IP layer does, and it's deliberately *not* consumer-scoped, because per-caller
metering is already handled above.

One trap: **if the gateway sits behind a load balancer you need `real-ip` in front.**
Otherwise every caller presents the balancer's address, your per-IP ceiling becomes a
global 20/min cap on the endpoint, and you've built a self-inflicted outage that
triggers on your next traffic spike. Verify from two source addresses — if throttling
one throttles the other, `real-ip` is missing.

## The arithmetic nobody does

Here's the cost argument, and the check that goes with it.

Without a per-caller bound, you must provision against what a caller *might* do. With
one, you provision against the sum of what you *sold*. That's real, and it's usually
what gets this funded.

But: **add up the committed quotas across the tiers you've actually sold, and compare
that with what your upstream can take.**

If the sum exceeds capacity, you have oversold. The quota will surface that as 429s to
customers rather than as an outage — which is a better failure, and it is still a
failure. Better to find it in a spreadsheet than in an incident.

(The illustrative tiers in this package sum to 11,060/min against an illustrative
3,000/min ceiling. That's deliberate, and it's exactly the check to run for real.)

## What it doesn't do

- **It's not per-request pricing.** The quota counts requests. A cheap read and a
  30-second report each consume one unit. If cost varies wildly by endpoint, split into
  separate products per endpoint group or the quota misprices your expensive paths.
- **It's not burst shaping.** A caller can spend a minute's budget in two seconds
  unless the window is short.
- **It doesn't meter your end users.** The unit is the app. Per-end-user limits are
  application logic.
- **`error_policy` is a commercial decision disguised as a config field.**
  `fail_close` returns 503 during a quota-backend outage, protecting metering accuracy
  at the cost of availability. `fail_open` protects availability by serving traffic you
  can't account for — and you may not notice it happened. Both are defensible. Make
  sure whoever owns the revenue line knows which one is live.
- **A product with no quota object is a 403, not "unlimited".** People reason that no
  limit set means no limit. It means no configuration. Unlimited is `limit: -1`.

## The second-order effects

Once every request is attributed to an app with a budget, things become possible that
weren't:

**Upgrade conversations get data.** An app repeatedly hitting its Free ceiling is a
qualified lead with a number attached. An Enterprise account never approaching its
quota is either over-provisioned or not really integrated yet — and both are worth
knowing. Neither signal exists without metering.
[Solution 04](../04-analytics/) has the queries.

**Incident attribution drops from hours to seconds.** "Which integration caused this?"
becomes a query rather than a log hunt with IP addresses at 3am.

**Chargeback becomes possible.** Per-app request counts are the input to attributing
infrastructure cost to the customers generating it. Today heavy users are subsidised by
light ones, and nobody knows by how much.

**A marketplace becomes reachable.** The product is the unit a partner subscribes to.
Without products there's nothing to list and nothing to self-serve onto.

## Try it

The full package — spec, four products, agent prompt, tests, and an honest record of
what's been validated — is in [`solutions/03-api-products/`](./).

Start with [the agent prompt](./helix-agent-prompt.md), then run
[`verify.sh`](./gateway/verify.sh) against your own environment and treat case 5 as the
gate.

The package is labelled **UNVALIDATED**: the enforcement model, including the isolation
case, was proven in an earlier internal build, but this particular document hasn't been
dry-run. The [validation record](./validation/gateway-validation.yaml) spells out what
was and wasn't established — including that nothing here establishes how your cluster
counts, which is the one that bites.

Two problems, one cause. The outage and the unenforceable pricing page are the same
missing fact: the gateway didn't know who was calling or what they'd paid for.
