# Agent-mode prompt — API-key identity for constrained callers

Paste this into **Helix Agent Mode**. It works from a **fresh, empty org**: the
agent *creates* the API, binds a public upstream so you get real data
immediately, protects both routes with API-key identity, dry-runs, and then
creates the product and app whose credential you test with.

Replace the `<<...>>` values. Everything else is deliberate — the table below
says why each block earns its place. Read [AGENT-GUIDE.md](../../AGENT-GUIDE.md)
first if you haven't.

---

## The prompt

> **Run it in steps, not as one mega-prompt.** These are the exact prompts
> verified on the **default agent model**. Paste **Step 1**, let the agent create
> the API and stop at the dry-run; confirm; then paste **Step 2**. Folding the
> whole build into a single prompt pushes a smaller model to attempt one oversized
> change and stall — one bounded ask per step is what keeps it reliable.

**Step 1 — create and protect the API**

```text
Create a new REST API called "<<Terminal API>>" and protect every route with
API-key authentication. This is a fresh org — I have no existing API.

Upstream: https://jsonplaceholder.typicode.com (public, so it returns real data;
I'll swap in my own later). Deploy to the "test" environment.

Routes: GET /fleet/price-list and POST /fleet/takings. The upstream paths differ
from mine, so add proxy-rewrite: /fleet/price-list -> /todos/1 and
/fleet/takings -> /posts.

Use helix-auth with mode validate and validate_auth_type key-auth on both routes,
reading the key from the HEADER X-Device-Key. key-auth is a validate_auth_type of
helix-auth, not a standalone plugin. apikey with source is required for key-auth —
a dry-run rejects the config without it.

No secret goes in the spec: the key lives on the app credential, and the route
only names the header it arrives in. Do not set secret_validation.

Put request-id in the SERVICE spec so it applies API-wide, not on each route. Do not
add cors — these callers are devices, not browsers.

Check get_plugin_config for helix-auth before writing config.

We are editing a LIVE route object, not authoring an OpenAPI document — so do not
follow the spec-generator examples for plugin placement. Each route object in
routeSpec takes "plugins" as a TOP-LEVEL key, and inside it each plugin is
keyed by its own NAME:
  { "name": ..., "uri": ..., "methods": [...], "service_id": ...,
    "plugins": { "<plugin-name>": { <that plugin's own fields> } } }
Do not promote a plugin's fields into the plugins map: "plugins":
{"response_status": 202, "content_type": ...} is four broken plugins, not one
working one — the plugin name level is mandatory.
There must be no "x-helix-gateway" key anywhere in a route object: a live route
silently discards that wrapper, the write still reports success, and the route
deploys with no plugins at all.

Skip validate_route — use dry_run_deploy for validation. Show me the spec, run
dry_run_deploy, then call get_revision and show me the stored routeSpec so I can see
the plugins landed. Wait before deploying.
```

**Step 2 — issue a credential and test it** (same session, after Step 1 deploys)

```text
Create a product that contains this API with a generous quota, deploy the product
to the test environment, then create a developer "<<Forecourt Estate>>" with one
app subscribed to it and give me the app's API key so I can test.

Then give me curl commands that show, in order: no key -> 401; the key in
X-Device-Key -> 200; an unknown key -> 401; the right key in an "apikey" header
-> 401; and the right key as a query parameter -> 401. The last two prove the
header name and the header SOURCE are both part of the contract.
```

The agent creates the API, fetches the real `helix-auth` schema from your org,
proposes the spec, and stops for your confirmation.

---

## Why the prompt is shaped this way

