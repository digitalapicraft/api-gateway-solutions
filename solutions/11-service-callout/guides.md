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
has two steps: Step 1 creates the API, the read route and the lookup, Step 2 adds
the write route. **Paste Step 1, check the result, then paste Step 2** in the same
chat.

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

**1. Create the API**

Pick one of the two ways below. Both give you the same thing: an API called
`Storefront API` with two routes and no plugins yet.

*Option A — from scratch*
1. Go to **API Gateway → APIs**, click **Add API** (or **Create your first API**).
2. Choose **Create from scratch**. Set **Display name** to `Storefront API`, then
   **Create**.
3. On the API's page, open **Configuration → Routes** and add two routes:
   - `GET /storefront/orders`, the list of orders
   - `POST /storefront/checkout`, placing an order

   The route form opens already filled in with the name *New* and the path
   `/new-route`. Clear both fields first, then type your own.

*Option B — from an OpenAPI spec*
1. Go to **API Gateway → APIs**, click **Add API** (or **Create your first API**).
2. Set **Method** to **Import an OpenAPI spec**.
3. Drag in your own OpenAPI 3.0 file, or use our example,
   [`example/api-spec-basic.yaml`](example/api-spec-basic.yaml): the same two
   routes, no plugins. Then click **Import**.

> **A spec can carry the plugins too.** Add an `x-helix-gateway` block that
> lists them. At the top level of the file it covers every route; under one
> path and method it covers that route only:
>
> ```yaml
> paths:
>   /storefront/orders:
>     get:
>       x-helix-gateway:
>         plugins:
>           service-callout:
>             uri: https://jsonplaceholder.typicode.com/users/1
>             phase: rewrite
>             map_response_to_ctx:
>               tenant_plan: body.company.name
>           proxy-rewrite:
>             uri: /headers
>             headers:
>               set:
>                 X-Tenant-Plan: "${ctx.helix.service_callout.tenant_plan}"
> ```
>
> [`example/api-spec.yaml`](example/api-spec.yaml) is this API with all its
> plugins already in place. Import that instead and you can skip step 2.

Either way, the API is not live yet: it has no upstream and isn't deployed.
That comes in step 3.

**2. Add the plugins**

Two plugins on each route do the work: one looks up the tenant's profile, the
other passes what it found to the backend as headers and sends the call to the
right backend path. Add them **before** you deploy: a live revision can't be
changed.

The two routes get different settings, so each plugin goes on one route, not
on the whole API.

On the API's page, open **Configuration → Plugins** and click **Configure
plugin**. A short wizard opens:

1. **Plugin** — pick the plugin from the catalog.
2. **Scope** — choose **Specific endpoint** and pick the route. (**Entire
   Revision** would apply it to every route.)
3. **Configure** — the JSON editor and the Properties list sit side by side.
   Paste the JSON below, or fill in the fields. Then **Next**. The tables show
   the simple fields; the nested settings are easiest to paste as JSON.
4. **Review** — shows the configuration before and after. Click **Apply**.

Run the wizard once for each plugin on each route: four times in all.

Two rules hold on both routes:

- **`phase` must be `rewrite`.** That makes the lookup finish before the header
  values are filled in. Set to `access`, it runs too late and the headers arrive
  empty, with no error.
- **Copy the `${ctx.helix.service_callout.…}` header values exactly, dots
  included.** Each one is the name under which the lookup stored a field; a
  typo gives an empty header, again with no error.

On the `GET /storefront/orders` route (Scope: **Specific endpoint**, that
route), the lookup is **fail-open**: if the
profile service is down, the call still reaches the backend, just without the
headers.

1. **`service-callout` — looks up the tenant's profile.** It calls the profile
   service and keeps three fields from the reply: the plan, the contact email,
   and the reply's status code.

   | Field | Value |
   |---|---|
   | **uri** | `https://jsonplaceholder.typicode.com/users/1` |
   | **method** | `GET` |
   | **phase** | `rewrite` |
   | **timeout** | `3000` |
   | **ssl_verify** | `true` |
   | **error_handling → policy** | `fail-open` |

   ```json
   {
     "uri": "https://jsonplaceholder.typicode.com/users/1",
     "method": "GET",
     "phase": "rewrite",
     "timeout": 3000,
     "ssl_verify": true,
     "map_response_to_ctx": {
       "tenant_plan": "body.company.name",
       "tenant_contact": "body.email",
       "profile_status": "status"
     },
     "error_handling": {
       "policy": "fail-open"
     },
     "keepalive": {
       "enabled": true,
       "pool_size": 32,
       "timeout": 60000
     }
   }
   ```

2. **`proxy-rewrite` — passes the profile on as headers.** It sends the call to
   `/headers` on the test backend, which echoes back the headers it received,
   and sets three `X-Tenant-*` headers from the lookup.

   ```json
   {
     "uri": "/headers",
     "headers": {
       "set": {
         "X-Tenant-Plan": "${ctx.helix.service_callout.tenant_plan}",
         "X-Tenant-Contact": "${ctx.helix.service_callout.tenant_contact}",
         "X-Profile-Status": "${ctx.helix.service_callout.profile_status}"
       }
     }
   }
   ```

