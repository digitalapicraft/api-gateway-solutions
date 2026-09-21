# Agent-mode prompt — OpenPGP at the edge

Paste these into **Helix Agent Mode**. They work from a **fresh, empty org**: the
agent *creates* the API and configures both crypto directions with placeholders
where your key material goes.

Replace the `<<...>>` values. Everything else is deliberate — the table below
says why each block earns its place. Read [AGENT-GUIDE.md](../../AGENT-GUIDE.md)
first if you haven't.

> **Do not paste key material into the agent.** The prompts deliberately ask for
> the placeholders `<PGP_PRIVATE_KEY>` and `<PGP_PUBLIC_KEY>`. Put the real armored
> blocks in yourself, in the control plane, and keep the filled-in spec out of
> version control.

---

## The prompt
> **Two steps, and expect to retry one of them.** Verified against the hosted
> agent: it produces exactly the right configuration when the nested `decrypt` /
> `encrypt` block is shown literally — and any given attempt has a real chance of
> ending in `stream closed with reason: error`, which is a tool-argument
> serialisation defect in the agent rather than anything about your prompt. Nothing
> is written when it happens. Retry; if the second attempt fails the same way,
> import [`gateway/api-spec.yaml`](gateway/api-spec.yaml) instead.

**Step 1 — the API and the inbound (decrypt) route**

```text
Create a new REST API called "Statements API" with ONE route for now.

Upstream: https://httpbin.org (reuse it if it already exists in this org as an
upstream). Deploy to the "test" environment.

Route: POST /statements/inbound -> proxy-rewrite uri /post

On that route add pgp-crypto. Its crypto configuration is NESTED under a "decrypt"
key — it is not flat. The route object must look exactly like this:

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

Leave <PGP_PRIVATE_KEY> as that literal placeholder — I will supply the real armored
key myself. Do not generate a key and do not ask me to paste one here.

Put request-id in the SERVICE spec so it applies API-wide.

There must be no "x-helix-gateway" key anywhere in a route object: a live route
silently discards that wrapper and deploys with no plugins. Skip validate_route —
use dry_run_deploy. Bind the upstream, run dry_run_deploy, then call get_revision
and show me the stored routeSpec. Wait before deploying.
```

**Step 2 — the outbound (encrypt) route**

```text
Add a second route, keeping the first exactly as it is:

  GET /statements/{statementId} -> proxy-rewrite uri /json

with pgp-crypto whose crypto configuration is NESTED under an "encrypt" key:

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

Send the routeSpec as a JSON array of both route objects. Then call get_revision,
show me the stored routeSpec, and run dry_run_deploy.
```

**Step 3 — the integration note for the counterparty**

```text
Now write me the integration note I should send the partner. It must say that both
directions use BASE64 of the ASCII-armored message, not the armor itself — a raw
armored body is rejected — and it must include a worked example of encrypting a
file and base64-encoding it before the POST.
```


---

## Why the prompt is shaped this way

| Block | Why it's there |
|---|---|
| **Two steps, not one** | Verified: the one-prompt version failed twice out of two on a tool-argument serialisation defect. Smaller writes are more likely to survive it. |
| **"This is a fresh org — create one"** | On a new free-trial org there is no API to "find". The agent must create it, or it stalls. |
| **"httpbin … /post echoes what it received"** | The only way to be sure the request direction worked is to see the plaintext arrive. |
| **The literal JSON route object, with `decrypt` nested** | Verified: asked in prose, the agent wrote `pgp-crypto: { target, source, public_key }` — flat, with no `encrypt` wrapper, which the schema rejects. Shown the nested shape, it reproduced it exactly. |
| **"Leave `<PGP_PRIVATE_KEY>` as that literal placeholder"** | Without it the agent either generates a key pair — putting a private key in a transcript — or asks you to paste yours. |
| **"Do NOT set `field`"** | Verified: on an encrypt block, `field` makes the response *only* that field's ciphertext and discards the document. An agent reading the schema offers it as a refinement. |
| **`fail_close_status` 400 inbound and 500 outbound** | Meaningfully different to a caller. Left alone the agent picks one default for both. |
| **"no `x-helix-gateway` key anywhere in a route object"** | Verified across this set: nested plugins on a live route are **silently discarded** — the write reports success, the dry-run passes, and the route deploys with no crypto at all. |
| **"call get_revision and show me the stored routeSpec"** | The only check in the toolchain that catches that silent drop. |
| **"Skip validate_route — use dry_run_deploy"** | Verified: `validate_route` fails on this build whatever you put in it — the tool posts `{"route": …}` and the control plane requires `{"routeSpec": [ … ]}`. |
| **Step 3 at all** | The wire format is what breaks the integration, and the counterparty is the one who has to change. Write the note while the context is fresh. |

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
My counterparty <<also runs this gateway / runs a cron job with gpg on it>>.
Write the configuration THEY need, mirroring mine: they decrypt what I send with
their own private key, and encrypt to my public key when they send to me. Be
explicit about which of the four key halves each party holds, and do not assume my
two placeholders are a pair — they are not.
```

**My partner insists on sending raw armor**
```text
My counterparty cannot base64 the armored message. Tell me honestly whether the
plugin can accept bare armor, and if it cannot, what my options are — do not invent
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

## Known failure modes when running this prompt

- **`stream closed with reason: error` after a route write.** A serialisation
  defect in the agent: the arguments arrive as a string with a stray bracket
  appended, nothing is written, and it is unrelated to your prompt. Retry once. If
  it repeats, import `gateway/api-spec.yaml` for the remaining step.
- **The agent writes `pgp-crypto: { target, source, … }` with no `encrypt` or
  `decrypt` wrapper.** Reply: `the crypto config is nested under an encrypt or
  decrypt key — show me the route object as JSON before you send it.`
- **The agent offers to generate a key pair.** Decline. Reply: `use the placeholder
  <PGP_PRIVATE_KEY>; I will supply the real key in the control plane.`
- **The agent sets `field` on the encrypt block.** Reply: `remove field — it makes
  the response only that field's ciphertext and throws the document away.`
- **The write succeeds and the routes have no plugins.** The agent nested them
  under `x-helix-gateway`. Read the revision back and rewrite with a top-level
  `plugins` key.
- **Every inbound request is rejected and the partner insists the file is valid.**
  They are sending raw armor. The body must be base64 *of* the armor.
- **500 on the statement route.** The public key is unparseable. The caller-facing
  message is generic by design.
- **`validate_route` errors and the agent stalls.** Not your config — the tool is
  broken against this control plane. Reply: `skip validate_route, run
  dry_run_deploy instead.`
- **Deploy fails with `Only INACTIVE revisions can be updated`.** Clone the
  revision or undeploy, then apply.

## Related

- **[Solution 12 — Key-value map](../12-key-value-map/helix-agent-prompt.md)** —
  the same crypto with per-partner keys fetched at request time.
- **[Solution 06 — Signed requests](../06-hmac-auth/helix-agent-prompt.md)** —
  authenticity rather than confidentiality.
- **[Solution 08 — API keys](../08-api-key/helix-agent-prompt.md)** — this package
  ships open on purpose.
