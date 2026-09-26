# Install — Solution 08 — API keys for callers that can't run a token exchange

[Overview](readme.md) · [Business need](business-need.md) · [How it works](how-it-works.md) · **Install** · [Configuration](configuration.md) · [Test & verify](testing.md) · [Changelog](changelog.md)

---

## Build it with the Helix Agent

Recommended path, and it works on a **fresh org** — the agent creates the API on
a public upstream so you get real data immediately. Two steps; confirm between
them. Full prompt with the reasoning, tweak knobs and failure modes:
[`helix-agent-prompt.md`](helix-agent-prompt.md).

```text
Create a REST API "<<Terminal API>>" on upstream
https://jsonplaceholder.typicode.com, environment test, with routes
GET /fleet/price-list and POST /fleet/takings. Fresh org — nothing exists yet.

My route paths are the contract with the fleet; the upstream's are not. Add
proxy-rewrite: /fleet/price-list -> /todos/1 and /fleet/takings -> /posts. Don't
rename my routes to match the backend.

Protect both with helix-auth, mode validate, validate_auth_type key-auth, reading
the key from the HEADER X-Device-Key. key-auth is a validate_auth_type here, not a
standalone plugin. apikey with source is required in practice — the dry-run rejects
the config without it, although the published schema marks it optional.

No secret goes in the spec: the key lives on the app credential and the route only
names the header it arrives in. Don't set secret_validation — despite the name it
accepts the credential's secret as an ALTERNATIVE credential, which widens what
authenticates.

Put request-id in the SERVICE spec so it applies API-wide. Don't add cors — these
callers are devices, not browsers.

Plugins go in a top-level "plugins" map on the route object, each under its own
plugin name. No "x-helix-gateway" wrapper — a live route discards it silently and
still reports success.

Show me the spec, run dry_run_deploy, then read the revision back so I can see
which plugins actually landed. Wait before deploying.
```

Then, in the same session:

```text
Create a product containing this API with a generous quota, deploy it to test,
then create a developer "<<Forecourt Estate>>" with one app subscribed to it and
give me the app's API key.

Then curl commands showing, in order: no key → 401; the key in X-Device-Key → 200;
an unknown key → 401; the right key in an "apikey" header → 401; and the right key
as a query parameter → 401. The last two prove the header NAME and the header
SOURCE are both part of the contract.
```

See [AGENT-GUIDE.md](../../AGENT-GUIDE.md) for what to do when the agent takes a
wrong turn.

## Install it directly

If you'd rather not go through the agent:

```bash
export ORG=<ORG_ID>
export TOKEN=<control-plane bearer token>      # short-lived
export BASE=https://<YOUR_GATEWAY_HOST>/api

# 1. Import gateway/api-spec.yaml (OpenAPI import in the portal, or Agent Mode).
#    There is nothing to fill in — this spec contains no secret and no key.

# 2. Bind your upstream to the service and deploy the revision to "test".

# 3. Create a PRODUCT containing this API, with a quota, and deploy the product to
#    the environment. Then create a DEVELOPER and one APP per caller, subscribed
#    to that product. The control plane issues each app's key and secret.

# 4. Prove it
GATEWAY=https://<YOUR_GATEWAY_HOST> \
DEVICE_KEY=<DEVICE_API_KEY> APP_SECRET=<APP_SECRET> \
./gateway/verify.sh
```

> An **ACTIVE** revision will not accept edits — you'll get `Only INACTIVE
> revisions can be updated`. Clone the revision (keeping the live one as a
> rollback target) or undeploy first.

## Step 1 — create and protect the API

```text
Create a REST API "<<Terminal API>>" on upstream
https://jsonplaceholder.typicode.com, environment test, with routes
GET /fleet/price-list and POST /fleet/takings. Fresh org — nothing exists yet.

My route paths are the contract with the fleet; the upstream's are not. Add
proxy-rewrite: /fleet/price-list -> /todos/1 and /fleet/takings -> /posts. Don't
rename my routes to match the backend.

Protect both with helix-auth, mode validate, validate_auth_type key-auth, reading
the key from the HEADER X-Device-Key. key-auth is a validate_auth_type here, not a
standalone plugin. apikey with source is required in practice — the dry-run rejects
the config without it, although the published schema marks it optional.

