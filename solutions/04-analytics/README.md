# Solution 04 — Analytics: you already have the data

**Analytics is on. Every request is captured. This is about making it answer
questions worth asking — and the three configuration decisions that determine
whether it can.**

| | |
|---|---|
| **Setup time** | ~10 minutes (there is no analytics plugin to add) |
| **Difficulty** | 🟢 Beginner |
| **Needs** | An API deployed to an environment · identity resolved on it · one app to generate traffic with |
| **Plugins** | `helix-auth` · `request-id` · `cors` — **and deliberately no analytics plugin** |
| **Build it with** | 🤖 **[the Helix Agent](helix-agent-prompt.md)** — recommended · or import [`gateway/api-spec.yaml`](gateway/api-spec.yaml) |
| **The actual content** | 📊 **[`charts.md`](charts.md)** — twelve questions worth asking, with the prompts to ask them |
| **Assets** | ✅ [Agent prompt](helix-agent-prompt.md) · ✅ [Chart catalogue](charts.md) · ✅ [Architecture](architecture.md) · ✅ [Business need](business-need.md) · ✅ [Spec](gateway/) · ✅ [Tests](tests/) · ✅ [Validation](validation/) · ✅ [Infographic](infographic.md) · ✅ [Blog](blog.md) · ✅ [Manifest](solution.yaml) |

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

## The three decisions that determine whether analytics is useful

This is the whole solution. Everything in the spec exists to demonstrate these.

### 1. Identity must be resolved

Without `helix-auth`, every row attributes to a source IP.

| | Without identity | With identity |
|---|---|---|
| "Which integration caused the spike?" | An IP address. Partners share NAT, rotate egress, run in clouds. | An app and a developer, by name. |
| "Who should we bill?" | Unanswerable | Per-app request counts |
| "Which partner's integration broke?" | Unanswerable | A named app, failing every call since 02:14 |

**This single decision is the difference between analytics you query and analytics you
scroll.** It's also why this solution depends on
[solution 01](../01-oauth-jwt/) — metering and attribution both need identity, and
identity is not something analytics can add after the fact.

### 2. Paths must be templated

`/orders/{orderId}` is **one row** in a per-route breakdown: one latency
distribution, one error rate, one call count you can trend.

Literal paths give you **one row per order**. Your top-routes chart becomes a list of
individual customer orders. Per-route p99 becomes meaningless, because each row has one
sample. Cardinality grows with your order volume, forever.

Nothing warns you about this. **The API works identically either way** — only the
analytics is ruined, and you find out when you first try to ask a route-level question.

### 3. A correlation id must exist

Aggregates tell you *what* happened. `X-Request-Id` is how you get from a row in a
chart to the specific request — and, because the header is forwarded upstream, to the
matching entry in **your backend's own logs** for the same call.

One caveat that matters more than the configuration: **ask your teams to log it.** The
gateway generates and records it regardless, but if nobody downstream writes it down,
you can correlate the gateway with itself and nothing else. It's the cheapest
observability work available and it's routinely skipped.

### The property these three share

**All three must be true *before* the data you want to query is generated.**

Analytics cannot retroactively attribute traffic captured without identity. It cannot
collapse literal paths into a template after the fact. Yesterday's un-attributed rows
stay un-attributed forever.

That's the real reason a solution about "reading charts" ships a gateway
configuration.

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
| 4 | One request by `X-Request-Id` | The bridge from "3% failed" to "*this* call failed, for *this* partner". |
| 5 | Apps above 80% of quota | **A sales pipeline, not an ops chart.** Upgrade leads with numbers attached. |
| 9 | 401s by app — failing *every* call or *some*? | Every call = broken config, and a partner who hasn't told you. Some = expired tokens, not refreshing. |
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

# 2. Set JWT_SIGNING_SECRET on the environment, then deploy the revision.

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

Plus `helix-auth` per route, which is what makes attribution possible, and templated
paths, which is a modelling decision rather than a plugin.

One route in the spec is there purely to make an analytics point:
`POST /orders/report` is deliberately kept separate as a **slow** route. Blending a
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
| 1 | Unauthenticated → 401, authenticated → 200 (identity *is* resolved) | ✅ |
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
- **You're about to onboard partners at scale.** Get the three decisions right *before*
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

| Stage | Status | Provenance |
|---|---|---|
| Configuration generated | **YES** | [`gateway/api-spec.yaml`](gateway/api-spec.yaml) |
| Local validation | **PASS** | Structural review, plus `verify.sh` syntax-checked and its guard paths executed. [`validation/local-validation.yaml`](validation/local-validation.yaml) |
| Gateway dry-run | **NOT RUN for this package** | — |
| Gateway deployed | **NOT RUN for this package** | — |
| Functional tests | **NOT RUN for this package** | `verify.sh` written and reviewed, not executed against a gateway |
| Analytics verified | **NOT RUN for this package** | See below — this is the one that matters, and it is manual by nature |

**On the prior art**, and this is worth being precise about: an earlier internal build
did confirm that the platform's global analytics captures real traffic and can be
queried per route — a two-request window was retrieved and matched what had been sent.
That establishes *capture works*. It does **not** establish anything about this
package's central claims: that identity resolution produces per-app attribution at
scale, or that templated paths aggregate as described. Neither was tested with enough
traffic or enough apps to demonstrate it.

Overall: **UNVALIDATED**. Run [`gateway/verify.sh`](gateway/verify.sh) against your own
environment, then do the manual analytics checks it prints — particularly the path
templating one. Full record:
[`validation/gateway-validation.yaml`](validation/gateway-validation.yaml).

## Related solutions

- **[01 — OAuth 2.0 with JWT](../01-oauth-jwt/)** — **the prerequisite.** Attribution
  is impossible without resolved identity, and identity cannot be added retroactively.
- **[03 — API Products](../03-api-products/)** — quota consumption charts (5, 6, 7),
  including the upgrade-lead query that's usually what gets this funded.
- **[02 — SOAP to REST](../02-soap-to-rest/)** — "which partner is calling the legacy
  system, how often?" is usually the first question asked the week after that goes
  live.
