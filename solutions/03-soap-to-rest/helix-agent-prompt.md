# Agent-mode prompt — serve a SOAP backend as REST/JSON

Paste this to the Helix Agent as one message, replacing the `<<...>>` values.
Bring your own SOAP endpoint, the handler path it answers on, and the REST
route you want partners to call.

This builds the mediation, which is what this solution is. **Authentication is
[solution 02](../02-oauth-jwt/)** — add it afterwards with that package's prompt
if you want it, or import [`example/api-spec.yaml`](example/api-spec.yaml), which
ships both layers already composed. Why the prompt is worded this way, what the
agent decides on its own, and what to check before you trust it are in the
[README](README.md#build-it-with-the-helix-agent).

## Prompt

```text
Create a REST API called "<<03-soap-to-rest>>" in the <<test>> environment,
fronting a SOAP backend at <<SOAP_UPSTREAM_URL>>. One route — POST <</locations>>
— proxying to the upstream path <<SOAP_HANDLER_PATH>>. Partners send and receive
JSON; the backend keeps speaking XML, and neither side changes to make that work.
```
