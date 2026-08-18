# Solution 04 — Analytics: you already have the data

**Analytics is on. Every request is captured. This is about making it answer
questions worth asking — and the request-path choices that determine whether it
can.** The API here is deliberately tiny: two routes, a standard response, no auth.

| | |
|---|---|
| **Setup time** | ~10 minutes (there is no analytics plugin to add) |
| **Difficulty** | 🟢 Beginner |
| **Needs** | An API deployed to an environment (this one is two simple routes) · a little traffic to query |
| **Plugins** | `mocking` (standard response) · `request-id` · `cors` — **and deliberately no analytics plugin** |
| **Build it with** | 🤖 **[the Helix Agent](helix-agent-prompt.md)** — recommended · or import [`gateway/api-spec.yaml`](gateway/api-spec.yaml) |
| **The actual content** | 📊 **[`charts.md`](charts.md)** — twelve questions worth asking, with the prompts to ask them |
| **Assets** | ✅ [Agent prompt](helix-agent-prompt.md) · ✅ [Chart catalogue](charts.md) · ✅ [Architecture](architecture.md) · ✅ [Business need](business-need.md) · ✅ [Spec](gateway/) · ✅ [Tests](tests/) · ✅ [Validation](validation/) · ✅ [Infographic](infographic.md) · ✅ [Manifest](solution.yaml) |

---

## Read this first

**You do not add an analytics plugin.** Analytics is enabled globally on the platform
via `helix-analytics`. Every request through every API is already being captured,
right now, including the ones you made before reading this.

There is deliberately no `helix-analytics` block anywhere in
[`gateway/api-spec.yaml`](gateway/api-spec.yaml). If you find yourself adding one — or
an agent proposes one — **that is the thing to correct.**

Which raises the obvious question: if it's already on, what is there to do?

## The problem

> *"We have analytics. I've looked at it. It tells me we did 4.2 million calls last
> month, and 1.8% of them failed.*
>
> *At 3am on Tuesday something hammered our orders endpoint and the on-call spent
> forty minutes trying to work out which of our 400 integrations it was. The
> dashboard showed a spike. It could not tell us whose spike it was, because every
> row was an IP address — and our partners share NAT gateways, run in clouds, and
> rotate egress addresses.*
>
> *So we have a chart that tells us something happened, and no way to act on it."*

That's the real failure, and it isn't a missing feature. The data was captured
faithfully. It just can't answer the question, because of decisions made on the
request path long before anyone opened a dashboard.

**Root cause:** analytics can only group by what the gateway knew at request time. If
the gateway didn't resolve *who* was calling, no query will recover it later.

## What makes the captured data useful

Analytics can only group by what the gateway knew at request time. Two request-path
choices are baked into this minimal API, and a third is a compose-in for when you
need per-app numbers.

### 1. Paths are templated (in this API)

`/orders/{orderId}` is **one row** in a per-route breakdown when you group by the
`route_id` dimension: one latency distribution, one error rate, one count you can
trend. Group by `api_path` instead and you get **one row per order id** — a top-routes
chart that is really a list of individual customer orders, and per-route percentiles
computed from one sample each.

Nothing warns you about this. **The API works identically either way** — only the
analytics differs, and you find out when you first ask a route-level question. So:
**group route-level charts by `route_id`, not `api_path`.**

### 2. A correlation id exists (in this API)

`request-id` stamps `X-Request-Id` on every call and forwards it upstream. It is **not**
an analytics dimension — you don't query analytics for one id. You narrow analytics to
a slice (this app, this route, this status, this window), then match the `X-Request-Id`
values in **your backend's own logs**. So **ask your teams to log it** — the gateway
generates and forwards it regardless, but if nobody downstream records it you can
correlate the gateway with itself and nothing else.

### 3. Identity — add it when you need per-app numbers (compose-in)

This minimal API has **no auth**, on purpose. Without identity resolved, every row
attributes to a **source IP** — and partners share NAT gateways, rotate egress
addresses and run in clouds, so an IP is close to no grouping at all.

When you need to answer "*which app* caused the spike / should be billed / broke", add
`helix-auth` to the routes — that's [solution 01](../01-oauth-jwt/) — and analytics
attributes to the app and developer automatically. You don't touch anything on the
analytics side; resolving identity on the request path is the whole change.

