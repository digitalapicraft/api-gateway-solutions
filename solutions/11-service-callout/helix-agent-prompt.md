# Agent-mode prompt — one shared lookup at the edge

> [Overview](README.md) · [Business need](business-need.md) · [Architecture](architecture.md) · [Guides](guides.md) · **Agent prompt** · [Tests](tests.md) · [API reference](api-reference.md)

---

Paste step 1 and wait for the agent to read the revision back. Then paste step 2
in the same session. Keep the `${ctx.helix…}` variable names exactly as written
— the dots are part of each name.

See [Guides](guides.md#build-it-with-the-helix-agent) if something looks off.

## Prompt

### Step 1 — the API, the callout, and the injection

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

### Step 2 — the write path, with the opposite failure policy

```text
Add a second route, POST /storefront/checkout -> proxy-rewrite uri /post, with the
same callout but error_handling policy fail-close and the message "tenant profile
unavailable" — on a write path we would rather fail than act without the answer.

Send routeSpec as a JSON array of both routes, then show me the stored routeSpec
and a curl that proves a client cannot spoof X-Tenant-Plan.
```
