# Architecture — API Products with enforced quota

The gateway becomes the **policy enforcement point for a commercial model**. It
resolves which app is calling, which product that app bought, and whether that
product's budget for the current window still has room. Your backend service is
unchanged and has no notion of tiers.

The important structural claim: the quota is attached to the **thing you sell** (a
product), not to a route, an IP, or a service. That's what makes a tier enforceable
rather than aspirational.

---

## The request path

```
┌────────┐      ┌───────────────────────────────────────────────────┐   ┌──────────┐
│ Client │      │                     Gateway                       │   │ Upstream │
└───┬────┘      │                                                   │   └────┬─────┘
    │           │                                                   │        │
    │ GET /posts                                                   │        │
    │ apikey: <client id>                                           │        │
    ├──────────►│  ┌─────────────── helix-auth ─────────────────┐   │        │
    │           │  │ validate + key-auth                         │   │        │
    │           │  │ resolve the CREDENTIAL by its key           │   │        │
    │           │  │ attach the consumer + its subscriptions     │   │        │
    │   401     │  │ (does NOT check the app's secret)           │   │        │
    │◄──────────┼──┤ unknown key ──────────────────────────────► │   │        │
    │           │  └──────────────────┬──────────────────────────┘   │        │
    │           │                     ▼                             │        │
    │           │  ┌────────── product resolution ───────────────┐   │        │
    │           │  │ a SHARED step, before the access phase      │   │        │
    │           │  │                                             │   │        │
    │           │  │ of the products this app subscribes to,     │   │        │
    │           │  │ take those covering this route's service_id │   │        │
    │           │  │ and pick the TOP-RANKED one                 │   │        │
    │   403     │  │                                             │   │        │
    │◄──────────┼──┤ no covering product, or no service_id ────► │   │        │
    │           │  └──────────────────┬──────────────────────────┘   │        │
    │           │                     ▼                             │        │
    │           │  ┌────────── api-product-enforcer ─────────────┐   │        │
    │           │  │ consume ONE unit of THAT product's quota     │   │        │
    │           │  │                                             │   │        │
    │           │  │ under quota → forward, attributed           │   │        │
    │   429     │  │ over quota  → 429 {"error":"quota exceeded"} │   │        │
    │◄──────────┼──┤ backend down + fail_close → 503             │   │        │
    │           │  └──────────────────┬──────────────────────────┘   │        │
    │           │                     └──────────────────────────────┼───────►│
    │   200     │                                                   │◄───────┤
    │◄──────────┴───────────────────────────────────────────────────┴────────┘
```

Four distinct rejection points, and they are worth being able to tell apart because
they look similar in a dashboard and mean entirely different things:

| Status | Meaning | Where to look |
|---|---|---|
| **401** | The gateway doesn't know who you are | The `apikey` header — is it the credential *key*, not the secret? |
| **403** | It knows who you are, but there's no product covering this route — or the route has no `service_id` | The app's subscription map; the route's service id |
| **429** | It knows who you are, it found your product, and your window is spent | Nothing is wrong. This is the system working. |
| **503** | The quota backend is unreachable and `error_policy` is `fail_close` | `plugin_attr.api-product-enforcer` |

## Execution order

Plugins run by **priority**, not in the order they appear in the document. The
dependency chain here is strict:

| Order | Step | Produces | Consumes |
|---|---|---|---|
| 1 | `helix-auth` (validate, key-auth) | the resolved credential and its product subscriptions | the `apikey` header |
| 2 | product resolution *(shared platform step)* | the single product this request will be metered against | step 1's subscriptions + the route's `service_id` |
| 3 | `api-product-enforcer` | a consumed quota unit, or a 429 | step 2's resolved product |
| — | `request-id` | `X-Request-Id` | — |
| — | analytics *(platform-global)* | per-request telemetry attributed to the app | step 1's identity |

**Step 3 can only work if step 1 produced a subscription.** This is the whole reason
`helix-auth` matters rather than raw `key-auth`: `key-auth` completes step 1's
authentication but not its subscription resolution, so step 2 finds nothing and step
3 returns 403 on every request. The configuration looks correct; the enforcer simply
has nothing to enforce against.

It's also why analytics can report quota consumption *per app* rather than per IP —
identity resolved at step 1 is what every downstream layer reads. See
[solution 04](../04-analytics/).

## The commercial model, precisely

```
Developer  ──────►  App  ──────►  { Product: rank, Product: rank }
(a Consumer)     (a Credential)         │
                       │                └──►  Product = APIs + QUOTA
                 key + secret                       │
                       │                            └──► limit, interval,
                  the key goes in                        interval_unit,
                  the apikey header                      quota_key_scope
```

Four properties follow, and each one is a common misunderstanding:

**Quota lives on the product.** Not the route, not the service. That's what makes it
a commercial artefact: changing what a tier is worth is a product edit, not a
deployment.

**Quota counts per app by default.** A developer with three apps gets three
independent buckets. This is usually correct — their staging integration misbehaving
should not spend their production budget. `quota_key_scope: developer` pools them,
and that's a real trade-off rather than a tidier default: pooling means one
misbehaving app of theirs *can* starve their production traffic.

**Two keys on one app share one bucket.** Isolation is per credential. This is the
single most common false alarm when testing — two keys from one app makes correct
isolation look broken, which is why [`verify.sh`](gateway/verify.sh) refuses to run
with the same key twice.

**One product is evaluated per request, and there is no fallback.** Of the products
an app subscribes to, only those covering this route's `service_id` are candidates,
and only the **top-ranked** candidate is evaluated. When its window is spent, the
request 429s. It does *not* spill into a second subscribed product.

