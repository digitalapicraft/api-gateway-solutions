# How it works — Solution 13 — PGP at the edge, so the keyring script can go

[Overview](readme.md) · [Business need](business-need.md) · **How it works** · [Install](install.md) · [Configuration](configuration.md) · [Test & verify](testing.md) · [Changelog](changelog.md)

---

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
> you need a `sub` row containing `e`. `gpg --quick-generate-key` does **not**
> produce one; use `gpg --quick-add-key <fpr> rsa3072 encr never` to add it.
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

## Request path

```
Partner ──base64(armor)──▶ Gateway ──plaintext──▶ Backend
                              │
                              ├── request-id   (API-wide, correlation)
                              ├── pgp-crypto   (priority 898)
                              │     decrypt: target request  (inbound route)
                              │     encrypt: target response (outbound route)
                              └── proxy-rewrite (rewrite phase — path only)

Partner ◀──base64(armor)── Gateway ◀──plaintext── Backend
```

- **Inbound**: the body arrives as base64 of an ASCII-armored PGP message. The
  plugin decodes, decrypts, replaces the request body with the plaintext, and sets
  `content-type: application/json` on the upstream call. The backend handles
  plaintext, exactly as it always has.
- **Outbound**: the backend returns its ordinary document. The plugin encrypts it
  to the configured public key and replaces the response body with base64 of the
  armored message, setting `content-type: text/plain`.

The implementation runs in-process, with a `gpg` binary as a fallback for material
the in-process path does not cover. That matters operationally in one way: the
crypto happens on the gateway's own CPU and is bounded by `max_body_size` and
`gpg_timeout_ms` rather than by a separate service's capacity.

## Native vs custom

Native, and the alternative is the status quo: a small service in the middle that
decrypts and forwards.

| | A keyring service | `pgp-crypto` at the edge |
|---|---|---|
| Ownership | Whoever wrote it, usually gone | The team that owns the path |
| Key storage | A filesystem on a VM | Control-plane configuration, encrypted at rest |
| Change process | Manual | A revision: reviewed, dry-run, rollback-able |
| Observability | Its own, if any | The same telemetry as every other route |
| Failure mode | A box that is down | A route that returns a status code |
| Per-counterparty keys | A config file it reads | One key pair per route — see the limitation below |

The one place the custom service wins is the *many counterparties* case, because it
can look a key up per request. That capability exists here too, and it is
[solution 12](../12-key-value-map/) — the same plugin, with the key fetched from a
store instead of written into the route.

## Why `fail-close` on both directions, for different reasons

| Direction | `fail-open` would | Which is |
|---|---|---|
| Inbound | Forward whatever arrived — ciphertext the backend cannot parse, or an unencrypted body an attacker chose | A backend processing input it was never meant to see |
| Outbound | **Return the statement in the clear** | Precisely the incident this solution exists to prevent |

The outbound case is the sharper one, because `fail-open` is what somebody reaches
for when the route starts erroring. It stops erroring by publishing plaintext. One
of the automated tests asserts that no readable plaintext survives in the response
for exactly that reason.

## The wire format, and why it surprises people

Both directions use **base64 of the ASCII-armored message**, not the armor. Armor
is already a text encoding; base64 on top of it is a second one.

Practically, the consequence is that a counterparty following the OpenPGP standard
correctly will be rejected. Their tool emits armor; the gateway wants armor
wrapped in base64. This is a documentation and integration-guide problem, not a
configuration one — there is no setting that accepts bare armor — so the
integration note is part of the deliverable, and one test asserts the rejection so
that the requirement stays visible.

## Two parties, four halves

Before the per-route limitation below, the more fundamental shape: a PGP
integration is **two key pairs held by two parties**, and each party holds only
half of the other's.

```
        YOU                                   THEM
   ┌──────────────┐                     ┌──────────────┐
   │ your private │◀──they encrypt──────│ your public  │
   │ (decrypt in) │                     │ (they hold)  │
   ├──────────────┤                     ├──────────────┤
   │ their public │──you encrypt───────▶│ their private│
   │ (encrypt out)│                     │ (they hold)  │
   └──────────────┘                     └──────────────┘
```

Both of the fields on this route are therefore about *different* pairs:
`decrypt.private_key` is yours, `encrypt.public_key` is theirs. They are not a
pair and were never generated together. The most common misreading of this
package is to treat the two placeholders as one key pair, which works — in the
sense that it deploys and round-trips — and is not what a real integration looks
like.

The direction determines which key is used, not the identity of the party. Your
counterparty encrypts with your public key and decrypts with their private key,
in the same integration, minutes apart.

## One key pair per route, per direction

`private_key` and `public_key` are fields on the route's plugin configuration.
That means:

- Two counterparties with different keys need two routes — this is a *per-route*
  limit, distinct from the two-party structure above. One route serves one
  counterparty in both directions, using two different pairs to do it.
- Rotating a key is a configuration change and a deploy, and the old and new keys
  cannot both be live on the same route — a hard cutover that has to be
  coordinated with the counterparty.
- Every key pair is a literal in a document that somebody could commit.

For a single long-lived partner integration that is acceptable and simple. Past
the first counterparty it is the dominant cost of the design, which is why the
package points at [solution 12](../12-key-value-map/) before you get there rather
than after.

## When not to use this shape

- **TLS already meets the requirement** — this adds key management for no gain.
- **You need to know who sent it** — that is a signature, not encryption.
- **Many counterparties** — [solution 12](../12-key-value-map/).
- **Large payloads** — whole-body buffering, CPU per request.
- **The backend is the thing you are protecting the data from** — this decrypts
  *for* the backend.

## Failure modes and what they look like

| Symptom | Cause |
|---|---|
| Every inbound request rejected, counterparty insists the file is fine | They are sending raw armor; the gateway wants base64 of it |
| 400 on inbound, no further detail | Correct: errors are deliberately generic. The reason is in the gateway's telemetry |
| 500 on outbound | The response could not be encrypted — usually an unparseable public key |
| The partner cannot decrypt a response that looks perfect | Encrypted to the wrong public key. Invisible from the gateway; only a round-trip test finds it |
| The response body is a short ciphertext and the rest of the document is gone | `field` was set on the encrypt block. It selects what is returned, not just what is encrypted |
| Month-end batch fails, everything else works | The body exceeded `max_body_size` |
| The statement came back readable | `fail_policy` is `fail-open` and encryption failed |
