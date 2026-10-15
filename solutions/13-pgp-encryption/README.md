# Solution 13 — PGP at the edge, so the keyring script can go

**The partner will only accept encrypted payloads and only sends encrypted ones
back. Today that is a Python script with a keyring on a VM, and it is the thing
that breaks at 2am.**

| | |
|---|---|
| **Setup time** | ~20 minutes |
| **Difficulty** | 🟡 Intermediate — you supply a key pair |
| **Needs** | A fresh org (its default **test** environment) · an OpenPGP key pair. The upstream echoes requests, so the decrypted plaintext is visible without a backend of your own. |
| **Plugins** | `pgp-crypto` (encrypt + decrypt) · `proxy-rewrite` · `request-id` |
| **Build it with** | 🤖 **[the Helix Agent](helix-agent-prompt.md)** — recommended · or import [`example/api-spec.yaml`](example/api-spec.yaml) |
| **Assets** | ✅ [Agent prompt](helix-agent-prompt.md) · ✅ [Architecture](architecture.md) · ✅ [Business need](business-need.md) · ✅ [Spec](example/) · ✅ [Tests](tests/) · ✅ [Manifest](solution.yaml) |

---

## The problem

> *"Our settlement partner is a bank. They will only accept PGP-encrypted
> instruction files, and everything they send us comes back encrypted. So between
> their endpoint and our service there is a Python script on a VM with a keyring on
> it, written by someone who left in 2022. It decrypts, forwards, re-encrypts. It
> is not in our deployment pipeline, it is not in our monitoring, and it is the
> thing that pages us at two in the morning on the last working day of the month."*

The crypto is not the problem. Nobody is arguing about OpenPGP. The problem is
*where* it lives:

1. **It is a service nobody owns.** It exists because two systems could not talk,
   not because anyone decided to build it.
2. **It holds the keys.** A VM with a keyring is the most sensitive asset in the
   integration and usually the least governed one.
3. **It is not in any of your controls.** No pipeline, no dashboard, no runbook —
   and the month-end batch is when you find that out.

**Root cause:** a wire-format concern is being solved by an application. Nothing
about decrypting a payload needs to know what the payload means, so nothing about
it needs to live in something that does.

## Business need

The thirty-second version: [`business-need.md`](business-need.md).

| Dimension | A keyring script on a VM | Crypto at the edge |
|---|---|---|
| **Who owns it** | Nobody — it was a workaround | The platform team, with everything else on the path |
| **Where the keys live** | On a VM, in a home directory | In the gateway's configuration, encrypted at rest by the control plane |
| **In the deployment pipeline** | No | Yes — it is a revision |
| **In monitoring** | No | Yes — the same telemetry as every other route |
| **Backend change to adopt** | — | None. The backend handles plaintext, as it always did |
| **What breaks at 2am** | A VM nobody has logged into for a year | The same thing that would break for any route |

## How a request flows

```mermaid
sequenceDiagram
    autonumber
    participant P as Partner
    participant GW as Gateway
    participant UP as Backend

    Note over P,GW: Inbound — the partner encrypts to your key
    P->>GW: POST /statements/inbound<br/>base64( armored PGP )
    alt decrypts cleanly
        Note over GW: pgp-crypto decrypt, target request
        GW->>UP: POST /post<br/>plaintext, content-type application/json
        UP-->>GW: 200
        GW-->>P: 200
    else not decryptable
        GW--xP: 400 — fail-close, the backend is never called
    end

    Note over P,GW: Outbound — you encrypt to the partner's key
    P->>GW: GET /statements/2024-Q1
    GW->>UP: GET /json
    UP-->>GW: 200 plaintext statement
    Note over GW: pgp-crypto encrypt, target response
    GW-->>P: 200 text/plain<br/>base64( armored PGP )
```

The backend never handles ciphertext. The partner never handles plaintext. Neither
side changes.

## Which key goes where — the two sides of the exchange

The two directions are not a round trip, and the single most common way to
misconfigure this is to treat them as one. **Encryption is always *to the
recipient***, so each direction uses a different key — and in a real integration,
a different key *pair*, held by a different party.

| | Your side — this package | Their side |
|---|---|---|
| **Sending** them a statement | `encrypt.public_key` = **their** public key | they decrypt with their private key |
| **Receiving** their instruction | `decrypt.private_key` = **your** private key | they encrypt to your public key |

