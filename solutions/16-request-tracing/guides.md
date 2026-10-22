# Guides — Request tracing

> [Overview](README.md) · [Business need](business-need.md) · [Architecture](architecture.md) · **Guides** · [Agent prompt](helix-agent-prompt.md) · [Tests](tests.md) · [API reference](api-reference.md)

---

Two parts. First, deploy an API worth tracing: the sample in this package, or
one of your own. Then open a trace session on it and read what comes back.

## Pick your path

To deploy the sample API:

| | Choose this if you… | Go to |
|---|---|---|
| **1. Helix Agent** | want the quickest result and are happy to paste a prompt | [Build it with the Helix Agent](#build-it-with-the-helix-agent) |
| **2. Helix control plane** | prefer clicking through screens | [Build it in the UI](#build-it-in-the-ui) |
| **3. API script** | are scripting this, or wiring it into a pipeline | [Install it directly](#install-it-directly) |

Already have a deployed API you want to debug? Skip straight to
[Start a trace session](#start-a-trace-session).

Then, for everyone: [Start a trace session](#start-a-trace-session) ·
[Read a record](#read-a-record) · [Record only what you need](#record-only-what-you-need) ·
[See it work](#see-it-work) · [Variations](#variations) ·
[Configuration reference](#configuration-reference) · [Troubleshooting](#troubleshooting)

## Build it with the Helix Agent

[`helix-agent-prompt.md`](helix-agent-prompt.md) builds and deploys the sample
API in one message. **The agent can't open a trace session**: tracing is not
part of the API's configuration, and the agent has no tool for it. When it
finishes, continue at [Start a trace session](#start-a-trace-session).

Before you trace, read the deployed revision back. Two things to check:

- `GET /posts/:postId` was stored with a **colon**. A path stored as
  `/posts/{postId}` never matches, and every lookup returns `404 Route Not Found`.
- `POST /posts` carries `request-validation` and `GET /posts/:postId` carries
  `proxy-rewrite`.

See [AGENT-GUIDE.md](../../AGENT-GUIDE.md) for the ground rules these prompts
assume.

## Build it in the UI

Screen and button names below are the real ones.

**Before you start:**

- **You have an account.** If you don't, register for a free trial at
  [trial.digitalapi.ai](https://trial.digitalapi.ai/). A new trial org comes
  with a `test` environment, which is all this walkthrough needs.
- **You're an org admin or a gateway admin.** Those roles can start traces.
  Product owners can't, and won't see **Start tracing session**.

**1. Import the API**
1. Go to **API Gateway → APIs**, click **Add API** (or **Create your first API**).
2. Set **Method** to **Import an OpenAPI spec**.
3. Drag in [`example/api-spec.yaml`](example/api-spec.yaml), or paste its
   contents, then click **Import**.

**2. Give it an upstream, then deploy it**
1. Go to **API Gateway → Upstreams → Add Upstream**. Name it, pick environment
   `test`, point it at `jsonplaceholder.typicode.com`, then **Create Upstream**.
2. Back on the API's page, click **Deploy** on the revision. Map the upstream
   you just created for `test`, then **Deploy**.

Import alone does not bind an upstream or deploy. Until you deploy, there is
nothing to trace.

## Install it directly

```bash
export ORG=<ORG_ID>
export TOKEN=<control-plane bearer token>      # short-lived
export CP=https://<YOUR_CONTROL_PLANE_HOST>
H=(-H "authorization: Bearer $TOKEN" -H 'content-type: application/json')

# 1. Import the spec. Keep both ids the response returns.
curl -s -H "authorization: Bearer $TOKEN" -F "file=@example/api-spec.yaml" \
  "$CP/api/orgs/$ORG/apis/from-spec"
# → {"api":{"id":"<API_ID>", ...}, "revision":{"id":"<REVISION_ID>", ...}}

# 2. Create an upstream, bind it to the revision, deploy the revision.
curl -s "${H[@]}" -X POST "$CP/orgs/$ORG/envs/<ENV_ID>/upstreams" \
  -d '{"name":"posts-upstream","specification":{"scheme":"https","nodes":[{"host":"jsonplaceholder.typicode.com","port":443,"weight":1}]}}'
# → {"id":"<UPSTREAM_ID>", ...}
curl -s "${H[@]}" -X PATCH "$CP/api/orgs/$ORG/apis/<API_ID>/revisions/<REVISION_ID>/upstream-bindings/add" \
  -d '{"environmentUpstreams":[{"environmentId":"<ENV_ID>","upstreamId":"<UPSTREAM_ID>"}]}'
curl -s "${H[@]}" -X POST "$CP/api/orgs/$ORG/apis/<API_ID>/revisions/<REVISION_ID>/deploy" \
  -d '{"environmentId":"<ENV_ID>","force":false}'

# 3. Open a trace session on it: 5 minutes, every request recorded.
curl -s "${H[@]}" -X POST "$CP/api/orgs/$ORG/apis/<API_ID>/envs/<ENV_ID>/trace/sessions" \
  -d '{"ttl_seconds":300}'
# → {"status":"active","session_id":"<SESSION_ID>","max_requests":10,"requests_traced":0, ...}

# 4. Send traffic, then read the records. Each raw_json is one full record.
curl -s "${H[@]}" "$CP/api/orgs/$ORG/trace/sessions/<SESSION_ID>/traces?limit=100" \
  | jq '.traces[].raw_json | fromjson | {method: .request.method, uri: .request.uri,
        status: .response.status, outcome, short_circuit, backend: .upstream.status}'

# 5. Stop it.
curl -s "${H[@]}" -X POST "$CP/api/orgs/$ORG/apis/<API_ID>/envs/<ENV_ID>/trace/sessions/<SESSION_ID>/stop"
```

The upstream call has no `/api` prefix. That is a real inconsistency in the
platform, not a typo. The same calls without narration:
[API reference](api-reference.md).

## Start a trace session

You can start one from two places: **Observability → Traces → Start tracing
session**, or **Start Trace** on the API's own page.

1. **Environment.** Pick the environment the API is deployed in. The API list
   stays disabled ("Select an environment first") until you do, because a
   session belongs to one API in one environment.
2. **API.** Pick the API.
3. **Duration.** Pick a card:

   | Card | Duration | Good for |
   |---|---|---|
   | **Quick check** | 1 minute | Validate a single change |
   | **Standard debug** | 5 minutes | Most investigations |
   | **Deep dive** | 15 minutes | Reproduce intermittent |
   | **Long capture** | 1 hour | Forensic / overnight |
   | Custom | 60 to 3,600 seconds | |

   Whichever you pick, the session records **up to 10 requests** by default,
   then stops recording. A longer duration gives the problem more time to
   happen. It doesn't give you more records.
4. Optional: **Advanced: filter which requests to capture.** See
   [Record only what you need](#record-only-what-you-need).
5. Click **Start tracing**. You land on the session's page, marked **Active**.

Now make the failing call happen: send it yourself, or ask the partner to retry.
For the sample API:

```bash
G=https://<YOUR_GATEWAY_HOST>
curl -s -X POST $G/posts -H 'content-type: application/json' -d '{"body":"no title"}'   # 400
curl -s $G/posts/1 -o /dev/null -w '%{http_code}\n'                                     # 200
curl -s $G/posts/999999 -o /dev/null -w '%{http_code}\n'                                # 404
```

Rows appear within a few seconds, with columns **Time**, **Method / Path**,
**Status** and **Latency**. A summary bar above them shows the total, errors,
latency percentiles and the top route.

## Read a record

Click the **path** in a row. The path is the button; the rest of the row does
nothing when clicked. The **Inspector** opens with the **Phase timeline** and
these tabs:

| Tab | Look here for |
|---|---|
| **Headers** | Request headers as received, and response headers as sent. |
| **Upstream** | The backend's address and status, and its connect and response times. |
| **Query** | Query parameters. |
| **Request** | The request body as received. |
| **Upstream Body** | The request body as your backend received it, after every plugin. |
| **Response** | The response body (the first few KB). |
| **Raw JSON** | The full record. Copy this into a ticket. |

Then answer one question: **who answered?**

- **The `POST /posts` 400.** Outcome **short circuit**, plugin
  `request-validation`, in the rewrite phase. There is no upstream phase and no
  backend status. **The gateway said no**, and the backend never saw it. The
  response body says why: `property "title" is required`.
- **The `GET /posts/1` 200.** In the rewrite phase, `proxy-rewrite`'s changes
  list `x-partner-channel` added with value `api`. The caller's response doesn't
  carry that header. Only the backend received it, and this record is the only
  place that shows it. The upstream phase takes most of the total time.
- **The `GET /posts/999999` 404.** No short circuit. **Upstream** shows status
  `404`. **The backend said no.** The gateway did its job and passed the answer
  through.

The full reading guide, including every outcome, is in
[Architecture](architecture.md#reading-a-record-who-answered).

## Record only what you need

Ten records go fast on an API with real traffic. A filter decides which requests
count. Requests that don't match are not recorded and don't use up the 10. The
filter is checked **after** the response, so you can filter on the status.

Open **Advanced: filter which requests to capture** in the start dialog, or pass
`filter` to the API:

| To record only… | Condition | `filter` in the API |
|---|---|---|
| failures | `status` ≥ `400` | `[["status", ">=", 400]]` |
| requests carrying your test header | `http_x_debug_trace` = `me` | `[["http_x_debug_trace", "==", "me"]]` |
| one path | `uri` matches `^/posts/` | `[["uri", "~~", "^/posts/"]]` |
| slow backend calls | `upstream_response_time` > `1` (seconds) | `[["upstream_response_time", ">", 1]]` |

The header filter is the safest way to trace a busy production API: only the
requests you send with `X-Debug-Trace: me` are recorded, and nobody else's
traffic, headers or credentials end up in a record. A header named `X-Debug-Trace`
is filtered as `http_x_debug_trace`: lowercase, with dashes turned into
underscores.

Some variables can't be used in a filter (for example `route_id`), because the
session already belongs to one API. The dialog marks them **Not allowed in
filters**, and the API answers `400` with the variable's name.

## See it work

`example/verify.sh` runs the whole thing end to end: it starts a session, sends
the three calls, waits for the records, checks that each one names the right
answerer, checks that tracing didn't change the response, then stops the
session.

```bash
GATEWAY=https://<YOUR_GATEWAY_HOST> \
CONTROL_PLANE=https://<YOUR_CONTROL_PLANE_HOST> \
TOKEN=<control-plane bearer token> \
ORG=<ORG_ID> API_ID=<API_ID> ENV_ID=<ENV_ID> \
./example/verify.sh
```

Exit code 0 means every check held. It needs `jq`. What each check proves:
[Tests](tests.md).

## Variations

**Trace an authenticated API.** Put `helix-auth` in front, as in
[solution 01](../01-api-products/). A missing or wrong key then shows as a short
circuit by `helix-auth`, and a quota rejection by `api-product-enforcer`. Trace
with a **test app's** key, because the key is recorded in plain text.

**Trace a slow API.** Use a longer duration and a latency filter, such as
`upstream_response_time` above `1`. It is in seconds, so that records only
calls where the backend took more than a second. Then compare the upstream
phase with the total: if most of the time is upstream, the delay is in your
backend.

**Capture more variables.** **Advanced: variables to capture** adds nginx
variables (for example `upstream_*`) and plugin values (`helix.<namespace>.<key>`)
to each record. That's how you see a value a plugin computed, such as a field a
[service callout](../11-service-callout/) fetched.

**Open a saved record.** **Upload trace file** on the Traces page opens `.json`
or `.ndjson` trace files (a record copied from **Raw JSON**, for example) in
the same viewer. The file is read in your browser.

## Configuration reference

There is no plugin configuration for tracing. A session is opened through the
control plane and takes three fields:

| Field | Default | What it means |
|---|---|---|
| `ttl_seconds` | `300` | How long the session stays open. The UI allows 60 to 3,600. |
| `filter` | none | Only matching requests are recorded and counted. An array of `[variable, operator, value]` conditions. |
| `trace_vars` | the gateway's core set | Extra nginx variables to record. `upstream_*` and `http_*` wildcards work. |
| `trace_ctx_vars` | none | Plugin values to record, as `helix.<namespace>.<key>`. |

Set by the gateway operator, not per session: the recorded-request cap (10 by
default) and the response-body capture size (about 4 KB by default).

The sample API's plugins:

```yaml
# POST /posts — the gateway refuses a post with no title
request-validation:
  body_schema:
    type: object
    required: [title]
  rejected_code: 400

# GET /posts/{postId} — tag the request on its way to the backend
proxy-rewrite:
  headers:
    set:
      X-Partner-Channel: api

# API-wide — a correlation id on every response
request-id:
  algorithm: uuid
  header_name: X-Request-Id
```

Placeholders in this package: `<ORG_ID>`, `<API_ID>`, `<ENV_ID>`,
`<REVISION_ID>`, `<UPSTREAM_ID>`, `<SESSION_ID>`, `<YOUR_GATEWAY_HOST>`,
`<YOUR_CONTROL_PLANE_HOST>`. Replace all of them before you run anything.

Every field of every plugin: [docs.digitalapi.ai/api-gateway](https://docs.digitalapi.ai/api-gateway).

## Troubleshooting

- **The session is Active but no rows appear.** Rows take a few seconds. If a
  minute passes, check that your calls reached **this** API in **this**
  environment: the right host, a deployed revision, and a path that matches a
  route. A `404 Route Not Found` never reaches the API, so it is never recorded.
- **It recorded a few requests, then nothing.** It hit the 10-request cap. It
  can still show as active until its duration runs out. Stop it, add a filter,
  and start a new one.
- **Start tracing gave me an old session.** One session per API per
  environment. Starting again returns the open one, with its original duration
  and filter. Stop it first.
- **Stop session does nothing.** Wait for the first row to load, then click
  again. On a session that has recorded nothing yet, or one opened from a link,
  the button may not respond. Ending the session through the API always works.
- **The filter was rejected.** The message names the variable. Variables that
  identify the route or service (`route_id`, `service_id`) are not allowed.
- **A body says it was not captured.** Response bodies are cut at about 4 KB,
  and large request bodies are skipped. The record says which happened.
- **I can see someone's API key in a trace.** That is expected: headers are not
  redacted. Use a test app's key, filter on a test header, and restrict who
  holds the gateway admin role.
- **`GET /posts/1` returns 404 Route Not Found after an agent build.** The route
  was stored as `/posts/{postId}`. Change it to `/posts/:postId` and redeploy.
  The agent can do this even when the prompt says `:postId`, so check the
  revision whatever the prompt says.
- **The agent says another API already uses these routes.** APIs deployed to
  the same environment share its host, so two APIs can't both serve
  `GET /posts/:postId`. Undeploy the other one, or ask for a path prefix such as
  `/trace-demo/posts`. Don't let it delete an API you still need.
