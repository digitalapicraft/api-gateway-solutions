# Agent-mode prompt — tiered quota with API Products

Paste this into **Helix Agent Mode**. It works from a blank organisation: the agent
finds the API, creates the products, applies `helix-auth` + `api-product-enforcer`,
dry-runs, deploys, and hands you two app keys to prove isolation with.

Replace the `<<...>>` values. Everything else is deliberate — the table below says
why each block earns its place.

Read [AGENT-GUIDE.md](../../AGENT-GUIDE.md) first if you haven't. This solution has
more platform-specific constraints than any other in the library, because a
general-purpose model brings generic rate-limiting habits to it and almost every one
of them is wrong here.

---

## The prompt

```text
Set up tiered throughput on my API using API Products, so that one partner's app
can never exhaust capacity for the others.

CONTEXT
- API to protect: <<Orders API>>   (find it with list_apis; if more than one
  matches, ask me before changing anything)
- Environment: <<staging>>
- Measured upstream ceiling: <<3000>> requests/minute total.

WHAT I WANT

1. Identify the caller.
   Add helix-auth in validate mode with validate_auth_type key-auth, reading the
   credential key from the "apikey" request header. Requests with no key or an
   unknown key must be rejected at the gateway and never reach upstream.

   Use helix-auth, NOT the raw key-auth plugin — I want the app's product
   subscription resolved, not just a static key checked.

2. Create four API Products bundling this API, each with a quota:
     - "<<Orders API>> — Free"        60 per 1 minute
     - "<<Orders API>> — Pro"         1000 per 1 minute
     - "<<Orders API>> — Enterprise"  10000 per 1 minute
     - "<<Orders API>> — Internal"    limit -1 (unlimited, but still authenticated)
   Every product must carry a quota object — a product without one is a 403, not
   "unlimited". Deploy all four to <<staging>>.

3. Enforce it.
   Add api-product-enforcer to the route with error_policy fail_close.
   Confirm the route has a service_id — without one the enforcer returns 403
   regardless of subscription.

4. Add request-id (uuid, X-Request-Id) so a disputed 429 has something to search
   on, and cors allowing the apikey and content-type headers with
   allow_credential false.

5. On POST /orders/search only, also add a limit-count of 20 per 60 seconds keyed
   on remote_addr with rejected_code 429. That endpoint hits the reporting store
   and I want a per-IP ceiling underneath the product quota, including for traffic
   that never authenticates.
   Tell me whether my gateway sits behind a proxy or load balancer — if it does I
   need real-ip in front of this, or every caller shares the balancer's address
   and my per-IP ceiling becomes a global cap on the endpoint.

CONSTRAINTS — known platform behaviour, please respect these
- Do NOT key any rate limit on consumer_name. Per-caller metering in this platform
  is the product quota, counted per app (the credential). The only limit-count in
  this design is the per-IP one on the search route.
- Do NOT put Redis settings in the api-product-enforcer route config. That plugin
  accepts only error_policy and ctx_namespace. quota_policy and the Redis
  connection live in plugin_attr.api-product-enforcer in the gateway's config.yaml.
  In your summary, tell me plainly that this has to be set to "redis" separately if
  I run more than one gateway node, and why — I want to know before I find out.
- Use limit-count, not limit-req.
- If you need a conditional match on a header or path, use filter_func (a Lua
  expression string), not vars — vars fails at deploy time.
- Check get_plugin_config for every plugin before writing config and use the schema
  this org actually has. Only schema fields plus _meta are legal — no invented or
  commentary fields in the plugin blocks.

BEFORE YOU DEPLOY
- Show me the full spec you are about to apply and wait for my confirmation.
- Run validate_route and dry_run_deploy first. If either fails, show me the error
  and your proposed fix rather than retrying blindly.
- Add up the four quotas against my stated upstream ceiling of <<3000>> rpm and
  tell me honestly whether I have oversold. Do not quietly adjust my numbers.

AFTER YOU DEPLOY
- Create a test developer with TWO SEPARATE APPS — one subscribed to Free, one to
  Pro — and give me both app keys. They must be different apps: two keys on the
  same app share one quota bucket and would not prove isolation.
- Give me a curl loop that shows the Free app getting 429 {"error":"quota
  exceeded"} after 60 requests while the Pro app still gets 200s in the same
  window.
- Tell me plainly what the 429 does and does not contain, so I can write the
  developer docs.

If anything is ambiguous for my org — the environment, the upstream, whether Redis
is configured, whether the route has a service_id — ask me instead of guessing.
```

