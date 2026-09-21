# Agent-mode prompt — one shared lookup at the edge

Paste this into **Helix Agent Mode**. It works from a **fresh, empty org**: the
agent *creates* the API, adds the callout and the header injection, dry-runs, and
stops.

Replace the `<<...>>` values. Everything else is deliberate — the table below
says why each block earns its place. Read [AGENT-GUIDE.md](../../AGENT-GUIDE.md)
first if you haven't.

---

## The prompt

> **Run it in steps, not as one mega-prompt.** These are the exact prompts
> verified on the **default agent model**. Paste **Step 1**, let the agent build
> and stop at the dry-run; confirm; then paste **Step 2**. `update_route_spec` is a
> full replace, so each step resends the whole route spec — keeping the steps
> small is what keeps the tool arguments small enough to serialise cleanly.

**Step 1 — the API, the callout, and the injection**

```text
Create a new REST API called "Storefront API" whose backend needs the calling
tenant's profile on every request. This is a fresh org — I have no existing API.

Upstream: https://httpbin.org (public; its /headers endpoint echoes request
headers back, so I can see what the backend received). Deploy to the "test"
environment.

Route: GET /storefront/orders -> proxy-rewrite uri /headers

Add service-callout on that route:
  uri https://jsonplaceholder.typicode.com/users/1
  method GET, phase rewrite, timeout 3000
  map_response_to_ctx: tenant_plan from body.company.name, tenant_contact from
  body.email, profile_status from status
  error_handling policy fail-open

phase MUST be rewrite. proxy-rewrite runs in the rewrite phase, so an access-phase
callout produces its values after the injection has already happened and the
headers arrive empty.

Then have proxy-rewrite SET these headers — set, not add, so a client cannot send
its own:
  X-Tenant-Plan: ${ctx.helix.service_callout.tenant_plan}
  X-Tenant-Contact: ${ctx.helix.service_callout.tenant_contact}
  X-Profile-Status: ${ctx.helix.service_callout.profile_status}
Those variable names are literal — the dots are part of the name.

Put request-id in the SERVICE spec so it applies API-wide.

We are editing a LIVE route object, not authoring an OpenAPI document — so do not
follow the spec-generator examples for plugin placement. Each route object in
routeSpec takes "plugins" as a TOP-LEVEL key, and inside it each plugin is
keyed by its own NAME:
  { "name": ..., "uri": ..., "methods": [...], "service_id": ...,
    "plugins": { "<plugin-name>": { <that plugin's own fields> } } }
Do not promote a plugin's fields into the plugins map: "plugins":
{"response_status": 202, "content_type": ...} is four broken plugins, not one
working one — the plugin name level is mandatory.
There must be no "x-helix-gateway" key anywhere in a route object: a live route
silently discards that wrapper, the write still reports success, and the route
deploys with no plugins at all. Set only the fields you need.
Skip validate_route — use dry_run_deploy. Bind the upstream, run dry_run_deploy,
then call get_revision and show me the stored routeSpec. Wait before deploying.
```

**Step 2 — the write path, with the opposite failure policy**

```text
Now add a second route, POST /storefront/checkout -> proxy-rewrite uri /post, with
the same callout but error_handling policy fail-close and the message "tenant
profile unavailable" — on a write path we would rather fail than act without the
answer. Send the routeSpec as a JSON array of both routes, then show me the stored
routeSpec and a curl that proves a client cannot spoof X-Tenant-Plan.
```


---

## Why the prompt is shaped this way

| Block | Why it's there |
|---|---|
| **"This is a fresh org — create one"** | On a new free-trial org there is no API to "find". The agent must create it, or it stalls looking for something that isn't there. |
| **"httpbin … /headers echoes request headers back"** | You can see exactly what the backend received. Without an echo upstream the whole solution is invisible and you are trusting the config. |
| **"phase MUST be rewrite"**, with the reason | The single most likely wrong turn, and the one that fails silently: an access-phase callout returns 200 with no headers at all. Stating only "use rewrite" is not enough — the agent needs the reason or it will tidy it back. |
| **"Those variable names are literal — the dots are part of the name"** | `${ctx.helix.service_callout.tenant_plan}` looks like a path expression. An agent that "corrects" it to a nested lookup produces empty headers. |
| **"SET these headers — set, not add"** | A security property, not a style choice. With `add`, a client can assert its own tenant plan and the backend will believe it. |
| **"map_response_to_ctx … profile_status from status"** | Mapping the callout's own HTTP status lets the backend tell a real answer from a fail-open miss. An agent left to itself maps only the business fields. |
| **Step 2's `fail-close` on the write path** | Makes the failure policy an explicit, per-route decision rather than an inherited default. It is the most consequential choice in this solution. |
| **"a curl that proves a client cannot spoof X-Tenant-Plan"** | Turns the security property into something demonstrated rather than claimed. |
| **"a FLAT plugins map … do NOT nest under x-helix-gateway"** | Verified: nested plugins on a live route are silently discarded — the write reports success, the dry-run passes, and the route deploys with nothing on it. |
| **"call get_revision and show me the stored routeSpec"** | The only check that catches that silent drop. |
| **"Skip validate_route — use dry_run_deploy"** | Verified: `validate_route` fails on this build whatever you put in it — the tool posts `{"route": …}` and the control plane requires `{"routeSpec": [ … ]}`. |
| **"Set only the fields you need"** | Verified: an agent volunteering `regex_uri: [null, null]` and `headers: {}` had two dry-runs rejected before removing them. |

## Tweak knobs

**Point it at my real profile service**
```text
Change the callout uri to <<https://profile.internal/api/tenants/current>> and
forward the caller's authorization header to it with forwarded_headers. Then tell
me what the profile service now needs to handle that it did not before.
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
would look like, what the invalidation story is, and be honest about whether it is
worth it at <<200>> requests per second.
```

**Identify the caller first**
```text
Add API-key authentication to both routes with helix-auth validate,
validate_auth_type key-auth, reading the key from X-Api-Key, and keep the callout
exactly as it is.
```
(That's [solution 08](../08-api-key/).)

## Known failure modes when running this prompt

- **200, and no enrichment headers at the backend.** Either the callout is on the
  access phase, or it failed under `fail-open`. Reply: `set phase: rewrite — the
  injection runs in the rewrite phase and an access-phase callout is too late.`
- **The headers arrive empty.** The variable name does not match
  `ctx.helix.<ctx_namespace>.<field>` exactly.
- **One header missing, the others fine.** That mapped path resolved to nothing. A
  path matching nothing is not an error.
- **A client-supplied header survives.** `headers.add` where `headers.set` belongs.
- **503 on every request.** The callout is unreachable and the policy is
  `fail-close`. That is the configured behaviour — check the callout URI from the
  gateway's network, not from your laptop.
- **The write route works and the read route does not (or vice versa).** The plugin
  is per route.
- **The write succeeds and the routes have no plugins.** The agent nested them under
  `x-helix-gateway`. Read the revision back.
- **`validate_route` errors and the agent stalls.** Not your config — the tool is
  broken against this control plane. Reply: `skip validate_route, run
  dry_run_deploy instead.`
- **Deploy fails with `Only INACTIVE revisions can be updated`.** Clone the
  revision or undeploy, then apply.

## Related

- **[Solution 12 — Key-value map](../12-key-value-map/helix-agent-prompt.md)** —
  the other way to get per-request data into a route.
- **[Solution 08 — API keys](../08-api-key/helix-agent-prompt.md)** — identify the
  caller; this package ships open on purpose.