| Block | Why it's there |
|---|---|
| **"This is a fresh org — create one"** | On a new free-trial org there is no API to "find". The agent must create it, or it stalls looking for something that isn't there. |
| **"Upstream: jsonplaceholder … real data with no backend of my own"** | You get a working end-to-end result immediately — real responses behind the credential check. Swap it for your own later. |
| **"Environment: test"** | Free-trial orgs get a `test` environment by default; that's where things deploy. |
| **"add proxy-rewrite … /todos/1 … /posts"** | The published route paths are the contract with the fleet; the upstream's paths are not. Saying this explicitly stops the agent renaming your routes to match the backend. |
| **"key-auth is a validate_auth_type of helix-auth, not a standalone plugin"** | The most likely wrong turn. A general model reaches for a `key-auth` plugin by name — it does not exist on this build. |
| **"apikey with source is required … a dry-run rejects the config without it"** | Verified: the published JSON schema marks `apikey` optional and the plugin's own check does not. Without this line the agent produces a config that fails at dry-run with a message about a property it believed was optional. |
| **"No secret goes in the spec"** | True here and worth stating, because it is *not* true of `helix-auth` in generate mode (solution 01), where the signing secret is a literal. An agent generalising from that solution will try to put a key in this one. |
| **"Do not set secret_validation"** | Its name reads like a second factor. It accepts the credential's secret as an *alternative* credential — turning it on widens what authenticates. |
| **"Do not add cors"** | Devices are not browsers. An agent pattern-matching on the other auth solutions will add a wildcard CORS policy this API has no use for. |
| **"the right key in an 'apikey' header -> 401"** | Proves the header name is genuinely enforced rather than one of several accepted. |
| **"Skip validate_route — use dry_run_deploy"** | Verified against the hosted agent, twice: `validate_route` **always fails** on this build. The tool posts `{"route": {…}}` and the control plane requires `{"routeSpec": [ … ]}`, so it returns 400 whatever you put in it. Asked for it, the agent retries, then emits a malformed tool call and the run dies. Asked for `dry_run_deploy` instead, the same prompt completes cleanly. |
| **"a FLAT plugins map"** | The agent's own spec-generator references teach `x-helix-gateway.plugins`, which is right for an OpenAPI *document* and wrong for a live route or service object — those take a flat `plugins` map. Without this line the agent carries the nesting across. |
| **"request-id in the SERVICE spec"** | API-wide plugins live on the service spec. Without this the agent copies `request-id` onto every route, which works but drifts from the package and has to be edited in N places later. |
| **"the right key as a query parameter -> 401"** | Proves `source: header` means header only. A key in a URL lands in every log it passes. |

## Tweak knobs

**My callers can only put the key in the query string**
```text
Change apikey.source to query on both routes, keeping the name apikey. Then tell
me, in the README's own words, what that costs me: which logs the key will now
appear in and what compensating controls you'd put on the route.
```

**One key per site rather than per terminal**
```text
Create one app per SITE instead of per terminal, and tell me what I lose: which
questions I can no longer answer in an incident, and what revoking one app now
takes offline.
```

**Meter these callers**
```text
Now meter them. The product quota is already counted per app, so set a real limit
on the product rather than adding a limit-count plugin keyed on the caller. Show
me what a caller sees when it goes over.
```
(That's [solution 03](../03-api-products/).)

**Move to tokens for the callers that can manage it**
```text
Some of these callers are partner backends that CAN cache a token and refresh it.
Add a second API for them using helix-auth generate + validate as in solution 01,
and leave the device API on key-auth. Do not mix the two on one route.
```

## Known failure modes when running this prompt

- **Dry-run fails naming `apikey`.** `apikey.source` is missing. Reply: `apikey
  with source: header is required for key-auth on this build — add it to both
  routes.`
- **The agent reaches for a `key-auth` plugin.** Reply: `key-auth is a
  validate_auth_type of helix-auth on this build, not a plugin.`
- **The agent puts a key value in the spec.** Reply: `the route names the header
  only. The key is issued on the app credential by the control plane — nothing
  goes in the document.`
- **A valid key returns 403, not 200.** Authentication worked; authorization did
  not. The app's product does not contain this API — add it and redeploy the
  product.
- **The agent renames the routes to `/todos/1` and `/posts`.** It matched the
  upstream instead of rewriting to it. Reply: `keep my route paths; use
  proxy-rewrite to reach the upstream's.`
- **Everything 401s with *Missing API key*.** The header on the wire is not the
  one in `apikey.key`, or the key is in the query string.
- **`validate_route` returns an error and the agent then stalls.** It is not your
  config. The tool sends `{"route": …}` and the control plane wants
  `{"routeSpec": [ … ]}`, so the call fails whatever it contains. Reply: `skip
  validate_route, run dry_run_deploy instead.`
- **`create_api` fails and the agent reports the API already exists.** A previous
  run left one behind. Give it a name that is free, or point it at the existing API.
- **Deploy fails with `Only INACTIVE revisions can be updated`.** Clone the
  revision or undeploy, then apply.

## Related

- **[Solution 01 — OAuth 2.0 with JWT](../01-oauth-jwt/helix-agent-prompt.md)** —
  the same question answered for callers that *can* run an exchange.
- **[Solution 06 — Signed requests](../06-hmac-auth/helix-agent-prompt.md)** — for
  callers that can hold a secret, when the payload's integrity matters.
- **[Solution 03 — API Products](../03-api-products/helix-agent-prompt.md)** —
  metering the apps this solution resolves.
