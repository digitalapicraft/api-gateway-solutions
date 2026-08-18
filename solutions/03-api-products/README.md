# Solution 03 — API Products: sell tiers you can actually enforce

**Bundle APIs into products with quotas. One partner's runaway retry loop
exhausts their own budget and nobody else's.**

| | |
|---|---|
| **Setup time** | ~20 minutes |
| **Difficulty** | 🟢 Beginner |
| **Needs** | An API deployed to an environment · a developer with **two** apps to test with · Redis if the gateway runs more than one node |
| **Plugins** | `helix-auth` (validate / key-auth) · `api-product-enforcer` · `request-id` · `cors` · route-scoped `limit-count` |
| **Build it with** | 🤖 **[the Helix Agent](helix-agent-prompt.md)** — recommended · or import [`gateway/api-spec.yaml`](gateway/api-spec.yaml) + [`products.json`](gateway/products.json) |
| **Assets** | ✅ [Agent prompt](helix-agent-prompt.md) · ✅ [Architecture](architecture.md) · ✅ [Business need](business-need.md) · ✅ [Spec + products](gateway/) · ✅ [Tests](tests/) · ✅ [Validation](validation/) · ✅ [Infographic](infographic.md) · ✅ [Manifest](solution.yaml) |

---

## The problem

> *"On Black Friday our checkout API was down for 22 minutes. It wasn't traffic — it
> was one integration partner whose retry loop had no backoff. They sent 40,000
> requests a minute at an endpoint sized for 3,000. Every other customer got 503s.
> We found out from Twitter.*
>
> *And the part that stings: we sell an 'Enterprise' tier that promises higher
> throughput. There is no technical difference between it and the free tier. It's a
> line in a contract."*

Three symptoms, one root cause:

1. **The noisy neighbour.** One badly behaved app consumes capacity provisioned for
   everyone. Blast radius: 100% of your consumers.
2. **The undifferentiated plan.** Sales sold "Enterprise" with a throughput promise.
   Engineering had no mechanism to make that promise real, so the tiers differ only
   in price.
3. **The invisible ceiling.** Nobody — not the customer, not support, not on-call —
   knows the actual per-caller limit, because the limit only exists as the point
   where the backend falls over.

**Root cause:** every caller shares one undifferentiated pool, and the gateway has
no idea *who* is calling or *what they bought*.

## Business need

Full version: [`business-need.md`](business-need.md).

| Dimension | Without product quota | With this solution |
|---|---|---|
| **Availability** | One app's bug is an outage for every consumer. Blast radius = 100%. | Blast radius = the offending app. |
| **Revenue protection** | Checkout traffic competes with batch and free-tier traffic for one pool. | Committed accounts get the throughput they pay for. |
| **Commercial** | "Enterprise tier" is a contract line with no enforcement, so there's no reason to upgrade. | The tier is a real, enforced difference. The quota becomes an upgrade trigger. |
| **Infra cost** | Provisioned for the worst-behaved caller's peak. | Provisioned for the sum of committed quotas. |
| **Attribution** | "Which partner caused this?" takes a log hunt. | Every request is attributed to an app and a developer. |

**The mechanism:** an unbounded worst case forces you to provision for a caller who
might do anything. A bounded one lets you provision for the sum of what you sold.

## The model — read this before configuring anything

This is where most people go wrong, because the mental model from other gateways
does not transfer.

| Concept | In Helix | Underneath |
|---|---|---|
| **Developer** | The organisation or person consuming your API | a Consumer |
| **App** | One integration belonging to a developer, with its own key/secret | a Credential |
| **Product** | A bundle of APIs plus a quota — the thing you sell | a product document |
| **Subscription** | An app subscribes to products, each with a **rank** | a `{productId: rank}` map |

**Quota is attached to the Product and counted per App.** Not per IP. Not per
developer. And never on `consumer_name` — that's the generic-gateway reflex, and it
meters the wrong thing here.

A developer with three apps gets **three independent buckets** by default. That's
usually what you want: their staging integration misbehaving shouldn't spend their
production budget. To pool a developer's apps into one bucket, set
`quota_key_scope: developer` on the product.

