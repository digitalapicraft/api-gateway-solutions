# Agent-mode prompt — make the analytics you already have useful

Paste these into **Helix Agent Mode**. There are two parts, and the split is the point.

**Part A** shapes the request path so the captured data can answer something. **Part
B** is the queries — and Part B is where the value is, which is why
[`charts.md`](charts.md) is twelve of them rather than one.

The first thing to know: **there is no analytics plugin to add.** Analytics is enabled
globally on the platform. Every request through every API is already captured. A prompt
asking the agent to "add analytics" is a prompt to correct, and Part A says so
explicitly because an agent trained on other platforms will reach for a plugin.

Read [AGENT-GUIDE.md](../../AGENT-GUIDE.md) § 7 first if you haven't.

---

## Part A — shape the request path

```text
I want the platform's analytics to be able to answer per-app and per-route questions
about my API. Analytics is already enabled globally, so do NOT add an analytics plugin
— there is nothing to turn on. Instead, make sure the request path is shaped so the
data being captured is actually useful.

CONTEXT
- API: <<Orders API>>   (find it with list_apis; if more than one matches, ask me
  before changing anything)
- Environment: <<staging>>
- JWT_SIGNING_SECRET already exists on <<staging>>. If it does not, tell me and stop.

WHAT I WANT

1. IDENTITY ON EVERY ROUTE.
   Confirm every route resolves the calling app, so analytics rows attribute to an app
   and developer rather than to a source IP address. Use helix-auth validate.

   Then tell me explicitly: is there any route that is currently unauthenticated? I
   need to know, because rows captured for those routes will never be attributable to
   anyone and no later query can recover it.

   (The token endpoint is expected to be unauthenticated — that one is fine and by
   design.)

2. REVIEW MY PATHS FOR TEMPLATING.
   Go through the OpenAPI paths and find any route where a path segment is really an
   identifier. Each of those must be declared as a path PARAMETER, not a literal.

   Tell me if you find a path that would produce one analytics row per entity instead
   of one row per route. This matters more than it looks: with literal paths, a
   per-route breakdown becomes a list of individual records, per-route p99 is computed
   from one sample per row, and cardinality grows with my data volume forever. The API
   works identically either way — only the analytics is ruined.

3. CORRELATION ID.
   Add request-id (uuid, header X-Request-Id) API-wide. Confirm it is forwarded to the
   upstream, so my backend can log the same id and I can join a gateway row to a
   backend log line.

4. LATENCY-PROFILE REVIEW.
   Tell me whether any two routes with very different latency profiles are grouped
   under one path pattern. If a 30-second report and a 40ms lookup share a row, the
   per-route latency describes neither and I would rather split them.

CONSTRAINTS
- Do NOT add helix-analytics or any analytics plugin. It is enabled globally. If you
  think one is needed, say why and stop rather than adding it.
- Only schema fields plus _meta are legal in a plugin block. No commentary keys.
- Check get_plugin_config for anything you do add.
- If you need a conditional match, use filter_func (a Lua expression string), not
  vars — vars fails at deploy time.

BEFORE YOU DEPLOY
- Show me the full spec and wait for my confirmation.
- Run validate_route and dry_run_deploy. If either fails, show me the error and your
  proposed fix rather than retrying blindly.

AFTER YOU DEPLOY
- Summarise the three things that determine whether my analytics is useful — identity,
  templating, correlation — and tell me which of them my API now satisfies and which
  it does not.
- Be explicit about anything that is now unrecoverable for data already captured.
```

**Then generate real traffic before asking anything.** Analytics is
capture-then-query — there is nothing to look at until calls have been made.
[`gateway/verify.sh`](gateway/verify.sh) seeds a deliberately labelled pattern
(successes, 401s, 404s, across several routes) and prints the exact counts to expect,
which makes the first query a real check rather than a vague look.

## Part B — the queries

Start with these four. The full catalogue, with what each answer is *for* and what
breaks it, is in **[`charts.md`](charts.md)**.

```text
Show me calls to <<Orders API>> in the last hour, broken down by app and route, with
status code counts. Tell me which app sent the most and what percentage of total
traffic that represents.
```

```text
Show me the per-route breakdown for <<Orders API>> over the last hour. I am checking
that /orders/{orderId} appears as ONE templated row rather than a separate row per
order id — tell me plainly which it is.
```

```text
Which routes on <<Orders API>> returned 4xx or 5xx yesterday? Give me the count by
status code and the error rate per route, and keep 4xx separate from 5xx — I care
about them differently.
```

```text
Give me p50, p95 and p99 latency per route on <<Orders API>> for the last 7 days.
Include the call count per route so I know which percentiles have enough samples to
trust, and flag any route where p99 is more than 10x p50.
```

---

## Why the prompts are shaped this way

