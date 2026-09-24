# Agent-mode prompt — per-partner key material, fetched at request time

Two steps, from a **fresh, empty org** to a registration route that stores a
partner's public key and a document route that fetches it per request. No key
material passes through the configuration at any point — which is the property
this package exists to have.

Read [solution 13](../13-pgp-encryption/helix-agent-prompt.md) first; it is the
same crypto with the key in the route. [AGENT-GUIDE.md](../../AGENT-GUIDE.md)
carries the standing rules these prompts assume.

---

## Step 1 — the registration route

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

## Step 2 — the document route

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

> If a step ends in `stream closed with reason: error`, nothing was written — a
> tool-argument defect in the agent, not your prompt. Retry once, then import
> [`gateway/api-spec.yaml`](gateway/api-spec.yaml) for the remaining step.

---

## Why it's shaped this way

- **Literal JSON, not prose.** Verified: given prose, the agent flattens nested
  plugin blocks and invents field names. Given the JSON, it reproduces it exactly.
- **The `$` references stay verbatim.** An agent that treats them as placeholders
  substitutes a value, and the route then serves one partner forever.
- **`headers`, plural.** The singular resolves to nothing, and the symptom is
  indistinguishable from "no key registered".
- **`encrypt` is a wrapper.** Verified: asked in prose, the agent wrote
  `pgp-crypto: { target, source, public_key }` flat, which the schema rejects.
- **Two steps.** A route write much past a kilobyte has a real chance of ending in
  the tool-argument serialisation defect. Smaller writes survive it more often.
- **Read the revision back.** Nested plugins on a live route are silently
  discarded: the write reports success and the dry-run passes.

## Tweak knobs

**Protect the registration route** *(do this before anything else)*
```text
Add API-key authentication to the /partners/keys route only, with helix-auth
validate, validate_auth_type key-auth, reading the key from X-Admin-Key. Leave the
document route as it is for now, and tell me what is still open after that change.
```
(That's [solution 08](../08-api-key/).)

**Key on the authenticated caller instead of a header**
```text
The partner id currently comes from a header the caller controls. Put helix-auth
validate on the document route and change both references from
$request.headers.x-partner-id to $consumer.public_key, so the entry is keyed on the
authenticated consumer. Explain what that changes about who can request what.
```

**Store something other than a key**
```text
I also want a per-partner upstream path stored alongside the key. Show me how to
fetch two entries on one route and how a second plugin would read the other one.
```

**Go back to the simple shape**
```text
I only have one counterparty after all. Show me what this looks like with the key
in the route instead, and be explicit about what I lose and what I stop having to
protect.
```
(That's [solution 13](../13-pgp-encryption/).)

## When it goes wrong

| Symptom | Cause |
|---|---|
| `stream closed with reason: error` after a route write | The agent's arguments arrived with a stray bracket appended; nothing was written. Retry once, then import the spec for the rest. |
| Every partner gets the fail-close error | The reference resolves to nothing. Check `headers` plural, and that the client sends the id header. |
| One partner works and the rest fail | A fixed string was written where a reference belongs. |
| The agent substitutes a value for `$request.headers.x-partner-id` | Reply: leave the `$` references as written — the plugin resolves them at request time, not you. |
| The agent writes `pgp-crypto` flat | Reply: the crypto config is nested under `encrypt` — show me the route object as JSON before sending. |
| The write succeeds and the routes have no plugins | Nested under `x-helix-gateway`. Read the revision back and rewrite with a top-level `plugins` key. |
| The document comes back readable | `fail_policy` is `fail-open` on the consuming plugin, which returns the backend's document in the clear. |
| Deploy fails: `Only INACTIVE revisions can be updated` | Clone the revision or undeploy, then apply. |

## Related

- **[Solution 13 — PGP encryption](../13-pgp-encryption/helix-agent-prompt.md)** —
  read first; same crypto, key in the route.
- **[Solution 11 — Service callout](../11-service-callout/helix-agent-prompt.md)** —
  when the per-request value comes from a service rather than a store.
- **[Solution 08 — API keys](../08-api-key/helix-agent-prompt.md)** — what belongs
  in front of the registration route.