Four key halves across two parties. You generate one pair and publish its public
half to them; they generate one and publish theirs to you. **You never hold their
private half, and they never hold yours** — which is the whole point of the
scheme, and why the two placeholders in the spec are not a pair:

```yaml
decrypt:
  private_key: "<PGP_PRIVATE_KEY>"   # YOURS.   They encrypt to its public half.
encrypt:
  public_key:  "<PGP_PUBLIC_KEY>"    # THEIRS.  You never see its private half.
```

If your counterparty's integration guide reads like the mirror image of yours,
you have it right.

### What their side looks like

This is the part most write-ups leave out, and it splits by whether your
counterparty runs a gateway too.

**If they do**, their spec is this one with the keys swapped and the directions
reversed — their outbound is your inbound:

```yaml
# THEIR gateway, mirroring yours
decrypt:                                 # they receive what you sent
  target: request
  private_key: "<THEIR_PRIVATE_KEY>"     # the pair whose public half you hold
encrypt:                                 # they send to you
  target: response
  public_key: "<YOUR_PUBLIC_KEY>"        # the public half of your decrypt key
```

**If they don't** — which is the common case, and usually means a scheduled job
with `gpg` on it — then "their config" is two commands and one file from you:

```bash
# once: import the public key YOU published to them
gpg --import your-org-public.asc

# sending you an instruction — encrypt to YOUR key, then base64 the armor
gpg --armor --encrypt -r ops@your-org.example -o msg.asc instruction.json
base64 -i msg.asc | tr -d '\n' > msg.b64        # the wire format, see below

# reading a statement you sent them — decrypt with THEIR private key
curl -s "$GW/statements/2024-Q1" | base64 -d | gpg --decrypt
```

Note the asymmetry that catches people: they encrypt with **your** public key and
decrypt with **their** private key, in the same integration, minutes apart. The
key they reach for depends on the direction, not on who they are.

### The note to send them

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
> you need a `sub` row containing `e`. `gpg --quick-generate-key "<uid>" default
> default 2y` creates one; naming an algorithm such as `rsa3072` in place of the
> first `default` does not. Add one with `gpg --quick-add-key <fpr> rsa3072 encr 2y`.
>
> **On failure** you will get a 400 with a generic message — the reason is in our
> logs, not your response. Quote the `X-Request-Id` header and we will look.

### What happens if you fill both from one pair

You get a loop — and it is genuinely useful, as long as you know what it is not.

With one pair in both fields, the outbound route encrypts to a key the inbound
route can decrypt, so the GET's own output feeds straight into the POST:

```bash
# encrypt direction — the gateway encrypts the backend's statement
curl -s "$GW/statements/2024-Q1" > out.b64

# decrypt direction — the gateway decrypts it again
curl -s -X POST "$GW/statements/inbound" \
  -H 'content-type: text/plain' --data-binary @out.b64
```

Two calls, no `gpg`, nothing to import, and it exercises both plugin directions.
The echoed `Content-Type: application/json` on the POST is the tell that
decryption actually happened rather than the body passing through.

Two things it cannot do, both worth knowing before you rely on it:

- **It cannot catch a key mismatch.** With one pair the two fields can never
  disagree, so the loop passes by construction. To exercise that path, put a
  different public key in the encrypt block: the GET still returns a well-formed
  200 and the POST then fails closed with 400. That is the failure mode that is
  invisible from the gateway's side in a real two-party setup.
- **It is not how production behaves.** Piping a statement you sent into your own
  inbound route is a single-party demo. In a real integration that POST would be
  rejected, because the statement was encrypted to *their* key and your inbound
  route holds *yours*.

## The wire format is base64 of the armor

**Both directions use base64 of the ASCII-armored message — not the armor
itself.**

```
encrypt (response) : body becomes base64("-----BEGIN PGP MESSAGE-----…"), content-type text/plain
decrypt (request)  : body must ARRIVE base64-encoded
```

Every PGP tool on earth emits armor. Your counterparty will send armor. Verified
against a gateway: a raw armored body was **rejected**; the same message
base64-encoded decrypted cleanly and the plaintext reached the backend with
`content-type: application/json` — which the plugin sets.

The rejection message says nothing about base64, so put the extra step in the
integration guide you hand the partner, in bold, with an example. The test suite
asserts the rejection precisely so this stays documented.

## Two more behaviours worth knowing before you design around them

**`field` on an encrypt block selects what is *returned*, not just what is
encrypted.** Verified: encrypting with `field: slideshow.author` returned **only
the ciphertext of that value** as the entire response body — not the document with
one field replaced. If you want the surrounding document intact, encrypt the whole
body and let the partner decrypt the lot.

