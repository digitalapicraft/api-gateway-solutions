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

Works on a **fresh, empty org**: the backend echoes the headers it receives, and
a public sample service stands in for your profile service.
[`helix-agent-prompt.md`](helix-agent-prompt.md) has two steps: Step 1 creates the
API and both routes, Step 2 adds the profile lookup and the headers to both.
**Paste the whole prompt as one message**, replacing the `{{...}}` values, then
run the checks in [See it work](#see-it-work).

**Before you trust it, check** what was stored in the revision, not what the
agent said:

- Both routes carry `service-callout` with **`phase: rewrite`**. In `access` the
  lookup finishes too late: the backend gets no headers, and nothing errors.
- Its `map_response_to_ctx` takes the plan from `body.company.name`, the contact
  from `body.email`, and the lookup's own `status`. The agent picks its own names
  for these fields; any names work.
- `proxy-rewrite` uses **`headers.set`**, not `add`, and each header reads the
  literal `${ctx.helix.service_callout.<field>}`, dots included, with a `<field>`
  that `map_response_to_ctx` defines.
- `GET /storefront/orders` is `fail-open`. `POST /storefront/checkout` is
  `fail-close` with the message `tenant profile unavailable`.
- The agent may leave out the 3000 ms `timeout` and the API-wide `request-id`
  that this package's spec carries. Add them if you want the same result.

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

If an API with the same name already exists in your org, the import fails with
*API with name '<name>' already exists*. Type another name in the form's
**Display name** field, which overrides the name in the spec, and import again.

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

1. **Plugin** — pick the plugin from the catalog. The lookup is listed as
   **Service Callout**.
2. **Scope** — choose **Specific endpoint** and pick the route. (**Entire
   Revision** would apply it to every route.)
3. **Configure** — the JSON editor and the Properties list sit side by side.
   **Paste the JSON below into the JSON editor**, rather than filling in the
   Properties fields: these settings are nested, and the JSON carries all of
   them at once. Then **Next**. The tables pick out the settings that matter
   most; the JSON holds all of them.
4. **Review** — shows the configuration before and after. Click **Apply**.

Run the wizard once for each plugin on each route: four times in all.

Two rules hold on both routes:

- **`phase` must be `rewrite`.** That makes the lookup finish before the header
  values are filled in. Set to `access`, it runs too late: the headers are left
  out altogether, and a header of the same name that the client sent is
  stripped too. Nothing errors.
- **Copy the `${ctx.helix.service_callout.…}` header values exactly, dots
  included.** Each one is the name under which the lookup stored a field. With a
  typo, or the wrong namespace, the header is left out, and a header of the
  same name that the client sent is stripped too, again with no error.

On the `GET /storefront/orders` route (Scope: **Specific endpoint**, that
route), the lookup is **fail-open**: if the
profile service is down, the call still reaches the backend, just without the
headers.

1. **Service Callout (`service-callout`) — looks up the tenant's profile.** It
   calls the profile service and keeps three fields from the reply: the plan,
   the contact email, and the reply's status code.

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

1. **Service Callout (`service-callout`) — the same lookup, refusing to go on
   without it.** It keeps two fields this time: the plan and the reply's status
   code.

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
your service, and the `map_response_to_ctx` paths to its response shape. To
look up each caller's own profile rather than one fixed record, see
[Look up the calling tenant](#variations).

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

**Changing it later.** A change to the upstream's host or port applies to the
live API straight away, with no new deploy. A change to its scheme does not:
undeploy the revision and deploy it again. A change to routes or plugins does
need one, because a live revision can't be edited: use **Clone Revision**, make
your change on the copy, then **Force Deploy** it. Rolling back needs no copy:
click **Deploy**, pick the older revision (for example `r1`), and click **Force
Deploy**.

No products, developers or apps are needed: the package ships unauthenticated.

## Install it directly

To script it, call the control plane instead. `BASE` is the API address the
portal calls (it usually starts with `api-`), not the portal page and not the
gateway's address:

```bash
export ORG=<ORG_ID>
export TOKEN=<control-plane bearer token>      # short-lived
export BASE=https://<YOUR_CONTROL_PLANE_API>/api
H=(-H "authorization: Bearer $TOKEN" -H 'content-type: application/json')

# 1. Import the spec. Nothing in it needs filling in. Keep both ids it returns.
#    For your own profile service, first change the callout uri and the
#    map_response_to_ctx paths.
#    The upload is multipart/form-data (-F "file=@..."). Send only the
#    authorization header with it: a JSON content-type header breaks the upload.
#    A JSON body, {"spec": <the document>}, also works.
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

**Look up the calling tenant.** The example asks for the same record
(`/users/1`) on every call, only so that it runs with nothing to fill in. In real
use, each caller needs its own profile. The callout's `uri` can't contain
request variables, but `custom_query_params` and `custom_headers` can. So keep
the `uri` fixed and send the tenant's id as a query parameter or a header:

```json
{
  "uri": "https://profiles.example.com/tenant",
  "custom_query_params": {
    "tenant_id": "$http_x_tenant_id"
  }
}
```

Here `$http_x_tenant_id` is the value of the caller's `X-Tenant-Id` header.
`custom_headers` takes the same form. Don't trust an id the caller simply types
in: take it from the caller's sign-in instead (see
[solution 08](../08-api-key/)). The profile service must answer with a single
object, not a list: see [Configuration reference](#configuration-reference).

The rest are follow-ups you can paste to the agent in the same chat, once the
build is working. Like the prompt, each says what you want to be true.

**Point it at my real profile service**
```text
Fetch the profile from {{callout_uri}} instead, and pass the caller's
Authorization header through to it. Then tell me what the profile service now has
to handle that it didn't before.
```

**The answer should decide whether the request is allowed**
```text
I want to refuse callers whose account is suspended, not just pass the plan on.
Tell me plainly whether this lookup can do that, and if not, show me the version of
this route that can.
```

**Cut the cost of the callout**
```text
This adds a round trip to every request. Show me what caching the lookup would
look like, what the invalidation story is, and whether it is worth it at
{{requests_per_second}} requests per second.
```

**Identify the caller first** — that's [solution 08](../08-api-key/).
```text
Require an app's API key in the X-Api-Key header on both routes, and keep the
lookup exactly as it is. Then create a developer, a product and an app, and give me
the key.
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
| `service-callout` | `phase` | `rewrite` | **Must** be `rewrite` so the values exist before `proxy-rewrite` reads them. With `access`, the route answers 200, the headers are left out (a client's own header of the same name is stripped too), and nothing errors. |
| `service-callout` | `timeout` | `3000` (ms) | The request waits for the lookup, so this is added to the route's worst case. Choose it; don't inherit it. |
| `service-callout` | `ssl_verify` | `true` | Check the profile service's TLS certificate. |
| `service-callout` | `map_response_to_ctx` | `tenant_plan: body.company.name`, `tenant_contact: body.email`, `profile_status: status` | Dotted paths into the answer. `status` and `headers.<name>` are also available. A path that matches nothing gives no value and no error. **The answer must be a single object, not a list:** a path into a list, such as `body.0.email`, doesn't resolve. |
| `service-callout` | `error_handling.policy` | `fail-open` (read) / `fail-close` (write) | What happens when the call fails. See the four options below. |
| `service-callout` | `error_handling.message` | `tenant profile unavailable` (write route) | The message returned with the 503 under `fail-close`. |
| `service-callout` | `keepalive` | `enabled: true`, `pool_size: 32`, `timeout: 60000` | Reuse connections. Without it every request pays a fresh TCP and TLS handshake to the profile service. `pool_size` is 5 if you don't set it. |
| `service-callout` | `ctx_namespace` | not set — the default, `service_callout` | Part of every variable name. Change it and every reference must change. |
| `proxy-rewrite` | `uri` | `/headers` (read) / `/post` (write) | The backend path. |
| `proxy-rewrite` | `headers.set` | `X-Tenant-*: ${ctx.helix.service_callout.<field>}` | `set` replaces a client's header; `add` wouldn't. The variable name is literal, dots included. |
| `request-id` | `algorithm` / `header_name` | `uuid` / `X-Request-Id` | API-wide. A callout doubles the places a request can be slow or fail; this id ties the gateway's and the backend's records of one request together. It isn't sent to the profile service unless you add it (below). |

**What counts as a failed lookup.** The profile service can't be reached, it
doesn't answer within `timeout`, or it answers with an error such as HTTP 404 (not
found) or 500 (server error). All of these trigger the policy, so a tenant with no
profile record is handled the same way as an outage.

**The four ways to handle a failed or slow lookup.** Three are values of
`error_handling.policy`; the fourth is a separate setting.

| Setting | What the caller and the backend see |
|---|---|
| `fail-open` | The request carries on; the headers are absent. |
| `fail-close` | HTTP 503 with `error_handling.message`; the backend is never called. |
| `log-only` | From the caller's side, the same as `fail-open`: the request carries on and the headers are absent. The error is only logged. |
| `async: true` | The request doesn't wait for the lookup, and the answer is never stored for it, so the headers are absent. That defeats the purpose here. |

**Other `service-callout` fields** the example doesn't set:

| Field | What it does |
|---|---|
| `forwarded_headers` | A list of header names from the caller's request to pass on to the profile service. |
| `custom_headers` | Headers to add to the lookup. Values can use request variables. |
| `custom_query_params` | Query parameters to add to the lookup's address. Values can use request variables. A parameter already in `uri` is kept, unless one here has the same name. |
| `request_body_template` | A body to send with the lookup, for a profile service that expects one. Values can use request variables. If set, it replaces `send_request_object`. |
| `send_request_object` | Sends the profile service a JSON description of the caller's request: method, path, headers, body and query string. Its headers include any key or token the caller sent. |

**Pass the request id to the profile service.** `X-Request-Id` reaches your
backend, but not the profile service. To send it there too, add
`custom_headers` to the callout's JSON. `$http_x_request_id` is the request's
`X-Request-Id` value, and `X-Corr-Id` is the header name the profile service
gets; use whatever name it expects:

```json
{
  "custom_headers": {
    "X-Corr-Id": "$http_x_request_id"
  }
}
```

Placeholders in this package: `<ORG_ID>`, `<API_ID>`, `<REVISION_ID>`,
`<UPSTREAM_ID>`, `<TEST_ENV_ID>`, `<YOUR_GATEWAY_HOST>`. Replace all of them
before you deploy.

Every field of every plugin, and the wider product docs:
[docs.digitalapi.ai/api-gateway](https://docs.digitalapi.ai/api-gateway).

## Troubleshooting

- **A tenant with no profile record gets HTTP 503 on checkout.** A 404 from the
  profile service counts as a failed lookup, the same as an outage, so
  `fail-close` refuses the request. On the read route (`fail-open`) the request
  carries on, and `X-Profile-Status` arrives as `404`.
- **200, but no enrichment headers at the backend.** The lookup is in
  `phase: access`; it must be `rewrite`. Phase beats priority, and nothing
  errors. The headers are left out altogether, and a caller's own header of the
  same name is stripped too. A lookup that failed under `fail-open` also leaves
  the headers out.
- **200, no enrichment headers, and a caller's own `X-Tenant-Plan` reaches the
  backend.** Nothing writes the headers: the lookup stores the profile and no
  plugin reads it. Add `proxy-rewrite` with `headers.set` reading
  `${ctx.helix.<ctx_namespace>.<field>}`, and put the lookup in `phase: rewrite`.
- **No headers on reads, 503 on every write, and a `lua-callout` on the
  routes.** The agent built its own mechanism, and its code reads fields the
  lookup never stored: the namespace holds only the names in
  `map_response_to_ctx`. Replace it with this package's design: `service-callout`
  in `phase: rewrite`, and `proxy-rewrite` with `headers.set`.
- **A header is missing though the lookup worked.** The variable name is
  literal, dots and all: `${ctx.helix.<ctx_namespace>.<field>}`, and `<field>`
  must be a name `map_response_to_ctx` defines. With a typo or the wrong
  namespace, the header is left out, and a caller's own header of the same name
  is stripped too. Change `ctx_namespace` and every reference changes.
- **A header is missing, and the profile service answers with a list.** A path
  into a list, such as `body.0.email`, doesn't resolve. The profile service must
  answer with a single object.
- **The routes exist but carry no plugins.** The agent put them under
  `x-helix-gateway` inside the live route, which a live route drops without an
  error. On a live route, plugins go in a top-level `plugins` map, each under
  its own name.
- **A mapped path that matches nothing is not an error.** A typo is invisible until
  a backend notices.
- **`set`, not `add`** — or callers can assert their own values.
- **Under `fail-open` the headers are absent, not empty.** Backends must handle
  that explicitly.
- **The callout is synchronous and its `timeout` is added to your worst case.**
  Choose the number; don't inherit it.
- **Keep `keepalive` on.** Without it every request pays a fresh TCP and TLS
  handshake to the profile service.
- **One route works and the other doesn't.** The lookup is set per route, not
  per API, so check each route has its own `service-callout` and
  `proxy-rewrite`. A route added later gets no enrichment either, and the
  symptom is a missing header rather than an error.
- **This is not an authorization decision.** `service-callout` stores an answer;
  it doesn't act on it. To *reject* based on the answer, use `forward-auth` or
  `opa`.
- **Anything you inject is visible to the backend and to anything on the way.**
  Map what the backend needs, not the whole profile.
- **503 on every request** under `fail-close` means the profile service can't be
  reached **from the gateway**. Test the URI from the gateway's network, not your
  laptop.
- **`Only INACTIVE revisions can be updated`.** A live revision can't be
  changed. Clone the revision or undeploy it, then apply the change.
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
