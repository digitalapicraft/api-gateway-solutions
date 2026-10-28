# Agent-mode prompt — per-partner key material, fetched at request time

> [Overview](README.md) · [Business need](business-need.md) · [Architecture](architecture.md) · [Guides](guides.md) · **Agent prompt** · [Tests](tests.md) · [API reference](api-reference.md)

---

Paste each step to the Helix Agent as its own message, in order, starting from a
fresh, empty org. Leave every `$` reference exactly as written: the gateway fills
them in at request time, not you.

If a step ends in `stream closed with reason: error`, nothing was written — a
tool-argument defect in the agent, not your prompt. Retry once, then import
[`example/api-spec.yaml`](example/api-spec.yaml) for the remaining step. See
[Troubleshooting](guides.md#troubleshooting) if something looks off.

## Prompt

### Step 1 — the registration route

```text
Create a REST API "Partner Documents API" with ONE route for now. Upstream
https://httpbin.org — reuse it if it already exists as an upstream in this org;
the org's upstream limit is low. Environment test.

Route: POST /partners/keys -> proxy-rewrite uri /post, with key-value-map. The
route object must look exactly like this:

{
  "name": "partners-keys",
  "uri": "/partners/keys",
  "methods": ["POST"],
  "service_id": "<the api id>",
  "plugins": {
    "proxy-rewrite": { "uri": "/post" },
    "key-value-map": {
      "fail_action": "close",
      "inserts": [
        { "key": "$request.headers.x-partner-id", "value": "$request.body.public_key" }
      ]
    }
  }
}

Those $ references are key-value-map templates, not shell variables — leave them
exactly as written, don't substitute values. It is "headers" plural; the singular
resolves to nothing, silently.

Put request-id in the SERVICE spec so it applies API-wide. No "x-helix-gateway"
key anywhere in a route object — a live route discards it silently and deploys
with no plugins.

Bind the upstream, run dry_run_deploy, then read the revision back. Wait before
deploying.
```

### Step 2 — the document route

```text
Add a second route, keeping the first exactly as it is:

  GET /partners/documents -> proxy-rewrite uri /json

with two plugins. key-value-map FETCHES the same reference the other route writes,
and pgp-crypto resolves that same reference against what it fetched — they agree
only because the template is identical, so don't paraphrase either one:

  "key-value-map": {
    "fail_action": "close",
    "fetch": { "keys": [ { "key": "$request.headers.x-partner-id" } ] }
  },
  "pgp-crypto": {
    "keys_ctx_namespace": "key_value_map",
    "encrypt": {
      "target": "response",
      "source": "body",
      "public_key": "$request.headers.x-partner-id",
      "fail_policy": "fail-close",
      "fail_close_status": 500,
      "fail_close_message": "no usable key is registered for this partner"
    }
  }

The crypto config is NESTED under "encrypt", not flat. Send routeSpec as a JSON
array of both routes, then read the revision back and run dry_run_deploy.
```
