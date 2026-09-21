# Agent-mode prompt — per-partner key material, fetched at request time

Paste these into **Helix Agent Mode**. They work from a **fresh, empty org**: the
agent *creates* the API, the registration route and the document route, and stops
at the dry-run. No key material is involved at any point — which is the property
this package exists to have.

Replace the `<<...>>` values. Everything else is deliberate — the table below
says why each block earns its place. Read [AGENT-GUIDE.md](../../AGENT-GUIDE.md)
first if you haven't, and [solution 13](../13-pgp-encryption/helix-agent-prompt.md)
before this one.

---

## The prompt

**Step 1 — the registration route**

```text
Create a new REST API called "Partner Documents API" with ONE route for now.

Upstream: https://httpbin.org (reuse it if it already exists in this org as an
upstream). Deploy to the "test" environment.

Route: POST /partners/keys -> proxy-rewrite uri /post

On that route add key-value-map. The route object must look exactly like this:

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
exactly as written. It is "headers" plural; the singular resolves to nothing.

Put request-id in the SERVICE spec so it applies API-wide.

There must be no "x-helix-gateway" key anywhere in a route object: a live route
silently discards that wrapper and deploys with no plugins. Skip validate_route —
use dry_run_deploy. Bind the upstream, run dry_run_deploy, then call get_revision
and show me the stored routeSpec. Wait before deploying.
```

**Step 2 — the document route**

```text
Add a second route, keeping the first exactly as it is:

  GET /partners/documents -> proxy-rewrite uri /json

with two plugins. key-value-map FETCHES the same reference the other route writes,
and pgp-crypto resolves that same reference against what it fetched:

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

The crypto config is NESTED under "encrypt" — it is not flat. Send the routeSpec as
a JSON array of both routes, then call get_revision, show me the stored routeSpec,
and run dry_run_deploy.
```

> If a step ends in `stream closed with reason: error`, nothing was written — that
> is a tool-argument defect in the agent, not your prompt. Retry once, then import
> [`gateway/api-spec.yaml`](gateway/api-spec.yaml) for the remaining step.


---

## Why the prompt is shaped this way

| Block | Why it's there |
|---|---|
| **Two steps, not one** | Verified across this set: a route write much past a kilobyte has a real chance of ending in a tool-argument serialisation defect. Smaller writes survive it more often. |
| **"This is a fresh org — create one"** | On a new free-trial org there is no API to "find". The agent must create it, or it stalls. |
| **"reuse it if it already exists"** | The org's upstream limit is low, and an agent that cannot create one stops rather than looking for the one already there. |
| **The literal JSON route object** | Verified: given prose, the agent flattens nested plugin blocks and invents field names. Given the JSON, it reproduces it exactly. |
| **"Those $ references are key-value-map templates, not shell variables"** | An agent that treats them as placeholders substitutes a value, and the route then serves one partner forever. |
| **"It is `headers` plural"** | The singular resolves to nothing, silently, and the symptom is indistinguishable from "no key registered". |
| **"the same reference the other route writes"** | The fetch and the crypto plugin agree only because the template is identical. Said once, an agent will paraphrase one of them. |
| **"The crypto config is NESTED under `encrypt`"** | Verified: asked in prose, the agent wrote `pgp-crypto: { target, source, public_key }` — flat, with no wrapper, which the schema rejects. |
| **"no `x-helix-gateway` key anywhere in a route object"** | Verified across this set: nested plugins on a live route are **silently discarded** — the write reports success, the dry-run passes, and the route deploys with nothing on it. |
| **"call get_revision and show me the stored routeSpec"** | The only check in the toolchain that catches that silent drop. |
| **"Skip validate_route — use dry_run_deploy"** | Verified: `validate_route` fails on this build whatever you put in it — the tool posts `{"route": …}` and the control plane requires `{"routeSpec": [ … ]}`. |

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

## Known failure modes when running this prompt

- **`stream closed with reason: error` after a route write.** A serialisation
  defect in the agent: the arguments arrive as a string with a stray bracket
  appended and nothing is written. Retry once; then import
  `gateway/api-spec.yaml` for the remaining step.
- **Every partner gets the fail-close error.** The reference resolves to nothing.
  Check `headers` plural, and that the client actually sends the id header.
- **One partner works and the rest fail.** A fixed string was written where a
  reference belongs.
- **The agent substitutes a value for `$request.headers.x-partner-id`.** Reply:
  `leave the $ references exactly as written — they are resolved by the plugin at
  request time, not by you.`
- **The agent writes `pgp-crypto` flat, with no `encrypt` wrapper.** Reply: `the
  crypto config is nested under encrypt — show me the route object as JSON before
  you send it.`
- **The write succeeds and the routes have no plugins.** The agent nested them
  under `x-helix-gateway`. Read the revision back and rewrite with a top-level
  `plugins` key.
- **The document comes back readable.** `fail_policy` is `fail-open` on the
  consuming plugin. That returns the backend's document in the clear.
- **`validate_route` errors and the agent stalls.** Not your config — the tool is
  broken against this control plane. Reply: `skip validate_route, run
  dry_run_deploy instead.`
- **Deploy fails with `Only INACTIVE revisions can be updated`.** Clone the
  revision or undeploy, then apply.

## Related

- **[Solution 13 — PGP encryption](../13-pgp-encryption/helix-agent-prompt.md)** —
  read first; same crypto, key in the route.
- **[Solution 11 — Service callout](../11-service-callout/helix-agent-prompt.md)** —
  when the per-request value comes from a service rather than a store.
- **[Solution 08 — API keys](../08-api-key/helix-agent-prompt.md)** — what belongs
  in front of the registration route.