No secret goes in the spec: the key lives on the app credential and the route only
names the header it arrives in. Don't set secret_validation — despite the name it
accepts the credential's secret as an ALTERNATIVE credential, which widens what
authenticates.

Put request-id in the SERVICE spec so it applies API-wide. Don't add cors — these
callers are devices, not browsers.

Plugins go in a top-level "plugins" map on the route object, each under its own
plugin name. No "x-helix-gateway" wrapper — a live route discards it silently and
still reports success.

Show me the spec, run dry_run_deploy, then read the revision back so I can see
which plugins actually landed. Wait before deploying.
```

## Step 2 — issue a credential and test it

```text
Create a product containing this API with a generous quota, deploy it to test,
then create a developer "<<Forecourt Estate>>" with one app subscribed to it and
give me the app's API key.

Then curl commands showing, in order: no key → 401; the key in X-Device-Key → 200;
an unknown key → 401; the right key in an "apikey" header → 401; and the right key
as a query parameter → 401. The last two prove the header NAME and the header
SOURCE are both part of the contract.
```

---

## Why it's shaped this way

- **`apikey` with `source` is required in practice.** The published schema marks it
  optional; the plugin's own check doesn't. Without this line the agent produces a
  config that fails at dry-run over a property it believed was optional.
- **`key-auth` is not a standalone plugin.** It's a `validate_auth_type` of
  `helix-auth`. A general model reaches for it by name.
- **No secret in the spec.** True here and worth saying, because it is *not* true
  of `helix-auth` in generate mode ([solution 02](../02-oauth-jwt/)), where the
  signing secret is a literal. An agent generalising from that will try to put a
  key in this one.
- **Not `secret_validation`.** Its name reads like a second factor. It isn't one.
- **Not `cors`.** Devices aren't browsers. An agent pattern-matching on the other
  auth solutions adds a wildcard policy this API has no use for.
- **`request-id` on the service spec.** API-wide plugins live there; copied onto
  each route it works, and then drifts.
- **The key-as-query-parameter test.** Proves `source: header` means header only.
  A key in a URL lands in every log it passes.

## Tweak knobs

**My callers can only put the key in the query string**
```text
Change apikey.source to query on both routes, keeping the name apikey. Then tell
me what that costs me: which logs the key will now appear in, and what
compensating controls you'd put on the route.
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
on the product rather than adding a limit-count keyed on the caller. Show me what
a caller sees when it goes over.
```
(That's [solution 01](../01-api-products/).)

**Move to tokens for the callers that can manage it**
```text
Some of these callers are partner backends that CAN cache and refresh a token. Add
a second API for them using helix-auth generate + validate as in solution 02, and
leave the device API on key-auth. Don't mix the two on one route.
```

## When it goes wrong

| Symptom | Cause |
|---|---|
| Dry-run fails naming `apikey` | `apikey.source` is missing. It's required in practice on both routes. |
| A valid key returns 403, not 200 | Authentication worked, authorization didn't — the app's product doesn't contain this API. |
| Everything 401s with *Missing API key* | The header on the wire isn't the one in `apikey.key`, or the key is in the query string. |
| The agent renames the routes to `/todos/1` and `/posts` | It matched the upstream instead of rewriting to it. Keep your paths; use `proxy-rewrite`. |
| The agent reaches for a `key-auth` plugin | It's a `validate_auth_type` of `helix-auth` here, not a plugin. |
| The agent puts a key value in the spec | The route names the header only; the control plane issues the key on the app credential. |
| `create_api` fails saying the API exists | A previous run left one behind. Use a free name. |
| Deploy fails: `Only INACTIVE revisions can be updated` | Clone the revision or undeploy, then apply. |

## Related

- **[Solution 02 — OAuth 2.0 with JWT](../02-oauth-jwt/install.md)** —
  the same question answered for callers that *can* run an exchange.
- **[Solution 06 — Signed requests](../06-hmac-auth/helix-agent-prompt.md)** — for
  callers that can hold a secret, when the payload's integrity matters.
- **[Solution 01 — API Products](../01-api-products/helix-agent-prompt.md)** —
  metering the apps this solution resolves.
