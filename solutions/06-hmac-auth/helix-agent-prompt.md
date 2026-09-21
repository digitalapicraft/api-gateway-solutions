# Agent-mode prompt — HMAC request signing

Paste this into **Agent Mode**. It works from a **fresh, empty org**: the agent
*creates* the API (there is nothing pre-existing to find), binds a public upstream
so you get real data immediately, puts `hmac-auth` on the routes, dry-runs, and
hands you an app credential to sign with.

Replace the `<<...>>` values. Everything else is deliberate — the table below says
why each block earns its place. Read [AGENT-GUIDE.md](../../AGENT-GUIDE.md) first
if you haven't.

---

## The prompt

> **Run it in steps, not as one mega-prompt.** These are the exact prompts shaped
> for the **default agent model**. Paste **Step 1**, let the agent create the API
> and stop at the dry-run; confirm; then paste **Step 2**. Folding the whole build
> into a single prompt pushes a smaller model to attempt one oversized change and
> stall — one bounded ask per step is what keeps it reliable.

**Step 1 — create the API and sign its routes**

```text
Create a new REST API called "<<Partner Events API>>" and protect it with HMAC
request signing using the hmac-auth plugin. This is a fresh org — I have no
existing API.

Upstream: https://jsonplaceholder.typicode.com (public, so it returns real data;
I'll swap in my own later). Deploy to the "test" environment.

Routes (paths match the upstream, so no path rewrite): POST /posts and
GET /posts/{postId}.

Put hmac-auth on each route individually, NOT at the API level, because the two
need different signed sets:
- POST /posts: signed_headers ["@request-target","date","digest"],
  validate_request_body true
- GET /posts/{postId}: signed_headers ["@request-target","date"],
  validate_request_body false  (no body, so no digest to bind)

On both: clock_skew 300, allowed_algorithms ["hmac-sha256","hmac-sha512"],
hide_credentials true, realm "partner-events".

signed_headers is not optional — without it the CLIENT decides what its own
signature covers, and a signature over just the keyId replays against any body
and any path. Do not drop it for brevity.

Do NOT add request-validation to these routes: it runs earlier in the same phase
and re-encodes the body, which breaks the digest comparison.

There is no secret to configure on the route — hmac-auth has no secret field.
The key_id and secret_key live on the app credential.

Also add request-id at the API level with header_name X-Request-Id.

Check get_plugin_config for hmac-auth before writing config. Show me the spec,
skip validate_route (it fails on this build whatever you put in it) and run
dry_run_deploy, then wait before deploying.
```

**Step 2 — create a credential and test it** (same session, after Step 1 deploys)

```text
Create an API product for this API with authMethods ["hmac-auth"] and a quota of
10000 per hour, deploy it to the same environment, then create a developer
"<<Settlement Partner>>" with an app subscribed to that product using
plugins {"hmac-auth": {}} so the key_id and secret_key are generated. Give me
both values — I know they are only returned once.

Then give me a bash script that signs and sends a request, and show me, in order:
no signature -> 401; a correct signature -> 201; the same headers with a modified
body -> 401; a Date 20 minutes old -> 401; and a signature whose headers= omits
"digest" -> 401.

For the signing base: keyId on the first line, then one line per headers= entry
in order ("@request-target" becomes "POST /posts", others become "name: value"),
joined by \n AND terminated with a final \n. Pipe printf straight into openssl —
$( ) strips the trailing newline and the signature will be wrong.
```

The agent creates the API, fetches the real `hmac-auth` schema from your org,
proposes the spec, and stops for your confirmation. See
[AGENT-GUIDE.md](../../AGENT-GUIDE.md) for why the prompt is shaped this way and
what to do when the agent takes a wrong turn.

---

## Why the prompt is shaped this way

| Block | Why it's there |
|---|---|
| **"This is a fresh org — create one"** | On a new org there is no API to "find". The agent must create it, or it stalls looking for something that isn't there. |
| **"Upstream: jsonplaceholder"** | Gives a working end-to-end result on a fresh org — real responses behind the signature — without standing up a backend. |
| **"Environment: test"** | Free-trial orgs get a `test` environment by default; that's where things deploy. |
| **"paths match the upstream"** | `/posts` is forwarded unchanged — keeps the spec clean, no `proxy-rewrite`. |
| **"per route, NOT at the API level"** | The two routes need different `signed_headers`. A model tidying up will hoist one block to the root, and then every bodyless GET must send a digest of the empty string or 401. |
| **"signed_headers is not optional"** | The single most likely wrong turn, and the most damaging. It is absent from the plugin's defaults, so a model writing "a reasonable hmac-auth config" omits it — and the result validates, deploys, and is wide open. |
| **"Do NOT add request-validation"** | A model asked to harden an ingest endpoint reaches for schema validation. On this route it silently breaks the digest: priority 2800 re-encodes the body before `hmac-auth` at 2530 hashes it. |
| **"no secret to configure on the route"** | Stops the agent inventing a `secret_key` or `signing_secret` field by analogy with `helix-auth`. `hmac-auth`'s route schema has neither. |
| **"authMethods [\"hmac-auth\"]"** | It defaults to `["helix-auth"]`, and the app creation then fails with an unhelpful error about an unsupported authentication plugin. |
| **"plugins {\"hmac-auth\": {}}"** | The empty object is the instruction to auto-generate. A model may try to invent values, which works but gives you a secret of its choosing. |
| **"I know they are only returned once"** | Pre-empts the agent offering to "fetch them again later". It cannot; `secret_key` is stored encrypted. |
| **"pipe printf straight into openssl"** | The signing gotcha. A model writing idiomatic bash will assign the base to a variable first, `$( )` eats the trailing newline, and every request 401s with a signature that looks correct. |
| **"headers= omits digest -> 401"** | The test that proves `signed_headers` is actually enforced rather than decorative. |

## Tweak knobs

**Tighter replay window**
```text
Reduce clock_skew to 60 seconds on both routes. Our callers are servers with NTP,
so a one-minute window is realistic and it cuts the replay window fivefold.
```

**Fail safe instead of per-route**
```text
Actually, move hmac-auth to the API level with the POST configuration
(signed_headers ["@request-target","date","digest"], validate_request_body true)
so any route I add later is signed by default. Tell my GET callers to send
Digest: SHA-256=47DEQpj8HBSa+/TImW+5JCeuQeRkm5NMpJWZG3hSuFU= — the digest of an
empty body — since the route will now require it.
```

**Add per-app quota on top**
```text
Also put api-product-enforcer on both routes so the product quota is enforced per
app. Confirm first that it resolves the credential from an hmac-auth consumer —
if the enforcer returns 401 "no ctx.consumer" or 403 "missing credential_id",
tell me rather than working around it.
```

**Let unsigned callers through as an anonymous consumer**
```text
Set anonymous_consumer on the GET route to <<a consumer you have created>> so
unsigned reads are allowed but attributed, while POST stays strictly signed.
```
