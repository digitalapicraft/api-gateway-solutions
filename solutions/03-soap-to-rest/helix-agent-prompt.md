# Agent-mode prompt — serve a SOAP backend as REST/JSON

Paste this to the Helix Agent as one message, replacing the `<<...>>` values.
Bring your own SOAP endpoint and the handler path it answers on.

This builds the mediation, which is what this solution is. **Authentication is
[solution 02](../02-oauth-jwt/)** — add it afterwards with that package's prompt
if you want it, or import [`gateway/api-spec.yaml`](gateway/api-spec.yaml), which
ships both layers already composed. Why the prompt is worded this way, what the
agent decides on its own, and what to check before you trust it are in the
[README](README.md#build-it-with-the-helix-agent).

## Prompt

```text
Create a REST API called "<<03-soap-to-rest>>" in the <<test>> environment,
fronting a SOAP backend at <<SOAP_UPSTREAM_URL>>. One route — POST /locations —
proxying to the upstream path <<SOAP_HANDLER_PATH>>. Partners send and receive
JSON; the backend keeps speaking XML, and neither side changes to make that work.

Do not set Content-Type when you rewrite the path. It is applied before the body
is converted, so the conversion never sees a JSON body, the backend is handed
JSON it cannot parse, and the call still returns 200 with a JSON-looking error.

Tell me anything in the JSON shape I wouldn't have designed by hand, and ask me
rather than guessing the handler path or the request field names.
```
