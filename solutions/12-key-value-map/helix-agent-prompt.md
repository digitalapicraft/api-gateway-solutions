# Agent-mode prompt — per-partner keys in the gateway's store

Paste this to the Helix Agent as one message, replacing the `{{...}}` values. It
works from a fresh, empty org on a public upstream, so you need nothing of your
own until you register a partner's key. Read [solution 13](../13-pgp-encryption/)
first; it is the same encryption with the key in the route. Why the prompt is
worded this way, what the agent decides on its own, and what to check before you
trust it are in the [README](README.md#build-it-with-the-helix-agent).

## Prompt

```text
Step 1:
Create a REST API called "{{api_name}}" in the {{environment}} environment, proxying
https://httpbin.org. Two routes: POST /partners/keys, which the upstream serves at
/post, and GET /partners/documents, which it serves at /json. Keep my paths.

Step 2:
Each partner's documents are encrypted to that partner's own PGP public key, and
the keys are stored at the gateway, never in this configuration. Update the routes
so that:
- POST /partners/keys stores the public_key from the request body under the
  partner id in the X-Partner-Id header, replacing any key stored for that partner
  before.
- GET /partners/documents fetches the key stored for the request's X-Partner-Id
  and returns the backend's document encrypted to it. A partner with no stored key
  gets a 500 and never the document in the clear.
Both routes refer to the partner id as $request.headers.x-partner-id, written
exactly that way everywhere it appears and left for the gateway to resolve on each
request. The encryption settings sit under "encrypt" in the PGP plugin's
configuration, not at its top level.
```