Rank is a routing decision, not a chain of budgets. If a 429 arrives sooner than you
expected, the usual cause is an app subscribed to something you'd forgotten about at
a higher rank.

## Where the quota is actually counted — and why that's off-route

`api-product-enforcer` accepts exactly two fields: `error_policy` and
`ctx_namespace`. It does **not** accept a backend.

```
gateway/api-spec.yaml                    the gateway's config.yaml
────────────────────────                 ─────────────────────────────────────
api-product-enforcer:                    plugin_attr:
  error_policy: fail_close                 api-product-enforcer:
                                             quota_policy: local | redis
  ← what to do when the                      redis_host: ...
    backend is unreachable                   ← WHERE the counter lives
```

The consequence is severe and invisible from the route:

> **Default `quota_policy` is `local`, which counts in each gateway node's own
> memory.** On a three-node gateway, a product with a 1,000/min quota serves roughly
> **3,000/min** — each node independently believes it is under the limit.

You will not observe this in a single-node test environment. You will observe it in
production, as a quota that appears not to work, and you will look for the cause in
the route configuration where it does not exist.

**More than one node → `quota_policy` must be `redis`.**

Note the inconsistency with `limit-count`, which *does* take `policy` and
`redis_host` on the route. That difference is real, and it's what leads people to
add Redis settings to the enforcer where they're rejected.

## Native vs custom

Everything here is native configuration. **No custom code is required, and writing
any would be actively harmful.**

| Requirement | How it's met | Why not custom |
|---|---|---|
| Identify the caller | `helix-auth` validate/key-auth | Credential storage lives in the control plane. |
| Resolve which product applies | the platform's shared product-resolution step | Rank ordering, service coverage and subscription state are platform state, not request state. |
| Count and enforce | `api-product-enforcer` | Distributed counting with correct window semantics is genuinely hard. A custom counter is where off-by-one-window and race-condition bugs live. |
| Attribute a disputed 429 | `request-id` + platform analytics | — |

The temptation to write custom code here usually takes one of two forms, and both
are mistakes:

- **A custom limiter keyed on something clever.** Whatever you key it on, you now
  have two systems counting, disagreeing under load, and no single answer to "what is
  this customer's remaining budget?"
- **Custom logic to fall back into a second product when the first is spent.** This
  sounds helpful and destroys the commercial model: a tier whose limit can be
  exceeded by subscribing to another tier isn't a limit.

## When to use this

Use it when:

- **You sell tiers and want them to be a technical difference**, not just a price
  difference. This is the primary case. A quota is what converts a contract line into
  an enforceable promise.
- **One caller can hurt everyone.** The quota's real product is a bounded blast
  radius.
- **You're provisioning for an unbounded worst case.** Bound it, then provision for
  the sum of what you sold. (Check that sum against your capacity — if it exceeds it,
  you've oversold, and the quota surfaces that as 429s rather than an outage. Better,
  but still worth knowing.)
- **You need per-app attribution** for chargeback, incident response, or upgrade
  conversations.
- **You're building toward a marketplace or self-serve onboarding.** The product is
  the unit a partner subscribes to; without one there is nothing to list.

Don't use it when:

- **Budget headers on the response are a hard requirement.** The enforcer emits no
  `X-RateLimit-*` and no `Retry-After`. If a partner contract requires them, that's
  `limit-count` with `show_limit_quota_header`, and you accept a different key.
- **You need sub-second burst shaping.** Quota counts requests within a window.
  Smoothing arrival rate or capping concurrency is a different control — `limit-conn`
  for in-flight requests.
- **The limit should be per end user.** The unit here is the app. The platform has no
  notion of your application's users.
- **Request cost varies wildly across endpoints.** Every request consumes one unit,
  so a cheap read and a 30-second report cost the same. Split into separate products
  per endpoint group, or the quota misprices your expensive paths.
- **There's no commercial model and you just want a global ceiling.** A plain
  `limit-count` is simpler; you don't need products.
- **You can't identify callers yet.** Metering requires identity. Start with
  [solution 01](../01-oauth-jwt/).

## Prerequisites

- The API exists, is deployed to an environment, and **the route has a
  `service_id`.** Without one the enforcer returns 403 regardless of subscription.
- `helix-auth` and `api-product-enforcer` exist in your org — confirm with
  `get_plugin_config`.
- Products created **and deployed to the environment**. Creating them isn't enough.
- A developer with **two apps**, each subscribed to a different product, so you can
  prove isolation rather than merely prove a limit exists.
- If the gateway runs more than one node: `quota_policy: redis` in
  `plugin_attr.api-product-enforcer`.

## Failure behaviour

| Condition | Result | Reaches upstream? |
|---|---|---|
| No `apikey` header | 401 | No |
| Unknown key | 401 | No |
| App subscribed to no product covering this API | 403 | No |
| Route has no `service_id` | 403 | No |
| Resolved product has no `quota` object | 403 | No — and note this is *not* "unlimited" |
| Product quota window exhausted | 429 `{"error":"quota exceeded"}` | No |
| Product `limit: -1` | passes, uncounted | Yes |
| Quota backend unreachable, `fail_close` (default) | 503 | No |
| Quota backend unreachable, `fail_open` | passes, unmetered | Yes |

Two rows deserve attention.

**"Resolved product has no quota object → 403."** People reason that a product
without a limit means no limit. It means no configuration, and under `fail_close`
that's a rejection. Unlimited is `limit: -1`.

**The `fail_open` / `fail_close` row is a commercial decision disguised as a config
field.** `fail_close` protects the accuracy of your metering at the cost of
availability during a backend incident. `fail_open` protects availability at the cost
of serving traffic you can't account for — and you may not notice it happened.
Whichever you choose, choose it deliberately, and make sure whoever owns the revenue
line knows which one is live.
