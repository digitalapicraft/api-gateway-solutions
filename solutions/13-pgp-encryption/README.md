# Solution 13 — PGP encryption: encrypt and decrypt partner files at the gateway

> **Overview** · [Business need](business-need.md) · [Architecture](architecture.md) · [Guides](guides.md) · [Agent prompt](helix-agent-prompt.md) · [Tests](tests.md) · [API reference](api-reference.md)

**In short:** when a partner insists on PGP-encrypted files in both directions,
let the gateway do the decrypting and encrypting, so neither your backend nor the
partner has to change, and no script on a server holds your keys.

| | |
|---|---|
| **Time to try it** | About 20 minutes |
| **Difficulty** | 🟡 Intermediate — you supply a key pair |
| **What you'll need** | A free test account (its default `test` environment) and an OpenPGP key pair. The upstream echoes requests, so you can see the decrypted text without a backend of your own. |

---

## What is PGP encryption at the gateway?

**PGP** (OpenPGP) is a long-standing standard for encrypting files and messages.
Each party has a **key pair**: a public key they hand out, and a private key they
keep. Anyone can encrypt a message *to* you with your public key; only your
private key can decrypt it.

Think of a padlock. You give your partner open padlocks (your public key). They
lock a box with one and send it. Only you have the key that opens it (your private
key). They do the same for you in the other direction.

Here the gateway does both jobs on the path the traffic already takes:

- **Inbound:** the partner sends an encrypted file. The gateway decrypts it with
  your private key and passes the plain content to your backend.
- **Outbound:** your backend returns a plain document. The gateway encrypts it to
  the partner's public key before it leaves.

## The use case

> *"Our settlement partner is a bank. They will only accept PGP-encrypted
> instruction files, and everything they send us comes back encrypted. So between
> their endpoint and our service there is a Python script on a VM with a keyring on
> it, written by someone who left in 2022. It decrypts, forwards, re-encrypts. It
> is not in our deployment pipeline and it is not in our monitoring."*

The encryption itself is not the problem. *Where it lives* is:

- **It is a service nobody owns.** It exists because two systems could not talk,
  not because anyone decided to build it.
- **It holds the keys.** A server with a keyring is the most sensitive part of the
  integration, and usually the least looked after.
- **It sits outside your usual controls** — no pipeline, no dashboard, no runbook —
  and you find that out during the month-end batch.

## What PGP at the gateway gives you

- **Decryption on the way in.** Your backend receives plain content, as it always
  has.
- **Encryption on the way out.** The partner receives an encrypted file, as the
  contract says.
- **Refusal, not leakage.** If a file cannot be decrypted, the backend is never
  called; if a response cannot be encrypted, it is not sent in the clear.
- **No change on either side.** Neither your backend nor the partner changes
  anything.

## Benefits

- **The keys leave the server nobody owns.** They live in the gateway's
  configuration, stored encrypted by the control plane, under the same access
  control as everything else.
- **Changes become reviewed revisions**, dry-run and rolled back like any other
  change.
- **Failures show up where you already look** — the same dashboards and request ids
  as every other route.
- **One less system to keep running.** The script, its server and its keyring can
  go.

## Example

Say your partner sends you instruction files and you send them statements:

| Request | What the gateway does | What comes back |
|---|---|---|
| Partner posts an encrypted instruction to `POST /statements/inbound` | Decrypts it with your private key | Your backend receives the plain JSON; the partner gets **HTTP 200 (OK)** |
| Partner posts a file that is not encrypted, or is in the wrong format | Cannot decrypt it | **HTTP 400 (bad request)**, and your backend is never called |
| Partner asks for `GET /statements/2024-Q1` | Encrypts your backend's statement to the partner's public key | HTTP 200, an encrypted file only the partner can read |

One format detail catches everyone: the file travels as **base64 of the
ASCII-armored message**, not the armored message itself, in both directions. Tell
your partner that up front. [How →](guides.md#the-note-to-send-your-partner)

**Setting this up in the gateway's UI takes three short steps:** put your keys into
a local copy of the spec, import it, then give it an upstream and deploy it.
[Full click-by-click walkthrough →](guides.md#build-it-in-the-ui)

[Build it any of three ways, then see it work →](guides.md)

## Where to go next

- **Want the business case first?** [Business need](business-need.md) explains why
  this matters, in plain terms.
- **Want to understand how it works?** [Architecture](architecture.md) covers both
  directions, which key goes where, and what this does not protect.
- **Ready to build it?** [Guides](guides.md) walks you through it step by step.
- **Want the full product documentation?** Every plugin, screen and API call is
  covered at [docs.digitalapi.ai/api-gateway](https://docs.digitalapi.ai/api-gateway).

## Related solutions

- **[12 — Key-value map](../12-key-value-map/)** — the same encryption with each
  partner's key fetched per request. Go there the moment you have a second partner.
- **[06 — Signed requests](../06-hmac-auth/)** — encryption keeps a message secret;
  it does not prove who sent it. For that you need a signature.
- **[08 — API keys](../08-api-key/)** — this package ships without authentication
  so the encryption is the only behaviour under test. Put identity in front of it.
