# Agent-mode prompt — HMAC request signing

> [Overview](README.md) · [Business need](business-need.md) · [Architecture](architecture.md) · [Guides](guides.md) · **Agent prompt** · [Tests](tests.md) · [API reference](api-reference.md)

---

Two steps, from a **fresh, empty org** to routes that only accept signed requests,
plus an app credential to sign with. Replace the `{{...}}` values, then **paste
Step 1, confirm, and paste Step 2**. The four optional follow-ups after them each
make one separate change; paste one only if you want it. Why the prompt is worded
this way, and what to check before you trust the result, are in
[Guides](guides.md#build-it-with-the-helix-agent).

## Prompt

### Step 1 — create the API and sign its routes

```text
Create a REST API "{{api_name}}" on upstream
https://jsonplaceholder.typicode.com, environment test, with routes POST /posts
and GET /posts/{postId} proxied straight through. Fresh org — nothing exists yet.

Protect both with hmac-auth, per route rather than at the API level, because they
need different signed sets:
- POST /posts: signed_headers ["@request-target","date","digest"],
  validate_request_body true
- GET /posts/{postId}: signed_headers ["@request-target","date"],
  validate_request_body false  (no body, so no digest to bind)

On both: clock_skew 300, allowed_algorithms ["hmac-sha256","hmac-sha512"],
hide_credentials true, realm "partner-events".

signed_headers is not optional. It has no default, so without it the CLIENT
decides what its own signature covers — a signature over just the keyId replays
against any body and any path. Don't drop it for brevity.

Don't add request-validation to these routes: it runs earlier in the same phase
and re-encodes the body, which breaks the digest comparison. And there is no
secret to configure on the route — hmac-auth has no secret field; key_id and
secret_key live on the app credential.

Also add request-id at the API level with header_name X-Request-Id.

Plugins go in a top-level "plugins" map on the route object, each under its own
plugin name. No "x-helix-gateway" wrapper — a live route discards it silently and
still reports success.

Show me the spec, run dry_run_deploy, then read the revision back so I can see
which plugins actually landed. Wait before deploying.
```

### Step 2 — a credential, and the five calls that prove it

```text
Create an API product for this API with authMethods ["hmac-auth"] and a quota of
10000 per hour, deploy it to the same environment, then create a developer
"{{developer_name}}" with an app subscribed to that product using
plugins {"hmac-auth": {}} so key_id and secret_key are generated. Give me both —
I know they are only returned once.

Then a bash script that signs and sends a request, showing in order: no signature
→ 401; a correct signature → 201; the same headers with a modified body → 401; a
Date 20 minutes old → 401; and a signature whose headers= omits "digest" → 401.

For the signing base: keyId on the first line, then one line per headers= entry in
order ("@request-target" becomes "POST /posts", others become "name: value"),
joined by \n AND terminated with a final \n. Pipe printf straight into openssl —
$( ) strips the trailing newline and the signature will be wrong.
```

### Optional follow-up — Tighter replay window

```text
Reduce clock_skew to 60 seconds on both routes. Our callers are servers with NTP,
so a one-minute window is realistic and it cuts the replay window fivefold.
```

### Optional follow-up — Fail safe instead of per-route

```text
Move hmac-auth to the API level with the POST configuration (signed_headers
["@request-target","date","digest"], validate_request_body true) so any route I
add later is signed by default. Tell my GET callers to send
Digest: SHA-256=47DEQpj8HBSa+/TImW+5JCeuQeRkm5NMpJWZG3hSuFU= — the digest of an
empty body — since the route will now require it.
```

### Optional follow-up — Add per-app quota on top

```text
Also put api-product-enforcer on both routes so the product quota is enforced per
app. Confirm first that it resolves the credential from an hmac-auth consumer — if
it returns 401 "no ctx.consumer" or 403 "missing credential_id", tell me rather
than working around it.
```

### Optional follow-up — Let unsigned callers through as an anonymous consumer

```text
Set anonymous_consumer on the GET route to {{anonymous_consumer_name}} so
unsigned reads are allowed but attributed, while POST stays strictly signed.
```
