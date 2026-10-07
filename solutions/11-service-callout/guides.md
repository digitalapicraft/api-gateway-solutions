# Guides — one outbound call, then injection

> [Overview](README.md) · [Business need](business-need.md) · [Architecture](architecture.md) · **Guides** · [Agent prompt](helix-agent-prompt.md) · [Tests](tests.md) · [API reference](api-reference.md)

---

Three ways to build the same thing, then how to see it work. Whichever way you
pick, the result is one API with two routes: `GET /storefront/orders`, enriched
with the tenant's profile and set to carry on if the profile service is down, and
`POST /storefront/checkout`, enriched the same way but set to refuse instead.

## Pick your path

| | Choose this if you… | Go to |
|---|---|---|
| **1. Helix Agent** | want the quickest result and are happy to paste a prompt | [Build it with the Helix Agent](#build-it-with-the-helix-agent) |
| **2. Helix control plane** | prefer clicking through screens | [Build it in the UI](#build-it-in-the-ui) |
| **3. API script** | are scripting this, or wiring it into a pipeline | [Install it directly](#install-it-directly) |

Then, for everyone: [See it work](#see-it-work) · [Variations](#variations) ·
[Configuration reference](#configuration-reference) · [Troubleshooting](#troubleshooting)

## Build it with the Helix Agent

Works on a **fresh, empty org**. [`helix-agent-prompt.md`](helix-agent-prompt.md)
has two steps: step 1 creates the API, the read route, the callout and the
headers; step 2 adds the write route with the opposite failure policy. Paste step
1, let the agent read the revision back, then paste step 2 in the same session.

The steps are kept small on purpose. `update_route_spec` replaces the whole route
list each time, so every step resends the complete route spec, and small steps
keep that small enough for the agent to send cleanly.

**Why the prompt is shaped the way it is:**

- **`phase: rewrite`, with the reason.** The most likely wrong turn, and it fails
  silently — an access-phase callout returns 200 with no headers and no error.
  Saying only "use rewrite" isn't enough; without the reason, the agent tidies it
  back.
- **The variable names are literal.** `${ctx.helix.service_callout.tenant_plan}`
  looks like a path to look up. An agent that "corrects" it produces empty headers.
- **`set`, not `add`.** A security property, not a style choice. With `add`, a
  client can assert its own tenant plan and the backend believes it.
- **`profile_status` from the callout's HTTP status.** Lets the backend tell a
  real answer from a fail-open miss. Left to itself, the agent maps only the
  business fields.
- **`fail-close` on the write path.** Makes the failure policy a deliberate
  per-route decision rather than an inherited default. It's the most consequential
  choice in this solution.
- **The live route object, named explicitly.** Plugins nested under
  `x-helix-gateway` on a live route are silently discarded — the write reports
  success and the dry-run passes. A shorter instruction ("put the plugins in a flat
  plugins map, do not nest them under x-helix-gateway") was ignored every time it
  was tried, right after the agent had read the spec generator's document-shaped
  examples. What worked was naming the live route object, telling the agent not to
  follow those examples, and showing the route-object shape — the wording in step 1.

**If the agent run goes wrong:**

| Symptom | Cause |
|---|---|
| 200, and no enrichment headers at the backend | The callout is on the access phase, or it failed under `fail-open`. |
| The headers arrive empty | The variable name doesn't match `ctx.helix.<ctx_namespace>.<field>` exactly. |
| One header missing, the others fine | That mapped path matched nothing. That isn't an error. |
| A client-supplied header survives | `headers.add` where `headers.set` belongs. |
| 503 on every request | The callout can't be reached and the policy is `fail-close`. That's the configured behaviour — check the URI from the gateway's network, not your laptop. |
| One route works and the other doesn't | The plugin is per route. |
| The write succeeds and the routes have no plugins | Nested under `x-helix-gateway`. Read the revision back. |
| Deploy fails: `Only INACTIVE revisions can be updated` | Clone the revision or undeploy, then apply. |

See [AGENT-GUIDE.md](../../AGENT-GUIDE.md) for the ground rules these prompts
assume.

## Build it in the UI

Screen and button names below are the real ones. The API lives under
**API Gateway** in the left sidebar.

**Before you start:**

- **You have an account.** If you don't, register for a free trial at
  [trial.digitalapi.ai](https://trial.digitalapi.ai/). A new trial org comes with
  a `test` environment, which is all this walkthrough needs.
- **You can create APIs.** If you don't see an **Add API** button, ask your org
  admin.

**1. Import the API**
1. Go to **API Gateway → APIs**, click **Add API** (or **Create your first API**).
2. Set **Method** to **Import an OpenAPI spec**.
3. Drag in [`example/api-spec.yaml`](example/api-spec.yaml), or paste its
   contents, then click **Import**. Nothing in it needs filling in.

This creates the API and its first revision. The imported spec already carries
`service-callout` (phase `rewrite`, fail-open on the read route, fail-close on the
write route), `proxy-rewrite` with the three `headers.set` entries, and
`request-id` API-wide, with the settings in the
[Configuration reference](#configuration-reference). There is no separate screen
to set them up in this walkthrough.

**2. Give it an upstream, then deploy it**
1. Go to **API Gateway → Upstreams → Add Upstream**. Name it, pick environment
   `test`, point it at `httpbin.org` (or your own backend), then
   **Create Upstream**.
2. Back on the API's page, click **Deploy** on the revision. The dialog asks you
   to map an upstream for `test`. Pick the one you just created, then **Deploy**.

No products, developers or apps are needed: the package ships unauthenticated.

**Using your own profile service?** Before importing, change the callout `uri` in
the spec to your service, and the `map_response_to_ctx` paths to its response
shape.

## Install it directly

If you'd rather script it against the control plane:

```bash
export ORG=<ORG_ID>
export TOKEN=<control-plane bearer token>      # short-lived
export BASE=https://<YOUR_GATEWAY_HOST>/api
H=(-H "authorization: Bearer $TOKEN" -H 'content-type: application/json')

# 1. Import the spec. Nothing in it needs filling in. Keep both ids it returns.
#    For your own profile service, first change the callout uri and the
#    map_response_to_ctx paths.
curl -s -H "authorization: Bearer $TOKEN" \
  -F "file=@example/api-spec.yaml" "$BASE/orgs/$ORG/apis/from-spec"
# → {"api":{"id":"<API_ID>", ...}, "revision":{"id":"<REVISION_ID>", ...}}

# 2. Import does NOT make the routes live. Create an upstream, bind it
#    to the revision, then deploy the revision.
curl -s "${H[@]}" -X POST "$BASE/orgs/$ORG/envs/<TEST_ENV_ID>/upstreams" \
  -d '{"name":"httpbin","specification":{"scheme":"https","nodes":[{"host":"httpbin.org","port":443,"weight":1}]}}'
# → {"id":"<UPSTREAM_ID>", ...}

curl -s "${H[@]}" -X PATCH "$BASE/orgs/$ORG/apis/<API_ID>/revisions/<REVISION_ID>/upstream-bindings/add" \
  -d '{"environmentUpstreams":[{"environmentId":"<TEST_ENV_ID>","upstreamId":"<UPSTREAM_ID>"}]}'
curl -s "${H[@]}" -X POST "$BASE/orgs/$ORG/apis/<API_ID>/revisions/<REVISION_ID>/deploy" \
  -d '{"environmentId":"<TEST_ENV_ID>","force":false}'
```

> Revisions must be **INACTIVE** to accept a spec change. If it's live, undeploy
> first, or clone the revision so you keep a rollback target.

The same calls without narration: [API reference](api-reference.md).

## See it work

The example backend echoes the headers it received, so you can see what your
backend would get:

```bash
curl -s "https://<YOUR_GATEWAY_HOST>/storefront/orders"
# the echo includes X-Tenant-Plan, X-Tenant-Contact and X-Profile-Status: 200

curl -s "https://<YOUR_GATEWAY_HOST>/storefront/orders" -H "X-Tenant-Plan: Enterprise-Unlimited"
# X-Tenant-Plan in the echo is still the profile service's value, not yours
```

To run all five checks as a script:

```bash
GATEWAY=https://<YOUR_GATEWAY_HOST> ./example/verify.sh
# Against a backend that doesn't echo headers:
GATEWAY=https://<YOUR_GATEWAY_HOST> ECHOES_HEADERS=0 ./example/verify.sh
```

`READ_PATH`, `WRITE_PATH`, `PLAN_HEADER`, `CONTACT_HEADER` and `STATUS_HEADER`
override the defaults if yours differ. Exit code 0 means the lookup happened,
reached the backend on both routes, and can't be spoofed. The failure-policy and
wrong-phase cases need a deliberately broken route: [Tests](tests.md).

## Variations

Each of these is a follow-up you can paste to the agent after step 2.

**Point it at my real profile service**
```text
Change the callout uri to {{callout_uri}} and
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
worth it at {{requests_per_second}} requests per second.
```

**Identify the caller first** — that's [solution 08](../08-api-key/).
```text
Add API-key authentication to both routes with helix-auth validate,
validate_auth_type key-auth, reading the key from X-Api-Key, and keep the callout
exactly as it is.
```

## Configuration reference

Source of truth: [`example/api-spec.yaml`](example/api-spec.yaml).

The read route:

```yaml
service-callout:
  uri: https://jsonplaceholder.typicode.com/users/1
  method: GET
  phase: rewrite
  timeout: 3000
  ssl_verify: true
  map_response_to_ctx:
    tenant_plan: body.company.name
    tenant_contact: body.email
    profile_status: status
  error_handling:
    policy: fail-open
  keepalive:
    enabled: true
    pool_size: 32
    timeout: 60000

proxy-rewrite:
  uri: /headers
  headers:
    set:
      X-Tenant-Plan: "${ctx.helix.service_callout.tenant_plan}"
      X-Tenant-Contact: "${ctx.helix.service_callout.tenant_contact}"
      X-Profile-Status: "${ctx.helix.service_callout.profile_status}"
```

The write route is the same, except: `map_response_to_ctx` maps only
`tenant_plan` and `profile_status`; `error_handling` is
`{policy: fail-close, message: "tenant profile unavailable"}`; and `proxy-rewrite`
uses `uri: /post` and sets only `X-Tenant-Plan` and `X-Profile-Status`.

| Plugin | Field | Value here | What it means |
|---|---|---|---|
| `service-callout` | `uri` / `method` | the public sample profile service / `GET` | Replace with your own profile service. It must be reachable from the gateway. |
| `service-callout` | `phase` | `rewrite` | **Must** be `rewrite` so the values exist before `proxy-rewrite` reads them. `access` gives 200 with no headers and no error. |
| `service-callout` | `timeout` | `3000` (ms) | The call is synchronous, so this is added to the route's worst case. Choose it; don't inherit it. |
| `service-callout` | `ssl_verify` | `true` | Verify the profile service's TLS certificate. |
| `service-callout` | `map_response_to_ctx` | `tenant_plan: body.company.name`, `tenant_contact: body.email`, `profile_status: status` | Dotted paths into the answer. `status` and `headers.<name>` are also available. A path that matches nothing gives no value and no error. |
| `service-callout` | `error_handling.policy` | `fail-open` (read) / `fail-close` (write) | What happens when the call fails. `log-only` is the third option. |
| `service-callout` | `error_handling.message` | `tenant profile unavailable` (write route) | The message returned with the 503 under `fail-close`. |
| `service-callout` | `keepalive` | `enabled: true`, `pool_size: 32`, `timeout: 60000` | Reuse connections. Without it every request pays a fresh TCP and TLS handshake to the profile service. |
| `service-callout` | `ctx_namespace` | not set — the default, `service_callout` | Part of every variable name. Change it and every reference must change. |
| `proxy-rewrite` | `uri` | `/headers` (read) / `/post` (write) | The backend path. |
| `proxy-rewrite` | `headers.set` | `X-Tenant-*: ${ctx.helix.service_callout.<field>}` | `set` replaces a client's header; `add` wouldn't. The variable name is literal, dots included. |
| `request-id` | `algorithm` / `header_name` | `uuid` / `X-Request-Id` | API-wide. A callout doubles the places a request can be slow or fail; this ties them together. |

Placeholders in this package: `<ORG_ID>`, `<API_ID>`, `<REVISION_ID>`,
`<UPSTREAM_ID>`, `<TEST_ENV_ID>`, `<YOUR_GATEWAY_HOST>`. Replace all of them
before you deploy.

Every field of every plugin, and the wider product docs:
[docs.digitalapi.ai/api-gateway](https://docs.digitalapi.ai/api-gateway).

## Troubleshooting

- **`phase: access` silently does nothing.** It must be `rewrite`. 200, no
  headers, no error. Phase beats priority.
- **The variable name is literal**, dots and all:
  `${ctx.helix.<ctx_namespace>.<field>}`. Change `ctx_namespace` and every
  reference changes.
- **A mapped path that matches nothing is not an error.** A typo is invisible until
  a backend notices.
- **`set`, not `add`** — or callers can assert their own values.
- **Under `fail-open` the headers are absent, not empty.** Backends must handle
  that explicitly.
- **The callout is synchronous and its `timeout` is added to your worst case.**
  Choose the number; don't inherit it.
- **Keep `keepalive` on.** Without it every request pays a fresh TCP and TLS
  handshake to the profile service.
- **It is per route, not per API.** A route added later gets no enrichment, and
  the symptom is a missing header rather than an error.
- **This is not an authorization decision.** `service-callout` stores an answer;
  it doesn't act on it. To *reject* based on the answer, use `forward-auth` or
  `opa`.
- **Anything you inject is visible to the backend and to anything on the way.**
  Map what the backend needs, not the whole profile.
- **503 on every request** under `fail-close` means the profile service can't be
  reached **from the gateway**. Test the URI from the gateway's network, not your
  laptop.
- **Confirm `service-callout` exists in your org** before you design around it.