| Block | Why it's there |
|---|---|
| **"Do NOT add an analytics plugin"** | The expected wrong turn, and it's stated twice. On most platforms observability is a plugin you enable, so a model will reach for one by name. Here it's already global, and an added block is noise at best. |
| **"tell me explicitly: is there any unauthenticated route"** | Asking the agent to *report* rather than *fix* is deliberate. Making a route authenticated may be a product decision you don't want made for you — but you absolutely need to know which rows will never be attributable. |
| **"Tell me if you find a path that would produce one row per entity"** | The failure nobody anticipates. The API behaves identically with literal paths, so nothing surfaces the problem until you try a route-level query — by which time the data exists and is unfixable. |
| **"Confirm it is forwarded to the upstream"** | A correlation id the gateway keeps to itself correlates the gateway with itself. The value comes from your backend logging the same id, and that's a conversation with your teams rather than a config change. |
| **"LATENCY-PROFILE REVIEW"** | Route design has analytics consequences. Nobody thinks of "should these be two routes?" as an observability question, and it is one. |
| **"Be explicit about anything now unrecoverable"** | The honest framing. Two of the three decisions can't be applied retroactively, and a reader should learn that from the agent's summary rather than from a disappointing query in six months. |
| **Part B asks for sample counts** | A p99 from twelve requests is noise presented as precision. Asking for the count alongside is the difference between a number and a trustworthy number. |
| **Part B keeps 4xx and 5xx separate** | They mean different things and drive different actions — 5xx is engineering, 4xx is usually a partner or your documentation. A single "error rate" is a number you can't act on. |

## Tweak knobs

**One partner's integration looks broken**
```text
App <<name>> is returning 401 on <<Orders API>>. Tell me whether it is failing EVERY
call or only some, since when, and whether the failures started at a specific time.
Every call means broken configuration on their side; some calls usually means expired
tokens and a client that is not refreshing before expiry.
```

**Find the clients that aren't caching tokens**
```text
Show me token requests per app over the last 24 hours alongside each app's total API
calls. With a 900-second token lifetime a well-behaved client needs about four tokens
an hour regardless of volume — flag anything approaching one token per API call, since
that client has doubled its own latency and made my token endpoint my busiest route.
```

**Build the upgrade pipeline** (needs [solution 03](../03-api-products/))
```text
For <<Orders API>>, show me each app's peak quota consumption as a percentage of its
product limit over the last 7 days. List anything above 80%, with the product and the
peak percentage. I want to open upgrade conversations with evidence rather than a hunch.
```

**Find quiet churn**
```text
Compare apps calling <<Orders API>> this week against last week. List apps that
appeared for the first time, and — more importantly — apps that called last week but
not this week. A partner who stopped calling is either churn, a broken integration, or
an expired credential, and all three deserve a phone call.
```

**Catch degradation early**
```text
Compare p95 latency per route on <<Orders API>> this week against the same period last
week. List any route where p95 increased by more than 20%, with both values and the
change window.
```

**Set up the standing dashboard**
```text
I want five panels, not twenty. Set up: traffic per hour with error rate overlaid; error
rate by route split 4xx/5xx; p95 per route with call counts; top apps by volume; and
apps above 80% of quota. Everything else I will ask ad hoc.
```

## Known failure modes when running this prompt

- **The agent adds a `helix-analytics` block.** The expected wrong turn. Reply:
  `analytics is enabled globally on this platform — there is no plugin to add. Remove
  that block and instead confirm identity, path templating and the correlation id.`
- **The agent reports "analytics is now enabled."** It was already enabled. Ask it to
  restate what actually changed: identity coverage, path templating, and the request id.
- **The query returns nothing.** No traffic has been generated yet, or you're outside
  the retention window. Analytics is capture-then-query — run
  [`verify.sh`](gateway/verify.sh) to seed a known pattern first.
- **Every row is an IP address.** Identity isn't resolved on that route. That is not
  fixable by querying differently, and rows already captured stay that way.
- **The per-route breakdown is a list of order ids.** Paths aren't templated. Fix the
  spec so future data is usable; the existing data is not recoverable.
- **The agent invents a field name and the query returns nothing.** Reply: `show me the
  field you filtered on, from the actual schema.` Field names vary by build.
- **A latency number looks implausible.** Ask for the sample count. A p99 from a handful
  of requests is noise.
- **`X-Request-Id` doesn't appear in your backend logs.** The gateway is forwarding it;
  your services aren't recording it. That's a conversation with your teams, and it is
  the cheapest observability work available.

## Related

- **[`charts.md`](charts.md)** — the full catalogue: twelve questions, what each answer
  is for, what breaks it, and a five-panel dashboard layout.
- **[Solution 01 — OAuth 2.0 with JWT](../01-oauth-jwt/helix-agent-prompt.md)** — the
  prerequisite. Attribution needs identity, and identity can't be added retroactively.
- **[Solution 03 — API Products](../03-api-products/helix-agent-prompt.md)** — deploy
  this and charts 5–7 start working.
