# Agent-mode prompt — mask sensitive values in the response and in the logs

> [Overview](README.md) · [Business need](business-need.md) · [Architecture](architecture.md) · [Guides](guides.md) · **Agent prompt** · [Tests](tests.md) · [API reference](api-reference.md)

---

Paste the four steps **one at a time**, in order, and let the agent read the
revision back after each one. Keep the masking patterns in step 3 exactly as
written.

If step 4 ends in `stream closed with reason: error`, nothing was written: import
[`example/api-spec.yaml`](example/api-spec.yaml) instead, which carries the same
configuration complete. See [Guides](guides.md#build-it-with-the-helix-agent) for
why, and for what to do if something else looks off.

## Prompt

### Step 1 — the API and the collection route

```text
Create a REST API "Support Console API" with ONE route for now. Upstream
https://jsonplaceholder.typicode.com — reuse it if it already exists as an upstream
in this org rather than creating another; the org's upstream limit is low.
Environment test.

Route: GET /support/customers -> proxy-rewrite uri /users
Put request-id in the SERVICE spec so it applies API-wide. Set only the fields you
need — an empty headers {} or a regex_uri of nulls is rejected at dry-run.

Plugins go in a top-level "plugins" map on the route object, each under its own
plugin name. No "x-helix-gateway" wrapper — a live route discards it silently and
still reports success.

Bind the upstream, run dry_run_deploy, then read the revision back so I can see
which plugins actually landed. Wait before deploying.
```

### Step 2 — the single-record route

```text
Add a second route to the same revision, keeping the first exactly as it is:

  GET /support/customers/{customerId}

It needs proxy-rewrite with regex_uri, not uri, so the id reaches the backend:
regex_uri: ["^/support/customers/(.*)$", "/users/$1"]

Send routeSpec as a JSON array of both route objects — update_route_spec replaces
the whole list. Then read the revision back.
```

### Step 3 — the masking the caller sees

```text
Give BOTH routes this response-rewrite block, verbatim — these are the exact
patterns, do not rewrite them:

filters:
  - regex: ("email"\s*:\s*")[^"@]+@
    replace: $1***@
    scope: global
  - regex: ("phone"\s*:\s*")[^"]*"
    replace: $1[redacted]"
    scope: global
  - regex: ("lat"\s*:\s*")[^"]*"
    replace: $1[redacted]"
    scope: global
  - regex: ("lng"\s*:\s*")[^"]*"
    replace: $1[redacted]"
    scope: global

Every filter keeps scope: global. The default is "once" — one match, then stop —
which on a list masks the first record and leaves the rest in the clear.

Send routeSpec as a JSON array of both routes, then read the revision back.
```

### Step 4 — the masking the logs keep

```text
Add log-data-mask to both routes, keeping everything else exactly as it is:
  response:
    - { type: body, name: email, action: replace, value: "[redacted]", body_format: json }
    - { type: body, name: phone, action: replace, value: "[redacted]", body_format: json }
  request:
    - { type: header, name: authorization, action: remove }
    - { type: header, name: x-api-key, action: remove }

Then read the revision back, and tell me in one sentence what log-data-mask does
NOT do.
```
