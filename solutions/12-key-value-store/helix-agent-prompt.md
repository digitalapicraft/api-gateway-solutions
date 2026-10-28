# Agent-mode prompt — build the per-caller sandbox

> [Overview](README.md) · [Business need](business-need.md) · [Architecture](architecture.md) · [Guides](guides.md) · **Agent prompt** · [Tests](tests.md) · [API reference](api-reference.md)

---

Paste each step to the Helix Agent as its own message, in order: create the API,
add the registration route, add the read route, then read the revision back. One
ask per step keeps each write small enough to land.

The last step is not optional: three of the four known agent-mode defects report
success at every step the agent shows you. See
[Troubleshooting](guides.md#troubleshooting) if something looks off.

## Prompt

### Step 1 — create the API

```text
Create an API called "Partner Sandbox API" in my organisation. Don't add any
routes or plugins yet — just create the API and tell me its id.
```

### Step 2 — the registration route

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
```

### Step 3 — the read route

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
it, and do not "correct" it to ${ctx...}. The braces break it.
```

### Step 4 — read the revision back

```text
Read back the current revision of the Partner Sandbox API and show me the plugins
stored on each route, so I can confirm both routes carry key-value-map AND
mocking under their own plugin names.
```
