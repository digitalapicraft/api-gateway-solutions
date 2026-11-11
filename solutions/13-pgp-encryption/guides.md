# Guides — OpenPGP at the edge, in both directions

> [Overview](README.md) · [Business need](business-need.md) · [Architecture](architecture.md) · **Guides** · [Agent prompt](helix-agent-prompt.md) · [Tests](tests.md) · [API reference](api-reference.md)

---

Three ways to build the same thing, then how to see it work. Whichever way you
pick, the result is one API with two routes: `POST /statements/inbound`, which
decrypts what the partner sends before your backend sees it, and
`GET /statements/:statementId`, which encrypts your backend's statement to the
partner's key.

**Every path needs the keys first:** your private key, its passphrase if it has
one, and your partner's public key. [Get the keys](#get-the-keys) shows how to
make them.

## Pick your path

| | Choose this if you… | Go to |
|---|---|---|
| **1. Helix Agent** | want the quickest result and are happy to paste a prompt | [Build it with the Helix Agent](#build-it-with-the-helix-agent) |
| **2. Helix control plane** | prefer clicking through screens and want to see every setting | [Build it in the UI](#build-it-in-the-ui) |
| **3. API script** | are scripting this, or wiring it into a pipeline | [Install it directly](#install-it-directly) |

Then, for everyone: [See it work](#see-it-work) · [Variations](#variations) ·
[Configuration reference](#configuration-reference) · [Troubleshooting](#troubleshooting)

### Get the keys

You need two keys in the configuration: **your private key** (the inbound route
decrypts with it) and **your partner's public key** (the outbound route encrypts
to it). You generate the first. The partner sends you the second, and you send
them your public half in return. If you only want to try the package, the
[throwaway pair](#try-it-with-throwaway-keys) below stands in for both sides.

**1. Install GnuPG.**

| Platform | Install |
|---|---|
| macOS | `brew install gnupg` |
| Debian, Ubuntu | `sudo apt install gnupg` |
| Windows | Gpg4win, then use `gpg` from a terminal |

Check it with `gpg --version`.

**2. Make a passphrase.** It protects the private key wherever the key sits:
your keyring, the exported file, a backup. Generate a random one and keep it in
your secrets store, because you need it in steps 3, 5 and 6:

```bash
openssl rand -base64 24
```

A passphrase is optional. The gateway works with an unprotected key too; then
leave `decrypt.passphrase` out in step 6.

**3. Generate your key pair.** Use a name and an address that identify the
integration, not a person:

```bash
gpg --quick-generate-key "Acme Statements <statements@acme.example>" default default 2y
```

It asks for the passphrase from step 2. To generate without the prompt, for
example in a script, pass it in:
`gpg --batch --pinentry-mode loopback --passphrase "$PGP_PASSPHRASE" --quick-generate-key …`.
The two `default`s matter: they create an **encryption subkey** alongside the signing key.
Name an algorithm in their place, such as `rsa3072`, and you get no encryption
subkey, so nothing can be encrypted to the key.

**4. Check the encryption subkey.**

```bash
gpg --list-keys statements@acme.example
```

You need a `sub` line marked **`[E]`** (E for encryption), such as
`sub   cv25519 <date> [E]`. Older gpg (2.2) makes an RSA key here instead of
cv25519; that works too, as long as the `[E]` line is there.

**5. Export both halves as ASCII armor.**

```bash
gpg --armor --export statements@acme.example > acme-public.asc               # send to the partner
gpg --armor --export-secret-keys statements@acme.example > acme-private.asc  # goes into the gateway
```

The second command asks for your passphrase. `acme-private.asc` begins with
`-----BEGIN PGP PRIVATE KEY BLOCK-----`; never send it to anyone.

**6. Put the keys and the passphrase into the routes.** In the console, open each route's
`pgp-crypto` configuration:

| Field | Paste |
|---|---|
| inbound route, `decrypt.private_key` | the whole of `acme-private.asc`, from `-----BEGIN` to `-----END` |
| inbound route, `decrypt.passphrase` | the passphrase from step 2; leave it out if your key has none |
| statement route, `encrypt.public_key` | the whole of the partner's public key file |

If you import the spec file instead, put the same values into your copy of it
before you import: see [Install it directly](#install-it-directly).

Before you paste the partner's key, check that it has an encryption subkey too:
`gpg --show-keys partner-public.asc` should show a `sub` line marked `[E]`.

**7. Remove the exported private key file** once it is in the gateway:
`rm acme-private.asc`. The key also stays in your local keyring. Keep it there,
or in your secrets store with its passphrase, for rotation and recovery.

The gateway can fall back to running `gpg` itself, so any key `gpg` can use
works. RSA keys (2048 and 3072) and the ed25519/cv25519 pair the command above
produces on gpg 2.3 and later both work, with or without a passphrase. If your partner insists on
RSA, generate with `rsa3072 sign 2y` in step 3, then add the subkey:
`gpg --quick-add-key <fingerprint> rsa3072 encr 2y`.

#### Try it with throwaway keys

No partner yet? Make both pairs in a temporary keyring, so nothing touches your
real one. Your pair is protected by a generated passphrase, as the prompt
expects; the stand-in partner's has none, so the test can decrypt with it
unattended. Both expire in a day:

```bash
export GNUPGHOME="$(mktemp -d)"
export PGP_PASSPHRASE="$(openssl rand -base64 18)"; echo "$PGP_PASSPHRASE"   # -> decrypt.passphrase
gpg --batch --pinentry-mode loopback --passphrase "$PGP_PASSPHRASE" \
    --quick-generate-key "Statements Ours <ours@example.test>" default default 1d
gpg --batch --passphrase '' --quick-generate-key "Bank Partner <partner@example.test>" default default 1d
gpg --batch --pinentry-mode loopback --passphrase "$PGP_PASSPHRASE" \
    --armor --export-secret-keys ours@example.test > ours-private.asc   # -> decrypt.private_key
gpg --armor --export partner@example.test > partner-public.asc          # -> encrypt.public_key
```

Paste the two files and the printed passphrase into the routes, as in step 6.
Then run the full test from the same shell, so it can play the partner. Use this
script, not the [quickest check](#see-it-work): that one needs one key pair in
both fields, and these are two different pairs, so its POST returns 400.

```bash
GATEWAY=https://<YOUR_GATEWAY_HOST> RECIPIENT=ours@example.test ./example/verify.sh
```

When you're done: `gpgconf --kill gpg-agent; rm -rf "$GNUPGHOME" ours-private.asc partner-public.asc; unset PGP_PASSPHRASE`.

## Build it with the Helix Agent

Works on a **fresh, empty org**. [`helix-agent-prompt.md`](helix-agent-prompt.md)
is one prompt in two steps: step 1 creates the API and its two routes, step 2
adds the decryption and encryption. Paste it as one message and replace the
`{{...}}` values. **Leave `<PGP_PRIVATE_KEY>`, `<PGP_PASSPHRASE>` and
`<PGP_PUBLIC_KEY>` as written**, or delete the passphrase sentence if your key
has none. When the routes exist, replace all three in the console with your real
keys and passphrase, as in [Get the keys](#get-the-keys). Then deploy, and run
the checks in [See it work](#see-it-work).

Before you trust it, read the revision (the saved version of the API's
configuration) back and check:

- **Both routes carry `pgp-crypto`:** a `decrypt` block with
  `fail_close_status: 400` on `POST /statements/inbound`, and an `encrypt` block
  with `fail_close_status: 500` and **no `field`** on the statement route.
- **The statement route's path is `/statements/:statementId`**, not
  `/statements/{statementId}`. The agent can store the second form even though
  the prompt writes the first. It matches only the literal text `{statementId}`,
  so every real id gets `404 Route Not Found`, and the dry-run doesn't catch it.
- **No `<PGP_` placeholder is left.** Both key fields hold your armored keys.
- **If your private key has a passphrase, `decrypt.passphrase` holds it.** It
  belongs with the private key on the inbound route; the `encrypt` block has none.

The agent picks its own failure messages and route names. They can differ from
the spec's, and they don't change the behaviour.

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
- **You have the keys.** Your own armored private key (for inbound), its
  passphrase if it has one, and your partner's armored public key (for outbound).
  [Get the keys](#get-the-keys) shows how to make them. For a first test, one pair
  can fill both. Which key goes where: [Architecture](architecture.md#two-parties-four-key-halves).

**1. Create the API**

Pick one of the two ways below. Both give you the same thing: an API called
`Statements API` with two routes and no plugins yet.

*Option A — from scratch*
1. Go to **API Gateway → APIs**, click **Add API** (or **Create your first API**).
2. Choose **Create from scratch**. Set **Display name** to `Statements API`, then
   **Create**.
3. On the API's page, open **Configuration → Routes** and add two routes:
   - `POST` `/statements/inbound`, where the partner sends you an encrypted file
   - `GET` `/statements/:statementId`, where the partner fetches a statement. The
     gateway writes a path parameter as `:statementId`, not `{statementId}`.

   The route form opens already filled in with the name *New* and the path
   `/new-route`. Clear both fields first, then type your own.

*Option B — from an OpenAPI spec*
1. Go to **API Gateway → APIs**, click **Add API** (or **Create your first API**).
2. Set **Method** to **Import an OpenAPI spec**.
3. Drag in your own OpenAPI 3.0 file, or use our example,
   [`example/api-spec-basic.yaml`](example/api-spec-basic.yaml): the same two
   routes, no plugins. Then click **Import**.

If an API with the same name already exists in your org, the import fails with
*API with name '<name>' already exists*. Type another name in the form's
**Display name** field, which overrides the name in the spec, and import again.

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
> and `<PGP_PUBLIC_KEY>` with your real armored key blocks first. If your private
> key has a passphrase, put it in `passphrase`. Then import your copy and you can
> skip step 2. **Keep the filled-in copy out of version control.**

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

Run the wizard once for each plugin on each route: four times, plus once for
`request-id` on the whole API.

**About the keys.** Before you deploy, replace `<PGP_PRIVATE_KEY>` and
`<PGP_PUBLIC_KEY>` with the whole armored key block, from `-----BEGIN PGP …-----`
to `-----END PGP …-----`. `passphrase` is empty, for a key without one. If your
private key has a passphrase, put it there instead (it is the value the agent
prompt writes as `<PGP_PASSPHRASE>`). The gateway uses each value exactly as
written: it does not fill in `<ENV:...>` or `${...}`, so a placeholder left in
place fails when a request arrives. The console saves placeholder text such as
`<PGP_PUBLIC_KEY>` as a key without a warning. In the JSON editor, each line break inside
the key is written as `\n`. The two keys are not a pair: the private key is
yours, the public key is your partner's.
[Which key goes where](architecture.md#two-parties-four-key-halves). How to make
them: [Get the keys](#get-the-keys).

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
   the whole response body. If the statement can't be encrypted, the caller never
   gets it in readable form. When the key can't be used, for example because the
   placeholder is still there, the caller gets **HTTP 200 with
   `{"message":"statement could not be encrypted"}` in the body**, not the 500
   set in `fail_close_status`. A client must check the body, not just the status
   code.

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

Then, on the **Entire Revision**:

1. **`request-id` — a tracking id on every call (recommended).** It adds an
   `X-Request-Id` header to each response. Every failure gives the partner the
   same short message, and this id is what they quote so you can find the call.
   Without it, responses carry no `X-Request-Id`.

   ```json
   {"algorithm":"uuid","header_name":"X-Request-Id"}
   ```

What every field means: [Configuration reference](#configuration-reference).

**3. Give it an upstream, then deploy it**

Before you deploy, check that no `<PGP_` placeholder is left in either route's
`pgp-crypto` configuration, and that `passphrase` holds your passphrase if your
key has one.

1. Go to **API Gateway → Upstreams → Add Upstream**. Name it, pick environment
   `test`, and add a node at `httpbin.org`, port `443`, scheme HTTPS. If you
   switch the scheme to HTTP, the port stays at `443`: change it to `80` by
   hand. If an `httpbin` upstream already exists in your org, reuse it.
2. **Pass Host** is set to **Rewrite**, which makes **Upstream Host** required.
   It fills in from the node's host; check it reads `httpbin.org`.
3. Click **Next** through the remaining tabs, then **Add Upstream**.
4. Back on the API's page, click **Deploy** on the revision. The dialog asks you
   to map an upstream for `test`. Pick the one you just created, then click
   **Map & Deploy**. (The button reads **Map & Deploy** while no upstream is
   mapped yet, and **Deploy** once one is.)

**Changing it later.** A change to the upstream's host or port applies to the
live API straight away, with no new deploy. A change to its scheme does not:
undeploy the revision and deploy it again. A change to routes or plugins does
need one, because a live revision can't be edited: use **Clone Revision**, make
your change on the copy, then **Force Deploy** it. Rolling back needs no copy:
click **Deploy**, pick the older revision (for example `r1`), and click **Force
Deploy**.

The control plane stores the key fields encrypted once supplied, but they still
appear in the revision you can read back, and in any spec file you import them
in.

## Install it directly

To script it, call the control plane instead. `BASE` is the API address the
portal calls (it usually starts with `api-`), not the portal page and not the
gateway's address:

```bash
export ORG=<ORG_ID>
export TOKEN=<control-plane bearer token>      # short-lived
export BASE=https://<YOUR_CONTROL_PLANE_API>/api
H=(-H "authorization: Bearer $TOKEN" -H 'content-type: application/json')

# 1. Copy the spec. In the copy, replace <PGP_PRIVATE_KEY> and <PGP_PUBLIC_KEY>
#    with real armored blocks, and set decrypt.passphrase if your private key has
#    one (see "Get the keys"). Do NOT commit the filled-in file.
cp example/api-spec.yaml statements-api.filled.yaml
#    After editing the copy, check no placeholder is left. This must print nothing:
grep -nE '^[^#]*<PGP_' statements-api.filled.yaml

# 2. Import the filled-in copy. Keep both ids the response returns.
curl -s -H "authorization: Bearer $TOKEN" -F "file=@statements-api.filled.yaml" \
  "$BASE/orgs/$ORG/apis/from-spec"
# → {"api":{"id":"<API_ID>", ...}, "revision":{"id":"<REVISION_ID>", ...}}

# 3. Import does NOT make the routes live. Create an upstream, bind it to the
#    revision, then deploy the revision.
# pass_host + upstream_host: without them the backend gets the gateway's host
# and every call returns 502.
curl -s "${H[@]}" -X POST "$BASE/orgs/$ORG/envs/<TEST_ENV_ID>/upstreams" \
  -d '{"name":"httpbin","specification":{"scheme":"https","pass_host":"rewrite","upstream_host":"httpbin.org","nodes":[{"host":"httpbin.org","port":443,"weight":1}]}}'
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
straight into the POST. With the [throwaway keys](#try-it-with-throwaway-keys)
the two fields hold different pairs, so the POST returns 400: run the script
further down instead.

```bash
GW=https://<YOUR_GATEWAY_HOST>

# encrypt direction — the gateway encrypts the backend's statement
curl -s "$GW/statements/2024-Q1" > out.b64

# decrypt direction — the gateway decrypts it again
curl -s -X POST "$GW/statements/inbound" \
  -H 'content-type: text/plain' --data-binary @out.b64
```

Two calls, no `gpg`, nothing to import, and it exercises both directions. The
POST's echo shows the backend's statement as readable JSON in `data`, which shows
that decryption actually happened. The echoed `Content-Type: application/json`
proves it only for a JSON file: a plain-text file arrives as `text/plain`.

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
> **Wire format:** base64 **of** the encrypted message, not the armor itself.
> `gpg --armor --encrypt`, then `base64` the result. Base64 of gpg's binary
> output (without `--armor`) works too, and line breaks in the base64 are fine.
> **A raw armored body is rejected with 400**, and the error does not mention
> base64.
>
> **Key requirements:** your key must carry an **encryption subkey**. Check with
> `gpg --list-keys --with-colons <uid> | awk -F: '/^(pub|sub)/{print $1, $12}'` —
> you need a `sub` row containing `e`. `gpg --quick-generate-key "<uid>" default
> default 2y` creates one; naming an algorithm such as `rsa3072` in place of the
> first `default` does not. Add one with `gpg --quick-add-key <fpr> rsa3072 encr 2y`.
>
> **On failure** you will get a 400 with the same short message, whatever the
> cause: wrong key, wrong format or a file over 1 MiB. Quote the `X-Request-Id`
> header and we will look.

## Variations

Follow-ups for the same agent session, once the build is standing. Same style as
the prompt: say what you want to be true.

**Write the note for the partner**
```text
Write me the integration note to send our bank partner. Both directions carry
base64 of the ASCII-armored message, not the armor itself, and a raw armored body
is refused. Include a worked example of encrypting a file and base64-encoding it
before the POST.
```
Or start from ours: [The note to send your partner](#the-note-to-send-your-partner).

**A second partner**
```text
We're adding a second bank, {{second_partner_name}}, with its own key pair. Tell me
what this design costs at two partners and at twenty, and show me the version that
picks the key per partner instead.
```
Do not copy this route once per partner with a key pair each. Fetch the key per
request instead: [solution 14](../14-per-partner-pgp-keys/) does exactly that and
keeps key material out of the spec entirely.

**Rotate our private key**
```text
Our private key is being rotated on {{rotation_date}}. Tell me what happens to
messages the partner encrypted to the old key, and the order to do the change in.
```
Changing the key on a route is a hard cutover: messages encrypted to the old key
fail after the switch, so agree the date with the partner.

**Only callers we know**
```text
Require an app's API key in the X-Api-Key header on both routes, and keep the
crypto exactly as it is. Then create a developer, a product and an app, and give me
the key.
```
The gateway doesn't check who sent a file. It doesn't read the signature, so a
file signed by someone else is accepted: anyone who has your public key can send
you one. This puts identity in front of both routes, as in
[solution 08](../08-api-key/), and keeps the crypto as it is.

**Encrypt one field only.** Set `field` on the encrypt block to the field's
path, for example `"field":"accountNumber"`. Only that field is encrypted, and the
rest of the document stays readable JSON. `include_full_body` controls this and
is on by default; set it to `false` and the response is only that field's
encrypted value.

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
| `pgp-crypto` | `decrypt.passphrase` | `""` | Empty for an unprotected key. If your key has a passphrase, put it here: it is a second literal in the document, so keep the filled-in file out of version control. A missing or wrong passphrase makes every inbound request fail with 400. |
| `pgp-crypto` | `decrypt.fail_policy` / `fail_close_status` | `fail-close` / `400` | Refuse a body that cannot be decrypted; the backend is not called. |
| `pgp-crypto` | `encrypt.target` / `encrypt.source` | `response` / `body` | Encrypt the whole response body. `field` isn't set: with it, only that field would be encrypted and the rest would stay readable. |
| `pgp-crypto` | `encrypt.public_key` | `<PGP_PUBLIC_KEY>` | **Your partner's** armored public key, used verbatim. |
| `pgp-crypto` | `encrypt.fail_policy` / `fail_close_status` | `fail-close` / `500` | Never send the statement unencrypted. When the key itself can't be used, the caller gets 200 with `fail_close_message` in the body instead of 500. |
| `pgp-crypto` | `max_body_size` | `1048576` (1 MiB) | The crypto buffers the whole body; larger bodies are rejected, not streamed. |
| `pgp-crypto` | `gpg_timeout_ms` | `5000` | Time limit for the `gpg` fallback path. |
| `proxy-rewrite` | `uri` | `/post` (inbound), `/json` (outbound) | The backend's paths. |
| `request-id` | `algorithm` / `header_name` | `uuid` / `X-Request-Id` | API-wide. Errors are vague; this is what a partner quotes. |

**Other `pgp-crypto` settings** the example doesn't use:

| Setting | What it does |
|---|---|
| `field` | Encrypts or decrypts one field instead of the whole body: a dotted path into the JSON body, or a header, query or form name. |
| `include_full_body` | With `field` on a body, keeps the rest of the JSON and replaces only that field. On by default; when `false`, the body becomes just that field's value. |
| `decode_base64` | Encrypting a response only. For a backend that already returns base64: the gateway decodes it before encrypting. The output is still base64 of the encrypted message. Off by default. |
| A key per caller | `public_key`, `private_key` and `passphrase` can name a value instead of holding one, such as `$consumer.public_key`, so each partner gets its own key. [Solution 14](../14-per-partner-pgp-keys/) shows how. |

> **`private_key` and `public_key` are used verbatim, and so is `passphrase`.**
> The gateway does not resolve `<ENV:...>` or `${...}`. Replace the placeholders
> with real armored blocks before deploying, and keep the filled-in spec out of
> version control. The control plane stores these fields encrypted once supplied,
> but they still travel in the document you import and still sit in the revision
> you can read back.

This is the same kind of risk as `signing_secret` in
[solution 02](../02-oauth-jwt/), and worse: a private key outlives a signing secret
and is usually shared with a partner.

Placeholders in this package: `<PGP_PRIVATE_KEY>`, `<PGP_PUBLIC_KEY>`,
`<PGP_PASSPHRASE>` (the agent prompt only; the spec ships `passphrase` empty),
`<ORG_ID>`, `<TEST_ENV_ID>`, `<API_ID>`, `<REVISION_ID>`, `<UPSTREAM_ID>`,
`<YOUR_CONTROL_PLANE_API>`, `<YOUR_GATEWAY_HOST>`. Replace all of them before you
deploy.

Every field of every plugin: [docs.digitalapi.ai/api-gateway](https://docs.digitalapi.ai/api-gateway).

## Troubleshooting

- **Every inbound request is refused with 400, even a correctly encrypted one.**
  The partner is sending raw armor: the body must be base64 *of* the armor, and
  the error does not say so. Or the placeholder is still in `private_key`. Or the
  key is passphrase-protected and `decrypt.passphrase` is missing or wrong.
- **A 400 on inbound, with no further detail.** That is expected: every inbound
  failure gives the same 400 and the same message, whether the key is wrong, the
  format is wrong, the passphrase is wrong or the file is over `max_body_size`.
  The reason is in the gateway's telemetry; ask for the `X-Request-Id`.
- **Every statement request returns 200 with
  `{"message":"statement could not be encrypted"}`.** The statement could not be
  encrypted, and the caller gets your `fail_close_message` with a 200, not the
  500 in `fail_close_status`. A client that only checks the status code thinks
  it worked, so check the body. The placeholder is still in `public_key`, or the
  public key can't be read, or it has no encryption subkey (what
  `gpg --quick-generate-key` makes when you name an algorithm such as `rsa3072`).
  [Get the keys](#get-the-keys) shows how to check for the subkey.
- **The partner cannot decrypt a response that looks perfect.** It was encrypted
  to the wrong public key. Nothing at the gateway shows this; only a round-trip
  test finds it.
- **Part of the statement comes back readable.** `field` was set on the encrypt
  block, so only that field is encrypted. Remove it to encrypt the whole
  statement, or ask the agent to.
- **The response is a short ciphertext and the rest of the document is gone.**
  `field` is set and `include_full_body` is `false`. Remove `field` to encrypt
  the whole statement.
- **A file from someone you don't know is accepted.** The gateway doesn't check
  who sent or signed a file: anyone who has your public key can send one. Put an
  API key in front: [Only callers we know](#variations).
- **A statement comes back readable.** `fail_policy` is `fail-open` on the
  encrypt block, and encryption failed. Set `fail-close`.
- **The month-end batch fails, and everything else works.** The body exceeded
  `max_body_size` (1 MiB here). The 400 and its message are the same as for any
  other failure, so check the file size first. Raise the limit deliberately,
  with the memory cost in mind.
- **Messages encrypted to the old key fail after a key change.** Changing the key
  on a route is a hard cutover. Agree the switch with the partner, or move the
  key to a store: [solution 14](../14-per-partner-pgp-keys/).
- **Deploy fails: `Only INACTIVE revisions can be updated`.** Clone the revision
  or undeploy, then apply.
- **`GET /statements/<id>` returns `404 Route Not Found`, and the inbound route
  works.** The agent stored the path as `/statements/{statementId}`. Change it to
  `/statements/:statementId`.
- **The agent says the gateway has no PGP plugin, and offers JWE or a backend
  change.** It didn't look `pgp-crypto` up. Keep the sentence in the prompt that
  names it, or import the spec.
- **A route write fails, or the session drops, and no route is stored.** The keys
  were pasted into the prompt, and the write was too large to send. Use the
  placeholders.
- **A route write ends in `stream closed with reason: error`.** The agent's tool
  arguments arrived malformed, and nothing was written. Retry once, then import
  the spec.
- **The agent writes `pgp-crypto` flat, with no `encrypt` or `decrypt` block.**
  Reply: "it's nested — show me the route object as JSON before sending."
- **The agent offers to generate a key pair.** Decline. Keep the placeholders,
  and paste your real keys in the console yourself.
- **The routes exist with no plugins, though the agent reported success.** The
  agent wrapped the plugins in `x-helix-gateway` inside the live route object,
  which a live route silently discards. Read the revision back, and rewrite them
  under a top-level `plugins` key.
- **Use the trace inspector to see each step.** On the API's page, open the
  **Observability** tab and click **Start trace session**. It shows the headers
  each plugin changes and the request body at every stage, which is the fastest
  way to see what each plugin did to a call. A session stops after 10 requests,
  so use **Advanced: filter which requests to capture** to record only the ones
  you care about (skipped requests don't count). The list doesn't refresh by
  itself: click **Refresh**. The **Inspector** shows API keys and cookies in
  plain text, so don't share your screen or paste a trace into a ticket without
  removing them. A compressed response, which browsers always ask for, is
  unreadable in the **Response** tab, so call the API with curl to read it. The
  **Upstream** tab's **Total** adds connect time to response time, so it can be
  larger than the request's own total.
- **See what changed, and when, in Audit Logs.** **Observability → Audit Logs**
  lists every clone, plugin change and deploy. Its times are in your local time,
  while analytics uses UTC. Anything done with your token, including scripts and
  the Helix Agent, appears under your name.
