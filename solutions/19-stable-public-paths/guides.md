# Guides — Stable public paths

> [Overview](README.md) · [Business need](business-need.md) · [Architecture](architecture.md) · **Guides** · [Agent prompt](helix-agent-prompt.md) · [Tests](tests.md) · [API reference](api-reference.md)

---

## Pick your path

| | Choose this if you… | Go to |
|---|---|---|
| **1. Helix Agent** | want the quickest result and are happy to paste a prompt | [Build it with the Helix Agent](#build-it-with-the-helix-agent) |
| **2. Helix control plane** | prefer clicking through screens | [Build it in the UI](#build-it-in-the-ui) |
| **3. API script** | are scripting this, or wiring it into a pipeline | [Install it directly](#install-it-directly) |

Then, for everyone: [See it work](#see-it-work) · [Variations](#variations) ·
[Configuration reference](#configuration-reference) ·
[Troubleshooting](#troubleshooting)

## Build it with the Helix Agent

The fastest path, and it works on a **fresh, empty org**. One prompt builds the
API, its three public paths, the rewrite on each, and the upstream, then
deploys it. [`helix-agent-prompt.md`](helix-agent-prompt.md) has it as two
numbered steps: paste the whole thing as one message, or one step at a time if
the run ends early. The agent asks you to confirm before it deploys.

When it finishes, open the revision and check the stored paths and rewrites
against the [Configuration reference](#configuration-reference), then run
[`example/verify.sh`](#run-it-as-a-script).

See [AGENT-GUIDE.md](../../AGENT-GUIDE.md) for the ground rules these prompts
assume.

## Build it in the UI

Screen and button names below are the real ones. Everything lives under
**API Gateway** in the left sidebar.

**Before you start:**

- **You have an account.** If you don't, register for a free trial at
  [trial.digitalapi.ai](https://trial.digitalapi.ai/). A new trial org comes
  with a `test` environment, which is all this walkthrough needs.

**1. Create the API**

Pick one of the two ways below. Both give you the same thing: an API called
`Customers API` with three routes and no plugins yet.

*Option A — from scratch*
1. Go to **API Gateway → APIs**, click **Add API** (or **Create your first API**).
2. Choose **Create from scratch**. Set **Display name** to `Customers API`, then
   **Create**.
3. On the API's page, open **Configuration → Routes** and add three routes, all
   method `GET`:
   - `/v1/customers`, the customer list
   - `/v1/customers/:customerId`, one customer
   - `/v1/customers/:customerId/orders`, one customer's orders

   The gateway writes a path parameter as `:customerId`, not `{customerId}`.
   The route form opens already filled in with the name *New* and the path
   `/new-route`. Clear both fields first, then type your own.

*Option B — from an OpenAPI spec*
1. Go to **API Gateway → APIs**, click **Add API** (or **Create your first API**).
2. Set **Method** to **Import an OpenAPI spec**.
3. Drag in or browse to your own OpenAPI 3.0 file, or use our example,
   [`example/api-spec-basic.yaml`](example/api-spec-basic.yaml): the same three
   routes, no plugins. There is no option to paste the spec as text. Then click
   **Import**.

If an API with the same name already exists in your org, the import fails with
*API with name '<name>' already exists*. Type another name in the form's
**Display name** field, which overrides the name in the spec, and import again.

> **A spec can carry the plugins too.** Add an `x-helix-gateway` block. At the
> top level of the file it covers every route; under one path and method it
> covers that route only:
>
> ```yaml
> paths:
>   /v1/customers:
>     get:
>       x-helix-gateway:
>         plugins:
>           proxy-rewrite:
>             uri: /users
> ```
>
> [`example/api-spec.yaml`](example/api-spec.yaml) is this API with all its
> plugins already in place. Import that instead and you can skip step 2.

Either way, the API is not live yet: it has no upstream and isn't deployed.
That comes in step 3.

**2. Add the plugins**

One `proxy-rewrite` per route sends each public path to the backend's own
path. Add them **before** you deploy: a live revision can't be changed.

On the API's page, open **Configuration → Plugins** and click **Configure
plugin**. A short wizard opens:

1. **Plugin** — pick the plugin from the catalog.
2. **Scope** — **Entire Revision** applies it to every route; **Specific
   endpoint** applies it to one route.
3. **Configure** — the JSON editor and the Properties list sit side by side.
   Paste the JSON below, or fill in the fields. Then **Next**.
4. **Review** — shows the configuration before and after. Click **Apply**.

Run it once for each item below.

1. **`proxy-rewrite` on `/v1/customers` — sends the list to `/users`.** Scope:
   **Specific endpoint**, `GET /v1/customers`. The public path has no id, so a
   fixed path is enough.

   | Field | Value |
   |---|---|
   | **uri** | `/users` |

   ```json
   {"uri":"/users"}
   ```

2. **`proxy-rewrite` on `/v1/customers/:customerId` — sends one customer to
   `/users/<id>`.** Scope: **Specific endpoint**, `GET /v1/customers/:customerId`.
   The pattern captures the id from the public path, and `$1` puts it into the
   backend path. A fixed **uri** here would send every caller to the same
   customer.

   ```json
   {"regex_uri":["^/v1/customers/([^/]+)$","/users/$1"]}
   ```

3. **`proxy-rewrite` on `/v1/customers/:customerId/orders` — sends the orders
   to `/users/<id>/todos`.** Scope: **Specific endpoint**,
   `GET /v1/customers/:customerId/orders`. The test backend calls orders
   "todos".

   ```json
   {"regex_uri":["^/v1/customers/([^/]+)/orders$","/users/$1/todos"]}
   ```

4. **`request-id` — puts an id on every response.** Scope: **Entire Revision**.
   Optional. It gives each response an `X-Request-Id` header, an id a caller can
   quote when they report a problem.

   ```json
   {"algorithm":"uuid","header_name":"X-Request-Id"}
   ```

Each plugin then appears under **Configuration → Plugins**. What every field
means: [Configuration reference](#configuration-reference).

**3. Give it an upstream, then deploy it**
1. Go to **API Gateway → Upstreams → Add Upstream**. Name it, pick environment
   `test`, and add a node at `jsonplaceholder.typicode.com`, port `443`, scheme
   HTTPS (or your own backend). If you switch the scheme to HTTP, the port stays
   at `443`: change it to `80` by hand.
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

No products, developers or apps are needed: the example has no sign-in.

## Install it directly

```bash
export ORG=<ORG_ID>
export TOKEN=<control-plane bearer token>      # short-lived
export CP=https://<YOUR_CONTROL_PLANE_API>
H=(-H "authorization: Bearer $TOKEN" -H 'content-type: application/json')

# 1. Import the spec. Nothing in it needs filling in. Keep both ids it returns.
curl -s -H "authorization: Bearer $TOKEN" -F "file=@example/api-spec.yaml" \
  "$CP/api/orgs/$ORG/apis/from-spec"
# → {"api":{"id":"<API_ID>", ...}, "revision":{"id":"<REVISION_ID>", ...}}

# 2. Create an upstream, bind it to the revision, deploy the revision.
curl -s "${H[@]}" -X POST "$CP/api/orgs/$ORG/envs/<ENV_ID>/upstreams" \
  -d '{"name":"customers-upstream","specification":{"scheme":"https","pass_host":"rewrite","upstream_host":"jsonplaceholder.typicode.com","nodes":[{"host":"jsonplaceholder.typicode.com","port":443,"weight":1}]}}'
# → {"id":"<UPSTREAM_ID>", ...}
# Keep pass_host and upstream_host. Without them the backend receives your
# gateway's host name instead of its own, and every call returns 502.
curl -s "${H[@]}" -X PATCH "$CP/api/orgs/$ORG/apis/<API_ID>/revisions/<REVISION_ID>/upstream-bindings/add" \
  -d '{"environmentUpstreams":[{"environmentId":"<ENV_ID>","upstreamId":"<UPSTREAM_ID>"}]}'
curl -s "${H[@]}" -X POST "$CP/api/orgs/$ORG/apis/<API_ID>/revisions/<REVISION_ID>/deploy" \
  -d '{"environmentId":"<ENV_ID>","force":false}'
```

The routes answer a few seconds after the deploy returns. The same calls
without narration: [API reference](api-reference.md).

## See it work

```bash
G=https://<YOUR_GATEWAY_HOST>
curl -s "$G/v1/customers" | jq length                          # 10
curl -s "$G/v1/customers?_limit=2" | jq length                 # 2: the query string reached the backend
curl -s "$G/v1/customers/3" | jq '{id, username}'              # {"id":3,"username":"Samantha"}
curl -s "$G/v1/customers/1/orders?_limit=3" | jq '[.[].userId]' # [1,1,1]
curl -s "$G/users/1"                                           # 404 Route Not Found
```

Customer 3 is the backend's `/users/3`. The two limits worked, so the query
string reached the backend through both kinds of rewrite. And the backend's own
path `/users/1` has no route, so a caller can't use it through the gateway.

### Run it as a script

`example/verify.sh` checks the whole contract: each public path returns the
right record, the query string reaches the backend, a path outside the
contract gets the gateway's 404, and the backend's own paths aren't reachable.

```bash
GATEWAY=https://<YOUR_GATEWAY_HOST> ./example/verify.sh
```

Exit code 0 means every check held. It needs `jq`. What each check proves:
[Tests](tests.md). Run it again after every backend change: that is what tells
you the contract still holds.

## Variations

### The backend moved

Say the backend team retires `/users/<id>/todos` and serves the same orders at
`/todos?userId=<id>`. Callers keep calling `/v1/customers/1/orders`. Only the
rewrite on that one route changes. On a cloned revision, set the orders route's
`proxy-rewrite` to:

```json
{"regex_uri":["^/v1/customers/([0-9]+)/orders$","/todos?userId=$1"]}
```

Then **Force Deploy** the copy. Run `verify.sh` and you'll see:

- **Cases 1 to 5 pass, with the same responses.** The list, the customer, the
  orders and the limited orders come back exactly as before the move.
- **Case 6 fails.** A caller who calls `/v1/customers/1/orders?userId=2` now
  gets customer 1's **and** customer 2's orders. The backend path now carries
  the id in its own query string, so the caller's `?userId=2` is added after it
  (`/todos?userId=1&userId=2`), and this backend returns both. Before the move,
  the id was in the path, and the backend ignored the extra parameter.

The gateway can't remove a caller's parameter. When a backend moves an id into
its query string, the backend must reject a repeated parameter, or keep a path
that carries the id. That is why `verify.sh` has case 6: the move looks safe
until you test it.

**Match digits only when the id goes into a query string:** `([0-9]+)`, not
`([^/]+)`. With the loose pattern, a caller can call
`/v1/customers/1&userId=2/orders` and the id itself adds a parameter
(`/todos?userId=1&userId=2`). With digits only, the pattern doesn't match,
nothing is rewritten, and the backend answers 404. The caller's own
`?_limit=3` still works: it arrives as `/todos?userId=1&_limit=3`.

### The backend moved to a new host

Change the upstream's node host, port or scheme. No rewrite changes, and
callers notice nothing. A host or port change applies straight away; a scheme
change needs an undeploy and deploy (see **Changing it later** in
[Build it in the UI](#build-it-in-the-ui)). Set **Upstream Host** to the new
host too.

### Publish a v2 next to v1

When the contract itself must change, add `/v2/...` routes beside the `/v1/...`
ones, each with its own rewrite. Both versions can point at the same backend
paths. Clients move to v2 at their own pace, and v1 keeps working until you
retire it.

## Configuration reference

Source of truth: [`example/api-spec.yaml`](example/api-spec.yaml).

```yaml
# GET /v1/customers — a fixed path
proxy-rewrite: { uri: /users }
# GET /v1/customers/:customerId — carry the id
proxy-rewrite: { regex_uri: ["^/v1/customers/([^/]+)$", "/users/$1"] }
# GET /v1/customers/:customerId/orders — carry the id, one level deeper
proxy-rewrite: { regex_uri: ["^/v1/customers/([^/]+)/orders$", "/users/$1/todos"] }
# API-wide — an id on every response
request-id: { algorithm: uuid, header_name: X-Request-Id }
```

| Plugin | Field | Value here | What it means |
|---|---|---|---|
| `proxy-rewrite` | `uri` | `/users` | The backend path for a public path with no id. The caller's query string is added after it. |
| `proxy-rewrite` | `regex_uri` | `[pattern, backend path]` | The pattern is matched against the public path, never the query string. `([^/]+)` captures one path segment; `$1` puts it back. If the pattern doesn't match, the path is sent on unchanged. When both `uri` and `regex_uri` are set, `uri` wins. |
| `request-id` | `algorithm` / `header_name` | `uuid` / `X-Request-Id` | Optional. An id on every response. If a request already carries an `X-Request-Id`, that id is kept. |

When you use your own backend, change the backend paths (`/users`,
`/users/$1`, `/users/$1/todos`), never the public ones.

Placeholders in this package: `<ORG_ID>`, `<API_ID>`, `<REVISION_ID>`,
`<UPSTREAM_ID>`, `<ENV_ID>`, `<YOUR_GATEWAY_HOST>`, `<YOUR_CONTROL_PLANE_API>`.
Replace all of them before you run anything.

Every field of every plugin: [docs.digitalapi.ai/api-gateway](https://docs.digitalapi.ai/api-gateway).
`example/api-spec-basic.yaml` is the same routes with no plugins, for adding
them yourself.

## Troubleshooting

- **Every call returns 404 Route Not Found.** The API isn't deployed in this
  environment, or the path differs from the route: paths are case-sensitive
  (`/V1/customers` is a different path), and a trailing slash
  (`/v1/customers/`) is a different path too.
- **A public path returns 404 with `{}` and an `X-Request-Id`.** The backend
  answered. Either it has no such record (try an id that exists), or the rewrite
  didn't run: a pattern that doesn't match sends the public path to the backend,
  which doesn't have it. Check the pattern against the route's path, character
  by character.
- **Every customer lookup returns the same customer.** The route has a fixed
  `uri`. It needs a `regex_uri` that carries the id.
- **The id routes return 404 Route Not Found after an agent build.** The route
  was stored as `/v1/customers/{customerId}`. Change it to
  `/v1/customers/:customerId` and redeploy. The agent can do this even when the
  prompt says `:customerId`, so check the revision.
- **`?_limit=2` is ignored.** The backend received it, because the query string
  always passes through. Check that your backend supports the parameter. If the
  rewrite target has its own `?`, the caller's parameters come after it, and a
  backend that takes the first of two values ignores the caller's.
- **A caller gets records that aren't theirs by adding a parameter.** The
  rewrite target carries the id in its query string. See
  [The backend moved](#the-backend-moved).
- **The agent built a second upstream for the same backend.** That works. If
  you later delete the API, delete that upstream too.
- **The agent says another API already uses these routes.** APIs deployed to
  the same environment share its host, so two APIs can't both serve
  `/v1/customers`. Undeploy the other one, or ask for a different prefix. Don't
  let it delete an API you still need.
- **Use the trace inspector to see each step.** On the API's page, open the
  **Observability** tab and click **Start trace session**. It shows the path
  `proxy-rewrite` sent to the backend (`upstream_uri`), which is the fastest
  way to check a rewrite. A session stops after 10 requests, so use
  **Advanced: filter which requests to capture** to record only the ones you
  care about (skipped requests don't count). The list doesn't refresh by
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
