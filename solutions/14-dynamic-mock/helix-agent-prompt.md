# Agent-mode prompt — build the per-caller sandbox

Four bounded steps: create the API, the registration route, the read route, then
read the revision back. One ask per step is not stylistic — a monolithic prompt
pushes the default agent model into an oversized tool call, and the failure is not
a clean error but a write that reports success and stores nothing.

[AGENT-GUIDE.md](../../AGENT-GUIDE.md) carries the standing rules these prompts
assume.

---

## Step 1 — create the API

```text
Create an API called "Partner Sandbox API" in my organisation. Don't add any
routes or plugins yet — just create the API and tell me its id.
```

## Step 2 — the registration route

```text
On the Partner Sandbox API, add a route POST /sandbox/partners. Give it exactly
two plugins, and keep the plugin-name level explicit — a "plugins" object whose
keys are "key-value-map" and "mocking".

key-value-map:
  fail_action: close
  inserts:
    - key: "tier:$request.headers.x-partner-id"
      value: "$request.headers.x-tier"
      ttl: 86400

mocking:
  response_status: 202
  content_type: application/json
  response_example: {"registered":true}

The key is a template, and the "tier:" prefix in front of it is deliberate — do
not move it, remove it, or turn it into a dotted suffix.
```

## Step 3 — the read route

```text
On the same API, add a route GET /sandbox/profile with exactly two plugins,
"key-value-map" and "mocking":

key-value-map:
  fail_action: close
  fetch:
    keys:
      - key: "tier:$request.headers.x-partner-id"
        alias: tier

mocking:
  content_type: application/json
  response_example: {"tier":"$ctx.helix.key_value_map.tier"}

The $ctx reference is literal text — do not rewrite it, do not add braces around
it, and do not "correct" it to ${ctx...}. The braces break it. The alias is also
load-bearing; without it the reference cannot resolve.
```

## Step 4 — read the revision back

```text
Read back the current revision of the Partner Sandbox API and show me the plugins
stored on each route, so I can confirm both routes carry key-value-map AND
mocking under their own plugin names.
```

**Not optional.** Three of the four known agent-mode defects report success at
every step the agent shows you.

---

## Why it's shaped this way

| Choice | Reason |
|---|---|
| **One route per step** | A prompt carrying two routes and four plugin blocks is deep enough to trigger the `update_route_spec` delimiter defect, which surfaces as `stream closed with reason: error` and writes nothing. |
| **"keep the plugin-name level explicit"** | The agent can drop that level and promote one plugin's fields into the `plugins` map — the route then deploys carrying several nonexistent plugins and none of the real one. The write succeeds and the dry-run passes. |
| **"the $ctx reference is literal text"** | `$ctx.helix.key_value_map.tier` looks like a path expression an assistant should tidy. An agent that "corrects" it to `${ctx.helix...}` produces empty values, a 200, and no error. |
| **No `request-validation` body schema** | A `body_schema` carrying a `properties` map is exactly the nesting depth that fails the delimiter defect 5 runs out of 5. Anything that deep belongs in spec import, not an agent write. |
| **Ask for `dry_run_deploy`, never `validate_route`** | `validate_route` always fails on this build: the tool posts `{"route": …}` and the endpoint requires `{"routeSpec": [ … ]}`. |

## Tweak knobs

- **Paths** — `/sandbox/partners` and `/sandbox/profile` are illustrative.
- **Fields** — this prompt stores one value per partner (`tier`). The shipped spec
  stores two; add a second `inserts` entry and a second aliased `fetch` key.
- **TTL** — 86400s. Pick it for how often partner data changes; past it, a partner
  silently reverts to the unregistered response.
- **Identity** — `x-partner-id` is a header the caller controls. In a real
  deployment, derive the identity from an authenticated credential instead.

## When it goes wrong

| Symptom | Cause |
|---|---|
| Values come back as empty strings, 200, nothing logged | The braces. `${ctx.helix...}` reads a different table that `key-value-map` never writes to. Use the bare `$ctx.` form. |
| The reference resolves partially, leaving a literal tail | A hyphen in a `$ctx` path segment ends the reference. Segments are `[A-Za-z0-9_]` only — underscores, never hyphens. |
| A header value renders as mangled text like `-partner-id` | `$request.headers.<name>` is `key-value-map`'s grammar and does not resolve inside `mocking`. Use `$http_x_partner_id`. |
| The response is invalid JSON but still returns 200 | A `$ctx` reference to a table expands to a JSON object. Don't wrap it in quotes. |
| Every partner sees the same value | The `alias` is missing, or the key template lost its per-caller reference. |
| The route deploys with plugins you never asked for | Defect 4 — the plugin-name level was dropped. Read the revision back. |
| `stream closed with reason: error`, nothing written | Defect 3 — the structure was too deep. Split the step or use spec import. |
