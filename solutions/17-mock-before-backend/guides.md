# Guides — Mock before the backend

> [Overview](README.md) · [Business need](business-need.md) · [Architecture](architecture.md) · **Guides** · [Agent prompt](helix-agent-prompt.md) · [Tests](tests.md) · [API reference](api-reference.md)

---

Two parts. First, deploy the mock so the frontend has a working URL today. Then,
when the backend is ready, switch the same routes over to it.

## Pick your path

| | Choose this if you… | Go to |
|---|---|---|
| **1. Helix Agent** | want the quickest result and are happy to paste a prompt | [Build it with the Helix Agent](#build-it-with-the-helix-agent) |
| **2. Helix control plane** | prefer clicking through screens | [Build it in the UI](#build-it-in-the-ui) |
| **3. API script** | are scripting this, or wiring it into a pipeline | [Install it directly](#install-it-directly) |

Then, for everyone: [See it work](#see-it-work) (call the mock, then switch
over) · [Variations](#variations) · [Configuration reference](#configuration-reference) ·
[Troubleshooting](#troubleshooting)

## Build it with the Helix Agent

The fastest path, and it works on a **fresh, empty org**. One prompt builds and
deploys the mocked API: the two routes, their sample responses and the upstream.
[`helix-agent-prompt.md`](helix-agent-prompt.md) has it as two numbered steps:
paste the whole thing as one message, or one step at a time if the run ends
early. The agent asks you to confirm before it deploys: answer yes. To switch
over later, follow [step 4 of Build it in the UI](#build-it-in-the-ui), and
check the upstream the agent created first (see
[Troubleshooting](#troubleshooting)). The agent also picks the name of the
header that marks a mocked answer, so read it back from the revision and run
the checks with `MOCK_HEADER=<that name>` (see
[Run it as a script](#run-it-as-a-script)).

See [AGENT-GUIDE.md](../../AGENT-GUIDE.md) for the ground rules these prompts
assume.

## Build it in the UI

Screen and button names below are the real ones. Everything lives under
**API Gateway** in the left sidebar.

**Before you start:**

- **You have an account.** If you don't, register for a free trial at
  [trial.digitalapi.ai](https://trial.digitalapi.ai/). A new trial org comes
  with a `test` environment, which is all this walkthrough needs.
- **You can create and deploy APIs.** Org admins and gateway admins can. If you
  don't see an **Add API** button, ask your org admin.

**1. Create the API**

Pick one of the two ways below. Both give you an API called `Shipments API`
with two routes and no mock yet.

*Option A — from scratch*
1. Go to **API Gateway → APIs**, click **Add API** (or **Create your first API**).
2. Choose **Create from scratch**. Set **Display name** to `Shipments API`, then
   **Create**.
3. On the API's page, open **Configuration → Routes** and add two routes:
   - method `GET`, path `/shipments/:shipmentId`, to track one shipment. The
     gateway writes a path parameter as `:shipmentId`, not `{shipmentId}`.
   - method `POST`, path `/shipments`, to create one

   The route form opens already filled in with the name *New* and the path
   `/new-route`. Clear both fields first, then type your own.

*Option B — from an OpenAPI spec*
1. Go to **API Gateway → APIs**, click **Add API** (or **Create your first API**).
2. Set **Method** to **Import an OpenAPI spec**.
3. Drag in or browse to your own OpenAPI 3.0 file, or use our example,
   [`example/api-spec-basic.yaml`](example/api-spec-basic.yaml): the same two
   routes with no mock. It is the version you switch to later, so it already
   carries a request id and the path mapping for the sample backend (see step
   4). There is no option to paste the spec as text. Then click **Import**.

If an API with the same name already exists in your org, the import fails with
*API with name '<name>' already exists*. Type another name in the form's
**Display name** field, which overrides the name in the spec, and import again.

> **A spec can carry the plugins too.** Add an `x-helix-gateway` block that
> lists them. At the top level of the file it covers every route; under one
> path and method it covers that route only:
>
> ```yaml
> paths:
>   /shipments:
>     post:
>       x-helix-gateway:
>         plugins:
>           mocking:
>             response_status: 201
>             content_type: application/json
>             response_example: '{"shipmentId":"SHP-1001","status":"LABEL_CREATED"}'
> ```
>
> [`example/api-spec.yaml`](example/api-spec.yaml) is this API with the mock
> already in place. Import that instead and you can skip step 2.

Either way, the API is not live yet: it has no upstream and isn't deployed.
That comes in step 3.

**2. Add the mock**

One plugin, `mocking`, added once to each route, plus `request-id` if you built
from scratch. Add them **before** you deploy: a live revision can't be changed.

On the API's page, open **Configuration → Plugins** and click **Configure
plugin**. A short wizard opens:

1. **Plugin** — pick the plugin from the catalog.
2. **Scope** — **Entire Revision** applies it to every route; **Specific
   endpoint** applies it to one route.
3. **Configure** — the JSON editor and the Properties list sit side by side.
   Paste the JSON below, or fill in the fields. Then **Next**.
4. **Review** — shows the configuration before and after. Click **Apply**.

**Paste the JSON into the JSON editor.** Inside `response_example` the quotes
are written `\"`, because the sample is text inside JSON. Typed into a
**Properties** field, those backslashes would be saved as part of the sample.

1. **`mocking` on `GET /shipments/:shipmentId` — answers with the sample
   shipment.** Scope: **Specific endpoint**, that route. The caller gets HTTP
   200 (OK) and the same shipment, whatever id it asks for.

   ```json
   {"response_status":200,"content_type":"application/json","with_mock_header":true,"response_example":"{\"shipmentId\":\"SHP-1001\",\"status\":\"IN_TRANSIT\",\"carrier\":\"Acme Freight\",\"eta\":\"2026-11-04T17:00:00Z\",\"events\":[{\"at\":\"2026-10-28T09:12:00Z\",\"status\":\"PICKED_UP\",\"location\":\"Rotterdam\"},{\"at\":\"2026-10-29T22:40:00Z\",\"status\":\"DEPARTED_HUB\",\"location\":\"Rotterdam\"},{\"at\":\"2026-10-30T06:05:00Z\",\"status\":\"ARRIVED_HUB\",\"location\":\"Leeds\"}]}"}
   ```

2. **`mocking` on `POST /shipments` — answers that the shipment was created.**
   Scope: **Specific endpoint**, that route. The caller gets HTTP 201 (created),
   a sample body, and `Location: /shipments/SHP-1001`.

   ```json
   {"response_status":201,"content_type":"application/json","with_mock_header":true,"response_headers":{"Location":"/shipments/SHP-1001"},"response_example":"{\"shipmentId\":\"SHP-1001\",\"status\":\"LABEL_CREATED\",\"carrier\":\"Acme Freight\",\"eta\":\"2026-11-04T17:00:00Z\",\"events\":[]}"}
   ```

3. **`request-id` — an id on every response, mocked or real.** Only if you
   built from scratch: `api-spec-basic.yaml` already carries it. Scope:
   **Entire Revision**. Every response then has an `X-Request-Id` header the
   frontend can quote in a bug report, and `verify.sh` checks for it.

   ```json
   {"algorithm":"uuid","header_name":"X-Request-Id"}
   ```

[`example/api-spec.yaml`](example/api-spec.yaml) writes each sample over several
lines; one line works the same.

**3. Give it an upstream, then deploy it**

The mock never calls a backend, but **a revision can't deploy without an
upstream**. Use the backend you will switch to. For this walkthrough that is the
public sample backend.

1. Go to **API Gateway → Upstreams → Add Upstream**. Name it, pick environment
   `test`, and add a node at `jsonplaceholder.typicode.com`, port `443`, scheme
   HTTPS (or your own backend's host). If you switch the scheme to HTTP, the
   port stays at `443`: change it to `80` by hand.
2. **Pass Host** is set to **Rewrite**, which makes **Upstream Host** required.
   It fills in from the node's host; check it reads
   `jsonplaceholder.typicode.com`.
3. Click **Next** through the remaining tabs, then **Add Upstream**.
4. Back on the API's page, click **Deploy** on the revision. The dialog asks you
   to map an upstream for `test`. Pick the one you just created, then click
   **Map & Deploy**. (The button reads **Map & Deploy** while no upstream is
   mapped yet, and **Deploy** once one is.)

Give the frontend team the gateway host and the two paths. They can start now.

**4. Switch over when the backend is ready**

A live revision can't be edited, so the switch is a copy without the mock:

1. On the API's page, use **Clone Revision**.
2. On the copy, open **Configuration → Plugins** and remove `mocking` from both
   routes.
3. **Only for the sample backend:** `jsonplaceholder.typicode.com` has no
   `/shipments`, so add `proxy-rewrite` to each route to map the paths onto its
   `/posts` (JSON in the [Configuration reference](#configuration-reference)).
   If you imported `api-spec-basic.yaml` it is already there. With your own
   backend serving `/shipments`, skip this.
4. Make sure the upstream points at the real backend, with **Pass Host** set to
   **Rewrite**, then **Force Deploy** the copy. Within a few seconds the same calls reach the backend, and `x-mock-by`
   is gone.

**Changing it later.** A change to the upstream's host or port applies to the
live API straight away, with no new deploy. A change to its scheme does not:
undeploy the revision and deploy it again. A change to routes or plugins does
need one: use **Clone Revision**, make your change on the copy, then **Force
Deploy** it. To go back to the mock, click **Deploy**, pick the mocked revision
(for example `r1`), and click **Force Deploy**; no clone is needed.

## Install it directly

`CP` is the API address the portal calls (it usually starts with `api-`), not
the portal page and not the gateway's address.

```bash
export ORG=<ORG_ID>
export TOKEN=<control-plane bearer token>      # short-lived
export CP=https://<YOUR_CONTROL_PLANE_API>
H=(-H "authorization: Bearer $TOKEN" -H 'content-type: application/json')

# 1. Import the mocked spec. Keep both ids the response returns.
curl -s -H "authorization: Bearer $TOKEN" -F "file=@example/api-spec.yaml" \
  "$CP/api/orgs/$ORG/apis/from-spec"
# → {"api":{"id":"<API_ID>", ...}, "revision":{"id":"<REVISION_ID>", ...}}

# 2. Create an upstream, bind it, deploy. Required even though the mock never
#    calls it. Keep pass_host and upstream_host, or the backend later receives
#    your gateway's host name and every call returns 502.
curl -s "${H[@]}" -X POST "$CP/api/orgs/$ORG/envs/<ENV_ID>/upstreams" \
  -d '{"name":"shipments-backend","specification":{"scheme":"https","pass_host":"rewrite","upstream_host":"jsonplaceholder.typicode.com","nodes":[{"host":"jsonplaceholder.typicode.com","port":443,"weight":1}]}}'
# → {"id":"<UPSTREAM_ID>", ...}
curl -s "${H[@]}" -X PUT "$CP/api/orgs/$ORG/apis/<API_ID>/revisions/<REVISION_ID>/envs/<ENV_ID>/bind-upstream" \
  -d '{"upstreamId":"<UPSTREAM_ID>"}'
curl -s "${H[@]}" -X POST "$CP/api/orgs/$ORG/apis/<API_ID>/revisions/<REVISION_ID>/envs/<ENV_ID>/deploy" \
  -d '{"force":false}'

# 3. Later, the switch-over: a new revision of the SAME API from the no-mock
#    spec, bound to the upstream, force-deployed over the mocked one.
curl -s -H "authorization: Bearer $TOKEN" -F "file=@example/api-spec-basic.yaml" \
  "$CP/api/orgs/$ORG/apis/<API_ID>/revisions/from-spec"
# → {"id":"<NEW_REVISION_ID>","revisionNumber":2,"state":"INACTIVE", ...}
curl -s "${H[@]}" -X PUT "$CP/api/orgs/$ORG/apis/<API_ID>/revisions/<NEW_REVISION_ID>/envs/<ENV_ID>/bind-upstream" \
  -d '{"upstreamId":"<UPSTREAM_ID>"}'
curl -s "${H[@]}" -X POST "$CP/api/orgs/$ORG/apis/<API_ID>/revisions/<NEW_REVISION_ID>/envs/<ENV_ID>/deploy" \
  -d '{"force":true}'

# Back to the mock: deploy the first revision again, with force.
curl -s "${H[@]}" -X POST "$CP/api/orgs/$ORG/apis/<API_ID>/revisions/<REVISION_ID>/envs/<ENV_ID>/deploy" \
  -d '{"force":true}'
```

A new revision starts with no upstream, so bind it before the deploy. Without
`"force":true` the deploy is refused while the other revision is live. The same
calls without narration: [API reference](api-reference.md).

## See it work

Call the mock the way the frontend will:

```bash
G=https://<YOUR_GATEWAY_HOST>
curl -s -i $G/shipments/SHP-1001     # 200, the sample shipment, x-mock-by: HELIX/...
curl -s $G/shipments/anything        # the same shipment: every id gets one answer
curl -s -i -X POST $G/shipments -H 'content-type: application/json' \
  -d '{"origin":"Rotterdam","destination":"Leeds"}'
                                     # 201, Location: /shipments/SHP-1001
```

After the switch-over, send the same calls. `GET /shipments/1` now returns the
sample backend's post 1, and `POST /shipments` its 201 with `"id": 101`. There is
no `x-mock-by` header. The host and paths are the ones the frontend already
uses.

### Run it as a script

`example/verify.sh` checks both stages. Run it once after deploying the mock,
then again with `STAGE=backend` after the switch-over:

```bash
GATEWAY=https://<YOUR_GATEWAY_HOST> ./example/verify.sh                 # the mock
GATEWAY=https://<YOUR_GATEWAY_HOST> STAGE=backend ./example/verify.sh   # after the switch
```

Exit code 0 means every check in that stage held. It needs `jq`. After an
agent build, add `MOCK_HEADER=<the header the agent chose>` to the first
command: it looks for `x-mock-by` by default. What each check proves:
[Tests](tests.md).

## Variations

**Answer slowly, to test loading states.** Add `"delay": 2` to a route's
`mocking` block. The mock waits that many **seconds** before answering.

**Random data of the right shape.** Replace `response_example` with
`response_schema`, a JSON Schema. Each call then gets made-up values of the
right types, different every time, which is useful for testing layout with
varied data. It isn't the agreed sample, so keep the fixed example for the
contract.

**Your own marker header.** Set `with_mock_header` to `false` and add a header
of your own in `response_headers`, such as `"X-Mock": "true"`. It disappears
with the mock at the switch-over, just like `x-mock-by`.

**Beyond a static mock.** For different answers per caller, see
[solution 12](../12-key-value-store/). To turn away a create with missing fields,
before and after the switch-over, see [solution 18](../18-validate-request-body/).

## Configuration reference

The mock, on each route:

| Field | Value here | What it means |
|---|---|---|
| `response_status` | `200` (GET), `201` (POST) | The status the caller gets. Default `200`. |
| `content_type` | `application/json` | The `Content-Type` of the answer. |
| `response_example` | the sample JSON | The body, sent as written. A `$` followed by a letter or digit is read as a variable. |
| `response_headers` | `Location: /shipments/SHP-1001` (POST) | Extra headers on the answer. |
| `with_mock_header` | `true` | Adds `x-mock-by` to every answer. On unless set to `false`. |
| `delay` | not set | Seconds to wait before answering. Default `0`. |
| `response_schema` | not set | A JSON Schema to generate random data from, instead of `response_example`. |

```yaml
# API-wide — an id on every response, mocked or real
request-id:
  algorithm: uuid
  header_name: X-Request-Id

# Switched-over version, sample backend only — map the paths onto /posts
proxy-rewrite:                           # on GET /shipments/:shipmentId
  regex_uri: ["^/shipments/(.*)$", "/posts/$1"]
proxy-rewrite:                           # on POST /shipments
  uri: /posts
```

The same `proxy-rewrite` blocks as JSON, for the plugin wizard:
`{"regex_uri":["^/shipments/(.*)$","/posts/$1"]}` and `{"uri":"/posts"}`.

Source of truth: [`example/api-spec.yaml`](example/api-spec.yaml) for the mock.
[`example/api-spec-basic.yaml`](example/api-spec-basic.yaml) is the same routes
with no mock: the switched-over version, and the starting point for adding the
mock yourself.

Placeholders in this package: `<ORG_ID>`, `<ENV_ID>`, `<API_ID>`,
`<REVISION_ID>`, `<NEW_REVISION_ID>`, `<UPSTREAM_ID>`, `<YOUR_GATEWAY_HOST>`,
`<YOUR_CONTROL_PLANE_API>`. Replace all of them before you run anything.

Every field of every plugin: [docs.digitalapi.ai/api-gateway](https://docs.digitalapi.ai/api-gateway).

## Troubleshooting

- **The deploy is refused with "Upstream not configured for environment".** A
  revision needs an upstream even when the mock answers every route. Bind one
  (step 3), then deploy.
- **The switch-over deploy is refused: "already has revision … deployed for
  this API".** Another revision of this API is live. Use **Force Deploy**, or
  `"force":true` through the API.
- **The new revision has no upstream.** A revision created from a spec starts
  with none. Map the upstream in the deploy dialog, or bind it through the API,
  before deploying.
- **`GET /shipments/SHP-1001` returns 404 Route Not Found after an agent
  build.** The route was stored as `/shipments/{shipmentId}`. Change it to
  `/shipments/:shipmentId` on a cloned revision and **Force Deploy** it. Check
  the revision whatever the prompt says.
- **A value in the sample comes back empty.** It started with `$`, which the
  mock reads as a variable. Write amounts as `12.50 USD`, not `$12.50`.
- **The sample comes back with backslashes in it.** The JSON was typed into a
  **Properties** field with `\"` quotes. Paste it into the JSON editor instead,
  or type plain quotes in the field.
- **The browser blocks the call with a CORS error.** The mock sends no CORS
  headers. Add the `cors` plugin, as [solution 12](../12-key-value-store/) does,
  or call through your frontend's development proxy.
- **After the switch-over, `GET /shipments/1` returns 404 with an empty body.**
  The backend has no such path. With the sample backend, `proxy-rewrite` is
  missing (step 4).
- **After the switch-over, `x-mock-by` is still there.** The mocked revision is
  still live. Deploy the copy with **Force Deploy**.
- **After the switch-over, every call returns 502 Bad Gateway.** The upstream
  sends your gateway's host name to the backend. The mock never called the
  upstream, so nothing showed this before. Open the upstream, set **Pass Host**
  to **Rewrite** and **Upstream Host** to the backend's host
  (`jsonplaceholder.typicode.com` for the sample). It applies straight away, with
  no new deploy. An upstream the Helix Agent created can need this.
- **After an agent build, the marker isn't `x-mock-by`, or reads
  `helix-gateway`.** The agent may switch the mock's own marker off and write
  one itself, under the same name or another, such as `X-Mock: true`. Either way
  the header is there while mocked and goes away with the mock. Read the name
  back from the revision and run the checks with `MOCK_HEADER=<that name>`.
- **Use the trace inspector to see who answered.** On the API's page, open the
  **Observability** tab and click **Start trace session**. A mocked call shows
  as **Upstream not called**, answered by `mocking`; after the switch-over it
  shows the backend's status. A session stops after 10 requests, and the list
  needs **Refresh**. More in [solution 16](../16-request-tracing/).
- **See what changed, and when, in Audit Logs.** **Observability → Audit Logs**
  lists every clone, plugin change and deploy. Its times are in your local time,
  while analytics uses UTC. Anything done with your token, including scripts and
  the Helix Agent, appears under your name.
