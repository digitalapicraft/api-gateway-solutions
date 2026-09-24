# Agent-mode prompt — HMAC request signing

Two steps, from a **fresh, empty org** to routes that only accept signed requests.
The agent creates the API on a public upstream, puts `hmac-auth` on the routes,
dry-runs, and hands you an app credential to sign with.

Paste one step at a time and confirm between them. Replace the `<<...>>` values.
[AGENT-GUIDE.md](../../AGENT-GUIDE.md) carries the standing rules these prompts
assume.

---

## Step 1 — create the API and sign its routes

```text
Create a REST API "<<Partner Events API>>" on upstream
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

## Step 2 — a credential, and the five calls that prove it

```text
Create an API product for this API with authMethods ["hmac-auth"] and a quota of
10000 per hour, deploy it to the same environment, then create a developer
"<<Settlement Partner>>" with an app subscribed to that product using
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

---

## Why it's shaped this way

- **`signed_headers` is stated as mandatory.** It has no default, so a model
  writing "a reasonable hmac-auth config" omits it — and the result validates,
  deploys, and is wide open. This is the most damaging wrong turn here.
- **Per route, not API-wide.** The two routes need different signed sets. Hoist one
  block to the root and every bodyless GET must send a digest of the empty string
  or 401.
- **No `request-validation`.** A model asked to harden an ingest endpoint reaches
  for schema validation. At priority 2800 it re-encodes the body before `hmac-auth`
  hashes it at 2530, and the digest silently stops matching.
- **No secret on the route.** Stops the agent inventing a `secret_key` or
  `signing_secret` field by analogy with `helix-auth`. The route schema has neither.
- **`authMethods: ["hmac-auth"]`.** It defaults to `["helix-auth"]`, and app
  creation then fails with an unhelpful error about an unsupported auth plugin.
- **`plugins {"hmac-auth": {}}`.** The empty object is the instruction to
  auto-generate. A model may invent values instead — which works, but gives you a
  secret of its choosing.
- **"Pipe printf straight into openssl".** A model writing idiomatic bash assigns
  the base to a variable first, `$( )` eats the trailing newline, and every request
  401s with a signature that looks correct.
- **The `headers=` omits-digest test.** The one that proves `signed_headers` is
  enforced rather than decorative.

## Tweak knobs

**Tighter replay window**
```text
Reduce clock_skew to 60 seconds on both routes. Our callers are servers with NTP,
so a one-minute window is realistic and it cuts the replay window fivefold.
```

**Fail safe instead of per-route**
```text
Move hmac-auth to the API level with the POST configuration (signed_headers
["@request-target","date","digest"], validate_request_body true) so any route I
add later is signed by default. Tell my GET callers to send
Digest: SHA-256=47DEQpj8HBSa+/TImW+5JCeuQeRkm5NMpJWZG3hSuFU= — the digest of an
empty body — since the route will now require it.
```

**Add per-app quota on top**
```text
Also put api-product-enforcer on both routes so the product quota is enforced per
app. Confirm first that it resolves the credential from an hmac-auth consumer — if
it returns 401 "no ctx.consumer" or 403 "missing credential_id", tell me rather
than working around it.
```

**Let unsigned callers through as an anonymous consumer**
```text
Set anonymous_consumer on the GET route to <<a consumer you have created>> so
unsigned reads are allowed but attributed, while POST stays strictly signed.
```

## When it goes wrong

| Symptom | Cause |
|---|---|
| A signature that looks correct always 401s | The signing base lost its trailing newline — `$( )` strips it. Pipe `printf` straight into `openssl`. |
| Every bodyless GET 401s | `hmac-auth` was hoisted to the API level, so the GET now requires a digest. |
| The digest stops matching after a "hardening" change | `request-validation` landed on the route and re-encoded the body. |
| App creation fails on an unsupported auth plugin | The product's `authMethods` is still the `["helix-auth"]` default. |
| The agent invents a `secret_key` field on the route | It has none. The credential carries it. |
| You need the secret again | It's returned once and stored encrypted. Rotate instead. |
