# Agent-mode prompt — serve a SOAP backend as REST/JSON

> [Overview](README.md) · [Business need](business-need.md) · [Architecture](architecture.md) · [Guides](guides.md) · **Agent prompt** · [Tests](tests.md) · [API reference](api-reference.md)

---

Paste this to the Helix Agent as one message, replacing the `{{...}}` values. Bring
your own SOAP endpoint, the handler path it answers on, and the REST route you want
partners to call.

It builds the translation only — the same API as
[`example/api-spec.yaml`](example/api-spec.yaml) — and **it is unauthenticated**:
add [solution 02](../02-oauth-jwt/) before partners call it. What to check before
you trust the result is in
[Build it with the Helix Agent](guides.md#build-it-with-the-helix-agent).

## Prompt

```text
Create a REST API called "{{api_name}}" in the {{environment}} environment,
fronting a SOAP backend at {{soap_upstream_url}}. One route — POST {{rest_route_path}}
— proxying to the upstream path {{soap_handler_path}}. Partners send and receive
JSON; the backend keeps speaking XML, and neither side changes to make that work.
```
