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

[`helix-agent-prompt.md`](helix-agent-prompt.md) has two steps: create the API with
its two routes, then make them store each partner's values and answer with them.
**Paste the whole prompt as one message** and replace the `{{...}}` values. It
builds a smaller version than the spec, with no `/sandbox/diagnostics` teaching
route. For the full version, import [`example/api-spec.yaml`](example/api-spec.yaml)
instead. Then run [`example/verify.sh`](example/verify.sh) as in
[See it work](#see-it-work).

**Before you trust it, read the stored revision back and check:**

- **The registration route** carries `key-value-map` with `inserts` keyed per
  partner (`tier:$request.headers.x-partner-id`, `settlement:…`), and `mocking`
  answering 202.
- **The profile route** carries a `key-value-map` `fetch` of the same keys, with an
  `alias` on each.
- **The profile route's `mocking`** reads `$ctx.helix.key_value_map.<alias>`: a bare
  `$`, no braces. `${ctx.helix…}` comes back empty, with a 200.
- **Both plugins sit under their own names** in each route's `plugins` map.

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

If an API with the same name already exists in your org, the import fails with
*API with name '<name>' already exists*. Type another name in the form's
**Display name** field, which overrides the name in the spec, and import again.

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
empty.

**JSON editor or Properties fields: the quotes differ.** In the JSON blocks below,
the quotes inside `response_example` are written `\"`, because that value is text
inside JSON. That is right for the JSON editor only. If you fill in the
**Properties** fields instead, type the value with plain quotes and no
backslashes, as in the registration route's table. Copy the `\"` form into a
Properties field and the backslashes are saved as part of the value: the reply is
then invalid JSON, yet the registration route still answers 202. The simplest way
is to paste each JSON block into the JSON editor.

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
   an `X-Partner-Tier` response header. For a partner with no stored tier, the
   header is left out, not sent empty.

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
   to map an upstream for `test`. Pick the one you just created, then click
   **Map & Deploy**. (The button reads **Map & Deploy** while no upstream is
   mapped yet, and **Deploy** once one is.)

**Changing it later.** A change to the upstream's host or port applies to the
live API straight away, with no new deploy. A change to its scheme does not:
undeploy the revision and deploy it again. A change to routes or plugins does
need one, because a live revision can't be edited: use **Clone Revision**, make
your change on the copy, then **Force Deploy** it. Rolling back needs no copy:
click **Deploy**, pick the older revision (for example `r1`), and click **Force
Deploy**. Stored partner values are not part of a revision: they survive a
redeploy and a rollback, and stay until they expire or are registered again.

**4. Register partners**

There is no screen for sandbox values, and no control-plane API either: on this
build, the registration route is the only way to write an entry. Send the requests
in [See it work](#see-it-work). Send all three headers every time: without
`x-partner-id` the values are saved with no partner id and shared by every caller
who sends none, and without `x-tier` and `x-settlement-account` nothing is stored
(see [Troubleshooting](#troubleshooting)).

**5. Before you expose it**

- **Protect `/sandbox/partners` like any admin endpoint**
  ([solution 08](../08-api-key/)). Anyone who can reach it can change any
  partner's values.
- **Don't let untrusted callers register.** Header values are copied into the
  reply as they are, with no escaping. A partner registered with
  `x-tier: gold","admin":"true` gets a profile with an extra `"admin":"true"`
  field in it. Only let trusted operators call the registration route, and check
  the values before they reach the gateway (letters, digits and hyphens only, for
  example).
- **Drop `/sandbox/diagnostics`**, which shows the store's contents to any caller.

## Install it directly

To script it, call the control plane instead. `BASE` is the API address the
portal calls (it usually starts with `api-`), not the portal page and not the
gateway's address:

```bash
export ORG=<ORG_ID>
export TOKEN=<control-plane bearer token>      # short-lived
export BASE=https://<YOUR_CONTROL_PLANE_API>/api
H=(-H "authorization: Bearer $TOKEN" -H 'content-type: application/json')

# 1. Import the spec (multipart — a raw application/yaml body is rejected with 415).
#    Keep both ids the response returns.
curl -s -H "authorization: Bearer $TOKEN" -F "file=@example/api-spec.yaml" \
  "$BASE/orgs/$ORG/apis/from-spec"
# → {"api":{"id":"<API_ID>", ...}, "revision":{"id":"<REVISION_ID>", ...}}

# 2. Bind an upstream and deploy. The upstream is never contacted — mocking
#    answers every route — but the binding is required for the revision to deploy.
# pass_host + upstream_host: without them the backend gets the gateway's host
# and every call returns 502.
curl -s "${H[@]}" -X POST "$BASE/orgs/$ORG/envs/<TEST_ENV_ID>/upstreams" \
  -d '{"name":"sandbox-placeholder","specification":{"scheme":"https","pass_host":"rewrite","upstream_host":"httpbin.org","nodes":[{"host":"httpbin.org","port":443,"weight":1}]}}'
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
curl -i "$GW/sandbox/profile" -H 'x-partner-id: acme-42'
# HTTP 200, with the header X-Partner-Tier: gold
# {"partner":"acme-42","tier":"gold","settlement":"GB29-SANDBOX-0001"}

curl "$GW/sandbox/profile" -H 'x-partner-id: globex-7'
# {"partner":"globex-7","tier":"bronze","settlement":"GB29-SANDBOX-0002"}

# a partner nobody registered: 200, empty values, and no X-Partner-Tier header
curl -i "$GW/sandbox/profile" -H 'x-partner-id: nobody-9'
# {"partner":"nobody-9","tier":"","settlement":""}

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

The `stored` part of the registration reply comes back with its keys in no fixed
order: `settlement:acme-42` may come before `tier:acme-42`. Compare it as JSON,
not as text. The profile reply always has the same order, because its template
fixes it.

To run all six checks as a script:

```bash
GATEWAY=https://<YOUR_GATEWAY_HOST> ./example/verify.sh
```

Exit code 0 means each partner gets their own values, a second partner never sees
the first one's, an unknown partner gets empty values, a change needs no deploy,
and the bare `$ctx` syntax works while the braced one does not. What each check
proves: [Tests](tests.md).

On a build from the agent prompt, checks 1 to 5 cover what it built. Check 6 needs
the `/sandbox/diagnostics` route, which the prompt leaves out, so it fails until
you add that route ([Variations](#variations)).

## Variations

Where a variation has a prompt, send it to the Helix Agent in the same session,
once the main build is done. Like the main prompt, it says what should be true and
leaves the plugins to the agent.

**Change the paths.** `/sandbox/partners`, `/sandbox/profile` and
`/sandbox/diagnostics` are illustrative; any paths work.

**Protect the registration route.** `/sandbox/partners` ships with no sign-in, so
anyone who can reach it can change any partner's values. Protect it like any admin
endpoint, for example with an operator's API key ([solution 08](../08-api-key/)).
With the agent:

```text
Require an operator's API key in the X-Admin-Key header on POST /sandbox/partners
only, and leave the profile route as it is. Tell me what is still open after that.
```

**Store more fields.** Add another `inserts` entry on the registration route and
another aliased `fetch` key on the profile route. The shipped spec and the agent
prompt both store two (`tier` and `settlement`). A hyphen in an alias is fine:
`$ctx.helix.key_value_map.my-tier` resolves like any other name. With the agent:

```text
Also store each partner's X-Region header, and return it as "region" in the
profile response.
```

**Show the store's contents while your team learns it.** The agent prompt leaves
out the `/sandbox/diagnostics` teaching route. To add it:

```text
Add GET /sandbox/diagnostics, answered by the gateway, showing the calling
partner's stored tier read two ways: as $ctx.helix.key_value_map.tier and as
${ctx.helix.key_value_map.tier}, plus everything stored for that partner. I'll
remove it before production.
```

Drop it before production: it shows the store's contents to any caller.

**Change the expiry.** Values are stored with `ttl: 86400` (24 hours). Pick it for
how often your partners' data changes. Past it, a partner silently reverts to the
unregistered response.

**Identify partners by credential, not header.** `x-partner-id` is a header the
caller controls. In a real deployment, derive the identity from an authenticated
credential instead ([solution 08](../08-api-key/)). With the agent:

```text
X-Partner-Id is a header anyone can send. Identify the calling app instead, and key
the stored values on that app, so a partner can only ever read its own.
```

**Tell a miss from an empty value.** Both render as `""`. Store a marker value if
you need to tell them apart.

**Reject malformed requests too.** This changes what the sandbox answers, not what
it accepts. Add `request-validation` by spec import if the sandbox should also
reject bad requests. On the registration route, the first thing to require is all
three headers: a registration without `x-partner-id` saves its values for every
caller who sends no id, and one without `x-tier` and `x-settlement-account`
stores nothing yet still answers 202.

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

- **You can't tell a mocked reply from a backend one.** Every reply the mock builds
  carries an `x-mock-by` response header, such as `x-mock-by: HELIX/dev` (the
  part after `HELIX/` names the gateway's version, so yours may differ). Look for
  it to tell a mocked reply from one a backend sent.
- **Values come back as empty strings, with a 200 and nothing logged.** Check the
  braces. `${ctx.helix...}` reads a different table that `key-value-map` never
  writes to. Use the bare `$ctx.` form.
- **Every partner gets empty values, even registered ones.** The `alias` is
  missing from the lookup. Without it, the looked-up value is filed under its full
  key (`tier:acme-42`), so `$ctx.helix.key_value_map.tier` finds nothing.
  Add `alias: tier` (and `alias: settlement`) to the `fetch` keys.
- **Every partner sees the same value.** The key template lost its per-caller
  part, so every partner reads the same entry. Keep
  `$request.headers.x-partner-id` in every key, on both routes.
- **A lookup finds nothing, or another caller's data.** The key used a dotted
  suffix, such as `tier:$request.headers.x-partner-id.tier`. That reads a header
  called `x-partner-id.tier`, which doesn't exist, so the key becomes just
  `tier:`. The lookup then finds nothing, or whatever a caller with no partner id
  stored. Put the label in front only: `tier:$request.headers.x-partner-id`.
- **Callers with no partner id all see the same values.** A registration was sent
  without `x-partner-id`, so its values were saved under `tier:` and
  `settlement:`, with no id. Every caller who sends no id reads them. Always send
  `x-partner-id` when you register, and protect the registration route.
- **Registration answers 202 with `{"registered":true,"stored":}`.** That reply is
  invalid JSON, and it means nothing was stored: the `x-tier` and
  `x-settlement-account` headers were missing. Send them and register again.
- **The registration said 202 but nothing was stored.** The 202 only confirms the
  store step was set up, not that a value was written. Fetch the profile to check.
- **A reply is invalid JSON with backslashes in it.** The `\"` form of a JSON
  block was typed into a **Properties** field, so the backslashes were saved as
  part of the value. Paste the JSON into the JSON editor instead, or type the
  value with plain quotes.
- **The profile has fields you never set, such as `"admin":"true"`.** Someone
  registered a value with quotes in it (`x-tier: gold","admin":"true`). Header
  values are copied into the reply with no escaping. Register the partner again
  with a clean value, and see step 5, *Before you expose it*, in
  [Build it in the UI](#build-it-in-the-ui).
- **The response is invalid JSON but still returns 200.** A `$ctx` reference to a
  table expands to a JSON object. Don't wrap it in quotes.
- **A header value shows up as mangled text like `-partner-id`.**
  `$request.headers.<name>` is `key-value-map`'s syntax and does not work inside
  `mocking`. Use `$http_x_partner_id`.
- **There is no `X-Partner-Tier` header.** The partner has no stored tier, so the
  header is left out, not sent empty.
- **A partner's values vanished.** They expired. Values are stored for 24 hours
  (86400 seconds). A redeploy or a rollback does not remove them.
- **Deploy fails: `Only INACTIVE revisions can be updated`.** Clone the revision
  or undeploy, then apply.
- **Built with the agent: it writes a design but creates nothing, or designs
  without the gateway's key-value store** (it says live execution is off, suggests
  a backend service, or picks a different plugin). The build needs `key-value-map`
  to store and look up each partner's values, and `mocking` to answer with
  `$ctx.helix.key_value_map.<alias>`. Start a new session and say that the values
  live in the gateway's key-value store and the gateway answers with `mocking`. The
  dependable path is to import [`example/api-spec.yaml`](example/api-spec.yaml).
- **Built with the agent: the route deploys with plugins you never asked for.**
  The plugin-name level was dropped, and one plugin's fields were promoted into
  the `plugins` map. Read the revision back and ask for a `plugins` object keyed
  by plugin name.
- **Built with the agent: `stream closed with reason: error`, and nothing was
  written.** The agent sent a malformed write for a large or deeply nested route.
  Retry once, or paste the two steps as separate messages. If it fails again,
  import [`example/api-spec.yaml`](example/api-spec.yaml).
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
  larger than the request's own total. In a trace of this API, the store's work
  shows up as a list called `kvm_ops`, one entry per store operation with its
  operation, key and value. Look there, not under the
  `helix.key_value_map` names the templates use.
- **See what changed, and when, in Audit Logs.** **Observability → Audit Logs**
  lists every clone, plugin change and deploy. Its times are in your local time,
  while analytics uses UTC. Anything done with your token, including scripts and
  the Helix Agent, appears under your name.
