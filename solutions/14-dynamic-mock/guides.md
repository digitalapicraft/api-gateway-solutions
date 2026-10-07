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

[`helix-agent-prompt.md`](helix-agent-prompt.md) has the build as four steps:
create the API, add the registration route, add the read route, then read the
revision back. Paste each as its own message.

**The prompt builds a smaller version than the spec.** It stores one value per
partner (`tier`) and leaves out the diagnostics route, `request-id` and `cors`. The
shipped spec stores two values (`tier` and `settlement`) and carries all three
routes. To get the full version, import [`example/api-spec.yaml`](example/api-spec.yaml)
instead. The prompt also stops at the read-back: bind an upstream and deploy as in
[Build it in the UI](#build-it-in-the-ui), step 2.

Why the prompt is shaped this way:

| Choice | Reason |
|---|---|
| **One route per step** | A prompt carrying two routes and four plugin blocks is deep enough to trigger the agent's tool-argument defect, which shows up as `stream closed with reason: error` and writes nothing. |
| **"keep the plugin-name level explicit"** | The agent can drop that level and promote one plugin's fields into the `plugins` map. The route then deploys carrying several plugins that do not exist and none of the real one; the write succeeds and the dry-run passes. |
| **"the $ctx reference is literal text"** | `$ctx.helix.key_value_map.tier` looks like something an assistant should tidy. "Correcting" it to `${ctx.helix...}` produces empty values, a 200, and no error. |
| **No `request-validation` body schema** | A body schema with a `properties` map is exactly the depth that fails the tool-argument defect, five runs out of five. Anything that deep belongs in spec import, not an agent write. |
| **Ask for `dry_run_deploy`, never `validate_route`** | `validate_route` always fails on this build: the tool sends `{"route": …}` and the endpoint expects `{"routeSpec": [ … ]}`. |

If the agent wants to change something it shouldn't, reply plainly:

- **It moves or removes the `tier:` prefix, or turns it into a dotted suffix.** The
  key is a template, and the prefix in front of it is deliberate. Ask it to keep
  the key exactly as written.
- **It drops the `alias`.** The alias is what lets the template refer to the value.
  Without it the reference cannot resolve.

Reading the revision back is the only check that catches a silently dropped
plugin. Confirm both routes carry `key-value-map` **and** `mocking`, each under its
own name.

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

**1. Import the API**
1. Go to **API Gateway → APIs**, click **Add API** (or **Create your first API**).
2. Set **Method** to **Import an OpenAPI spec**.
3. Drag in [`example/api-spec.yaml`](example/api-spec.yaml), or paste its
   contents, then click **Import**.

This creates the API and its first revision with all three routes, each carrying
`key-value-map` and `mocking`, plus `request-id` and `cors` API-wide. These plugin
settings are carried by the imported spec; there is no separate screen to set them
on.

Import does **not** bind an upstream or deploy, and nothing warns you if you skip
that. The routes just never go live.

**2. Give it an upstream, then deploy it**
1. Go to **API Gateway → Upstreams → Add Upstream**. Name it, pick environment
   `test`, point it at any host (for example `httpbin.org`), then **Create
   Upstream**. It is never contacted — `mocking` answers every route — but the
   revision cannot deploy without one.
2. Back on the API's page, click **Deploy** on the revision. The dialog asks you
   to map an upstream for `test`. Pick the one you just created, then **Deploy**.

**3. Register partners**

There is no screen for sandbox values, and no control-plane API either: on this
build, the registration route is the only way to write an entry. Send the requests
in [See it work](#see-it-work).

**4. Before you expose it**

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