| Question | This minimal API (no identity) | After adding solution 01 |
|---|---|---|
| "Which integration caused the spike?" | A source IP | An app and a developer, by name |
| "Who should we bill?" | Unanswerable | Per-app request counts |
| "Which partner's integration broke?" | A source IP | A named app, failing since 02:14 |

**Note the asymmetry that makes this urgent:** templating and identity **cannot be
applied retroactively** to data already captured. Get them right before the data you
want to query is generated.

### Why this ships a gateway configuration at all

Templating and identity **cannot be applied retroactively**. Analytics cannot collapse
literal paths into a template after the fact, and it cannot attribute traffic captured
without identity. Yesterday's fragmented or un-attributed rows stay that way. That's
why a solution about "reading charts" still ships a request-path configuration — get it
right before the data you want to query is generated.

## What to actually ask

**[`charts.md`](charts.md) is the substance of this package.** Twelve questions, each
with the agent prompt to ask it, what the answer looks like, the decision it informs,
and the configuration mistake that makes it useless.

A sample of the ones that earn their place immediately:

| # | Question | What it's for |
|---|---|---|
| 1 | Calls by app, last 24h | Your baseline. You can't spot an anomaly without knowing normal. |
| 2 | Error rate by route, **4xx split from 5xx** | 5xx is your problem; 4xx is usually your partner's, or your docs'. Conflating them gives you a number you can't act on. |
| 3 | p50/p95/p99 per route, **with sample counts** | The p99/p50 *ratio* is the signal. A p99 from 12 requests is noise. |
| 4 | Narrow to a slice, then match `X-Request-Id` in your logs | The bridge from "3% failed" to "*this* call failed" — a log-side join, not an analytics query. |
| 5 | Apps above 80% of quota | **A sales pipeline, not an ops chart.** Upgrade leads with numbers attached. |
| 9 | Errors by route/status (or by app, once identity is added) | Every call failing = broken config; some = intermittent. 4xx vs 5xx tells you whose problem it is. |
| 11 | Apps that **stopped** calling | The signal nobody watches. Churn, a broken integration, or an expired credential. |

Charts 5–7 need [solution 03](../03-api-products/) deployed, because quota consumption
requires a quota to exist.

`charts.md` also has a five-panel dashboard layout, and an argument for why the other
seven charts should stay *investigative* rather than going on a wall.

## Build it with the Helix Agent

Recommended path. Full prompt: [`helix-agent-prompt.md`](helix-agent-prompt.md).

Note what this prompt does **not** ask for:

```text
I want the platform's analytics to be able to answer per-app and per-route questions
about my Orders API. Analytics is already enabled globally, so do NOT add an
analytics plugin — instead make sure the request path is shaped so the captured data
is useful.

1. Confirm identity is resolved on every route, so calls attribute to the calling app
   rather than to a source IP. If any route is unauthenticated, tell me which — those
   rows will never be attributable.

2. Review my OpenAPI paths for templating. Any route where a path segment is an
   identifier must be declared as a parameter, not a literal. Tell me if you find a
   path that will produce one analytics row per entity.

3. Add request-id (uuid, X-Request-Id) API-wide, and confirm it is forwarded upstream
   so my backend can log the same id.

Then show me the spec, dry-run it, and wait for my confirmation.
```

Then, once traffic exists:

```text
Show me calls to Orders API in the last hour, broken down by app and route, with
status code counts. Tell me which app sent the most.
```

**That's the pattern worth internalising: analytics is capture-then-query.** You don't
assert it on the request path. You make real calls and then ask. See
[AGENT-GUIDE.md](../../AGENT-GUIDE.md) § 7.

## Install it directly

```bash
export ORG=<ORG_ID>
export BASE=https://<YOUR_GATEWAY_HOST>/api

# 1. Import gateway/api-spec.yaml. There is NO analytics plugin in it — that is
#    correct. Bind your upstream.

# 2. Deploy the revision. (No secrets or auth on this minimal API.)

# 3. Create a developer and an app; keep the client_id and client_secret.

# 4. Seed a known traffic pattern and check the request path is correctly shaped
GATEWAY=https://<YOUR_GATEWAY_HOST> \
CLIENT_ID=<CLIENT_ID> CLIENT_SECRET=<CLIENT_SECRET> \
./gateway/verify.sh

# 5. Then VERIFY ANALYTICS MANUALLY, using the queries verify.sh prints. Analytics
#    is verified by observation, never by assertion — see § Testing.
```

