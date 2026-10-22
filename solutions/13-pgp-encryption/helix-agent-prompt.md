# Agent-mode prompt — OpenPGP at the edge

> [Overview](README.md) · [Business need](business-need.md) · [Architecture](architecture.md) · [Guides](guides.md) · **Agent prompt** · [Tests](tests.md) · [API reference](api-reference.md)

---

Paste each step to the Helix Agent as its own message, in order, starting from a
fresh, empty org. **Don't paste key material into the agent:** the prompts ask for
the literal placeholders `<PGP_PRIVATE_KEY>` and `<PGP_PUBLIC_KEY>`, and you put
the real armored blocks in yourself.

Expect to retry a step. Any route write has a real chance of ending in
`stream closed with reason: error`, a tool-argument defect in the agent rather than
anything about your prompt; nothing is written when it happens. Retry once, then
import [`example/api-spec.yaml`](example/api-spec.yaml). See
[Troubleshooting](guides.md#troubleshooting) if something looks off.

## Prompt

### Step 1 — the API and the inbound (decrypt) route

```text
Create a REST API "Statements API" with ONE route for now. Upstream
https://httpbin.org — reuse it if it already exists as an upstream in this org.
Its /post echoes what it received, which is the only way to be sure the request
direction worked. Environment test.

Route: POST /statements/inbound -> proxy-rewrite uri /post, with pgp-crypto. Its
crypto configuration is NESTED under a "decrypt" key, not flat. The route object
must look exactly like this:

{
  "name": "statements-inbound",
  "uri": "/statements/inbound",
  "methods": ["POST"],
  "service_id": "<the api id>",
  "plugins": {
    "proxy-rewrite": { "uri": "/post" },
    "pgp-crypto": {
      "decrypt": {
        "target": "request",
        "source": "body",
        "private_key": "<PGP_PRIVATE_KEY>",
        "fail_policy": "fail-close",
        "fail_close_status": 400,
        "fail_close_message": "request body is not a PGP message this gateway can decrypt"
      }
    }
  }
}

Leave <PGP_PRIVATE_KEY> as that literal placeholder — I'll supply the real armored
key myself. Don't generate a key and don't ask me to paste one here.

Put request-id in the SERVICE spec so it applies API-wide. No "x-helix-gateway"
key anywhere in a route object — a live route discards it silently and deploys
with no crypto at all.

Bind the upstream, run dry_run_deploy, then read the revision back. Wait before
deploying.
```

### Step 2 — the outbound (encrypt) route

```text
Add a second route, keeping the first exactly as it is:

  GET /statements/{statementId} -> proxy-rewrite uri /json

with pgp-crypto nested under an "encrypt" key:

  "pgp-crypto": {
    "encrypt": {
      "target": "response",
      "source": "body",
      "public_key": "<PGP_PUBLIC_KEY>",
      "fail_policy": "fail-close",
      "fail_close_status": 500
    }
  }

Do NOT set "field" on the encrypt block — it makes the response only that field's
ciphertext and discards the rest of the document.

Send routeSpec as a JSON array of both route objects, then read the revision back
and run dry_run_deploy.
```

### Step 3 — the integration note for the counterparty

```text
Now write me the integration note to send the partner. It must say that both
directions use BASE64 of the ASCII-armored message, not the armor itself — a raw
armored body is rejected — and include a worked example of encrypting a file and
base64-encoding it before the POST.
```