---

## Why the prompt is shaped this way

| Block | Why it's there |
|---|---|
| **"Use helix-auth, not raw key-auth"** | The most likely wrong turn. `key-auth` authenticates but resolves no product, so `api-product-enforcer` then 403s every request with nothing in context to enforce against. The symptom reads as a subscription problem and is actually a plugin choice. |
| **"Every product must carry a quota"** | A product with no `quota` object returns 403 under the default `fail_close` — it does **not** mean unlimited. `-1` means unlimited. This trips people who reason by analogy from "no limit set". |
| **"Confirm the route has a `service_id`"** | No service id → 403 before quota is evaluated. Easy to miss because nothing about the plugin config suggests it, and the error is indistinguishable from a missing subscription. |
| **"Do NOT key on `consumer_name`"** | Per-caller metering here is the product quota, keyed on the credential. A model trained on generic gateway documentation will reach for `limit-count` + `consumer_name` by default, and produce something that looks right, meters the wrong thing, and silently coexists with the real quota. |
| **"Do NOT put Redis in the route config"** | The enforcer's schema accepts only `error_policy` and `ctx_namespace`. An agent that "helpfully" adds `policy: redis` produces config that fails validation — or worse, passes and silently counts per node. |
| **"tell me plainly… if I run more than one gateway node"** | This is the single most common way the solution is deployed wrong, and it is invisible from the route config. Forcing it into the agent's summary is the cheapest possible insurance. |
| **"Tell me whether my gateway sits behind a proxy"** | Without `real-ip`, a per-IP limiter behind a load balancer throttles *everyone* at 20/min. That's a self-inflicted outage waiting for a traffic spike. |
| **"Add up the four quotas… tell me honestly whether I have oversold"** | The quota only saves you money if the sum of committed quotas is below your capacity. An agent asked to configure will configure; asked to check arithmetic, it checks. |
| **"Do not quietly adjust my numbers"** | Tier limits are commercial decisions. An agent that helpfully scales Enterprise down to fit your upstream has silently rewritten a contract. |
| **"TWO SEPARATE APPS"** | Quota is per app. Testing with two keys from one app makes correct isolation look broken, and this is the single most common false alarm. |
| **BEFORE YOU DEPLOY** | `validate_route` → `dry_run_deploy` → confirm → `deploy_revision`. Deploying over an ACTIVE revision fails; stopping to show the spec keeps you in the loop at the step that's hard to undo. |
| **"Tell me what the 429 contains"** | Forces the agent to surface the no-`X-RateLimit`-headers reality now, instead of you learning it from a partner. |

## Tweak knobs

Each is a different piece of content and a different conversation.

**Pool a developer's apps into one bucket**
```text
Quota should be per developer, not per app — a customer's three apps should share
one budget. Set quota_key_scope to developer on each product, and tell me what that
changes about blast radius: if their staging integration misbehaves, does it now
spend their production budget?
```

**Per-second shaping rather than per-minute bursts**
```text
Use interval 1 with interval_unit second and proportionally smaller limits, so the
quota shapes traffic instead of letting a full minute's budget go in the first two
seconds. Tell me what this does to a client that legitimately batches.
```

**Serve unmetered rather than error during a quota-backend outage**
```text
Set error_policy to fail_open on api-product-enforcer. If the quota backend is
unreachable I would rather over-serve than return 503 on a revenue path. Explain in
your summary exactly what stops being enforced when it trips, and how I would know
it had.
```