## Configuration

Source of truth: [`gateway/api-spec.yaml`](gateway/api-spec.yaml). The whole API-wide
block is two plugins, and the notable thing is the absence:

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

    # NO helix-analytics BLOCK. Analytics is global. Adding one here is the
    # mistake this solution exists to prevent.
```

The only route-level plugin is `mocking`, returning a standard response. Templated
paths are a modelling decision, not a plugin. Add `helix-auth` per route
([solution 01](../01-oauth-jwt/)) when you want per-app attribution rather than per-IP.

One route in the spec is there purely to make an analytics point:
If you later add routes with very different latency profiles — say a fast lookup and
a slow report — keep them as **separate routes**. Blending a
30-second report into a 40ms lookup under one path pattern produces an average that
describes neither. **If a route's latency profile is wildly different from its
neighbours, it wants its own row** — that's an analytics argument for route design.

## Testing

```bash
GATEWAY=https://<YOUR_GATEWAY_HOST> \
CLIENT_ID=<CLIENT_ID> CLIENT_SECRET=<CLIENT_SECRET> ./gateway/verify.sh
```

**What `verify.sh` can and cannot do — this matters here more than in the other
solutions.**

Analytics is captured asynchronously and read from the portal or the agent. **No shell
script can assert that a chart is correct**, and this one doesn't pretend to. What it
does:

| # | Check | Automated? |
|---|---|---|
| 1 | Both routes → 200 with a standard response | ✅ |
| 2 | `X-Request-Id` present on responses | ✅ |
| 3 | Seeds a **known, labelled** traffic pattern across routes and status codes — deliberately including failures | ✅ |
| 4 | Prints the exact queries to run and the counts to expect | ✅ |
| 5 | **Analytics reflects that pattern, attributed per app** | ❌ manual |
| 6 | **The templated route appears as `/orders/{orderId}`, not as literal ids** | ❌ manual |
| 7 | **The same `X-Request-Id` appears in your backend's logs** | ❌ manual |

Exit 0 means *the request path is correctly shaped and a known pattern is seeded.* It
does **not** mean analytics is verified. Checks 5–7 are manual, they're the ones that
actually matter, and they're recorded as manual in
[`tests/test-plan.yaml`](tests/test-plan.yaml) rather than quietly folded into a
passing exit code.

**Check 6 is the one to not skip.** It's the only way to discover that your paths
aren't templated, and it's unrecoverable after the fact — data captured against literal
paths stays that way.

## Gotchas

- **Don't add a `helix-analytics` block.** It's global. An agent will propose one
  because that's how observability works on most platforms; correct it.
- **Unauthenticated routes produce unattributable rows, permanently.** No query
  recovers identity that was never resolved. If a route is public and you need
  attribution on it, that's an auth change, not an analytics one.
- **Untemplated paths are unrecoverable too.** One row per entity, forever, for data
  already captured. Check this before you have a year of it.
- **`X-Request-Id` is worth little if your backend doesn't log it.** The expensive half
  of correlation is the free half — asking your teams.
- **Latency is measured at the edge.** It includes your upstream's total time but
  cannot break it into your internal hops. For per-hop timing you want distributed
  tracing; `X-Request-Id` is the thread connecting the two.
- **Bodies are not captured.** By design — capturing bodies means capturing customer
  data. Analytics tells you *which app called what and got what back*, never *what was
  in the payload*.
- **Retention is finite and it's a platform setting.** [`charts.md`](charts.md) asks
  for 30-day and week-on-week comparisons. Confirm your window covers the questions
  you intend to ask before building a report that silently truncates.
- **A single API-wide latency average is close to useless** if the API has both fast
  and slow routes. Per-route, or don't bother.
- **Rejected requests attribute only when identity resolved.** A 401 from an unknown
  key has no app to attribute to — expect an "unidentified" bucket, and don't read it
  as zero.
- **Charts nobody acts on are ornaments.** The habit worth building: when a chart
  moves, write down what you did about it. A chart with no history of action can be
  deleted.

## When to use it

Use it when:

- **You have analytics and can't get an actionable answer out of it.** That's the
  common case, and it's a request-path problem masquerading as a tooling problem.
- **You're about to onboard partners at scale.** Get templating (and identity, via solution 01) right *before*
  the data arrives, because two of them are unrecoverable.
- **Incident attribution takes too long.** Chart 1 plus chart 4 turns forty minutes
  into a query.
- **You need chargeback or upgrade signals.** Per-app counts are the input to both.
- **You're standing up a permanent dashboard** and want five panels people read rather
  than twenty nobody does.

Don't use it when:

- **You need per-hop latency inside your own services.** That's distributed tracing.
  This is edge observability, and the two connect via `X-Request-Id`.
- **You need request/response bodies.** Deliberately not captured.
- **You need real-time alerting on a threshold.** This is query-and-chart. Alerting is
  a different tool fed by different data.
- **Your API is genuinely anonymous and must stay that way.** Then attribution is
  impossible in principle, and volume/latency/error-rate charts are all you get. That's
  still worth having; just don't expect chart 1 to work.

## Limitations

- **Analytics cannot be retrofitted onto badly-shaped data.** Un-attributed traffic and
  untemplated paths stay that way. This is the most consequential limitation in the
  package.
- **`verify.sh` cannot verify analytics.** It verifies the request path and seeds a
  known pattern. The three checks that matter are manual.
- **Attribution requires identity.** Anonymous traffic groups by IP, which for partner
  APIs is close to no grouping at all.
- **Latency is edge-measured**, not per-hop.
- **Bodies are not captured**, by design.
- **Retention is a platform setting**, and it bounds which questions are answerable.
- **Quota charts need [solution 03](../03-api-products/).** Charts 5–7 in
  `charts.md` assume `api-product-enforcer` and products with quotas.
- **Exact query syntax and field names vary by build.** The prompts in `charts.md` are
  phrased for the agent, which knows your org's schema; ask it to show you the field it
  filtered on rather than guessing.

Full list: [`solution.yaml`](solution.yaml) § `limitations`.

## Validation status

**Validated against a gateway — analytics attribution and path-templating confirmed through the analytics API.**

| Stage | Status | Provenance |
|---|---|---|
| Configuration generated | **YES** | [`gateway/api-spec.yaml`](gateway/api-spec.yaml) — no analytics plugin, by design |
| Local validation | **PASS** | [`validation/local-validation.yaml`](validation/local-validation.yaml) |
| Gateway dry-run | **PASS** | Non-destructive validation on a gateway. |
| Gateway deployed | **DEPLOYED** | Four routes ACTIVE, including the templated `/orders/{orderId}`. |
| Functional tests | **PASS** | `gateway/verify.sh` seeded a labelled pattern; identity and correlation id confirmed. |
| Analytics verified | **VERIFIED** | Queried the control-plane analytics API — see below. |

Overall: **READY.** Confirmed live, by querying the analytics API:

- **Analytics is global** — with no plugin in the spec, every call was captured.
- **Per-app attribution works** — grouping by `app_name` / `developer` /
  `product_name` returned the calling app by name, and counts matched the seed.
- **Without identity, rows attribute to a source IP** — expected on this minimal API;
  add [solution 01](../01-oauth-jwt/) to attribute per app.
- **Path templating works at `route_id`** — five distinct `/orders/{orderId}`
  values aggregate to **one** row by `route_id`, versus five by `api_path`. Group
  route-level charts by `route_id`.
- **Latency separation works** — the slow report route showed ~1000ms vs ~0ms for
  the fast reads, not one blended average.

**One correction the run produced:** `X-Request-Id` is **not** an analytics
dimension. Correlating a single request is a join in *your* logs via the forwarded
header, not an analytics query. `charts.md` has been updated. Full record:
[`validation/gateway-validation.yaml`](validation/gateway-validation.yaml).

## Related solutions

- **[01 — OAuth 2.0 with JWT](../01-oauth-jwt/)** — **the compose-in for per-app numbers.** Attribution
  is impossible without resolved identity, and identity cannot be added retroactively.
- **[03 — API Products](../03-api-products/)** — quota consumption charts (5, 6, 7),
  including the upgrade-lead query that's usually what gets this funded.
- **[02 — SOAP to REST](../02-soap-to-rest/)** — "which partner is calling the legacy
  system, how often?" is usually the first question asked the week after that goes
  live.