**Errors are generic on purpose.** The caller sees `failed to encrypt response` or
your `fail_close_message`, and nothing else. Unparseable key, wrong recipient, body
too large — all one message. That is correct (an error that describes your key
material is an error that helps an attacker) and it means a partner cannot
self-diagnose. Give them `X-Request-Id` and a support path.

## Configuration

Source of truth: [`example/api-spec.yaml`](example/api-spec.yaml).

Inbound:

```yaml
pgp-crypto:
  decrypt:
    target: request
    source: body
    private_key: "<PGP_PRIVATE_KEY>"
    fail_policy: fail-close
    fail_close_status: 400
```

Outbound:

```yaml
pgp-crypto:
  encrypt:
    target: response
    source: body
    public_key: "<PGP_PUBLIC_KEY>"
    fail_policy: fail-close
    fail_close_status: 500
```

**`fail-close` on both, and the reasons differ.** Inbound, forwarding a body the
gateway could not decrypt gives the backend ciphertext it cannot read — or, with
`fail-open`, whatever arrived. Outbound, the failure mode of `fail-open` is
**returning the statement in the clear**, which is the incident this whole
solution exists to prevent. One of the tests asserts that no readable plaintext
survives in the response, and that is the test that catches someone switching the
policy "so it stops breaking".

### The key material is a literal, and that is the catch

> **⚠️ `private_key` and `public_key` are used verbatim.** The gateway does not
> resolve `<ENV:...>` or `${...}`. Replace the placeholders with real armored
> blocks before deploying, and keep the filled-in spec out of version control. The
> control plane stores these fields encrypted once supplied, but they still travel
> in the document you import and still sit in the revision you can read back.

This is the same class of footgun as `signing_secret` in
[solution 02](../02-oauth-jwt/), and worse: a private key outlives a signing
secret and is usually shared with a counterparty.

**If you have more than one counterparty, do not copy this route N times with N
key pairs.** Fourteen partners becomes fourteen routes, fourteen keys in the
document, and a deploy every time one of them rotates. Fetch the key per request
instead — [solution 14](../14-per-partner-pgp-keys/) does exactly that and keeps key
material out of the spec entirely.

