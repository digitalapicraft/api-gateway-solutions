# Guides — OpenPGP at the edge, in both directions

> [Overview](README.md) · [Business need](business-need.md) · [Architecture](architecture.md) · **Guides** · [Agent prompt](helix-agent-prompt.md) · [Tests](tests.md) · [API reference](api-reference.md)

---

Three ways to build the same thing, then how to see it work. Whichever way you
pick, the result is one API with two routes: `POST /statements/inbound`, which
decrypts what the partner sends before your backend sees it, and
`GET /statements/{statementId}`, which encrypts your backend's statement to the
partner's key.

## Pick your path

| | Choose this if you… | Go to |
|---|---|---|
| **1. Helix Agent** | want the quickest result and are happy to paste a prompt | [Build it with the Helix Agent](#build-it-with-the-helix-agent) |
| **2. Helix control plane** | prefer clicking through screens and want to see every setting | [Build it in the UI](#build-it-in-the-ui) |
| **3. API script** | are scripting this, or wiring it into a pipeline | [Install it directly](#install-it-directly) |

Then, for everyone: [See it work](#see-it-work) · [Variations](#variations) ·
[Configuration reference](#configuration-reference) · [Troubleshooting](#troubleshooting)

## Build it with the Helix Agent

Works on a **fresh, empty org**. [`helix-agent-prompt.md`](helix-agent-prompt.md)
has three steps: the inbound (decrypt) route, the outbound (encrypt) route, then a
note for your partner. **Paste each as its own message.** If a step ends with
`stream closed with reason: error`, retry it once, then import
[`example/api-spec.yaml`](example/api-spec.yaml) instead.

See [AGENT-GUIDE.md](../../AGENT-GUIDE.md) for the ground rules these prompts
assume.

## Build it in the UI

Screen and button names below are the real ones. The API lives under
**API Gateway** in the left sidebar.

**Before you start:**

- **You have an account.** If you don't, register for a free trial at
  [trial.digitalapi.ai](https://trial.digitalapi.ai/). A new trial org comes with a
  `test` environment, which is all this walkthrough needs.
- **You can create APIs.** If you don't see an **Add API** button, ask your org
  admin.
- **You have the keys.** Your own armored private key (for inbound) and your
  partner's armored public key (for outbound). For a first test, one pair can fill
  both. Which key goes where: [Architecture](architecture.md#two-parties-four-key-halves).

**1. Create the API**

Pick one of the two ways below. Both give you the same thing: an API called
`Statements API` with two routes and no plugins yet.

*Option A — from scratch*
1. Go to **API Gateway → APIs**, click **Add API** (or **Create your first API**).
2. Choose **Create from scratch**. Set **Display name** to `Statements API`, then
   **Save**.
3. On the API's page, open **Configuration → Routes** and add two routes:
   - `POST` `/statements/inbound`, where the partner sends you an encrypted file
   - `GET` `/statements/:statementId`, where the partner fetches a statement. The
     gateway writes a path parameter as `:statementId`, not `{statementId}`.

*Option B — from an OpenAPI spec*
1. Go to **API Gateway → APIs**, click **Add API** (or **Create your first API**).
2. Set **Method** to **Import an OpenAPI spec**.
3. Drag in your own OpenAPI 3.0 file, or use our example,
   [`example/api-spec-basic.yaml`](example/api-spec-basic.yaml): the same two
   routes, no plugins. Then click **Import**.

> **A spec can carry the plugins too.** Add an `x-helix-gateway` block that
> lists them. At the top level of the file it covers every route; under one
> path and method it covers that route only. This is the inbound route's:
>
> ```yaml
> /statements/inbound:
>   post:
>     x-helix-gateway:
>       plugins:
>         pgp-crypto:
>           decrypt:
>             target: request
>             source: body
>             private_key: "<PGP_PRIVATE_KEY>"
>             passphrase: ""
>             fail_policy: fail-close
>             fail_close_status: 400
>         proxy-rewrite:
>           uri: /post
> ```
>
> [`example/api-spec.yaml`](example/api-spec.yaml) is this API with all its
> plugins already in place. To use it, copy it and replace `<PGP_PRIVATE_KEY>`
> and `<PGP_PUBLIC_KEY>` with your real armored key blocks first, then import
> your copy and you can skip step 2. **Keep the filled-in copy out of version
> control.**

Either way, the API is not live yet: it has no upstream and isn't deployed.
That comes in step 3.

**2. Add the plugins**

These plugins decrypt what your partner sends and encrypt what you send back. Add
them **before** you deploy: a live revision can't be changed.

Each one goes on one route, not on the whole API.

On the API's page, open **Configuration → Plugins** and click **Configure
plugin**. A short wizard opens:

1. **Plugin** — pick the plugin from the catalog.
2. **Scope** — choose **Specific endpoint** and pick the route. (**Entire
   Revision** would apply it to every route.)
3. **Configure** — the JSON editor and the Properties list sit side by side.
   Paste the JSON below, or fill in the fields. Then **Next**.
4. **Review** — shows the configuration before and after. Click **Apply**.

Run the wizard once for each plugin on each route: four times in all.

**About the keys.** Replace `<PGP_PRIVATE_KEY>` and `<PGP_PUBLIC_KEY>` with the
whole armored key block, from `-----BEGIN PGP …-----` to `-----END PGP …-----`.
The gateway uses the value exactly as written: it does not fill in `<ENV:...>` or
`${...}`, so a placeholder left in place fails when a request arrives. In the
JSON editor, each line break inside the key is written as `\n`. The two keys are
not a pair: the private key is yours, the public key is your partner's.
[Which key goes where](architecture.md#two-parties-four-key-halves).

On the **`POST /statements/inbound`** route (Scope: **Specific endpoint**, that
route):

1. **`pgp-crypto` — decrypts the file your partner sends.** The backend receives
   the plain file and never sees the encrypted one. If the body can't be
   decrypted, the caller gets HTTP 400 (a bad request) and the backend is not
   called.

   ```json
   {"decrypt":{"target":"request","source":"body","private_key":"<PGP_PRIVATE_KEY>","passphrase":"","fail_policy":"fail-close","fail_close_status":400,"fail_close_message":"request body is not a PGP message this gateway can decrypt"},"max_body_size":1048576,"gpg_timeout_ms":5000}
   ```

2. **`proxy-rewrite` — sends the request to the right backend path.**

   | Field | Value |
   |---|---|
   | **uri** | `/post` |

   ```json
   {"uri":"/post"}
   ```

On the **`GET /statements/:statementId`** route (Scope: **Specific endpoint**,
that route):

1. **`pgp-crypto` — encrypts the statement to your partner's key.** It encrypts
   the whole response body, never one field of it. If the statement can't be
   encrypted, the caller gets HTTP 500 (a server-side error), never the statement
   in readable form.

   ```json
   {"encrypt":{"target":"response","source":"body","public_key":"<PGP_PUBLIC_KEY>","fail_policy":"fail-close","fail_close_status":500,"fail_close_message":"statement could not be encrypted"},"max_body_size":1048576,"gpg_timeout_ms":5000}
   ```

2. **`proxy-rewrite` — sends the request to the right backend path.**

   | Field | Value |
   |---|---|
   | **uri** | `/json` |

   ```json
   {"uri":"/json"}
   ```

Repeat for each plugin and route. What every field means, and the optional extra (`request-id`) the full spec adds:
[Configuration reference](#configuration-reference).

**3. Give it an upstream, then deploy it**
1. Go to **API Gateway → Upstreams → Add Upstream**. Name it, pick environment
   `test`, point it at `httpbin.org`, then **Create Upstream**. If an `httpbin`
   upstream already exists in your org, reuse it.
2. Back on the API's page, click **Deploy** on the revision. The dialog asks you
   to map an upstream for `test`. Pick the one you just created, then **Deploy**.

The control plane stores the key fields encrypted once supplied, but they still
appear in the revision you can read back, and in any spec file you import them
in.

## Install it directly

If you'd rather script it against the control plane:

```bash
export ORG=<ORG_ID>
export TOKEN=<control-plane bearer token>      # short-lived
export BASE=https://<YOUR_GATEWAY_HOST>/api
H=(-H "authorization: Bearer $TOKEN" -H 'content-type: application/json')

# 1. Copy the spec, then replace <PGP_PRIVATE_KEY> and <PGP_PUBLIC_KEY> in the copy
#    with real armored blocks. Do NOT commit the filled-in file.
cp example/api-spec.yaml statements-api.filled.yaml

# 2. Import the filled-in copy. Keep both ids the response returns.
curl -s -H "authorization: Bearer $TOKEN" -F "file=@statements-api.filled.yaml" \
  "$BASE/orgs/$ORG/apis/from-spec"
# → {"api":{"id":"<API_ID>", ...}, "revision":{"id":"<REVISION_ID>", ...}}

# 3. Import does NOT make the routes live. Create an upstream, bind it to the
#    revision, then deploy the revision.
curl -s "${H[@]}" -X POST "$BASE/orgs/$ORG/envs/<TEST_ENV_ID>/upstreams" \
  -d '{"name":"httpbin","specification":{"scheme":"https","nodes":[{"host":"httpbin.org","port":443,"weight":1}]}}'
# → {"id":"<UPSTREAM_ID>", ...}

curl -s "${H[@]}" -X PATCH "$BASE/orgs/$ORG/apis/<API_ID>/revisions/<REVISION_ID>/upstream-bindings/add" \
  -d '{"environmentUpstreams":[{"environmentId":"<TEST_ENV_ID>","upstreamId":"<UPSTREAM_ID>"}]}'
curl -s "${H[@]}" -X POST "$BASE/orgs/$ORG/apis/<API_ID>/revisions/<REVISION_ID>/deploy" \
  -d '{"environmentId":"<TEST_ENV_ID>","force":false}'
```

> Revisions must be **INACTIVE** to accept a spec change. If it's live, undeploy
> first, or clone the revision so you keep a rollback target.

The same calls without narration: [API reference](api-reference.md).

## See it work

**The quickest check uses one key pair in both fields.** The outbound route then
encrypts to a key the inbound route can decrypt, so the GET's own output feeds
straight into the POST:

```bash
GW=https://<YOUR_GATEWAY_HOST>

# encrypt direction — the gateway encrypts the backend's statement
curl -s "$GW/statements/2024-Q1" > out.b64

# decrypt direction — the gateway decrypts it again
curl -s -X POST "$GW/statements/inbound" \
  -H 'content-type: text/plain' --data-binary @out.b64
```

Two calls, no `gpg`, nothing to import, and it exercises both directions. The
echoed `Content-Type: application/json` on the POST shows that decryption actually
happened rather than the body passing through.

Two things this loop cannot do:

- **It cannot catch a key mismatch.** With one pair, the two fields can never
  disagree, so the loop passes by design. To see that path, put a different public
  key in the encrypt block: the GET still returns a well-formed 200, and the POST
  then fails with 400. That is the failure you cannot see from the gateway in a
  real two-party setup.
- **It is not how production behaves.** In a real integration that POST would be
  rejected, because the statement was encrypted to *their* key and your inbound
  route holds *yours*.

To run every check as a script:

```bash
# checks 1-4 need only bash, curl and base64
GATEWAY=https://<YOUR_GATEWAY_HOST> ./example/verify.sh

# add the round trip when you have keys to hand
GATEWAY=https://<YOUR_GATEWAY_HOST> \
GNUPGHOME=/path/to/keyring RECIPIENT=partner@example.com ./example/verify.sh
```

Exit code 0 means the response is encrypted, no plaintext leaks, wrongly framed
bodies are refused, and — with keys — the round trip works. What each check
proves: [Tests](tests.md).

### What your partner's side looks like

**If they also run a gateway**, their spec is this one with the keys swapped and
the directions reversed — their outbound is your inbound:

```yaml
# THEIR gateway, mirroring yours
decrypt:                                 # they receive what you sent
  target: request
  private_key: "<THEIR_PRIVATE_KEY>"     # the pair whose public half you hold
encrypt:                                 # they send to you
  target: response
  public_key: "<YOUR_PUBLIC_KEY>"        # the public half of your decrypt key
```

**If they don't** — the common case, usually a scheduled job with `gpg` on it —
then "their config" is two commands and one file from you:

```bash
# once: import the public key YOU published to them
gpg --import your-org-public.asc

# sending you an instruction — encrypt to YOUR key, then base64 the armor
gpg --armor --encrypt -r ops@your-org.example -o msg.asc instruction.json
base64 -i msg.asc | tr -d '\n' > msg.b64        # the wire format

# reading a statement you sent them — decrypt with THEIR private key
curl -s "$GW/statements/2024-Q1" | base64 -d | gpg --decrypt
```

They encrypt with **your** public key and decrypt with **their** private key, in the
same integration. The key depends on the direction, not on who they are.

### The note to send your partner

Copy this, fill in the two blanks, and it is a complete integration brief:

> **Endpoint** `POST <your host>/statements/inbound`
>
> **Encrypt to:** the public key attached (`ops@your-org.example`). Send us your
> own public key and we will encrypt statements to it.
>
> **Wire format:** base64 **of** the ASCII-armored message — not the armor. Armor
> is already a text encoding; we need another layer on top. `gpg --armor --encrypt`
> then `base64` the result. **A raw armored body is rejected with 400**, and the
> error does not mention base64.
>
> **Key requirements:** your key must carry an **encryption subkey**. Check with
> `gpg --list-keys --with-colons <uid> | awk -F: '/^(pub|sub)/{print $1, $12}'` —
> you need a `sub` row containing `e`. `gpg --quick-generate-key` does **not**
> produce one; use `gpg --quick-add-key <fpr> rsa3072 encr never` to add it.
>
> **On failure** you will get a 400 with a generic message — the reason is in our
> logs, not your response. Quote the `X-Request-Id` header and we will look.

## Variations

**More than one partner.** Do not copy this route once per partner with a key pair
each. Fetch the key per request instead: [solution 12](../12-key-value-map/) does
exactly that and keeps key material out of the spec entirely.

**Put identity in front.** Encrypting to a partner's key does not check who called.
Add authentication to both routes, as in [solution 08](../08-api-key/), and keep
the crypto as it is.

**Encrypt one field only.** Not available in the way it sounds: `field` on an
encrypt block returns **only** that field's ciphertext as the whole response body.
If you want the rest of the document intact, encrypt the whole body.

## Configuration reference

Source of truth: [`example/api-spec.yaml`](example/api-spec.yaml).
[`example/api-spec-basic.yaml`](example/api-spec-basic.yaml) is the same routes
with no plugins, for adding them yourself.

Inbound:

```yaml
pgp-crypto:
  decrypt:
    target: request
    source: body            # `field` omitted = the whole body
    private_key: "<PGP_PRIVATE_KEY>"
    passphrase: ""
    fail_policy: fail-close
    fail_close_status: 400
    fail_close_message: "request body is not a PGP message this gateway can decrypt"
  max_body_size: 1048576
  gpg_timeout_ms: 5000
```

Outbound:

```yaml
pgp-crypto:
  encrypt:
    target: response
    source: body            # the WHOLE body
    public_key: "<PGP_PUBLIC_KEY>"
    fail_policy: fail-close
    fail_close_status: 500
    fail_close_message: "statement could not be encrypted"
  max_body_size: 1048576
  gpg_timeout_ms: 5000
```

| Plugin | Field | Value here | What it means |
|---|---|---|---|
| `pgp-crypto` | `decrypt.target` / `decrypt.source` | `request` / `body` | Decrypt the whole request body before the backend sees it. |
| `pgp-crypto` | `decrypt.private_key` | `<PGP_PRIVATE_KEY>` | **Your** armored private key, used verbatim. |
| `pgp-crypto` | `decrypt.passphrase` | `""` | The key is assumed unprotected. A passphrase is a second literal in the document. |
| `pgp-crypto` | `decrypt.fail_policy` / `fail_close_status` | `fail-close` / `400` | Refuse a body that cannot be decrypted; the backend is not called. |
| `pgp-crypto` | `encrypt.target` / `encrypt.source` | `response` / `body` | Encrypt the whole response body. Do not set `field`. |
| `pgp-crypto` | `encrypt.public_key` | `<PGP_PUBLIC_KEY>` | **Your partner's** armored public key, used verbatim. |
| `pgp-crypto` | `encrypt.fail_policy` / `fail_close_status` | `fail-close` / `500` | Never send the statement unencrypted. |
| `pgp-crypto` | `max_body_size` | `1048576` (1 MiB) | The crypto buffers the whole body; larger bodies are rejected, not streamed. |
| `pgp-crypto` | `gpg_timeout_ms` | `5000` | Time limit for the `gpg` fallback path. |
| `proxy-rewrite` | `uri` | `/post` (inbound), `/json` (outbound) | The backend's paths. |
| `request-id` | `algorithm` / `header_name` | `uuid` / `X-Request-Id` | API-wide. Errors are vague; this is what a partner quotes. |

> **`private_key` and `public_key` are used verbatim.** The gateway does not
> resolve `<ENV:...>` or `${...}`. Replace the placeholders with real armored
> blocks before deploying, and keep the filled-in spec out of version control. The
> control plane stores these fields encrypted once supplied, but they still travel
> in the document you import and still sit in the revision you can read back.

This is the same kind of risk as `signing_secret` in
[solution 02](../02-oauth-jwt/), and worse: a private key outlives a signing secret
and is usually shared with a partner.

Placeholders in this package: `<PGP_PRIVATE_KEY>`, `<PGP_PUBLIC_KEY>`, `<ORG_ID>`,
`<TEST_ENV_ID>`, `<API_ID>`, `<REVISION_ID>`, `<UPSTREAM_ID>`,
`<YOUR_GATEWAY_HOST>`. Replace all of them before you deploy.

Every field of every plugin: [docs.digitalapi.ai/api-gateway](https://docs.digitalapi.ai/api-gateway).

## Troubleshooting

| Symptom | Cause |
|---|---|
| Every inbound request is rejected, and the partner insists the file is valid | They are sending raw armor. The body must be base64 *of* the armor. The error does not say so. |
| 400 on inbound, no further detail | Correct: errors are vague on purpose. The reason is in the gateway's telemetry; ask for the `X-Request-Id`. |
| 500 on the statement route | The response could not be encrypted — usually a public key that cannot be read. |
| 200 with an error message in the body | A key that is present but unusable — an OpenPGP key with no encryption subkey, which is what `gpg --quick-generate-key` produces. Assert on the body, not the status. |
| The partner cannot decrypt a response that looks perfect | Encrypted to the wrong public key. Nothing at the gateway shows this; only a round-trip test finds it. |
| The response is a short ciphertext and the rest of the document is gone | `field` was set on the encrypt block. It selects what is returned, not just what is encrypted. |
| Month-end batch fails, everything else works | The body exceeded `max_body_size`. Raise it deliberately, with the memory cost in mind. |
| The statement came back readable | `fail_policy` is `fail-open` and encryption failed. |
| Messages encrypted to the old key fail after a key change | Rotation on a route is a hard cutover. Agree the switch with the partner, or move the key to a store — [solution 12](../12-key-value-map/). |
| Deploy fails: `Only INACTIVE revisions can be updated` | Clone the revision or undeploy, then apply. |

If you built it with the agent:

| Symptom | Cause |
|---|---|
| `stream closed with reason: error` after a route write | The agent's tool arguments arrived malformed; nothing was written. Retry once, then import the spec for the rest. |
| The agent writes `pgp-crypto` flat, with no `encrypt`/`decrypt` wrapper | Reply: it's nested — show me the route object as JSON before sending. |
| The agent offers to generate a key pair | Decline. Use the placeholder; supply the real key yourself. |
| The agent sets `field` on the encrypt block | Reply: remove it — it returns only that field's ciphertext and throws the document away. |
| The write succeeds and the routes have no plugins | Nested under `x-helix-gateway`. Read the revision back and rewrite with a top-level `plugins` key. |