Two keys on the *same* app always share one bucket. This matters for testing — see
§ *Testing*.

## How a request flows

```
Client
  │  apikey: <the app's client id>
  ▼
helix-auth  (validate + key-auth)
  │  resolves the credential → attaches the consumer
  │  key-auth does NOT check the app's secret — only generate mode does
  ▼
product resolution   (a shared step, before the access phase)
  │  picks the TOP-RANKED product the app subscribes to that ALSO
  │  covers this route's service_id
  │  no match → 403, before quota is considered at all
  ▼
api-product-enforcer
  │  consumes one unit of THAT product's quota
  │  under quota → forward, attributed to the app and developer
  │  over quota  → 429 {"error":"quota exceeded"}
  ▼
Upstream
```

**One product is evaluated per request, and there is no fallback.** If the
top-ranked product's window is exhausted, the request 429s — it does not spill into
a second product the app also subscribes to. Rank is a routing decision, not a chain
of budgets.

### Tier design that works

| Product | `limit` | `interval_unit` | Who it's for |
|---|---|---|---|
| Free | 60 | minute | Evaluation — low enough that production use is impossible |
| Pro | 1000 | minute | Normal production, ~2× a healthy integration's p95 |
| Enterprise | 10000 | minute | Committed accounts, backed by a contractual number |
| Internal | −1 | — | First-party services: unmetered, still authenticated and attributed |

`limit: -1` means unlimited — the enforcer marks the request absorbed and skips the
counter entirely.

Two design notes worth more than the numbers:

- **Free must be unusable for production.** If it's generous enough to build on,
  nobody upgrades and you've given the product away.
