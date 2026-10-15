# Agent-mode prompt — PGP encryption and decryption at the gateway

Paste this to the Helix Agent as one message, replacing the `{{...}}` values. It
works from a fresh, empty org on a public upstream that echoes what it receives.
Leave `<PGP_PRIVATE_KEY>` and `<PGP_PUBLIC_KEY>` exactly as written: the agent puts
them in the configuration as placeholders, and you paste your real ASCII-armored
keys over them in the console afterwards, so no key passes through the chat.
[Get the keys](README.md#get-the-keys) shows how to make them. Why the
prompt is worded this way, what the agent decides on its own, and what to check
before you trust it are in the [README](README.md#build-it-with-the-helix-agent).

## Prompt

```text
Step 1:
Create a REST API called "{{api_name}}" in the {{environment}} environment, proxying
https://httpbin.org. Two routes: POST /statements/inbound, which the upstream
serves at /post, and GET /statements/:statementId, which it serves at /json. Keep
my paths.

Step 2:
Our bank partner exchanges statements with us as PGP-encrypted messages, and our
backend must only ever see plaintext. Update the routes so that:
- POST /statements/inbound decrypts the request body with our private key before
  it reaches the backend. A body that isn't a PGP message we can decrypt is
  refused with a 400.
- GET /statements/:statementId encrypts the whole response to the partner's public
  key. If it can't be encrypted, the caller gets a 500, never the plaintext.
Use the gateway's pgp-crypto plugin for both.
Write our private key as <PGP_PRIVATE_KEY> and the partner's public key as
<PGP_PUBLIC_KEY>, exactly like that. I'll paste the real keys in myself.
```
