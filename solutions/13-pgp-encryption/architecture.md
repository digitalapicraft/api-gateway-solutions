# Architecture — crypto as a property of the path

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
