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
I want to demonstrate the platform's always-on analytics on a deliberately minimal
API. This is a fresh org — I have no existing API, so CREATE one. Analytics is
already enabled globally, so do NOT add an analytics plugin — there is nothing to
turn on. Keep the API simple and shape the request path so the captured data is
useful.

CONTEXT
- Create an API named <<Posts API>>.
- Upstream: https://jsonplaceholder.typicode.com (public, returns real data).
- Environment: test   (my free-trial org's default).

WHAT I WANT

1. CREATE A MINIMAL API.
   Two routes that proxy the upstream and nothing else on them — this API exists to
   generate analytics traffic, not to enforce policy:
     - GET /posts
     - GET /posts/{postId}
   Route paths match the upstream, so no proxy-rewrite is needed. Do NOT add auth,
   quota or transforms here. (For per-APP attribution rather than per-IP I compose in
   identity later — solution 01 — but not as part of this.)

2. USE TEMPLATED PATHS.
   /posts/{postId} MUST be a path PARAMETER, not a literal id. Grouped by the
   route_id analytics dimension it is ONE row; as literal paths it becomes one row
   per id — a per-route breakdown that is a list of individual records, with
   per-route latency from one sample each. The API works identically either way;
   only the analytics is ruined.

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

## Part B — the queries (NOT via the agent)

Once the API is built and traffic exists, you read analytics through the **metrics
API or the portal** — not by asking the agent. The agent builds APIs; it does not run
analytics queries. A query is a structured POST, e.g.:

```json
POST /api/orgs/{orgId}/analytics/metrics/requests-count
{ "startTime":"…", "endTime":"…",
  "filters":[{"column":"api_name","operator":"EQ","value":["posts-api"]}],
  "dimensions":["route_id","response_status_code"],
  "excludeTimeUnit":true }
```

The full catalogue — traffic over time, errors by route/status, latency (`AVG`/`MAX`
— the API has no percentiles), data transfer, per-app views once you add identity —
with the exact request bodies, dimensions and filter operators, is in
**[`charts.md`](charts.md)**. It also lists what analytics *cannot* do (percentiles,
quota-consumption, per-request lookup), so you don't build a report around a metric
that isn't there.

---

## Why the prompts are shaped this way
## Why the prompts are shaped this way

| Block | Why it's there |
|---|---|
| **"Do NOT add an analytics plugin"** | The expected wrong turn, and it's stated twice. On most platforms observability is a plugin you enable, so a model will reach for one by name. Here it's already global, and an added block is noise at best. |
| **"tell me explicitly: is there any unauthenticated route"** | Asking the agent to *report* rather than *fix* is deliberate. Making a route authenticated may be a product decision you don't want made for you — but you absolutely need to know which rows will never be attributable. |
| **"Tell me if you find a path that would produce one row per entity"** | The failure nobody anticipates. The API behaves identically with literal paths, so nothing surfaces the problem until you try a route-level query — by which time the data exists and is unfixable. |
| **"Confirm it is forwarded to the upstream"** | A correlation id the gateway keeps to itself correlates the gateway with itself. The value comes from your backend logging the same id, and that's a conversation with your teams rather than a config change. |
| **"LATENCY-PROFILE REVIEW"** | Route design has analytics consequences. Nobody thinks of "should these be two routes?" as an observability question, and it is one. |
| **"Be explicit about anything now unrecoverable"** | The honest framing. Two of the three decisions can't be applied retroactively, and a reader should learn that from the agent's summary rather than from a disappointing query in six months. |

## Reading the analytics afterwards

Everything you'd want to *ask* of analytics — traffic over time, errors by route and
status, latency (`AVG`/`MAX`), data transfer, and per-app views once you add identity
— is a query against the **metrics API** (or the portal), not a prompt to the agent.
The agent built the API; it does not read charts.

The real request bodies, dimensions and filter operators are in
[`charts.md`](charts.md), which also states plainly what the API cannot do:
**no percentiles** (only `AVG`/`MIN`/`MAX`/`SUM`), **no quota-consumption metric**
(you can count 429s, not "% of limit used"), and **no per-request lookup** (that's a
log-side join on `X-Request-Id`). Per-app, per-developer and 429/throttle views need
identity ([solution 01](../01-oauth-jwt/)) and, for anything quota-related,
[solution 03](../03-api-products/).

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
- **A latency number looks implausible.** Check the request count for that row — an
  `AVG`/`MAX` over a handful of requests is noise.
- **`X-Request-Id` doesn't appear in your backend logs.** The gateway is forwarding it;
  your services aren't recording it. That's a conversation with your teams, and it is
  the cheapest observability work available.

## Related

- **[`charts.md`](charts.md)** — the full catalogue: the real metrics-API queries, what each answer
  is for, what breaks it, and a five-panel dashboard layout.
- **[Solution 01 — OAuth 2.0 with JWT](../01-oauth-jwt/helix-agent-prompt.md)** — the
  prerequisite. Attribution needs identity, and identity can't be added retroactively.
- **[Solution 03 — API Products](../03-api-products/helix-agent-prompt.md)** — deploy
  this and the quota/429 recipes start working.
