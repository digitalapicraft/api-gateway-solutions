# Guides — Validate the request body

> [Overview](README.md) · [Business need](business-need.md) · [Architecture](architecture.md) · **Guides** · [Agent prompt](helix-agent-prompt.md) · [Tests](tests.md) · [API reference](api-reference.md)

---

## Pick your path

| | Choose this if you… | Go to |
|---|---|---|
| **1. Helix Agent** | want the quickest result and are happy to paste a prompt | [Build it with the Helix Agent](#build-it-with-the-helix-agent) |
| **2. Helix control plane** | prefer clicking through screens | [Build it in the UI](#build-it-in-the-ui) |
| **3. API script** | are scripting this, or wiring it into a pipeline | [Install it directly](#install-it-directly) |

Then, for everyone: [See it work](#see-it-work) · [Variations](#variations) ·
[Configuration reference](#configuration-reference) · [Troubleshooting](#troubleshooting)

## Build it with the Helix Agent

The fastest path, and it works on a **fresh, empty org**. One prompt builds and
deploys the sample API: the two routes, the body check on each, the path change
and the upstream. [`helix-agent-prompt.md`](helix-agent-prompt.md) has it as
two numbered steps: paste the whole thing as one message, or one step at a time
if the run ends early. The agent may ask you to confirm before it deploys.

When it finishes, read the revision back: each route should carry
`request-validation` with the fields and values you asked for, and the change
route should read `/tickets/:ticketId`, with a colon.

See [AGENT-GUIDE.md](../../AGENT-GUIDE.md) for the ground rules these prompts
assume.

## Build it in the UI

Screen and button names below are the real ones. The API lives under
**API Gateway** in the left sidebar.

**Before you start:**

- **You have an account.** If you don't, register for a free trial at
  [trial.digitalapi.ai](https://trial.digitalapi.ai/). A new trial org comes
  with a `test` environment, which is all this walkthrough needs.
- **You can create and deploy APIs.** Org admins and gateway admins can. If you
  don't see an **Add API** button, ask your org admin.

**1. Create the API**

Pick one of the two ways below. Both give you the same thing: an API called
`Support Tickets API` with two routes and no plugins yet.

*Option A — from scratch*
1. Go to **API Gateway → APIs**, click **Add API** (or **Create your first API**).
2. Choose **Create from scratch**. Set **Display name** to `Support Tickets API`,
   then **Create**.
3. On the API's page, open **Configuration → Routes** and add two routes:
   - method `POST`, path `/tickets`, to open a ticket
   - method `PATCH`, path `/tickets/:ticketId`, to change one. The gateway
     writes a path parameter as `:ticketId`, not `{ticketId}`.

   The route form opens already filled in with the name *New* and the path
   `/new-route`. Clear both fields first, then type your own.

*Option B — from an OpenAPI spec*
1. Go to **API Gateway → APIs**, click **Add API** (or **Create your first API**).
2. Set **Method** to **Import an OpenAPI spec**.
3. Drag in or browse to your own OpenAPI 3.0 file, or use our example,
   [`example/api-spec-basic.yaml`](example/api-spec-basic.yaml): the same two
   routes, no plugins. There is no option to paste the spec as text. Then click
   **Import**.

> **A spec can carry the plugins too.** Add an `x-helix-gateway` block that
> lists them. At the top level of the file it covers every route; under one
> path and method it covers that route only:
>
> ```yaml
> paths:
>   /tickets:
>     post:
>       x-helix-gateway:
>         plugins:
>           request-validation:
>             body_schema:
>               type: object
>               required: [title, priority]
> ```
>
> [`example/api-spec.yaml`](example/api-spec.yaml) is this API with all its
> plugins already in place. Import that instead and you can skip step 2.

Either way, the API is not live yet: it has no upstream and isn't deployed.
That comes in step 3.

**2. Add the plugins**

Three plugins do the job: one checks the body, one changes the path, one adds
an id to every response. Add them **before** you deploy: a live revision can't
be changed.

On the API's page, open **Configuration → Plugins** and click **Configure
plugin**. A short wizard opens:

1. **Plugin** — pick the plugin from the catalog.
2. **Scope** — **Entire Revision** applies it to every route; **Specific
   endpoint** applies it to one route.
3. **Configure** — the JSON editor and the Properties list sit side by side.
   Paste the JSON below, or fill in the fields. Then **Next**.
4. **Review** — shows the configuration before and after. Click **Apply**.

Do this once for each item below.

1. **`request-validation` on `POST /tickets` — the rule for a new ticket.**
   Scope: **Specific endpoint**, `POST /tickets`. Both fields are required;
   `title` is a string of at least one character; `priority` is one of three
   values. A body that breaks the rule gets a 400 from the gateway.

   ```json
   {"body_schema":{"type":"object","required":["title","priority"],"properties":{"title":{"type":"string","minLength":1},"priority":{"enum":["low","normal","high"]}}},"rejected_code":400}
   ```

2. **`request-validation` on `PATCH /tickets/:ticketId` — the rule for a
   change.** Scope: **Specific endpoint**, `PATCH /tickets/:ticketId`. The same
   field rules with no `required` list: a caller sends only what changes.

   ```json
   {"body_schema":{"type":"object","properties":{"title":{"type":"string","minLength":1},"priority":{"enum":["low","normal","high"]}}},"rejected_code":400}
   ```

3. **`proxy-rewrite` on `POST /tickets` — sends it to the backend's `/posts`.**
   Scope: **Specific endpoint**, `POST /tickets`.

   | Field | Value |
   |---|---|
   | **uri** | `/posts` |

   ```json
   {"uri":"/posts"}
   ```

4. **`proxy-rewrite` on `PATCH /tickets/:ticketId` — sends `/tickets/7` to
   `/posts/7`.** Scope: **Specific endpoint**, `PATCH /tickets/:ticketId`. The
   first value matches the path and keeps the id; the second is the new path,
   with `$1` standing for the id.

   ```json
   {"regex_uri":["^/tickets/(.*)$","/posts/$1"]}
   ```

5. **`request-id` — an id on every response.** Scope: **Entire Revision**.
   Optional: the check works without it. It gives each response, the 400s
   included, an `X-Request-Id` header a caller can quote when they report a
   problem.

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

## Install it directly

To script it, call the control plane instead. `CP` is the API address the
portal calls (it usually starts with `api-`), not the portal page and not the
gateway's address:

```bash
export ORG=<ORG_ID>
export TOKEN=<control-plane bearer token>      # short-lived
export CP=https://<YOUR_CONTROL_PLANE_API>
H=(-H "authorization: Bearer $TOKEN" -H 'content-type: application/json')

# 1. Import the spec. It carries all three plugins. Keep both ids it returns.
curl -s -H "authorization: Bearer $TOKEN" -F "file=@example/api-spec.yaml" \
  "$CP/api/orgs/$ORG/apis/from-spec"
# → {"api":{"id":"<API_ID>", ...}, "revision":{"id":"<REVISION_ID>", ...}}

# 2. Create an upstream, bind it to the revision, deploy the revision.
curl -s "${H[@]}" -X POST "$CP/api/orgs/$ORG/envs/<ENV_ID>/upstreams" \
  -d '{"name":"tickets-upstream","specification":{"scheme":"https","pass_host":"rewrite","upstream_host":"jsonplaceholder.typicode.com","nodes":[{"host":"jsonplaceholder.typicode.com","port":443,"weight":1}]}}'
# → {"id":"<UPSTREAM_ID>", ...}
# Keep pass_host and upstream_host. Without them the backend receives your
# gateway's host name instead of its own, and every call returns 502.
curl -s "${H[@]}" -X PUT "$CP/api/orgs/$ORG/apis/<API_ID>/revisions/<REVISION_ID>/envs/<ENV_ID>/bind-upstream" \
  -d '{"upstreamId":"<UPSTREAM_ID>"}'
curl -s "${H[@]}" -X POST "$CP/api/orgs/$ORG/apis/<API_ID>/revisions/<REVISION_ID>/envs/<ENV_ID>/deploy" \
  -d '{"force":false}'
```

The routes answer a few seconds after the deploy. The same calls without
narration: [API reference](api-reference.md).

## See it work

Send a good ticket, then a few bad ones (`-i` shows the headers):

```bash
G=https://<YOUR_GATEWAY_HOST>
curl -si -X POST $G/tickets -H 'content-type: application/json' \
  -d '{"title":"Printer on fire","priority":"high"}'   # 201, X-Powered-By: Express
curl -s  -X POST $G/tickets -H 'content-type: application/json' \
  -d '{"title":"Printer on fire"}'                     # 400 property "priority" is required
curl -s  -X POST $G/tickets -H 'content-type: application/json' \
  -d '{"title":null,"priority":"high"}'                # 400 … "title" … expected string, got userdata
curl -s  -X POST $G/tickets -H 'content-type: application/json' \
  -d '{"title":"Printer on fire","priority":"urgent"}' # 400 … "priority" … matches none of the enum values
curl -s  -X PATCH $G/tickets/1 -H 'content-type: application/json' \
  -d '{"priority":"low"}' -o /dev/null -w '%{http_code}\n'   # 200
```

The 201 carries the backend's `X-Powered-By: Express` header. The 400s don't:
the gateway answered them, and the backend never saw the request. What each
message means: [Architecture](architecture.md#what-the-caller-sees).

To see the same thing in a record, open a trace session on the API and send a
bad body: the outcome reads **Upstream not called**, answered by
`request-validation`. [Solution 16](../16-request-tracing/) shows how.

### Run it as a script

`example/verify.sh` sends seven calls and checks each status, that each 400
names the right field, and that only the good calls reach the backend:

```bash
GATEWAY=https://<YOUR_GATEWAY_HOST> ./example/verify.sh
```

Exit code 0 means every check held. What each check proves: [Tests](tests.md).

## Variations

Each of these was run against the sample backend. Change the route's
`request-validation` JSON and deploy again.

**One fixed message instead of the checker's.** Add `rejected_msg`:

```json
{"body_schema":{…},"rejected_code":400,"rejected_msg":"{\"error\":\"invalid_ticket\",\"message\":\"A ticket needs a title and a priority of low, normal or high.\"}"}
```

Every refused body then gets that text, whatever was wrong, the no-body case
included. It is sent as `content-type: text/plain`, even when it looks like
JSON. The trade-off:

| | The checker's message (the sample) | `rejected_msg` |
|---|---|---|
| Names the field | yes | no |
| You choose the wording | no: `userdata`, `table` and parser messages included | yes, up to 256 characters |
| Describes your rules to anyone who tries | yes, one field at a time | no |
| Same text for every mistake | no | yes |

**Refuse a title of only spaces.** Swap `minLength` for a `pattern` that needs
one non-space character: `"title":{"type":"string","pattern":"\\S"}`. A title
of `"   "` then gets `property "title" validation failed: failed to match
pattern "\\S" with "   "`.

**Refuse fields you didn't list.** Add `"additionalProperties":false` next to
`properties`. A body with `"priorty":"high"` then gets `additional properties
forbidden, found priorty`. Only do this if every caller sends exactly the
listed fields.

**Accept JSON bodies only.** Add a `header_schema` next to `body_schema`:

```json
{"header_schema":{"type":"object","required":["content-type"],"properties":{"content-type":{"type":"string","pattern":"^application/json"}}}}
```

A form body then gets `property "content-type" validation failed: failed to
match pattern "^application/json" with "application/x-www-form-urlencoded"`,
and a request with no content type gets `property "content-type" is required`.
`application/json; charset=utf-8` still passes.

## Configuration reference

**`request-validation`** — one per route that needs a rule.

| Field | Default | What it means |
|---|---|---|
| `body_schema` | none | The JSON Schema the body must match. |
| `header_schema` | none | A JSON Schema for the request headers. Write header names in lowercase, as in [Variations](#variations). At least one of the two schemas is required. |
| `rejected_code` | `400` | The status sent when a check fails. |
| `rejected_msg` | none | A fixed text sent instead of the checker's message, 1 to 256 characters. |

**`proxy-rewrite`** — `uri` sets one fixed backend path. `regex_uri` is a pair:
a pattern for the incoming path and the path to send, where `$1` is the first
bracketed part of the pattern.

**`request-id`** — `header_name` (default `X-Request-Id`), `algorithm` (default
`uuid`), and `include_in_response` (default `true`). The gateway may already
set an id before the plugin runs, so don't rely on the id's format.

Source of truth: [`example/api-spec.yaml`](example/api-spec.yaml).
`example/api-spec-basic.yaml` is the same routes with no plugins, for adding
them yourself.

Placeholders in this package: `<ORG_ID>`, `<API_ID>`, `<ENV_ID>`,
`<REVISION_ID>`, `<UPSTREAM_ID>`, `<YOUR_GATEWAY_HOST>`,
`<YOUR_CONTROL_PLANE_API>`. Replace all of them before you run anything.

Every field of every plugin: [docs.digitalapi.ai/api-gateway](https://docs.digitalapi.ai/api-gateway).

## Troubleshooting

- **A good ticket gets a 400.** Read the message: it names the field. Enum
  values are exact, so `"HIGH"` is refused where `"high"` is allowed, and a
  title must be a string, not a number.
- **A bad ticket gets a 201.** The check isn't on that route, or the revision
  with it isn't deployed. Open **Configuration → Plugins** and check that
  `request-validation` is on `POST /tickets`.
- **Every call gets a 404 with a JSON body from the backend.** `proxy-rewrite`
  is missing, so the backend received `/tickets`, a path it doesn't have. Add
  it as in step 2 of [Build it in the UI](#build-it-in-the-ui).
- **`PATCH /tickets/1` returns `404 Route Not Found` after an agent build.** The
  route was stored as `/tickets/{ticketId}`. Change it to `/tickets/:ticketId`
  and deploy again. Check the revision whatever the prompt says.
- **Every change with a field gets 400 "the input data should be an empty
  table".** Only an empty `{}` gets through. The `PATCH` rule carries an empty
  `"required": []`. Delete that line: a rule where nothing is required has no
  `required` list at all. The configuration imports, dry-runs and deploys with
  it, so only a real `PATCH` shows the problem. Check for it after an agent
  build.
- **The 400 is an HTML page.** The request had no body. Send a JSON body, or set
  `rejected_msg` to get your own text for this case too.
- **The message says `userdata` or `table`.** That is the checker's word for a
  JSON `null` and a JSON list. The field it names is the one to fix.
- **A form-encoded body got through.** The check reads form fields like JSON
  fields. Add the content-type rule from [Variations](#variations).
- **The agent says another API already uses these routes.** APIs deployed to
  the same environment share its host, so two APIs can't both serve
  `POST /tickets`. Undeploy the other one, or ask for a path prefix. Don't let
  it delete an API you still need.
- **Use the trace inspector to see each step.** On the API's page, open the
  **Observability** tab and click **Start trace session**. A refused body shows
  **Upstream not called**, answered by `request-validation`. Click **Refresh** to
  see new rows. The **Inspector** shows keys and cookies in plain text.
- **See what changed, and when, in Audit Logs.** **Observability → Audit Logs**
  lists every clone, plugin change and deploy. Its times are in your local time,
  while analytics uses UTC. Anything done with your token, including scripts and
  the Helix Agent, appears under your name.
