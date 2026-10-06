# Agent-mode prompt — serve a SOAP backend as REST/JSON

Paste this to the Helix Agent as one message, replacing the `{{...}}` values.
Bring your own SOAP endpoint, the handler path it answers on, and the REST
route you want partners to call.

This builds the mediation, which is what this solution is — the same thing
[`example/api-spec.yaml`](example/api-spec.yaml) carries, so the prompt and the
spec describe one API. **It is unauthenticated.** Identity is
[solution 02](../02-oauth-jwt/); add it with that package's prompt before
partners call this. Why the prompt is worded this way, what the
agent decides on its own, and what to check before you trust it are in the
[README](README.md#build-it-with-the-helix-agent).

## Prompt

```text
Create a REST API called "{{api_name}}" in the {{environment}} environment,
fronting a SOAP backend at {{soap_upstream_url}}. One route — POST {{rest_route_path}}
— proxying to the upstream path {{soap_handler_path}}. Partners send and receive
JSON; the backend keeps speaking XML, and neither side changes to make that work.
```
