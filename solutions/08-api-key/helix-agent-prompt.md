# Agent-mode prompt — API-key identity for constrained callers

> [Overview](README.md) · [Business need](business-need.md) · [Architecture](architecture.md) · [Guides](guides.md) · **Agent prompt** · [Tests](tests.md) · [API reference](api-reference.md)

---

Two steps, from a **fresh, empty org** to two routes behind an API key, plus the
product and app whose key you test with. Replace the `{{...}}` values, then
**paste Step 1, confirm, and paste Step 2** in the same session. Why the prompt is
worded this way, and what to check before you trust the result, are in
[Guides](guides.md#build-it-with-the-helix-agent).

## Prompt

### Step 1 — create and protect the API

```text
Create a REST API "{{api_name}}" on upstream
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

### Step 2 — issue a credential and test it

```text
Create a product containing this API with a generous quota, deploy it to test,
then create a developer "{{developer_name}}" with one app subscribed to it and
give me the app's API key.

Then curl commands showing, in order: no key → 401; the key in X-Device-Key → 200;
an unknown key → 401; the right key in an "apikey" header → 401; and the right key
as a query parameter → 401. The last two prove the header NAME and the header
SOURCE are both part of the contract.
```
