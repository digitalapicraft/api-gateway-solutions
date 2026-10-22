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

Then, for everyone: [See it work](#see-it-work) (start a trace session and read a
record) · [Variations](#variations) · [Configuration reference](#configuration-reference) ·
[Troubleshooting](#troubleshooting)

## Build it with the Helix Agent

The fastest path, and it works on a **fresh, empty org**. One prompt builds and
deploys the sample API: the two routes, their plugins and the upstream.
[`helix-agent-prompt.md`](helix-agent-prompt.md) has it as two numbered steps:
paste the whole thing as one message, or one step at a time if the run ends
early.

The agent can't start a trace session, because tracing is not part of the API's
configuration. When it finishes, continue at
[Start a trace session](#start-a-trace-session).

See [AGENT-GUIDE.md](../../AGENT-GUIDE.md) for the ground rules these prompts
assume.

## Build it in the UI

Screen and button names below are the real ones. The API lives under
**API Gateway** in the left sidebar; traces live under **Observability**.

**Before you start:**

- **You have an account.** If you don't, register for a free trial at
  [trial.digitalapi.ai](https://trial.digitalapi.ai/). A new trial org comes
  with a `test` environment, which is all this walkthrough needs.
- **You're an org admin or a gateway admin.** Those roles can create APIs and
  start traces. Product owners can't, and won't see **Start tracing session**.
- **An environment exists** (for example `test`). Environments are created under
  **Admin → Orgs → (your org) → Environments**, not from the API Gateway sidebar,
  and need a Gateway to attach to. Ask your admin if you're not sure.

**1. Create the API**

Pick one of the two ways below. Both give you the same thing: an API called
`Posts API` with two routes and no plugins yet. Plugins are optional for
tracing; step 2 adds three that make a trace more useful to read.

*Option A — from scratch*
1. Go to **API Gateway → APIs**, click **Add API** (or **Create your first API**).
2. Choose **Create from scratch**. Set **Display name** to `Posts API`, then
   **Create**.
3. On the API's page, open **Configuration → Routes** and add two routes:
   - method `POST`, path `/posts`, to create a post
   - method `GET`, path `/posts/:postId`, to read one post. The gateway writes a
     path parameter as `:postId`, not `{postId}`.

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
> x-helix-gateway:
>   plugins:
>     request-id:
>       algorithm: uuid
>       header_name: X-Request-Id
> ```
>
> [`example/api-spec.yaml`](example/api-spec.yaml) is this API with all its
> plugins already in place. Import that instead and you can skip step 2.

Either way, the API is not live yet: it has no upstream and isn't deployed.
That comes in step 3.

**2. Add the plugins (optional)**

**Tracing doesn't need any plugin.** It works on any deployed API, with or
without them. The three plugins below are here so your first trace has
something to show: a call the gateway turns away on its own, and a header the
gateway changes on the way to your backend. With them, you can see in a trace
how to tell a problem caused by the gateway from one caused by your backend.
You can skip this step, or use your own API instead.

If you do add them, add them **before** you deploy: a live revision can't be
changed.

On the API's page, open **Configuration → Plugins** and click **Configure
plugin**. A short wizard opens:

1. **Plugin** — pick the plugin from the catalog.
2. **Scope** — **Entire Revision** applies it to every route; **Specific
   endpoint** applies it to one route.
3. **Configure** — the JSON editor and the Properties list sit side by side.
   Paste the JSON below, or fill in the fields. Then **Next**.
4. **Review** — shows the configuration before and after. Click **Apply**.

Do this once for each plugin below.

1. **`request-validation` — refuses a new post with no title.** Scope:
   **Specific endpoint**, `POST /posts`. When the body has no `title`, the
   gateway answers with HTTP 400 (bad request) itself, and your backend never
   sees the call.

   | Field | Value |
   |---|---|
   | **body_schema → type** | `object` |
   | **body_schema → required** | `title` |
   | **rejected_code** | `400` |

   ```json
   {"body_schema":{"type":"object","required":["title"]},"rejected_code":400}
   ```

2. **`proxy-rewrite` — tags each lookup on its way to the backend.** Scope:
   **Specific endpoint**, `GET /posts/:postId`. It adds the header
   `X-Partner-Channel: api` to the request your backend receives. The caller
   never sees this header; a trace does.

   | Field | Value |
   |---|---|
   | **headers → set** | `X-Partner-Channel`: `api` |

   ```json
   {"headers":{"set":{"X-Partner-Channel":"api"}}}
   ```

3. **`request-id` — puts an id on every response.** Scope: **Entire Revision**.
   This one is optional: tracing works without it. It adds an `X-Request-Id`
   header with a new id to every response, so the id a partner quotes in their
   report can be matched to a trace record.

   | Field | Value |
   |---|---|
   | **algorithm** | `uuid` |
   | **header_name** | `X-Request-Id` |

   ```json
   {"algorithm":"uuid","header_name":"X-Request-Id"}
   ```

Each plugin then appears under **Configuration → Plugins**. What every field
means: [Configuration reference](#configuration-reference).

**3. Give it an upstream, then deploy it**
1. Go to **API Gateway → Upstreams → Add Upstream**. Name it, pick environment
   `test`, and add a node at `jsonplaceholder.typicode.com`, port `443`, scheme
   HTTPS (or your own host). If you switch the scheme to HTTP, the port stays at
   `443`: change it to `80` by hand.
2. **Pass Host** is set to **Rewrite**, which makes **Upstream Host** required.
   It fills in from the node's host; check it reads
   `jsonplaceholder.typicode.com`.
3. Click **Next** through the remaining tabs, then **Add Upstream**.
4. Back on the API's page, click **Deploy** on the revision. The dialog asks you
   to map an upstream for `test`. Pick the one you just created, then **Deploy**.

Until you deploy, there is nothing to trace. Once it is deployed, continue at
[Start a trace session](#start-a-trace-session).

**Changing it later.** A change to the upstream (host, port, scheme) applies to
the live API straight away, with no new deploy. A change to routes or plugins
does need one, because a live revision can't be edited: use **Clone Revision**,
make your change on the copy, then **Force Deploy** it. The same steps roll you
back: clone the older revision and force-deploy that.

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
curl -s "${H[@]}" -X POST "$CP/api/orgs/$ORG/envs/<ENV_ID>/upstreams" \
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

The same calls without narration: [API reference](api-reference.md).

## See it work

Open a trace session, send a few calls, then read what was recorded. You can do
it by hand in the UI, or run the script at the end.

### Start a trace session

You can start one from two places:

- **Observability → Traces** in the left sidebar, then **Start tracing session**.
- The API's own page: open the **Observability** tab and click **Start trace
  session**, or click **Start Trace** at the top of the page. The API is then
  already chosen for you.

The **Start tracing session** dialog opens:

1. **Environment.** Pick the environment the API is deployed in. A session
   belongs to one API in one environment.
2. **API.** Pick the API. The list reads "Select an environment first" until
   you pick an environment. If you started from the API's page, this is already
   filled in.
3. **How long should we capture?** Pick a card. **Standard debug** is picked
   for you.

   | Card | Duration | Good for |
   |---|---|---|
   | **Quick check** | 1 minute | Validate a single change |
   | **Standard debug** | 5 minutes | Most investigations |
   | **Deep dive** | 15 minutes | Reproduce intermittent |
   | **Long capture** | 1 hour | Forensic / overnight |
   | **Custom (seconds)** | 60 to 3,600 seconds | |

   Whichever you pick, the session stops recording after **10 requests**. That
   limit is set on the server, not in this dialog. A longer duration gives the
   problem more time to happen. It doesn't give you more records.
4. Optional: **Advanced: filter which requests to capture.** Requests the
   filter skips don't count toward the 10. See
   [Record only what you need](#record-only-what-you-need).
5. Click **Start tracing**. You land straight on the session's page, marked
   **Active**.

If a session is already running on this API, **Start tracing** stays greyed
out and the dialog says so. There can be only one at a time: stop that one
first.

Now make the failing call happen: send it yourself, or ask the partner to retry.
For the sample API:

```bash
G=https://<YOUR_GATEWAY_HOST>
curl -s -X POST $G/posts -H 'content-type: application/json' -d '{"body":"no title"}'   # 400
curl -s $G/posts/1 -o /dev/null -w '%{http_code}\n'                                     # 200
curl -s $G/posts/999999 -o /dev/null -w '%{http_code}\n'                                # 404
```

Wait a few seconds, then click **Refresh**: the list does not update by itself.
Each request is a row, with the columns **Time**, **Method / Path**, **Status**
and **Latency**. A summary bar above the rows shows the **Total**, the
**Errors**, the **Latency** (p50, p95 and p99) and the **Top route**. To narrow
the list, use the search box, the status filter (**2xx success**, **4xx client
error** and so on) or the latency filter.

To come back to a session later, open **Observability → Traces** and click it in
the list, or open the API's **Observability** tab and click **View traces** next
to it.

### Read a record

Click the **path** in a row. The path is the button; the rest of the row does
nothing when clicked. The record opens:

- **At the top:** the method, path, status and total time, and an **Outcome**
  badge. **Copy as cURL** copies the request as a `curl` command, so you can
  send it again.
- **Phase timeline:** how long each stage took.
- **Request chain:** each plugin that ran, in order, and what it changed.
  Plugins that ran but did nothing are hidden. Turn on **Show passive
  executions** to see them.
- **Inspector:** the details, in these tabs:

| Tab | Look here for |
|---|---|
| **Headers** | Request headers as received, and response headers as sent. |
| **Upstream** | The backend's address and status, and its connect and response times. |
| **Query** | Query parameters. |
| **Request** | The request body as received. |
| **Upstream Body** | The request body as your backend received it, after every plugin. |
| **Response** | The response body (the first few KB). |
| **Raw JSON** | The full record. Copy this into a ticket. |

> **Warning: a record shows secrets in plain text.** The **Inspector** shows API
> keys and cookies exactly as the caller sent them. Don't share your screen
> while it is open, and remove keys and cookies before you paste a record into a
> ticket or chat.

Then answer one question: **who answered?**

- **The `POST /posts` 400.** The **Outcome** badge reads **Upstream not
  called**. In **Request chain**, `request-validation` in the rewrite phase is
  marked **Upstream not called** too: it answered with a 400 response itself.
  There is no backend status. **The gateway said no**, and the backend never saw the call. The
  response body says why: `property "title" is required`. In **Raw JSON**, this
  outcome is `short_circuit`.
- **The `GET /posts/1` 200.** The **Outcome** badge reads **OK**. In
  **Request chain**, `proxy-rewrite` in the rewrite phase lists one change: the
  header `x-partner-channel` added with the value `api`. The caller's response
  doesn't carry that header. Only the backend received it, and this record is
  the only place that shows it. The **Phase timeline** shows the backend call
  takes most of the total time.
- **The `GET /posts/999999` 404.** The **Outcome** badge reads **Client error**,
  and no plugin answered. The **Upstream** tab shows status `404`. **The backend
  said no.** The gateway did its job and passed the answer through.

The full reading guide, including every outcome, is in
[Architecture](architecture.md#reading-a-record-who-answered).

### Run it as a script

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

### Record only what you need

Ten records go fast on an API with real traffic. A filter decides which requests
are recorded. Requests that don't match are skipped and don't count toward the
10. The filter is checked **after** the response, so you can filter on the
status.

Open **Advanced: filter which requests to capture** in the start dialog and
click **Add condition**, or pass `filter` to the API. Each condition is a
variable, an operator and a value:

| To record only… | Condition in the dialog | `filter` in the API |
|---|---|---|
| failures | `status` **greater than or equal** `400` | `[["status", ">=", 400]]` |
| requests carrying your test header | `http_x_debug_trace` **is** `me` | `[["http_x_debug_trace", "==", "me"]]` |
| one path | `uri` **matches regex** `^/posts/` | `[["uri", "~~", "^/posts/"]]` |
| slow backend calls | `upstream_response_time` **greater than** `1` (seconds) | `[["upstream_response_time", ">", 1]]` |

The header filter is the safest way to trace a busy production API: only the
requests you send with `X-Debug-Trace: me` are recorded, and nobody else's
traffic, headers or credentials end up in a record. A header named `X-Debug-Trace`
is filtered as `http_x_debug_trace`: lowercase, with dashes turned into
underscores. It isn't in the dialog's list of variables, so type it and pick
**Use "http_x_debug_trace"**.

A session with a filter is marked **Filtered** on its page. It can show no
records at all, if nothing matched yet.

Some variables can't be used in a filter (for example `route_id`), because the
session already belongs to one API. The dialog marks them **Not allowed in
filters**, and the API answers `400` with the variable's name.

### Other variations

**Trace an authenticated API.** Put `helix-auth` in front, as in
[solution 01](../01-api-products/). A missing or wrong key then shows as
**Upstream not called**, answered by `helix-auth`. A request over the quota
shows the same way, answered by `api-product-enforcer`. Trace with a **test
app's** key, because the key is recorded in plain text.

**Trace a slow API.** Use a longer duration and a latency filter, such as
`upstream_response_time` above `1`. It is in seconds, so that records only
calls where the backend took more than a second. Then compare the upstream
phase with the total: if most of the time is upstream, the delay is in your
backend.

**Capture more variables.** **Advanced: variables to capture**, in the start
dialog, adds more of the gateway's request variables to each record. Pick them
from the list, use a wildcard such as `upstream_*`, or pick **All resolved
variables**. Under **Plugin context variables**, pick `helix` to record every
value the gateway's plugins stored for the request. That's how you see a value
a plugin worked out, such as a field a
[service callout](../11-service-callout/) fetched.

**Open a saved record.** **Upload trace file** on the Traces page opens `.json`
or `.ndjson` trace files (a record copied from **Raw JSON**, for example) in
the same viewer. The file is read in your browser.

## Configuration reference

There is no plugin configuration for tracing. A session is opened through the
control plane and takes four fields, all optional:

| Field | Default | What it means |
|---|---|---|
| `ttl_seconds` | `300` | How long the session stays open. The UI allows 60 to 3,600. |
| `filter` | none | Only matching requests are recorded and counted. An array of `[variable, operator, value]` conditions. |
| `trace_vars` | the gateway's core set | Extra request variables to record. `upstream_*` and `http_*` wildcards work. |
| `trace_ctx_vars` | none | Plugin values to record, as `helix.<namespace>.<key>`. |

Set by the gateway operator, not per session: the recorded-request cap (10 by
default) and the response-body capture size (about 4 KB by default).

Source of truth: [`example/api-spec.yaml`](example/api-spec.yaml) for the
sample API's routes and plugins.
[`example/api-spec-basic.yaml`](example/api-spec-basic.yaml) is the same routes
with no plugins, for adding them yourself. The sample API's plugins:

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

- **The session is Active but no rows appear.** The list doesn't update by
  itself: wait a few seconds, then click **Refresh**. If a minute passes, check that your calls reached **this** API in **this**
  environment: the right host, a deployed revision, and a path that matches a
  route. A `404 Route Not Found` never reaches the API, so it is never recorded.
- **It recorded a few requests, then nothing.** It hit the 10-request cap. It
  can still show as active until its duration runs out. Stop it, add a filter,
  and start a new one.
- **Start tracing is greyed out, or the API gave me an old session.** Only one
  session can run per API per environment. The dialog won't start a second one.
  Through the API, starting again returns the open one, with its original
  duration and filter. Stop it first.
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
- **After an agent build, a post with no title gets 201, or a lookup's record
  shows no `proxy-rewrite`.** The agent left a plugin off. Open the revision's
  **Configuration → Plugins**: `request-validation` should be on `POST /posts`,
  and `proxy-rewrite` on `GET /posts/:postId`. Add a missing one as in
  [step 2 of Build it in the UI](#build-it-in-the-ui), on a cloned revision
  (see **Changing it later** there).
- **The agent says another API already uses these routes.** APIs deployed to
  the same environment share its host, so two APIs can't both serve
  `GET /posts/:postId`. Undeploy the other one, or ask for a path prefix such as
  `/trace-demo/posts`. Don't let it delete an API you still need.
- **Run the same request again after a fix.** **Copy as cURL**, at the top of a
  record, copies the request as a `curl` command, headers and body included.
  After you change a plugin and redeploy, start a new session, send that command
  again, and compare the two records. Remove keys and cookies from the command
  before you share it.
- **See what changed, and when, in Audit Logs.** **Observability → Audit Logs**
  lists every clone, plugin change and deploy. Use it when a record shows a
  plugin you didn't expect. Its times are in your local time, while analytics
  uses UTC. Anything done with your token, including scripts and the Helix
  Agent, appears under your name.
