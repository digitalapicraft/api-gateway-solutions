# Guides — Maintenance mode

> [Overview](README.md) · [Business need](business-need.md) · [Architecture](architecture.md) · **Guides** · [Agent prompt](helix-agent-prompt.md) · [Tests](tests.md) · [API reference](api-reference.md)

---

Two parts. First, build and deploy the API in its normal state. Then switch
maintenance on, check it, and switch it back. Do the whole thing on a test
environment before the real window.

## Pick your path

| | Choose this if you… | Go to |
|---|---|---|
| **1. Helix Agent** | want the quickest result and are happy to paste a prompt | [Build it with the Helix Agent](#build-it-with-the-helix-agent) |
| **2. Helix control plane** | prefer clicking through screens | [Build it in the UI](#build-it-in-the-ui) |
| **3. API script** | are scripting this, or wiring it into a pipeline | [Install it directly](#install-it-directly) |

Then, for everyone: [See it work](#see-it-work) (switch on, check, switch back)
· [Variations](#variations) · [Configuration reference](#configuration-reference)
· [Troubleshooting](#troubleshooting)

## Build it with the Helix Agent

[`helix-agent-prompt.md`](helix-agent-prompt.md) has three steps. Send each as
its own message, at its own time. Step 1 builds and deploys the API. Step 2,
when the window opens, makes a maintenance revision from the live one and
deploys it. Step 3, when the window closes, deploys the earlier revision again.
The agent asks you to confirm each deploy.

It may put the maintenance response on each route rather than once for the
whole API; both work. After step 1, check that the route for one booking reads
`/bookings/:bookingId`, with a colon. See [AGENT-GUIDE.md](../../AGENT-GUIDE.md).

## Build it in the UI

Screen and button names below are the real ones. The API lives under
**API Gateway** in the left sidebar.

**Before you start:**

- **You have an account.** If you don't, register for a free trial at
  [trial.digitalapi.ai](https://trial.digitalapi.ai/). A new trial org comes
  with a `test` environment, which is all this walkthrough needs.

**1. Create the API**

Pick one of the two ways below. Both give you an API called `Bookings API` with
three routes and no plugins yet.

*Option A — from scratch*
1. Go to **API Gateway → APIs**, click **Add API** (or **Create your first API**).
2. Choose **Create from scratch**. Set **Display name** to `Bookings API`, then
   **Create**.
3. On the API's page, open **Configuration → Routes** and add three routes:
   - `GET` `/bookings`, to list bookings
   - `POST` `/bookings`, to create a booking
   - `GET` `/bookings/:bookingId`, to read one booking. The gateway writes a
     path parameter as `:bookingId`, not `{bookingId}`.

   The route form opens already filled in with the name *New* and the path
   `/new-route`. Clear both fields first, then type your own.

*Option B — from an OpenAPI spec*
1. Go to **API Gateway → APIs**, click **Add API** (or **Create your first API**).
2. Set **Method** to **Import an OpenAPI spec**.
3. Drag in your own OpenAPI 3.0 file, or use our example,
   [`example/api-spec-basic.yaml`](example/api-spec-basic.yaml): the same
   routes, no plugins. Then click **Import**.

> **A spec can carry the plugins too.** Add an `x-helix-gateway` block that
> lists them. At the top level of the file it covers every route; under one
> path and method it covers that route only. The maintenance response can sit
> there already, switched off:
>
> ```yaml
> x-helix-gateway:
>   plugins:
>     mocking:
>       _meta:
>         disable: true        # off until you switch it on in a copy
>       response_status: 503
> ```
>
> [`example/api-spec.yaml`](example/api-spec.yaml) is this API with all its
> plugins already in place, the maintenance response included and switched
> off. Import that instead and you can skip step 2.

Either way, the API is not live yet: it has no upstream and isn't deployed.
That comes in step 3.

**2. Add the plugins**

Two plugins make the normal state. Add them **before** you deploy: a live
revision can't be changed. The maintenance response is not added now. It goes
on a copy of the revision when you switch maintenance on, in
[See it work](#switch-maintenance-on).

On the API's page, open **Configuration → Plugins** and click **Configure
plugin**. A short wizard opens:

1. **Plugin** — pick the plugin from the catalog.
2. **Scope** — **Entire Revision** applies it to every route; **Specific
   endpoint** applies it to one route.
3. **Configure** — the JSON editor and the Properties list sit side by side.
   Paste the JSON below, or fill in the fields. Then **Next**.
4. **Review** — shows the configuration before and after. Click **Apply**.

Do this once for each plugin below.

1. **`proxy-rewrite` — sends `/bookings` calls to the backend's `/posts`.**
   Scope: **Entire Revision**. The sample backend calls bookings "posts", so
   `/bookings/7` becomes `/posts/7` on the way to it. With a backend of your own
   whose paths match, skip this plugin.

   ```json
   {"regex_uri":["^/bookings(.*)$","/posts$1"]}
   ```

2. **`request-id` — puts an id on every response.** Scope: **Entire Revision**.
   Every response carries an `X-Request-Id` header, the maintenance 503
   included, so a caller can quote it. Optional: see the
   [Configuration reference](#configuration-reference).

   ```json
   {"algorithm":"uuid","header_name":"X-Request-Id"}
   ```

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
   to map an upstream for `test`. Pick the one you just created, then click
   **Map & Deploy**. (The button reads **Map & Deploy** while no upstream is
   mapped yet, and **Deploy** once one is.)

**Changing it later.** A change to the upstream's host or port applies to the
live API straight away, with no new deploy. A change to its scheme does not:
undeploy the revision and deploy it again. A change to routes or plugins does
need one, because a live revision can't be edited: use **Clone Revision**, make
your change on the copy, then **Force Deploy** it. To roll back, click
**Deploy**, pick the older revision (for example `r1`) and click **Force
Deploy**; no clone is needed. Switching maintenance on and off is exactly this.

## Install it directly

```bash
export ORG=<ORG_ID>
export TOKEN=<control-plane bearer token>      # short-lived
export CP=https://<YOUR_CONTROL_PLANE_API>
export ENV_ID=<ENV_ID>
H=(-H "authorization: Bearer $TOKEN" -H 'content-type: application/json')

# 1. Import the spec. Keep both ids the response returns.
curl -s -H "authorization: Bearer $TOKEN" -F "file=@example/api-spec.yaml" \
  "$CP/api/orgs/$ORG/apis/from-spec"
# → {"api":{"id":"<API_ID>", ...}, "revision":{"id":"<REVISION_ID>", ...}}

# 2. Create an upstream, bind it to the revision, deploy the revision.
curl -s "${H[@]}" -X POST "$CP/api/orgs/$ORG/envs/$ENV_ID/upstreams" \
  -d '{"name":"bookings-upstream","specification":{"scheme":"https","pass_host":"rewrite","upstream_host":"jsonplaceholder.typicode.com","nodes":[{"host":"jsonplaceholder.typicode.com","port":443,"weight":1}]}}'
# → {"id":"<UPSTREAM_ID>", ...}
# Keep pass_host and upstream_host. Without them the backend receives your
# gateway's host name instead of its own, and every call returns 502.
curl -s "${H[@]}" -X PATCH "$CP/api/orgs/$ORG/apis/<API_ID>/revisions/<REVISION_ID>/upstream-bindings/add" \
  -d "{\"environmentUpstreams\":[{\"environmentId\":\"$ENV_ID\",\"upstreamId\":\"<UPSTREAM_ID>\"}]}"
curl -s "${H[@]}" -X POST "$CP/api/orgs/$ORG/apis/<API_ID>/revisions/<REVISION_ID>/deploy" \
  -d "{\"environmentId\":\"$ENV_ID\",\"force\":false}"
```

The API is now live in its normal state, with the maintenance response in
place and switched off. The switch itself is in
[See it work](#switch-maintenance-on). The same calls without narration:
[API reference](api-reference.md).

## See it work

`example/verify.sh` checks one state per run. It needs only the gateway's
address, and exits 0 when every call matches the state you name:

```bash
GATEWAY=https://<YOUR_GATEWAY_HOST> ./example/verify.sh                    # normal
GATEWAY=https://<YOUR_GATEWAY_HOST> MODE=maintenance ./example/verify.sh   # maintenance
```

Run it in normal mode now: four calls, each answered by the backend. What each
check proves: [Tests](tests.md).

### Switch maintenance on

First choose the end time, and write it twice: as a date for `Retry-After`
(`Sat, 07 Nov 2026 03:00:00 GMT`, always GMT) and in the message. Then pick one
of the three ways below.

**In the UI.**
1. On the API's page, use **Clone Revision** on the live revision.
2. On the copy, open **Configuration → Plugins**, click **Configure plugin**,
   pick `mocking`, Scope **Entire Revision**, and paste this, with your time:

   ```json
   {"response_status":503,"content_type":"application/json","with_mock_header":false,"response_headers":{"Retry-After":"Sat, 07 Nov 2026 03:00:00 GMT"},"response_example":"{\"error\":\"maintenance\",\"message\":\"Bookings is down for planned maintenance. Please try again after 03:00 UTC.\",\"retry_after\":\"2026-11-07T03:00:00Z\"}"}
   ```

   Then **Next** and **Apply**. If the copy already has `mocking` (it does if
   you imported `example/api-spec.yaml`), this replaces its settings, and
   leaving out `_meta` switches it on. If you use the Properties list instead,
   type the body as plain text, without the backslashes.
3. **Force Deploy** the copy.

**With the API.** With the variables from
[Install it directly](#install-it-directly) set, `jq` copies the live settings,
switches the maintenance response on and sets the time:

```bash
API=<API_ID>
curl -s "${H[@]}" "$CP/api/orgs/$ORG/apis/$API/revisions" | jq -c '.content[] | {id, revisionNumber, state}'
LIVE=<the id whose state is ACTIVE>     # keep it: switching back deploys it

NEW=$(curl -s "${H[@]}" -X POST "$CP/api/orgs/$ORG/apis/$API/revisions/$LIVE/clone" | jq -r .id)
curl -s "${H[@]}" "$CP/api/orgs/$ORG/apis/$API/revisions/$NEW" \
  | jq --arg until 'Sat, 07 Nov 2026 03:00:00 GMT' \
       --arg message '{"error":"maintenance","message":"Bookings is down for planned maintenance. Please try again after 03:00 UTC.","retry_after":"2026-11-07T03:00:00Z"}' \
       '{serviceSpec: (.serviceSpec
           | del(.plugins.mocking._meta)
           | .plugins.mocking.response_headers["Retry-After"] = $until
           | .plugins.mocking.response_example = $message)}' \
  | curl -s "${H[@]}" -X PUT "$CP/api/orgs/$ORG/apis/$API/revisions/$NEW/service-spec" -d @-
curl -s "${H[@]}" -X POST "$CP/api/orgs/$ORG/apis/$API/revisions/$NEW/deploy" \
  -d "{\"environmentId\":\"$ENV_ID\",\"force\":true}"
```

This expects the maintenance response already in the revision, switched off,
as `example/api-spec.yaml` ships it. The copy keeps the upstream mapping, so
there is nothing to bind.

**With the Helix Agent.** Send step 2 of the [prompt](helix-agent-prompt.md),
with your end time, and confirm the deploy when it asks.

### Check the maintenance state

A second or two after the deploy, every call gets the same answer:

```bash
curl -i https://<YOUR_GATEWAY_HOST>/bookings/1
# HTTP/2 503
# content-type: application/json
# retry-after: Sat, 07 Nov 2026 03:00:00 GMT
# {"error":"maintenance","message":"Bookings is down for planned maintenance. …"}
```

Then run `verify.sh` with `MODE=maintenance`: four calls, each answered by the
gateway, each with `Retry-After` and a JSON body. It also tells you if the
`Retry-After` date is already in the past.

### Switch it back

- **In the UI:** click **Deploy**, pick the revision you had before (for
  example `r1`) and click **Force Deploy**. No clone is needed.
- **With the API:** deploy `$LIVE` again with
  `-d "{\"environmentId\":\"$ENV_ID\",\"force\":true}"`.
- **With the Helix Agent:** send step 3 of the prompt.

Run `verify.sh` in normal mode once more: four passes mean the backend is
answering again. The maintenance revision stays in the list, unchanged.

## Variations

**Get the copy ready ahead of time.** Clone and add the maintenance response
the day before, but don't deploy it. At the start of the window, deploy it.
If a newer revision goes live in between, clone that one instead, or the copy
would take back its changes.

**Read-only maintenance.** If only writes must stop, add `mocking` with Scope
**Specific endpoint**, `POST /bookings`, instead of **Entire Revision**. Reads
keep reaching the backend; new bookings get the 503. Say so in the message.

**No known end.** Set `Retry-After` to a number of seconds, such as `300`, and
say "we'll be back shortly" in the message. Callers check again every few
minutes. Why not seconds for a known window:
[Architecture](architecture.md#why-retry-after-is-a-date-here).

**Your own message.** The body is yours to shape. Keep it JSON, keep the time
in it, and keep the same shape for every API, so your apps handle it once.

## Configuration reference

The maintenance response, `mocking`, at the top level of the spec (every route):

| Field | Value here | What it means |
|---|---|---|
| `_meta.disable` | `true` in the normal revision | Switches the plugin off without removing it. Leave it out, or set `false`, to switch it on. |
| `response_status` | `503` | Service unavailable. |
| `response_headers` | `Retry-After: Sat, 07 Nov 2026 03:00:00 GMT` | Headers added to the answer. Change the date for every window. |
| `response_example` | the JSON message | The body, as text. Change the time in it for every window. |
| `content_type` | `application/json` | The answer's `Content-Type`. |
| `with_mock_header` | `false` | Leaves out the `x-mock-by` header the plugin adds by default. Callers should see a maintenance answer, not a test one. |

The other two, also at the top level:

| Plugin | Field | Value | What it does |
|---|---|---|---|
| `proxy-rewrite` | `regex_uri` | `["^/bookings(.*)$", "/posts$1"]` | `/bookings` becomes `/posts`, `/bookings/7` becomes `/posts/7`. Only for the sample backend. |
| `request-id` | `algorithm`, `header_name` | `uuid`, `X-Request-Id` | An id on every response. If a call already arrives with an `X-Request-Id`, the gateway keeps that one, so the id you see may not be in the dashed UUID form. |

Source of truth: [`example/api-spec.yaml`](example/api-spec.yaml).
`example/api-spec-basic.yaml` is the same routes with no plugins, for adding
them yourself.

Placeholders: `<ORG_ID>`, `<API_ID>`, `<ENV_ID>`, `<REVISION_ID>`,
`<UPSTREAM_ID>`, `<YOUR_GATEWAY_HOST>`, `<YOUR_CONTROL_PLANE_API>`. Replace
all of them before you run anything.

Every field of every plugin: [docs.digitalapi.ai/api-gateway](https://docs.digitalapi.ai/api-gateway).

## Troubleshooting

- **Still 200 after switching on.** The copy isn't the deployed revision, or
  its maintenance response is still off. Check which revision is live, and that
  the copy's `mocking` has no `"_meta": {"disable": true}`.
- **The deploy is refused because another revision is already deployed.** Use
  **Force Deploy** (`"force":true` in the API). That replaces the live revision
  and keeps it.
- **"Only INACTIVE revisions can be updated".** You're editing the live
  revision. Clone it and edit the copy.
- **Callers retry straight away.** The `Retry-After` date is in the past, or
  written in a shape clients can't read. Use exactly
  `Sat, 07 Nov 2026 03:00:00 GMT`: day name, two-digit day, month, year, 24-hour
  time, `GMT`.
- **`GET /bookings/1` returns 404 Route Not Found after an agent build.** The
  route was stored as `/bookings/{bookingId}`. Change it to
  `/bookings/:bookingId` and redeploy. The agent can do this even when the
  prompt says `:bookingId`, so check the revision whatever the prompt says.
- **The agent run stops partway.** Start a new conversation and send the same
  step again. Steps 2 and 3 name the API, so a new conversation finds it. If
  step 1 stopped after creating the API, ask the agent to carry on with that
  API rather than create another.
- **Use the trace inspector to see each step.** On the API's page, open the
  **Observability** tab and click **Start trace session**. During maintenance a
  call's record says **Upstream not called**, answered by `mocking`. A session
  stops after 10 requests, and the list doesn't refresh by itself: click
  **Refresh**. The **Inspector** shows API keys and cookies in plain text, so
  don't share your screen or paste a trace into a ticket without removing them.
- **See what changed, and when, in Audit Logs.** **Observability → Audit Logs**
  lists every clone, plugin change and deploy. Its times are in your local time,
  while analytics uses UTC. Anything done with your token, including scripts and
  the Helix Agent, appears under your name.
