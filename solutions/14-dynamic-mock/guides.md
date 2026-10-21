# Guides — a sandbox that answers every partner with their own values

> [Overview](README.md) · [Business need](business-need.md) · [Architecture](architecture.md) · **Guides** · [Agent prompt](helix-agent-prompt.md) · [Tests](tests.md) · [API reference](api-reference.md)

---

Three ways to build the same thing, then how to see it work. Whichever way you
pick, the result is one API whose routes are answered by the gateway itself: a
registration route that stores a partner's values, and a profile route that returns
the calling partner's own values.

## Pick your path

| | Choose this if you… | Go to |
|---|---|---|
| **1. Helix Agent** | want the quickest result and are happy to paste a prompt | [Build it with the Helix Agent](#build-it-with-the-helix-agent) |
| **2. Helix control plane** | prefer clicking through screens and want to see every setting | [Build it in the UI](#build-it-in-the-ui) |
| **3. API script** | are scripting this, or wiring it into a pipeline | [Install it directly](#install-it-directly) |

Then, for everyone: [See it work](#see-it-work) · [Variations](#variations) ·
[Configuration reference](#configuration-reference) · [Troubleshooting](#troubleshooting)

## Build it with the Helix Agent

[`helix-agent-prompt.md`](helix-agent-prompt.md) has four steps: create the API,
add the registration route, add the read route, then read the revision back.
**Paste each as its own message.** The prompt builds a smaller version than the
spec; for the full version, import [`example/api-spec.yaml`](example/api-spec.yaml)
instead.

See [AGENT-GUIDE.md](../../AGENT-GUIDE.md) for the ground rules these prompts
assume.

## Build it in the UI

Screen and button names below are the real ones. The API lives under
**API Gateway** in the left sidebar.

**Before you start:**

- **You have an account.** If you don't, register for a free trial at
  [trial.digitalapi.ai](https://trial.digitalapi.ai/). A new trial org comes with a
  `test` environment.
- **You can create APIs.** If you don't see an **Add API** button, ask your org
  admin.
- **The environment has the key-value store available.** It is infrastructure this
  spec uses, not something it creates.

**1. Create the API**

Pick one of the two ways below. Both give you the same thing: an API called
`Partner Sandbox API` with three routes and no plugins yet.

*Option A — from scratch*
1. Go to **API Gateway → APIs**, click **Add API** (or **Create your first API**).
2. Choose **Create from scratch**. Set **Display name** to `Partner Sandbox API`,
   then **Create**.
3. On the API's page, open **Configuration → Routes** and add three routes:
   - `POST` `/sandbox/partners`, where an operator registers a partner's values
   - `GET` `/sandbox/profile`, which answers a partner with their own values
   - `GET` `/sandbox/diagnostics`, a teaching route that shows how a stored value
     is referenced

   The route form opens already filled in with the name *New* and the path
   `/new-route`. Clear both fields first, then type your own.

*Option B — from an OpenAPI spec*
1. Go to **API Gateway → APIs**, click **Add API** (or **Create your first API**).
2. Set **Method** to **Import an OpenAPI spec**.
3. Drag in your own OpenAPI 3.0 file, or use our example,
   [`example/api-spec-basic.yaml`](example/api-spec-basic.yaml): the same three
   routes, no plugins. Then click **Import**.

> **A spec can carry the plugins too.** Add an `x-helix-gateway` block that
> lists them. At the top level of the file it covers every route; under one
> path and method it covers that route only. This is the profile route's:
>
> ```yaml
> /sandbox/profile:
>   get:
>     x-helix-gateway:
>       plugins:
>         key-value-map:
>           fail_action: close
>           fetch:
>             keys:
>               - key: "tier:$request.headers.x-partner-id"
>                 alias: tier
>               - key: "settlement:$request.headers.x-partner-id"
>                 alias: settlement
>         mocking:
>           content_type: application/json
>           response_headers:
>             X-Partner-Tier: "$ctx.helix.key_value_map.tier"
>           response_example: |-
>             {"partner":"$http_x_partner_id","tier":"$ctx.helix.key_value_map.tier","settlement":"$ctx.helix.key_value_map.settlement"}
> ```
>
> [`example/api-spec.yaml`](example/api-spec.yaml) is this API with all its
> plugins already in place. Import that instead and you can skip step 2.

Either way, the API is not live yet: it has no upstream and isn't deployed.
That comes in step 3.

**2. Add the plugins**

Two plugins on each route turn it into a sandbox: `key-value-map` stores or looks
up the partner's values, and `mocking` answers the request with them, so no
backend is ever called. Add them **before** you deploy: a live revision can't be
changed.

Each one goes on one route, not on the whole API.

On the API's page, open **Configuration → Plugins** and click **Configure
plugin**. A short wizard opens:

1. **Plugin** — pick the plugin from the catalog.
2. **Scope** — choose **Specific endpoint** and pick the route. (**Entire
   Revision** would apply it to every route.)
3. **Configure** — the JSON editor and the Properties list sit side by side.
   Paste the JSON below, or fill in the fields. Then **Next**.
4. **Review** — shows the configuration before and after. Click **Apply**.

Run the wizard once for each plugin on each route: six times in all.

Keep every value that starts with `$` exactly as written. They are not
placeholders for you to fill in: the gateway reads them as each request arrives.
`$request.headers.x-partner-id` is the caller's partner id, and
`$ctx.helix.key_value_map.tier` is the value just stored or looked up. Write the
second kind with a bare `$` and no braces: `${...}` around it always comes out
empty. A hyphen ends that kind of reference, so keep the names in it to letters,
digits and underscores.

On the **`POST /sandbox/partners`** route (Scope: **Specific endpoint**, that
route):

1. **`key-value-map` — stores the partner's values.** It saves the tier and the
   settlement account from the request headers under the partner id, for one day
   (86400 seconds). Registering the same id again replaces them.

   ```json
   {"fail_action":"close","inserts":[{"key":"tier:$request.headers.x-partner-id","value":"$request.headers.x-tier","ttl":86400},{"key":"settlement:$request.headers.x-partner-id","value":"$request.headers.x-settlement-account","ttl":86400}]}
   ```

2. **`mocking` — answers with what was stored.** The caller gets HTTP 202
   (accepted) and the stored values back.

   | Field | Value |
   |---|---|
   | **response_status** | `202` |
   | **content_type** | `application/json` |
   | **response_example** | `{"registered":true,"stored":$ctx.helix.key_value_map.inserted}` |

   ```json
   {"response_status":202,"content_type":"application/json","response_example":"{\"registered\":true,\"stored\":$ctx.helix.key_value_map.inserted}"}
   ```

On the **`GET /sandbox/profile`** route (Scope: **Specific endpoint**, that
route):

1. **`key-value-map` — looks up the calling partner's values.** `alias` gives each
   value a fixed name (`tier`, `settlement`), so the next plugin can refer to it
   whichever partner is calling.

   ```json
   {"fail_action":"close","fetch":{"keys":[{"key":"tier:$request.headers.x-partner-id","alias":"tier"},{"key":"settlement:$request.headers.x-partner-id","alias":"settlement"}]}}
   ```

2. **`mocking` — answers with that partner's profile.** It also puts the tier in
   an `X-Partner-Tier` response header.

   ```json
   {"content_type":"application/json","response_headers":{"X-Partner-Tier":"$ctx.helix.key_value_map.tier"},"response_example":"{\"partner\":\"$http_x_partner_id\",\"tier\":\"$ctx.helix.key_value_map.tier\",\"settlement\":\"$ctx.helix.key_value_map.settlement\"}"}
   ```

On the **`GET /sandbox/diagnostics`** route (Scope: **Specific endpoint**,
that route):

1. **`key-value-map` — looks up the calling partner's tier.**

   ```json
   {"fail_action":"close","fetch":{"keys":[{"key":"tier:$request.headers.x-partner-id","alias":"tier"}]}}
   ```

2. **`mocking` — shows the same value written two ways.** The bare `$` form
   resolves and the `${...}` form comes out empty, which makes the difference
   easy to see.

   ```json
   {"content_type":"text/plain","response_example":"bare_form   = $ctx.helix.key_value_map.tier\nbrace_form  = ${ctx.helix.key_value_map.tier}\nnamespace   = $ctx.helix.key_value_map"}
   ```

Repeat for each plugin and route. What every field means, and the two optional extras (`request-id`, `cors`) the full
spec adds: [Configuration reference](#configuration-reference).

**3. Give it an upstream, then deploy it**
1. Go to **API Gateway → Upstreams → Add Upstream**. Name it, pick environment
   `test`, and add a node at `httpbin.org`, port `443`, scheme HTTPS (any host
   will do). If you switch the scheme to HTTP, the port stays at `443`: change
   it to `80` by hand. It is never contacted — `mocking` answers every route —
   but the revision cannot deploy without one.
2. **Pass Host** is set to **Rewrite**, which makes **Upstream Host** required.
   It fills in from the node's host; check it reads `httpbin.org`.
3. Click **Next** through the remaining tabs, then **Add Upstream**.
4. Back on the API's page, click **Deploy** on the revision. The dialog asks you
   to map an upstream for `test`. Pick the one you just created, then **Deploy**.

**Changing it later.** A change to the upstream (host, port, scheme) applies to
the live API straight away, with no new deploy. A change to routes or plugins
does need one, because a live revision can't be edited: use **Clone Revision**,
make your change on the copy, then **Force Deploy** it. The same steps roll you
back: clone the older revision and force-deploy that.

**4. Register partners**

There is no screen for sandbox values, and no control-plane API either: on this
build, the registration route is the only way to write an entry. Send the requests
in [See it work](#see-it-work).

**5. Before you expose it**

Protect `/sandbox/partners` ([solution 08](../08-api-key/)) and drop
`/sandbox/diagnostics`, which shows the store's contents to any caller.

## Install it directly

If you'd rather script it against the control plane:

```bash
export ORG=<ORG_ID>
export TOKEN=<control-plane bearer token>      # short-lived
export BASE=https://<YOUR_GATEWAY_HOST>/api
H=(-H "authorization: Bearer $TOKEN" -H 'content-type: application/json')

# 1. Import the spec (multipart — a raw application/yaml body is rejected with 415).
#    Keep both ids the response returns.
curl -s -H "authorization: Bearer $TOKEN" -F "file=@example/api-spec.yaml" \
  "$BASE/orgs/$ORG/apis/from-spec"
# → {"api":{"id":"<API_ID>", ...}, "revision":{"id":"<REVISION_ID>", ...}}

# 2. Bind an upstream and deploy. The upstream is never contacted — mocking
#    answers every route — but the binding is required for the revision to deploy.
curl -s "${H[@]}" -X POST "$BASE/orgs/$ORG/envs/<TEST_ENV_ID>/upstreams" \
  -d '{"name":"sandbox-placeholder","specification":{"scheme":"https","nodes":[{"host":"httpbin.org","port":443,"weight":1}]}}'
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

```bash
GW=https://<YOUR_GATEWAY_HOST>

# register two partners
curl -X POST "$GW/sandbox/partners" \
  -H 'x-partner-id: acme-42' -H 'x-tier: gold' -H 'x-settlement-account: GB29-SANDBOX-0001'
# {"registered":true,"stored":{"tier:acme-42":"gold","settlement:acme-42":"GB29-SANDBOX-0001"}}
curl -X POST "$GW/sandbox/partners" \
  -H 'x-partner-id: globex-7' -H 'x-tier: bronze' -H 'x-settlement-account: GB29-SANDBOX-0002'

# each one reads its own
curl "$GW/sandbox/profile" -H 'x-partner-id: acme-42'
# {"partner":"acme-42","tier":"gold","settlement":"GB29-SANDBOX-0001"}

curl "$GW/sandbox/profile" -H 'x-partner-id: globex-7'
# {"partner":"globex-7","tier":"bronze","settlement":"GB29-SANDBOX-0002"}

# change one, with no deploy
curl -X POST "$GW/sandbox/partners" \
  -H 'x-partner-id: acme-42' -H 'x-tier: platinum' -H 'x-settlement-account: GB29-SANDBOX-0009'
curl "$GW/sandbox/profile" -H 'x-partner-id: acme-42'
# {"partner":"acme-42","tier":"platinum","settlement":"GB29-SANDBOX-0009"}

# see both template syntaxes side by side
curl "$GW/sandbox/diagnostics" -H 'x-partner-id: acme-42'
# bare_form   = platinum
# brace_form  =
# namespace   = {"tier":"platinum"}
```

To run all six checks as a script:

```bash
GATEWAY=https://<YOUR_GATEWAY_HOST> ./example/verify.sh
```

Exit code 0 means each partner gets their own values, a second partner never sees
the first one's, an unknown partner gets empty values, a change needs no deploy,
and the bare `$ctx` syntax works while the braced one does not. What each check
proves: [Tests](tests.md).

## Variations

**Change the paths.** `/sandbox/partners`, `/sandbox/profile` and
`/sandbox/diagnostics` are illustrative; any paths work.

**Store more fields.** Add another `inserts` entry on the registration route and
another aliased `fetch` key on the profile route. The shipped spec already stores
two (`tier` and `settlement`); the agent prompt stores one.

**Change the expiry.** Values are stored with `ttl: 86400` (24 hours). Pick it for
how often your partners' data changes. Past it, a partner silently reverts to the
unregistered response.

**Identify partners by credential, not header.** `x-partner-id` is a header the
caller controls. In a real deployment, derive the identity from an authenticated
credential instead ([solution 08](../08-api-key/)).

**Tell a miss from an empty value.** Both render as `""`. Store a marker value if
you need to tell them apart.

**Reject malformed requests too.** This changes what the sandbox answers, not what
it accepts. Add `request-validation` by spec import if the sandbox should also
reject bad requests.

## Configuration reference

Source of truth: [`example/api-spec.yaml`](example/api-spec.yaml).
[`example/api-spec-basic.yaml`](example/api-spec-basic.yaml) is the same routes
with no plugins, for adding them yourself.

Registration route:

```yaml
key-value-map:
  fail_action: close
  inserts:
    - key: "tier:$request.headers.x-partner-id"
      value: "$request.headers.x-tier"
      ttl: 86400
    - key: "settlement:$request.headers.x-partner-id"
      value: "$request.headers.x-settlement-account"
      ttl: 86400

mocking:
  response_status: 202
  content_type: application/json
  response_example: |-
    {"registered":true,"stored":$ctx.helix.key_value_map.inserted}
```

Profile route:

```yaml
key-value-map:
  fail_action: close
  fetch:
    keys:
      - key: "tier:$request.headers.x-partner-id"
        alias: tier
      - key: "settlement:$request.headers.x-partner-id"
        alias: settlement

mocking:
  content_type: application/json
  response_headers:
    X-Partner-Tier: "$ctx.helix.key_value_map.tier"
  response_example: |-
    {"partner":"$http_x_partner_id","tier":"$ctx.helix.key_value_map.tier","settlement":"$ctx.helix.key_value_map.settlement"}
```

| Plugin | Field | Value here | What it means |
|---|---|---|---|
| `key-value-map` | `fail_action` | `close` | Fail the request on a store error. It does **not** cover a missing value. |
| `key-value-map` | `inserts[].key` | `tier:$request.headers.x-partner-id` | The storage key, built from the caller's id with a label in front. |
| `key-value-map` | `inserts[].value` | `$request.headers.x-tier` | The value comes from the request, never from this file. |
| `key-value-map` | `inserts[].ttl` | `86400` | Seconds before the value expires. A choice, not a platform default. |
| `key-value-map` | `fetch.keys[].alias` | `tier`, `settlement` | Renames the published field so a fixed template can refer to it. |
| `mocking` | `response_status` | `202` (registration) | The registration answer. Not proof of a write. |
| `mocking` | `response_example` | the JSON above | The body, built from `$ctx.helix.key_value_map.*` (bare form). The `inserted` table sits unquoted because it expands to a JSON object. |
| `mocking` | `response_headers` | `X-Partner-Tier` | Response headers are filled in the same way as the body. |
| `request-id` | `algorithm` / `header_name` | `uuid` / `X-Request-Id` | API-wide. A handle for a "my sandbox says bronze" report; the store logs nothing per request. |
| `cors` | `allow_origins` / `allow_methods` / `allow_headers` | `*` / `GET,POST,OPTIONS` / `content-type,x-partner-id,x-tier,x-settlement-account` | API-wide, for browser-based partner tools. Tighten `allow_origins` before real use. |

The diagnostics route repeats the profile route's fetch and answers in plain text
with the value in both syntaxes plus the whole namespace. Drop it before
production.

Placeholders in this package: `<ORG_ID>`, `<TEST_ENV_ID>`, `<API_ID>`,
`<REVISION_ID>`, `<UPSTREAM_ID>`, `<YOUR_GATEWAY_HOST>`. Replace all of them before
you run anything.

Every field of every plugin: [docs.digitalapi.ai/api-gateway](https://docs.digitalapi.ai/api-gateway).

## Troubleshooting

Each of these returns a 200, which is what makes them hard to spot.

| Symptom | Cause |
|---|---|
| Values come back as empty strings, 200, nothing logged | The braces. `${ctx.helix...}` reads a different table that `key-value-map` never writes to. Use the bare `$ctx.` form. |
| The reference resolves partly, leaving a literal tail | A hyphen in a `$ctx` path segment ends the reference. Segments are letters, digits and underscores only. |
| A header value renders as mangled text like `-partner-id` | `$request.headers.<name>` is `key-value-map`'s syntax and does not work inside `mocking`. Use `$http_x_partner_id`. |
| The response is invalid JSON but still returns 200 | A `$ctx` reference to a table expands to a JSON object. Don't wrap it in quotes. |
| A lookup never finds anything | The key used a dotted suffix (`$request.headers.x-partner-id.tier`), which looks up a header named `x-partner-id.tier`. Put the label in front: `tier:$request.headers.x-partner-id`. |
| Every partner sees the same value | The `alias` is missing, or the key template lost its per-caller reference. |
| A partner's values vanished | They expired. Values are stored with a 24-hour TTL. |
| The registration said 202 but nothing was stored | The 202 confirms the insert was configured, not written. Fetch the profile to check. |
| Deploy fails: `Only INACTIVE revisions can be updated` | Clone the revision or undeploy, then apply. |

If you built it with the agent:

| Symptom | Cause |
|---|---|
| The route deploys with plugins you never asked for | The plugin-name level was dropped. Read the revision back and ask for a `plugins` object keyed by plugin name. |
| `stream closed with reason: error`, nothing written | The structure was too deep for one write. Split the step, or use spec import. |

- **Use the trace inspector to see each step.** On the API's page, open
  **Observability → Start trace**. It shows the headers each plugin changes and
  the request body at every stage, which is the fastest way to see what each
  plugin did to a call.