**Different products per endpoint group**
```text
Split into two products: one covering the read endpoints and one covering writes, so
a customer can buy high read throughput without write access. Tell me how rank
interacts with this — if an app subscribes to both, which one gets evaluated on a
read?
```

**Concurrency instead of rate**, for slow report endpoints
```text
POST /orders/report takes 30+ seconds per call, so requests-per-minute is the wrong
control. Add limit-conn capping concurrent in-flight requests per IP at 3 on that
route, alongside the product quota.
```

**Swap the static key for a token flow**
```text
Callers should exchange a client id and secret for a short-lived token instead of
sending a static key. Add a POST /oauth/token route with helix-auth in generate
mode, switch the protected routes to validate with validate_auth_type jwt-auth
sharing the same signing secret, and keep api-product-enforcer behind it so quota
still works.
```
(That's [solution 01](../01-oauth-jwt/) composed with this one.)

## Follow-up prompts for the same session

1. `Show me which apps hit their product quota in the last hour, and by how much they went over.`
2. `Which apps are consistently using more than 80% of their quota? Those are upgrade conversations — give me the list with the numbers I'd quote.`
3. `Enterprise are complaining. Raise their product quota to 25000/min — but first tell me whether that breaks my 3000 rpm upstream ceiling, and what you'd do instead.`
4. `Our internal health-check app should never be metered. Move it to the Internal product and confirm it stays authenticated and attributed.`
5. `Write the developer-portal docs for these four tiers, including the retry-with-backoff-and-jitter contract, given the 429 carries no Retry-After header.`

## Known failure modes when running this prompt

- **Everything 403s after deploy.** Almost always: the test app isn't subscribed to
  a product covering this API, or the route has no `service_id`. Ask the agent to
  `get_app` and confirm the `products` map is non-empty, then confirm the service
  id.
- **Everything 401s.** You're sending the app's *secret* instead of its *key*.
  Key-auth validate resolves on the credential key (client id).
- **No 429 ever arrives.** Either the quota is higher than you think, or
  `quota_policy` is `local` on a multi-node gateway and each node is counting
  separately. Check which product actually won, too — only the top-ranked covering
  product is evaluated.
- **The 429 arrives much sooner than expected.** The app is probably subscribed to a
  product you'd forgotten about at a higher rank. Ask the agent which product was
  resolved.
- **The agent adds `policy: redis` to `api-product-enforcer`.** Reply: `that field
  isn't in the enforcer's schema — the quota backend is configured in plugin_attr,
  not on the route. Remove it.`
- **The agent reaches for `limit-count` + `consumer_name` anyway.** The expected
  wrong turn. Reply: `we don't meter on consumer_name — the product quota already
  counts per app. Remove that limiter.`
- **Isolation looks broken — both apps 429 together.** Check they're really two
  separate apps. Two keys on one app share a bucket. (`verify.sh` refuses to run
  with the same key twice for exactly this reason.)
- **The per-IP limiter throttles everyone at once.** The gateway is behind a proxy
  and every caller shares the balancer's address. You need `real-ip` in front.
- **Deploy fails with `Only INACTIVE revisions can be updated`.** Tell the agent to
  undeploy, apply, then redeploy — or clone the revision first.
- **The agent puts a `description` key inside a plugin block.** Only schema fields
  plus `_meta` are legal. Reply: `move that to a YAML comment.`

## Related

- **[Solution 01 — OAuth 2.0 with JWT](../01-oauth-jwt/helix-agent-prompt.md)** —
  metering requires identity. Swap the static key for a token flow.
- **[Solution 02 — SOAP to REST](../02-soap-to-rest/helix-agent-prompt.md)** — put a
  quota on a mediated legacy system and it becomes a tiered product.
- **[Solution 04 — Analytics](../04-analytics/helix-agent-prompt.md)** — the
  quota-consumption and upgrade-lead queries.