- **Pick the window with intent.** A per-minute window **absorbs** bursts; a
  per-second window **shapes** them. Contracts written in requests/*day* are the
  worst of both: one app can spend the whole day's budget in 40 seconds and then go
  dark until midnight.

Then **add up the committed quotas across the tiers you've actually sold and compare
that with what your upstream can take.** Provisioning for the sum of committed
quotas is the cost saving here — but only if that sum is below your capacity. If it
isn't, you've oversold, and the quota surfaces that as 429s instead of an outage.
Better, but still worth knowing.

## Build it with the Helix Agent

Recommended path. Full prompt with all the constraints:
[`helix-agent-prompt.md`](helix-agent-prompt.md).

```text
Set up tiered throughput on my Orders API using API Products, so one partner's app
can never exhaust capacity for the others.

Identify the caller with helix-auth in validate mode, key-auth type, reading the
credential key from the "apikey" header. Use helix-auth, not the raw key-auth
plugin — I want the app's product subscription resolved, not just a static key
checked.

Create four API Products bundling this API, each with a quota: Free 60/min, Pro
1000/min, Enterprise 10000/min, and Internal with limit -1 for unlimited. Every
product must carry a quota object — a product without one is a 403, not
"unlimited". Deploy all four to staging.

Enforce it with api-product-enforcer, error_policy fail_close. Confirm the route
has a service_id — without one the enforcer returns 403 regardless of subscription.

Do NOT key any rate limit on consumer_name, and do NOT put Redis settings in the
api-product-enforcer block — that plugin only accepts error_policy and
ctx_namespace.

Show me the spec, dry-run it, and wait for me to confirm before deploying.
```

Then, and this part is what makes it demonstrable:

```text
Create a test developer with TWO SEPARATE APPS — one subscribed to Free, one to Pro
— and give me both keys. They must be different apps: two keys on the same app
share one quota bucket and would not prove isolation.

Then give me a curl loop showing the Free app getting 429 after 60 requests while
the Pro app still gets 200s in the same window.
```

The agent will fetch the real plugin schemas from your org, propose the spec, and
stop for your confirmation. See [AGENT-GUIDE.md](../../AGENT-GUIDE.md) for why the
constraints are phrased that way and what to say when the agent reaches for
`limit-count` + `consumer_name` anyway — which it will, because that's the generic
answer.

## Install it directly

```bash
export ORG=<ORG_ID>
export TOKEN=<control-plane bearer token>      # short-lived
export BASE=https://<YOUR_GATEWAY_HOST>/api
H=(-H "authorization: Bearer $TOKEN" -H 'content-type: application/json')

# 1. Import gateway/api-spec.yaml (OpenAPI import, or Agent Mode). It carries
#    helix-auth + api-product-enforcer. Bind your upstream. CONFIRM THE ROUTE HAS
#    A service_id — without one the enforcer 403s regardless of subscription.

# 2. Create the products, then deploy each one to the environment.
jq -c '.products[]' gateway/products.json | while read -r p; do
  curl -s "${H[@]}" -X POST "$BASE/orgs/$ORG/products" -d "$p" | jq -r '.id // .message'
done
curl -s "${H[@]}" -X POST "$BASE/orgs/$ORG/envs/<ENV_ID>/products/<PRODUCT_ID>/deploy"

# 3. Create a developer, then TWO apps, each subscribing to one product
#    (products is a {productId: rank} map). Keep both app keys.

# 4. If the gateway runs more than one node, set quota_policy to redis in
#    plugin_attr.api-product-enforcer in the gateway's config.yaml. This is NOT
#    in the route config and nothing here will remind you.

# 5. Prove it — including isolation
GATEWAY=https://<YOUR_GATEWAY_HOST> \
FREE_KEY=<free app client id> PRO_KEY=<pro app client id> FREE_LIMIT=60 \
./gateway/verify.sh
```

> Revisions must be **INACTIVE** to accept a spec change. If it's live: undeploy
> first, or clone the revision so you keep a rollback target.

## Configuration

Source of truth: [`gateway/api-spec.yaml`](gateway/api-spec.yaml) and
[`gateway/products.json`](gateway/products.json). Two API-wide blocks carry the
solution:

```yaml
# identity — resolves the app AND its product subscriptions
helix-auth:
  mode: validate
  validate_auth_type: key-auth
  apikey:
    source: header
    key: apikey

# enforcement — meters against the resolved product's quota
api-product-enforcer:
  error_policy: fail_close
```

That's the entire enforcer configuration. **It accepts only `error_policy` and
`ctx_namespace`.** If you're reaching for a `policy: redis` or a `redis_host` here,
stop — see the next section.

`error_policy: fail_close` means a quota-backend outage returns 503. Switching to
`fail_open` is a deliberate commercial decision: you're choosing to serve unmetered
traffic during an incident rather than serve errors. Both are defensible. Pick one
knowingly.

## The quota backend is not in this file

**This is the single most common way the solution is deployed wrong, and nothing in
the route config hints at it.**

`api-product-enforcer` takes no backend configuration. The `local`-vs-`redis`
choice and the connection settings live in `plugin_attr.api-product-enforcer` in
the **gateway's `config.yaml`**.

The default is `local`, which counts in each node's own memory. So on a
three-node gateway, a product with a 1,000/min quota serves roughly **3,000/min** —
each node independently believes it's under the limit.

You will not notice this in a single-node test environment. You will notice it in
production, as a quota that seems not to work, and you'll spend the afternoon
inspecting the route config where the answer isn't.

**More than one node → `quota_policy` must be `redis`.**

## What the caller actually sees

Be honest with partners about this, because it's the part that surprises them:

```http
HTTP/1.1 429 Too Many Requests
content-type: application/json

{"error":"quota exceeded"}
```

**`api-product-enforcer` emits no `X-RateLimit-*` headers and no `Retry-After`.** A
client cannot read its remaining quota off a response. Two consequences to design
around:

- **Publish the retry contract in your docs**, since the response can't carry it.
  Tell integrators the window length and tell them to back off exponentially *with
  jitter*. Without jitter, every client retries at the same instant at the top of
  each window and you've built a thundering herd on a schedule.
- **Surface remaining quota in the portal and analytics**, not in headers. See
  [solution 04](../04-analytics/) for the queries.

If you genuinely need budget headers on the response today, that's a `limit-count`
with `show_limit_quota_header: true` — a *different* limiter with a different key.
Don't try to make the product enforcer do it.

## The second layer on the search route

`POST /orders/search` carries a route-scoped `limit-count` of 20/60s keyed on
`remote_addr`, **in addition** to the product quota. This is deliberate, and the
reasoning generalises:

- The product quota is **per app**, and it only applies to traffic that
  authenticated. Anything that fails auth never reaches the enforcer.
- This endpoint hits the reporting store, which is the expensive backend. It needs a
  ceiling per *source*, including from traffic that never authenticates.
- So the key is `remote_addr` — deliberately **not** consumer-scoped, because
  per-caller metering is already handled above.

**If the gateway sits behind a proxy or load balancer you need `real-ip` in front**,
or every caller shares the balancer's address and your per-IP ceiling becomes a
global 20/min cap on the endpoint. That's a self-inflicted outage waiting for a
traffic spike.

Note `limit-count` *does* take its backend on the route (`policy`, `redis_host`) —
unlike the product enforcer. The inconsistency is real; don't let it lead you to
put Redis settings in the enforcer.

## Testing

```bash
GATEWAY=https://<YOUR_GATEWAY_HOST> \
FREE_KEY=<free app client id> PRO_KEY=<pro app client id> FREE_LIMIT=60 \
./gateway/verify.sh
```

Exit 0 means all five held:

| # | Case | Expected |
|---|---|---|
| 1 | No key | `401` |
| 2 | Unknown key | `401` |
| 3 | Valid Free key | `200` |
| 4 | Past the window | `429` `{"error":"quota exceeded"}` |
| 5 | **A second app on a different product, at that same moment** | still `200` |

**Case 5 is the whole point.** Cases 1–4 only prove a rate limit exists — any
limiter does that. Case 5 proves the limit is scoped to the *offending app* rather
than to your API, which is the entire business case. Don't skip it.

The two keys **must come from two separate apps.** Quota is counted per app, so two
keys on one app share a bucket and correct isolation will look broken.
`verify.sh` refuses to run if you pass the same key twice.

Full plan, including the boundary case at exactly the limit and the fail-close
behaviour:
[`tests/test-plan.yaml`](tests/test-plan.yaml).

## Gotchas

Each of these has cost somebody an afternoon.

- **The quota backend isn't on the route.** On more than one node, `quota_policy`
  must be `redis` in `plugin_attr.api-product-enforcer`. Default `local` counts per
  node, so an N-node cluster serves ~N× the quota you sold. See § above.
- **The route needs a `service_id`.** No service id → 403, before quota is even
  considered. Nothing in the plugin config suggests this.
- **A product with no `quota` object is a 403**, not "unlimited". Unlimited is
  `limit: -1`.
- **Use `helix-auth`, not raw `key-auth`.** `key-auth` authenticates but resolves no
  product subscription, so the enforcer 403s every request with nothing in context
  to enforce against. The symptom looks like a subscription problem and is actually a
  plugin choice.
- **Never key a rate limit on `consumer_name`.** Per-caller metering here is the
  product quota, counted on the credential. The only `limit-count` in this design is
  the per-IP one on the search route.
- **`fail_close` is the default**, so a quota-backend outage returns 503. If
  unmetered traffic beats errors for your business, set `fail_open` deliberately —
  and know you're choosing to over-serve during an incident.
- **Key-auth validate does not check the app's secret.** The value in the `apikey`
  header is the credential **key** (client id). For proof of possession, use the
  client-credentials flow — [solution 01](../01-oauth-jwt/).
- **Two keys on one app share one bucket.** A test using two keys from one app will
  look like the quota is broken.
- **Only the top-ranked covering product is evaluated.** If a 429 arrives sooner
  than you expect, check which product actually won — the app may be subscribed to
  something you forgot about at a higher rank.
- **`real-ip` is required in front of the per-IP limiter** if the gateway is behind
  a proxy, or every caller shares the balancer's address.
- **Use `filter_func`, not `vars`,** for conditional route matching — `vars` is
  typed incompatibly between the control plane and the gateway and fails at deploy.
- **Confirm `api-product-enforcer` exists in your org** with `get_plugin_config`
  before designing around it.

## When to use it

Use it when:

- **You sell tiers** and want them to be a real technical difference rather than a
  price difference.
- **One caller can hurt everyone**, and you want the blast radius to be that caller.
- **You're provisioning for a worst case you can't bound.** Bound it, then provision
  for the sum of what you sold.
- **You want per-app attribution** for chargeback, incident response or upgrade
  conversations.
- **You're building toward a marketplace.** The product is the unit a partner
  subscribes to; without it there's nothing to list.

Don't use it when:

- **You need budget headers on the response.** The enforcer doesn't emit them. Use
  `limit-count` if the header is a hard requirement, and accept that it's a
  different key.
- **You need burst shaping at sub-second resolution.** Quota counts requests in a
  window. Shaping concurrency or smoothing arrival rate is a different control —
  `limit-conn` for concurrency, and see the tweak knobs in the agent prompt.
- **The limit should be per end user rather than per app.** Quota counts per
  credential (or per developer). It has no notion of your application's users.
- **There's no commercial model at all** and you just want a global ceiling. A plain
  `limit-count` is simpler and you don't need products.
- **You can't identify callers yet.** Start with [solution 01](../01-oauth-jwt/) —
  metering requires identity.

## Limitations

- **No budget headers.** No `X-RateLimit-*`, no `Retry-After`. The retry contract
  lives in your documentation; remaining quota comes from the portal, not the
  response.
- **One product per request, no fallback.** The top-ranked covering product is
  evaluated; when its window is spent the request 429s rather than spilling into
  another subscribed product.
- **Per-app counting by default.** Two keys on one app share a bucket. Use
  `quota_key_scope: developer` to pool a developer's apps.
- **Multi-node correctness depends on `quota_policy: redis`** in `plugin_attr`,
  which is invisible from this route config.
- **The quota is a request count, not a cost.** A cheap read and an expensive report
  consume one unit each. If cost varies wildly per endpoint, split into separate
  products per endpoint group.
- **`fail_close` trades availability for accuracy** during a quota-backend outage.
  Whichever you choose, you're choosing.
- **No per-end-user metering.** The unit is the app.

Full list: [`solution.yaml`](solution.yaml) § `limitations`.

## Validation status

**Validated against a gateway — imported, dry-run, deployed, and passed `verify.sh` including the isolation check.**

| Stage | Status | Provenance |
|---|---|---|
| Configuration generated | **YES** | [`gateway/api-spec.yaml`](gateway/api-spec.yaml), [`gateway/products.json`](gateway/products.json) |
| Local validation | **PASS** | [`validation/local-validation.yaml`](validation/local-validation.yaml) |
| Gateway dry-run | **PASS** | Non-destructive validation on a gateway. |
| Gateway deployed | **DEPLOYED** | Two products, two apps on different products, ACTIVE. |
| Functional tests | **PASS (5/5)** | `gateway/verify.sh` exit 0 — **including isolation** (case 5). |

Overall: **READY.** Confirmed live: quota is exact (a Free app at 5/min served
exactly five 200s then 429 in a clean window); isolation holds (a second app on a
different product kept getting 200s while the first was throttled); the 429 body is
`{"error":"quota exceeded"}` with **no** `Retry-After` and **no** `X-RateLimit-*`
headers; a product without a `quota` object is rejected at creation; and an app
whose product doesn't cover the API gets 403. Two observations worth knowing: the
429 is JSON but carries `content-type: text/plain`, and the quota window is a fixed
calendar minute (a boundary-straddling burst can briefly serve 2×). The multi-node
`quota_policy` pitfall could not be exercised on a single-node test — verify it on
your own cluster. Full record:
[`validation/gateway-validation.yaml`](validation/gateway-validation.yaml).

## Related solutions

- **[01 — OAuth 2.0 with JWT](../01-oauth-jwt/)** — metering requires identity.
  Start there if you can't yet name your callers, or swap the static key for a token
  flow.
- **[02 — SOAP to REST](../02-soap-to-rest/)** — put a quota on a mediated legacy
  system and it becomes a tiered product.
- **[04 — Analytics](../04-analytics/)** — which apps are approaching their quota,
  who hit 429 and how often. The upgrade-conversation queries.