On the `POST /storefront/checkout` route (Scope: **Specific endpoint**, that
route), the lookup is **fail-close**: if the
profile service can't be reached, the gateway answers HTTP 503 (service
unavailable) with `tenant profile unavailable`, and the backend is never called.
Taking an order without knowing the account's status is worse than refusing it.

1. **`service-callout` — the same lookup, refusing to go on without it.** It
   keeps two fields this time: the plan and the reply's status code.

   | Field | Value |
   |---|---|
   | **uri** | `https://jsonplaceholder.typicode.com/users/1` |
   | **method** | `GET` |
   | **phase** | `rewrite` |
   | **timeout** | `3000` |
   | **ssl_verify** | `true` |
   | **error_handling → policy** | `fail-close` |
   | **error_handling → message** | `tenant profile unavailable` |

   ```json
   {
     "uri": "https://jsonplaceholder.typicode.com/users/1",
     "method": "GET",
     "phase": "rewrite",
     "timeout": 3000,
     "ssl_verify": true,
     "map_response_to_ctx": {
       "tenant_plan": "body.company.name",
       "profile_status": "status"
     },
     "error_handling": {
       "policy": "fail-close",
       "message": "tenant profile unavailable"
     },
     "keepalive": {
       "enabled": true,
       "pool_size": 32,
       "timeout": 60000
     }
   }
   ```

2. **`proxy-rewrite` — passes the profile on as headers.** It sends the call to
   `/post` on the test backend, which echoes back what it received.

   ```json
   {
     "uri": "/post",
     "headers": {
       "set": {
         "X-Tenant-Plan": "${ctx.helix.service_callout.tenant_plan}",
         "X-Profile-Status": "${ctx.helix.service_callout.profile_status}"
       }
     }
   }
   ```

Repeat for each plugin and route. The optional extra (`request-id`) the full
spec adds API-wide: [Configuration reference](#configuration-reference).

**Using your own profile service?** In this step, change the callout `uri` to
your service, and the `map_response_to_ctx` paths to its response shape.

**3. Give it an upstream, then deploy it**
1. Go to **API Gateway → Upstreams → Add Upstream**. Name it, pick environment
   `test`, and add a node at `httpbin.org`, port `443`, scheme HTTPS (or your
   own backend). If you switch the scheme to HTTP, the port stays at `443`:
   change it to `80` by hand.
2. **Pass Host** is set to **Rewrite**, which makes **Upstream Host** required.
   It fills in from the node's host; check it reads `httpbin.org`.
3. Click **Next** through the remaining tabs, then **Add Upstream**.
4. Back on the API's page, click **Deploy** on the revision. The dialog asks you
   to map an upstream for `test`. Pick the one you just created, then click
   **Map & Deploy**. (The button reads **Map & Deploy** while no upstream is
   mapped yet, and **Deploy** once one is.)

**Changing it later.** A change to the upstream (host, port, scheme) applies to
the live API straight away, with no new deploy. A change to routes or plugins
does need one, because a live revision can't be edited: use **Clone Revision**,
make your change on the copy, then **Force Deploy** it. The same steps roll you
back: clone the older revision and force-deploy that.

No products, developers or apps are needed: the package ships unauthenticated.

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
# pass_host + upstream_host: without them the backend gets the gateway's host
# and every call returns 502.
curl -s "${H[@]}" -X POST "$BASE/orgs/$ORG/envs/<TEST_ENV_ID>/upstreams" \
  -d '{"name":"httpbin","specification":{"scheme":"https","pass_host":"rewrite","upstream_host":"httpbin.org","nodes":[{"host":"httpbin.org","port":443,"weight":1}]}}'
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
[`example/api-spec-basic.yaml`](example/api-spec-basic.yaml) is the same routes
with no plugins, for adding them yourself.

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
- **Use the trace inspector to see each step.** On the API's page, open the
  **Observability** tab and click **Start trace session**. It shows the headers
  each plugin changes and the request body at every stage, which is the fastest
  way to see what each plugin did to a call. A session stops after 10 requests,
  so use **Advanced: filter which requests to capture** to record only the ones
  you care about (skipped requests don't count). The list doesn't refresh by
  itself: click **Refresh**. The **Inspector** shows API keys and cookies in
  plain text, so don't share your screen or paste a trace into a ticket without
  removing them. A compressed response, which browsers always ask for, is
  unreadable in the **Response** tab, so call the API with curl to read it. The
  **Upstream** tab's **Total** adds connect time to response time, so it can be
  larger than the request's own total.
- **See what changed, and when, in Audit Logs.** **Observability → Audit Logs**
  lists every clone, plugin change and deploy. Its times are in your local time,
  while analytics uses UTC. Anything done with your token, including scripts and
  the Helix Agent, appears under your name.
