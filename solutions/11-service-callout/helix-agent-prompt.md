# Agent-mode prompt — one shared lookup at the edge

Two steps, from a **fresh, empty org** to a route that calls the profile service
once and hands the answer to the backend as headers the caller cannot forge.

Keep the steps small: `update_route_spec` is a full replace, so each step resends
the whole route spec, and small steps keep the tool arguments small enough to
serialise cleanly. [AGENT-GUIDE.md](../../AGENT-GUIDE.md) carries the standing
rules these prompts assume.

---

## Step 1 — the API, the callout, and the injection

```text
Create a REST API "Storefront API" whose backend needs the calling tenant's profile
on every request. Upstream https://httpbin.org — its /headers endpoint echoes
request headers back, so I can see what the backend received. Environment test.
Fresh org — nothing exists yet.

Route: GET /storefront/orders -> proxy-rewrite uri /headers

Add service-callout on that route:
  uri https://jsonplaceholder.typicode.com/users/1
  method GET, phase rewrite, timeout 3000
  map_response_to_ctx: tenant_plan from body.company.name, tenant_contact from
  body.email, profile_status from status
  error_handling policy fail-open

phase MUST be rewrite. proxy-rewrite runs in the rewrite phase, so an access-phase
callout produces its values after the injection has already happened and the
headers arrive empty, with a 200 and no error.

Then have proxy-rewrite SET these headers — set, not add, so a client cannot assert
its own tenant plan:
  X-Tenant-Plan: ${ctx.helix.service_callout.tenant_plan}
  X-Tenant-Contact: ${ctx.helix.service_callout.tenant_contact}
  X-Profile-Status: ${ctx.helix.service_callout.profile_status}
Those variable names are literal — the dots are part of the name, not a path
expression. Don't "correct" them into a nested lookup.

Put request-id in the SERVICE spec so it applies API-wide. Set only the fields you
need — an empty headers {} or a regex_uri of nulls is rejected at dry-run.

Plugins go in a top-level "plugins" map on the route object, each under its own
plugin name. No "x-helix-gateway" wrapper — a live route discards it silently and
still reports success.

Bind the upstream, run dry_run_deploy, then read the revision back. Wait before
deploying.
```

## Step 2 — the write path, with the opposite failure policy

```text
Add a second route, POST /storefront/checkout -> proxy-rewrite uri /post, with the
same callout but error_handling policy fail-close and the message "tenant profile
unavailable" — on a write path we would rather fail than act without the answer.

Send routeSpec as a JSON array of both routes, then show me the stored routeSpec
and a curl that proves a client cannot spoof X-Tenant-Plan.
```

---

## Why it's shaped this way

- **`phase: rewrite`, with the reason.** The most likely wrong turn, and it fails
  silently — an access-phase callout returns 200 with no headers and no error.
  Saying only "use rewrite" isn't enough; without the reason the agent tidies it
  back.
- **The variable names are literal.** `${ctx.helix.service_callout.tenant_plan}`
  looks like a path expression. An agent that "corrects" it produces empty headers.
- **`set`, not `add`.** A security property, not a style choice. With `add`, a
  client can assert its own tenant plan and the backend believes it.
- **`profile_status` from the callout's HTTP status.** Lets the backend tell a real
  answer from a fail-open miss. An agent left to itself maps only the business
  fields.
- **`fail-close` on the write path.** Makes the failure policy an explicit
  per-route decision rather than an inherited default. It's the most consequential
  choice in this solution.
- **Read the revision back.** Nested plugins on a live route are silently
  discarded — the write reports success and the dry-run passes.

## Tweak knobs

**Point it at my real profile service**
```text
Change the callout uri to <<https://profile.internal/api/tenants/current>> and
forward the caller's authorization header to it with forwarded_headers. Then tell
me what the profile service now has to handle that it didn't before.
```

**The answer should decide whether the request is allowed**
```text
I don't just want the plan as a header — I want to REJECT callers whose account is
suspended. Tell me plainly whether service-callout can do that, and if not, show me
the forward-auth version of this route instead.
```

**Cut the cost of the callout**
```text
This adds a round trip to every request. Show me what caching the callout response
would look like, what the invalidation story is, and be honest about whether it's
worth it at <<200>> requests per second.
```

**Identify the caller first**
```text
Add API-key authentication to both routes with helix-auth validate,
validate_auth_type key-auth, reading the key from X-Api-Key, and keep the callout
exactly as it is.
```
(That's [solution 08](../08-api-key/).)

## When it goes wrong

| Symptom | Cause |
|---|---|
| 200, and no enrichment headers at the backend | The callout is on the access phase, or it failed under `fail-open`. |
| The headers arrive empty | The variable name doesn't match `ctx.helix.<ctx_namespace>.<field>` exactly. |
| One header missing, the others fine | That mapped path resolved to nothing. A path matching nothing is not an error. |
| A client-supplied header survives | `headers.add` where `headers.set` belongs. |
| 503 on every request | The callout is unreachable and the policy is `fail-close`. That's the configured behaviour — check the URI from the gateway's network, not your laptop. |
| One route works and the other doesn't | The plugin is per route. |
| The write succeeds and the routes have no plugins | Nested under `x-helix-gateway`. Read the revision back. |
| Deploy fails: `Only INACTIVE revisions can be updated` | Clone the revision or undeploy, then apply. |

## Related

- **[Solution 12 — Key-value map](../12-key-value-map/helix-agent-prompt.md)** —
  the other way to get per-request data into a route.
- **[Solution 08 — API keys](../08-api-key/helix-agent-prompt.md)** — identify the
  caller; this package ships open on purpose.