## Get the keys

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
| Windows | [Gpg4win](https://www.gpg4win.org/), then use `gpg` from a terminal |

Check it with `gpg --version`.

**2. Generate your key pair.** Use a name and an address that identify the
integration, not a person:

```bash
gpg --quick-generate-key "Acme Statements <statements@acme.example>" default default 2y
```

It asks for a passphrase. Choose one; the gateway can hold it (step 5). The two
`default`s matter: they create an **encryption subkey** alongside the signing key.
Name an algorithm in their place, such as `rsa3072`, and you get no encryption
subkey, so nothing can be encrypted to the key.

**3. Check the encryption subkey.**

```bash
gpg --list-keys statements@acme.example
```

You need a `sub` line ending in **`[E]`**, such as `sub   cv25519 2026-10-15 [E]`.

**4. Export both halves as ASCII armor.**

```bash
gpg --armor --export statements@acme.example > acme-public.asc               # send to the partner
gpg --armor --export-secret-keys statements@acme.example > acme-private.asc  # goes into the gateway
```

The second command asks for your passphrase. `acme-private.asc` begins with
`-----BEGIN PGP PRIVATE KEY BLOCK-----`; never send it to anyone.

**5. Put the keys into the routes.** In the console, open each route's
`pgp-crypto` configuration:

| Field | Paste |
|---|---|
| inbound route, `decrypt.private_key` | the whole of `acme-private.asc`, from `-----BEGIN` to `-----END` |
| inbound route, `decrypt.passphrase` | the passphrase from step 2; leave it out if you chose none |
| statement route, `encrypt.public_key` | the whole of the partner's public key file |

Before you paste the partner's key, check that it has an encryption subkey too:
`gpg --show-keys partner-public.asc` should show a `sub` line ending in `[E]`.

**6. Remove the exported private key file** once it is in the gateway:
`rm acme-private.asc`. The key also stays in your local keyring. Keep it there,
or in your secrets store, for rotation and recovery.

The gateway runs `gpg` itself, so any key `gpg` can use works. This package has
been verified with RSA keys (2048 and 3072) and with the ed25519/cv25519 pair the
command above produces, with and without a passphrase. If your partner insists on
RSA, generate with `rsa3072 sign 2y`, then add the subkey:
`gpg --quick-add-key <fingerprint> rsa3072 encr 2y`.

### Try it with throwaway keys

No partner yet? Make both pairs in a temporary keyring, so nothing touches your
real one. These keys have no passphrase and expire in a day:

```bash
export GNUPGHOME="$(mktemp -d)"
gpg --batch --passphrase '' --quick-generate-key "Statements Ours <ours@example.test>" default default 1d
gpg --batch --passphrase '' --quick-generate-key "Bank Partner <partner@example.test>" default default 1d
gpg --armor --export-secret-keys ours@example.test > ours-private.asc   # -> decrypt.private_key
gpg --armor --export partner@example.test > partner-public.asc          # -> encrypt.public_key
```

Paste the two files into the routes as in step 5, with no passphrase. Then run
the full test from the same shell, so it can play the partner:

```bash
GATEWAY=https://<YOUR_GATEWAY_HOST> RECIPIENT=ours@example.test ./example/verify.sh
```

When you're done: `gpgconf --kill gpg-agent; rm -rf "$GNUPGHOME" ours-private.asc partner-public.asc`.

## Build it with the Helix Agent

Recommended path, about twenty minutes. The whole build is **one prompt**:
[`helix-agent-prompt.md`](helix-agent-prompt.md). Paste it as a single message and
replace the `{{...}}` values. **Leave `<PGP_PRIVATE_KEY>` and `<PGP_PUBLIC_KEY>` as
written.** When the routes exist, paste your real ASCII-armored keys over them in
the console, as in [Get the keys](#get-the-keys), then deploy. Run
[`example/verify.sh`](example/verify.sh) as under
[Testing](#testing). [AGENT-GUIDE.md](../../AGENT-GUIDE.md) carries the standing
rules the prompt assumes.

> **Check what was stored, not what the agent said.** Read the revision back. The
> statement route's path must be **`/statements/:statementId`**. The 2026-10-14
> build stored `/statements/{statementId}`, though the prompt wrote `:statementId`.
> That path matches only the literal text `{statementId}`, so every real id gets
> `404 Route Not Found`, and the dry-run doesn't catch it. Each route should carry
> `pgp-crypto`: a `decrypt` block with `fail_close_status: 400` on the inbound
> route, and an `encrypt` block with `fail_close_status: 500` and **no `field`** on
> the statement route. Both key fields should hold your armored keys, not the
> placeholders.

### Why the prompt is worded the way it is

The prompt describes the exchange the way the integration team would: what the
partner sends, what the backend must see, and what happens when the crypto
fails. Three choices carry the weight:

- **It names `pgp-crypto`.** That is the only plugin name in the prompt. Without
  it, the 2026-10-14 agent said the gateway has no PGP plugin and offered JWE or
  a backend change instead. The plugin exists, but the agent doesn't find it
  unless it is named.
- **The keys are placeholders, not pasted in.** An earlier wording passed the
  armored keys in the prompt. The resulting route write was too large to send,
  and it failed three times out of three, with nothing usable stored. Placeholders
  also keep your private key out of the conversation.
- **The failure outcomes are statuses.** "Refused with a 400" and "a 500, never the
  plaintext" become `fail-close` with those statuses. "Encrypts the whole
  response" is what keeps `field` off the encrypt block: `field` returns only that
  field's ciphertext and drops the rest of the document.

### What the agent decides for you

| | The prompt says | This package's spec | The 2026-10-14 run |
|---|---|---|---|
| Failure messages | nothing | "request body is not a PGP message this gateway can decrypt" · "statement could not be encrypted" | "Request body is not a decryptable PGP message" · "Response could not be encrypted" |
| Correlation id | nothing | `request-id`, API-wide | `request-id`, API-wide |
| Route names | nothing | from the spec's operations | `post-inbound-statement`, `get-statement-by-id` |

None of these change the behaviour. The path syntax, the two blocks and the
fail-close statuses do.

## Variations

Follow-ups for the same session, once the build above is standing. Use the same
register as the prompt and say what you want to be true.

**Write the note for the partner**
```text
Write me the integration note to send our bank partner. Both directions carry
base64 of the ASCII-armored message, not the armor itself, and a raw armored body
is refused. Include a worked example of encrypting a file and base64-encoding it
before the POST.
```

**A second partner**
```text
We're adding a second bank, {{second_partner_name}}, with its own key pair. Tell me
what this design costs at two partners and at twenty, and show me the version that
picks the key per partner instead.
```
That is [14](../14-per-partner-pgp-keys/).

**Rotate our private key**
```text
Our private key is being rotated on {{rotation_date}}. Tell me what happens to
messages the partner encrypted to the old key, and the order to do the change in.
```

**Only callers we know**
```text
Require an app's API key in the X-Api-Key header on both routes, and keep the
crypto exactly as it is. Then create a developer, a product and an app, and give me
the key.
```
That is [08](../08-api-key/).

## When the agent goes wrong

**Read the stored revision before you trust any of it.**

| Symptom | Cause |
|---|---|
| The agent says the gateway has no PGP plugin, and offers JWE or a backend change | It didn't look `pgp-crypto` up (seen 2026-10-14). Keep the sentence naming it, or import the spec. |
| `GET /statements/<id>` returns `404 Route Not Found`, and the inbound route works | The path was stored as `/statements/{statementId}` (seen 2026-10-14). Change it to `/statements/:statementId`. |
| The route write fails, or the session drops, with no route stored | The keys were pasted into the prompt, and the write was too large to send (seen 2026-10-14). Use the placeholders. |
| Every inbound request is refused with 400, even a correctly encrypted one | The body is raw armor, not base64 of the armor; or the placeholder is still in `private_key`. |
| Every statement request returns 500 | The placeholder is still in `public_key`, or the key doesn't parse. |
| The response is a short ciphertext instead of the whole statement | `field` was set on the encrypt block. Remove it. |
| A statement comes back in plaintext | `fail_policy: fail-open` on the encrypt block. Set `fail-close`. |
| The routes exist with **no plugins**, at exit 0 | The agent wrapped them in `x-helix-gateway` inside the live route object, which a live route silently discards. |
| Deploy fails: `Only INACTIVE revisions can be updated` | Clone the revision or undeploy, then apply. |

## Install it directly

```bash
export ORG=<ORG_ID>
export TOKEN=<control-plane bearer token>      # short-lived
export BASE=https://<YOUR_GATEWAY_HOST>/api

# 1. Replace <PGP_PRIVATE_KEY> and <PGP_PUBLIC_KEY> with real armored blocks.
#    Do NOT commit the filled-in file.
# 2. Import example/api-spec.yaml, bind your backend, deploy the revision to "test".
# 3. Prove it — cases 1-4 need only bash, curl and base64:
GATEWAY=https://<YOUR_GATEWAY_HOST> ./example/verify.sh
#    Add the round trip when you have keys to hand:
GATEWAY=https://<YOUR_GATEWAY_HOST> \
GNUPGHOME=/path/to/keyring RECIPIENT=partner@example.com ./example/verify.sh
```

## Testing

Exit 0 means all of these held:

| # | Case | Expected |
|---|---|---|
| 1 | The statement route | `200`, `text/plain`, body is **base64 of armor** |
| 2 | **No readable plaintext in the response** | nothing of the document survives |
| 3 | **A raw armored request body** | `400` — the wire format is base64 of armor |
| 4 | A plaintext request body | `400`, and the backend never called |
| 5 | base64(armored) inbound | `200`, and the backend received the plaintext |
| 6 | The statement, decrypted | round-trips to the backend's document |

**Cases 1-4 need nothing but bash, curl and base64**, which is deliberate — they
are the ones worth running in a pipeline that holds no key material. Case 2 is the
one that catches a `fail-open` policy quietly returning the statement in the clear.
Case 6 is the only one that proves the *right* recipient key was used: encrypting
to the wrong public key passes every other check and produces a document the
partner cannot read.

## Gotchas

- **base64 of armor, both directions.** Not armor. The error message does not say
  so.
- **`field` on an encrypt block discards the rest of the document.** Verified.
- **Errors are generic.** Unparseable key, wrong recipient and oversized body all
  look identical to the caller.
- **The key material is a literal in the document.** No `<ENV:...>` resolution.
- **Encrypting to the wrong public key is invisible from the gateway's side.** Only
  a round-trip test catches it.
- **`fail-open` on the response direction returns the plaintext.** Do not.
- **Rotation is a hard cutover.** Old and new keys cannot both be live on one
  route. [Solution 14](../14-per-partner-pgp-keys/) turns this into a data change.
- **Crypto buffers the whole body.** `max_body_size` rejects rather than streams;
  month-end batch files are how people discover this.
- **Encryption is not authentication.** Anyone who can reach the route gets a
  document they cannot read — which is not the same as being refused. Put
  [solution 08](../08-api-key/) in front.
- **Encryption is not signing.** This gives confidentiality. It does not prove who
  sent the message; for that see [solution 06](../06-hmac-auth/).

## When to use it

Use it when:

- A counterparty's contract specifies PGP and the backend cannot or should not
  handle it.
- There is already a script doing this, owned by nobody.
- Payloads must be encrypted at rest beyond the gateway, or in a queue.
- You want the crypto inside the same pipeline, telemetry and review process as the
  rest of the path.

Don't use it when:

- **TLS is enough.** If the requirement is confidentiality in transit and nothing
  more, this adds key management for no gain.
- **You need to prove who sent it.** That is a signature —
  [solution 06](../06-hmac-auth/).
- **You have many counterparties.** Use [solution 14](../14-per-partner-pgp-keys/) rather
  than N routes with N key pairs.
- **The payloads are large.** Crypto buffers the body and costs CPU per request.
- **The backend must never see plaintext.** This decrypts *for* the backend. If the
  backend is the thing you are protecting the data from, the crypto belongs
  further in.

## Limitations

- **base64-of-armor in both directions**, which no standard PGP tool produces by
  default.
- **`field` on encrypt returns only that field's ciphertext.**
- **Key material is a literal in the document**, with no environment indirection.
- **Rotation is a hard cutover** on a route.
- **One key pair per route**, hence [solution 14](../14-per-partner-pgp-keys/).
- **Generic errors** to the caller, by design.
- **A wrong recipient key is undetectable at the gateway.**
- **Whole-body buffering**, bounded by `max_body_size`.
- **Confidentiality only** — no sender authentication, no signing, no
  non-repudiation.
- **Not authentication.** Reaching the route is not the same as being entitled to.
- **Whether *your* key material parses was never tested here.** Validation used
  a throwaway key pair. A key that doesn't parse is a runtime failure, not a
  config error, and it won't show up in a dry-run.

Full list: [`solution.yaml`](solution.yaml) § `limitations`.

## Validation status

**Validated against a gateway — imported, dry-run, deployed, and exercised.**

| Stage | Status | Provenance |
|---|---|---|
| Configuration generated | **YES** | [`example/api-spec.yaml`](example/api-spec.yaml) |
| Local validation | **PASS** | Structural review of the spec and tests |
| Gateway dry-run | **PASS** | Non-destructive, against a temporary import. |
| Gateway deployed | **DEPLOYED** | Revision ACTIVE in a test environment, with a throwaway RSA-3072 key pair. |
| Functional tests | **PASS (7/7)** | Both directions, both rejection cases, and the full round trip. |
| Agent-mode run, current wording | **PASS after two hand fixes (config + functional)**, 2026-10-14, `tencent/hy3` | The prompt as shipped, run once. Both routes stored `pgp-crypto` as asked: `decrypt` fail-close 400 inbound, `encrypt` fail-close 500 on the statement route, no `field`, placeholders verbatim, `request-id` API-wide. The agent stopped before deploying and asked whether the keys were in. **The statement path was stored as `/statements/{statementId}`**: as built, a real id returned 404. With throwaway keys pasted over the placeholders and the path corrected to `/:statementId`, `verify.sh` passed **7/7**, including the round trip both ways. The routes ran under an `/agentrun-13` prefix, because this package's reference API holds the bare paths in that environment |
| Agent-mode run, plugin not named | **FAIL**, 2026-10-14, `tencent/hy3` | The same prompt without the sentence naming `pgp-crypto`. The agent said the gateway has no PGP plugin and offered JWE or a backend change. Nothing was built |
| Agent-mode run, keys in the prompt | **FAIL**, 2026-10-14, `tencent/hy3` | The armored keys pasted into the prompt. The route write was refused three times out of three; nothing usable was stored |

Overall: **READY.** The wire format and the `field` behaviour were established by
running them, not by reading the schema. The agent builds the crypto correctly
from the shipped prompt; check the statement path, as above, before you deploy.

## Related solutions

- **[14 — Per-partner PGP keys](../14-per-partner-pgp-keys/)** — the same crypto with the key
  fetched per request. Go there the moment you have a second counterparty.
- **[06 — Signed requests](../06-hmac-auth/)** — confidentiality is not
  authenticity. If you need to know who sent it, you need a signature.
- **[08 — API keys](../08-api-key/)** — this package ships unauthenticated so the
  crypto is the only behaviour under test.
