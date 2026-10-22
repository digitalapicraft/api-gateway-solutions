# Guides — a bidirectional gRPC stream, authenticated at the edge

> [Overview](README.md) · [Business need](business-need.md) · [Architecture](architecture.md) · **Guides** · [Agent prompt](helix-agent-prompt.md) · [Tests](tests.md) · [API reference](api-reference.md)

---

Three ways to build the same thing, then how to see it work. Whichever way you
pick, the result is one API whose routes are gRPC method paths, each checking an
app key as the stream opens, in front of an upstream whose scheme is `grpc`.

**This package has two halves.** [`example/api-spec.yaml`](example/api-spec.yaml)
carries the routes and the key check. The gRPC setting lives on a separate
**upstream** object, which you create first. Import the spec without it and the
routes proxy over plain HTTP to a gRPC port, which fails as if the backend were
broken.

## Pick your path

| | Choose this if you… | Go to |
|---|---|---|
| **1. Helix Agent** | want the quickest result and are happy to paste a prompt | [Build it with the Helix Agent](#build-it-with-the-helix-agent) |
| **2. Helix control plane** | prefer clicking through screens and want to see every setting | [Build it in the UI](#build-it-in-the-ui) |
| **3. API script** | are scripting this, or wiring it into a pipeline | [Install it directly](#install-it-directly) |

Then, for everyone: [See it work](#see-it-work) · [Variations](#variations) ·
[Configuration reference](#configuration-reference) · [Troubleshooting](#troubleshooting)

## Build it with the Helix Agent

[`helix-agent-prompt.md`](helix-agent-prompt.md) has four steps: the upstream, the
API, the `Ping` route, then bind, deploy and read it back. **Paste each as its own
message.** The prompt routes `Ping` only; for the streaming methods and schema
discovery, import [`example/api-spec.yaml`](example/api-spec.yaml) instead.

See [AGENT-GUIDE.md](../../AGENT-GUIDE.md) for the ground rules these prompts
assume.

## Build it in the UI

Screen and button names below are the real ones. The API lives under
**API Gateway** in the left sidebar; developers, products and apps live under
**API Distribution**.

**Before you start:**

- **You have an account.** If you don't, register for a free trial at
  [trial.digitalapi.ai](https://trial.digitalapi.ai/). A new trial org comes with a
  `test` environment.
- **You can create APIs, products and apps.** If you don't see an **Add API**,
  **Add API Product** or **Add App** button, ask your org admin.
- **You have a gRPC backend the gateway can reach**, and know its host and port.

**1. Create the API**

Pick one of the two ways below. Both give you the same thing: an API called
`Timing Unit Stream API` with five routes and no plugins yet.

*Option A — from scratch*
1. Go to **API Gateway → APIs**, click **Add API** (or **Create your first API**).
2. Choose **Create from scratch**. Set **Display name** to
   `Timing Unit Stream API`, then **Create**.
3. On the API's page, open **Configuration → Routes** and add five routes, all
   with method `POST`. Each path is a gRPC method path, written
   `/<package>.<Service>/<Method>`, because every gRPC call is a `POST` to one:
   - `/timing.TimingUnit/Ping`, a quick one-off health check
   - `/timing.TimingUnit/Status`, the long-lived status stream
   - `/timing.TimingUnit/Commands`, the long-lived command stream
   - `/grpc.reflection.v1alpha.ServerReflection/ServerReflectionInfo` and
     `/grpc.reflection.v1.ServerReflection/ServerReflectionInfo`, which let a
     client discover the service's methods. Add **both**: a client tries `v1`
     first and only falls back to `v1alpha` if `v1` answers cleanly.

   The route form opens already filled in with the name *New* and the path
   `/new-route`. Clear both fields first, then type your own.

*Option B — from an OpenAPI spec*
1. Go to **API Gateway → APIs**, click **Add API** (or **Create your first API**).
2. Set **Method** to **Import an OpenAPI spec**.
3. Drag in your own OpenAPI 3.0 file, or use our example,
   [`example/api-spec-basic.yaml`](example/api-spec-basic.yaml): the same five
   routes, no plugins. Then click **Import**.

> **A spec can carry the plugins too.** Add an `x-helix-gateway` block that
> lists them. At the top level of the file it covers every route; under one
> path and method it covers that route only. This is one route's:
>
> ```yaml
> /timing.TimingUnit/Ping:
>   post:
>     x-helix-gateway:
>       plugins:
>         helix-auth:
>           mode: validate
>           validate_auth_type: key-auth
>           apikey: { source: header, key: X-Unit-Key }
> ```
>
> [`example/api-spec.yaml`](example/api-spec.yaml) is this API with all its
> plugins already in place. Import that instead and you can skip step 2.

Either way, the API is not live yet: it has no upstream and isn't deployed.
That comes in step 3.

**2. Add the plugins**

One plugin checks every caller. Add it **before** you deploy: a live revision
can't be changed.

It goes on each of the five routes, the same way every time.

On the API's page, open **Configuration → Plugins** and click **Configure
plugin**. A short wizard opens:

1. **Plugin** — pick the plugin from the catalog.
2. **Scope** — choose **Specific endpoint** and pick the route. (**Entire
   Revision** would apply it to every route.)
3. **Configure** — the JSON editor and the Properties list sit side by side.
   Paste the JSON below, or fill in the fields. Then **Next**.
4. **Review** — shows the configuration before and after. Click **Apply**.

Run the wizard once for each of the five routes.

On **every route** (`Ping`, `Status`, `Commands` and both reflection routes),
each time with Scope **Specific endpoint** and that route:

1. **`helix-auth` — checks who is calling.** It reads the app's key from the
   `X-Unit-Key` gRPC metadata once, when the call or stream opens. A missing or
   unknown key gets HTTP 401 (not authenticated) before the backend is contacted.

   | Field | Value |
   |---|---|
   | **mode** | `validate` |
   | **validate_auth_type** | `key-auth` |
   | **apikey → source** | `header` |
   | **apikey → key** | `X-Unit-Key` |

   ```json
   {"mode":"validate","validate_auth_type":"key-auth","apikey":{"source":"header","key":"X-Unit-Key"}}
   ```

Don't add a plugin that reads or changes the message body on these routes: a
streaming route can't carry one.

Repeat for each route. What every field means, and the optional extra (`request-id`) the full spec adds:
[Configuration reference](#configuration-reference).

**3. Create the gRPC upstream, then deploy it**
1. Go to **API Gateway → Upstreams → Add Upstream**. Name it (for example
   `timing-grpc`), pick environment `test`, and add a node with your gRPC
   backend's host and port.

   The upstream's scheme must be `grpc` (or `grpcs` for a TLS backend). This
   guide has not confirmed a scheme choice on that screen. If you don't see one,
   create the upstream with the API call in
   [Install it directly](#install-it-directly), step 2, then carry on here.
2. **Pass Host** is set to **Rewrite**, which makes **Upstream Host** required.
   It fills in from the node's host; check it matches your gRPC backend.
3. Click **Next** through the remaining tabs, then **Add Upstream**.
4. Back on the API's page, click **Deploy** on the revision. The dialog asks you
   to map an upstream for `test`. Pick the gRPC upstream you just created, then
   click **Map & Deploy**. (The button reads **Map & Deploy** while no upstream
   is mapped yet, and **Deploy** once one is.)

**Changing it later.** A change to the upstream's host or port applies to the
live API straight away, with no new deploy. A change to its **scheme** (`grpc` or
`grpcs`) does not: undeploy the revision and deploy it again. A change to routes or plugins
does need one, because a live revision can't be edited: use **Clone Revision**,
make your change on the copy, then **Force Deploy** it. The same steps roll you
back: clone the older revision and force-deploy that.

**4. Create a product for it**
1. Go to **API Distribution → API Products**, click **Add API Product**.
2. Under **Basic Information**, set a **Display Name**.
3. Under **APIs**, click **Add API**, select this API, then **Continue**.
4. Under **Authentication Methods**, leave the default (`helix-auth`).
5. Under **Quota**, make sure **Enable request quota** is on. It is by default,
   set to 1000 per 1 hour, so don't click the switch: that turns the quota off,
   and every product needs one. Set
   **Request limit**, **Interval** and **Unit** to the allowance you want; here
   it counts **streams, not messages**. Check the summary line, for example
   *"Subscribers can make up to 1000 requests per 1 hour"*.
6. Leave **Quota scope** on **App level**, so every app gets its own allowance.
   **Developer level** makes all of a developer's apps share one.
7. Click **Create API Product**, then **Deploy** it to `test`.

**5. Create a developer**

Go to **API Distribution → Developers**, click **Add Developer**, fill in the name
and email, then **Add**.

**6. Create an app**

Go to **API Distribution → Apps**, click **Add App**. Pick the **Environment** and
the **Developer**, add the product from step 4, pick an authentication method and
let credentials auto-generate, then **Create App**.

**7. Get the app's key**

On the app's **Overview** tab, find the **Authentication** card. It shows
`helix-auth` with a key and a secret, both hidden, each with a show and a copy
button. Copy the **key**, not the secret: the key (the app's client id) is what
clients send as the `X-Unit-Key` gRPC metadata. **Generate New Credentials**, in
the same card, issues a new pair.

## Install it directly

If you'd rather script it against the control plane:

```bash
export ORG=<ORG_ID>
export TOKEN=<control-plane bearer token>      # short-lived
export BASE=https://<YOUR_GATEWAY_HOST>/api
H=(-H "authorization: Bearer $TOKEN" -H 'content-type: application/json')

# 1. Import the spec. Keep both ids the response returns.
curl -s -H "authorization: Bearer $TOKEN" -F "file=@example/api-spec.yaml" \
  "$BASE/orgs/$ORG/apis/from-spec"
# → {"api":{"id":"<API_ID>", ...}, "revision":{"id":"<REVISION_ID>", ...}}

# 2. The gRPC half: an upstream whose scheme is grpc (grpcs for a TLS backend).
curl -s "${H[@]}" -X POST "$BASE/orgs/$ORG/envs/<TEST_ENV_ID>/upstreams" \
  -d '{"name":"timing-grpc","specification":{"scheme":"grpc","type":"roundrobin","pass_host":"node",
       "nodes":[{"host":"<GRPC_UPSTREAM_HOST>","port":<GRPC_UPSTREAM_PORT>,"weight":1,"priority":1}]}}'
# → {"id":"<UPSTREAM_ID>", ...}

# 3. Bind it to the revision, then deploy the revision.
curl -s "${H[@]}" -X PATCH "$BASE/orgs/$ORG/apis/<API_ID>/revisions/<REVISION_ID>/upstream-bindings/add" \
  -d '{"environmentUpstreams":[{"environmentId":"<TEST_ENV_ID>","upstreamId":"<UPSTREAM_ID>"}]}'
curl -s "${H[@]}" -X POST "$BASE/orgs/$ORG/apis/<API_ID>/revisions/<REVISION_ID>/deploy" \
  -d '{"environmentId":"<TEST_ENV_ID>","force":false}'

# 4. A product covering the API, deployed. Every product needs a quota object;
#    here it counts streams, not messages.
curl -s "${H[@]}" -X POST "$BASE/orgs/$ORG/products" \
  -d '{"name":"timing-units","displayName":"Timing units","apiIds":["<API_ID>"],"quota":{"limit":<LIMIT>,"interval":1,"interval_unit":"minute"}}'
# → {"id":"<PRODUCT_ID>", ...}
curl -s "${H[@]}" -X POST "$BASE/orgs/$ORG/envs/<TEST_ENV_ID>/products/<PRODUCT_ID>/deploy"

# 5. A developer, then an app subscribed to the product (products is a
#    {productId: rank} map; developerId and the environment are path segments).
#    The response carries the app's key — that is UNIT_KEY.
curl -s "${H[@]}" -X POST "$BASE/orgs/$ORG/developers" \
  -d '{"firstName":"<FIRST_NAME>","lastName":"<LAST_NAME>","email":"<EMAIL>"}'
# → {"id":"<DEVELOPER_ID>", ...}
curl -s "${H[@]}" -X POST "$BASE/orgs/$ORG/developers/<DEVELOPER_ID>/envs/<TEST_ENV_ID>/apps" \
  -d '{"name":"<APP_NAME>","products":{"<PRODUCT_ID>":1},"plugins":{"helix-auth":{}}}'
```

> **A scheme change does not reach a deployed revision.** If you edit the
> upstream's scheme later, undeploy the revision and deploy it again.

> Revisions must be **INACTIVE** to accept a spec change. If it's live, undeploy
> first, or clone the revision so you keep a rollback target.

The same calls without narration: [API reference](api-reference.md).

## See it work

**Start with the one-off call.** `Ping` is the cheapest proof that routing, the
`grpc` upstream and the key check are all correct. Once it answers, anything still
failing is specific to streaming.

```bash
GW=<your-gateway-host>          # no scheme, e.g. gw.example.com
KEY=<app credential key>

# discover the service over the connection — no .proto needed
grpcurl -H "X-Unit-Key: $KEY" "$GW:443" list
# grpc.reflection.v1alpha.ServerReflection
# timing.TimingUnit

# a one-off call
grpcurl -H "X-Unit-Key: $KEY" -d '{"from":"verify"}' "$GW:443" timing.TimingUnit.Ping

# no key: check the HTTP status directly, because a gRPC client cannot read it
curl -s -o /dev/null -w '%{http_code}\n' --http2 -X POST \
  "https://$GW/timing.TimingUnit/Ping" -H 'content-type: application/grpc'
# 401
```

To run all six checks as a script:

```bash
GATEWAY=<your-gateway-host> \
UNIT_KEY=<app credential key> \
./example/verify.sh
```

No `.proto` file is needed — this package routes reflection, so the schema is
discovered over the connection. `HOLD_SECONDS` defaults to 20. Raise it past the
longest idle gap you expect in production and run it again before you commit to
hours-long connections. What each check proves: [Tests](tests.md).

**Count and time the connections** with the analytics API:

```
POST /api/orgs/{orgId}/analytics/metrics/requests-count
POST /api/orgs/{orgId}/analytics/metrics/response-time     # aggregation: MAX
{ "dimensions": ["api_path"],                              # or ["app_name"]
  "filters": [{"column":"api_name","operator":"EQ","value":["<your api>"]}],
  "excludeTimeUnit": true }
```

`requests-count` is your connection count, one row per stream:

```
/timing.TimingUnit/Commands        1
/timing.TimingUnit/Status          2
/timing.TimingUnit/Ping            5
```

`response-time` is the connection lifetime. A stream held open for 25 seconds
reports about 24,000 ms:

```
/timing.TimingUnit/Commands   24235      <- the held stream
/timing.TimingUnit/Ping           9      <- a one-off call
```

A stream's row appears when the stream **closes**. For counts of connections open
right now, `requests-count` over a recent window answers it.

## Variations

**A TLS backend.** Use `grpcs` and your backend's TLS port on the upstream object;
everything else is unchanged.

**Your own service.** Replace `timing.TimingUnit` with your own package and service
in the route paths. They must match the wire paths exactly: `/<package>.<Service>/<Method>`,
always `POST`. Keep both reflection routes.

**A different key header.** `X-Unit-Key` is arbitrary; any header works, and it
travels as gRPC metadata. Change `apikey.key` on every route.

**No reflection.** If you choose not to route reflection, hand clients a `.proto`
or a protoset, and set `PROTOSET` when you run `verify.sh`. Get one from a backend
that has reflection enabled:
`grpcurl -plaintext -protoset-out svc.protoset <backend:port> describe <pkg>.<Service>`.

**Metering.** A product quota on this API counts **streams**, not messages. That
can be exactly what you want for "how many connections may this unit open"; it
cannot do per-message billing.

## Configuration reference

Source of truth: [`example/api-spec.yaml`](example/api-spec.yaml) for the routes
and plugins, plus the upstream object, which the spec cannot carry.
[`example/api-spec-basic.yaml`](example/api-spec-basic.yaml) is the same routes
with no plugins, for adding them yourself.

Every route — `Ping`, `Status`, `Commands` and both reflection versions — carries
the same block:

```yaml
helix-auth:
  mode: validate
  validate_auth_type: key-auth
  apikey:
    source: header
    key: X-Unit-Key
```

| Plugin / object | Field | Value here | What it means |
|---|---|---|---|
| `helix-auth` | `mode` | `validate` | Checks an existing credential. |
| `helix-auth` | `validate_auth_type` | `key-auth` | A mode of `helix-auth`, not a separate plugin. Resolves the calling app. |
| `helix-auth` | `apikey.source` / `apikey.key` | `header` / `X-Unit-Key` | Read the key from gRPC metadata, which arrives as HTTP/2 headers. |
| `request-id` | `algorithm` / `header_name` | `uuid` / `X-Request-Id` | API-wide. The handle for a caller reporting a dropped stream. |
| upstream | `specification.scheme` | `grpc` | What makes this a gRPC proxy. `grpcs` for TLS. |
| upstream | `specification.type` / `pass_host` | `roundrobin` / `node` | Load-balancing and host-header handling for the node list. |
| upstream | `specification.nodes` | `[{host, port, weight: 1, priority: 1}]` | Your gRPC backend. |

Deliberately **not** in the spec: any plugin that reads or rewrites a body, and any
CORS block — a gRPC client is not a browser, and grpc-web is a different solution.

Idle streams are governed by the route-level `timeout.read`, which every upstream
message restarts. Keep any heartbeat interval shorter than it.

Placeholders in this package: `<ORG_ID>`, `<TEST_ENV_ID>`, `<API_ID>`,
`<REVISION_ID>`, `<UPSTREAM_ID>`, `<PRODUCT_ID>`, `<DEVELOPER_ID>`,
`<GRPC_UPSTREAM_HOST>`, `<GRPC_UPSTREAM_PORT>`, `<LIMIT>`, `<YOUR_GATEWAY_HOST>`.
Replace all of them before you run anything.

Every field of every plugin: [docs.digitalapi.ai/api-gateway](https://docs.digitalapi.ai/api-gateway).

## Troubleshooting

| Symptom | Cause |
|---|---|
| Every call returns 502 | The upstream scheme is `http`, or it was changed without an undeploy and deploy. A scheme edit does not reach a deployed revision. |
| The route never matches | The gRPC method path was "tidied". Restore the dot and the single slash: `/timing.TimingUnit/Ping`. |
| `Unauthenticated` with a complaint about content type | Working as designed — a gateway 401 is not a valid gRPC response. Check the HTTP status directly with `curl`. |
| A client cannot discover the service | Route **both** reflection versions. `v1alpha` alone leaves the `v1` attempt on no route, and the client stops rather than falling back. |
| The stream delivers every message but ends without a gRPC status | Something on the path is dropping HTTP/2 trailers. Every hop between the client and the gateway must speak HTTP/2. `verify.sh` check 4 catches this. |
| The stream breaks as soon as it carries data | A body-touching plugin is on the route. Remove it. |
| An idle stream closes on its own | It exceeded the route's read timeout. Send heartbeats more often than that timeout, or raise it. |
| A revoked app is still connected | Expected. The key is checked once, when the stream opens. The open stream continues until it ends. |
| A quota allows far more messages than expected | Expected. It counts streams, not messages. |
| Deploy fails: `Only INACTIVE revisions can be updated` | Clone the revision or undeploy, then apply. |

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
