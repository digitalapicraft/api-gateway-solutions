# Install — Solution 13 — PGP at the edge, so the keyring script can go

[Overview](readme.md) · [Business need](business-need.md) · [How it works](how-it-works.md) · **Install** · [Configuration](configuration.md) · [Test & verify](testing.md) · [Changelog](changelog.md)

---

## Build it with the Helix Agent

Three steps, and expect to retry one. Full prompt with the reasoning, tweak knobs
and failure modes: [`helix-agent-prompt.md`](helix-agent-prompt.md).

> **Don't paste key material into the agent** — the prompts ask for placeholders,
> and you put the real armored blocks in yourself. And any route write has a real
> chance of ending in `stream closed with reason: error`, a tool-argument defect in
> the agent rather than anything about your prompt; nothing is written when it
> happens. Retry once, then import [`gateway/api-spec.yaml`](gateway/api-spec.yaml).

**Step 1 — the API and the inbound (decrypt) route**

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

**Step 2 — the outbound (encrypt) route**

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

**Step 3 — the integration note for the counterparty**

```text
Now write me the integration note to send the partner. It must say that both
directions use BASE64 of the ASCII-armored message, not the armor itself — a raw
armored body is rejected — and include a worked example of encrypting a file and
base64-encoding it before the POST.
```

## Install it directly

```bash
export ORG=<ORG_ID>
export TOKEN=<control-plane bearer token>      # short-lived
export BASE=https://<YOUR_GATEWAY_HOST>/api

# 1. Replace <PGP_PRIVATE_KEY> and <PGP_PUBLIC_KEY> with real armored blocks.
#    Do NOT commit the filled-in file.
# 2. Import gateway/api-spec.yaml, bind your backend, deploy the revision to "test".
# 3. Prove it — cases 1-4 need only bash, curl and base64:
GATEWAY=https://<YOUR_GATEWAY_HOST> ./gateway/verify.sh
#    Add the round trip when you have keys to hand:
GATEWAY=https://<YOUR_GATEWAY_HOST> \
GNUPGHOME=/path/to/keyring RECIPIENT=partner@example.com ./gateway/verify.sh
```

## Step 1 — the API and the inbound (decrypt) route

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

## Step 2 — the outbound (encrypt) route

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

## Step 3 — the integration note for the counterparty

```text
Now write me the integration note to send the partner. It must say that both
directions use BASE64 of the ASCII-armored message, not the armor itself — a raw
armored body is rejected — and include a worked example of encrypting a file and
base64-encoding it before the POST.
```

---

## Why it's shaped this way

- **Literal JSON, with the wrapper shown.** Verified: asked in prose, the agent
  wrote `pgp-crypto: { target, source, public_key }` — flat, no wrapper, which the
  schema rejects. Shown the nested shape, it reproduced it exactly.
- **The placeholders stay placeholders.** Without that instruction the agent either
  generates a key pair — putting a private key in a transcript — or asks you to
  paste yours.
- **No `field` on encrypt.** Verified: it makes the response *only* that field's
  ciphertext and discards the document. An agent reading the schema offers it as a
  refinement.
- **400 inbound, 500 outbound.** Meaningfully different to a caller. Left alone the
  agent picks one default for both.
- **Two route writes, not one.** The one-prompt version failed twice out of two on
  the serialisation defect. Smaller writes survive it more often.
- **Step 3 at all.** The wire format is what breaks the integration, and the
  counterparty is the one who has to change. Write the note while it's fresh.
- **Read the revision back.** Nested plugins on a live route are silently
  discarded: the write reports success and the dry-run passes.

## Tweak knobs

**I have more than one counterparty**
```text
I have <<fourteen>> partners, each with their own key. Tell me plainly what this
route shape costs at that number, then show me the key-value-map version where the
key is fetched per request from a partner id in the request.
```
(That's [solution 12](../12-key-value-map/).)

**Write the counterparty's side for me**
```text
My counterparty <<also runs this gateway / runs a cron job with gpg on it>>. Write
the configuration THEY need, mirroring mine: they decrypt what I send with their
own private key, and encrypt to my public key when they send to me. Be explicit
about which of the four key halves each party holds, and don't assume my two
placeholders are a pair — they are not.
```

**My partner insists on sending raw armor**
```text
My counterparty cannot base64 the armored message. Tell me honestly whether the
plugin can accept bare armor, and if it cannot, what my options are — don't invent
a setting.
```

**Encrypt only part of the document**
```text
I only need one field of the statement encrypted, not the whole document. Tell me
exactly what `field` does to the response before you configure it.
```

**Put identity in front of it**
```text
Add API-key authentication to both routes with helix-auth validate,
validate_auth_type key-auth, reading the key from X-Api-Key. Keep the crypto
exactly as it is — encrypting to a partner's key is not the same as checking who
called.
```
(That's [solution 08](../08-api-key/).)

## When it goes wrong

| Symptom | Cause |
|---|---|
| `stream closed with reason: error` after a route write | The agent's arguments arrived with a stray bracket appended; nothing was written. Retry once, then import the spec for the rest. |
| The agent writes `pgp-crypto` flat, with no `encrypt`/`decrypt` wrapper | Reply: it's nested — show me the route object as JSON before sending. |
| The agent offers to generate a key pair | Decline. Use the placeholder; supply the real key in the control plane. |
| The agent sets `field` on the encrypt block | Reply: remove it — it returns only that field's ciphertext and throws the document away. |
| The write succeeds and the routes have no plugins | Nested under `x-helix-gateway`. Read the revision back and rewrite with a top-level `plugins` key. |
| Every inbound request is rejected, and the partner insists the file is valid | They're sending raw armor. The body must be base64 *of* the armor. |
| 500 on the statement route | The public key is unparseable. The caller-facing message is generic by design. |
| 200 with an error message in the body | A key that is present but unusable — an OpenPGP key with no encryption subkey, which is what `gpg --quick-generate-key` produces. Assert on the body, not the status. |
| Deploy fails: `Only INACTIVE revisions can be updated` | Clone the revision or undeploy, then apply. |

## Related

- **[Solution 12 — Key-value map](../12-key-value-map/helix-agent-prompt.md)** —
  the same crypto with per-partner keys fetched at request time.
- **[Solution 06 — Signed requests](../06-hmac-auth/helix-agent-prompt.md)** —
  authenticity rather than confidentiality.
- **[Solution 08 — API keys](../08-api-key/helix-agent-prompt.md)** — this package
  ships open on purpose.
