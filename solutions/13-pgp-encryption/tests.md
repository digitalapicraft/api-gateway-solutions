# Tests — OpenPGP at the edge, in both directions

> [Overview](README.md) · [Business need](business-need.md) · [Architecture](architecture.md) · [Guides](guides.md) · [Agent prompt](helix-agent-prompt.md) · **Tests** · [API reference](api-reference.md)

---

10 test cases in total: **6 automated**, run by `example/verify.sh` against a live
deployment, and **4 manual**, for behaviour you have to set up deliberately (a
wrong key, an oversized file, a key change). The full machine-readable plan is
[`tests/test-plan.yaml`](tests/test-plan.yaml); this page is the readable
walkthrough of what it checks and why.

## Running the automated tests

```bash
# checks 1-4: nothing but bash, curl and base64
GATEWAY=https://<YOUR_GATEWAY_HOST> ./example/verify.sh

# add the round trip when you have keys to hand
GATEWAY=https://<YOUR_GATEWAY_HOST> \
GNUPGHOME=/path/to/keyring RECIPIENT=partner@example.com ./example/verify.sh
```

For the round trip, `GNUPGHOME` must hold the private key matching the route's
`public_key` and the public key matching the route's `private_key`; `RECIPIENT` is
the uid to encrypt the inbound test message to. Without `gpg` or those variables,
the round trip is skipped and announced, not silently passed. Override the paths
with `READ_PATH` (default `/statements/2024-Q1`) and `WRITE_PATH` (default
`/statements/inbound`).

Exit code 0 means all of these held:

| # | Case | Expected |
|---|---|---|
| 1 | The statement route | `200`, `text/plain`, body is **base64 of armor** |
| 2 | **No readable plaintext in the response** | nothing of the document survives |
| 3 | **A raw armored request body** | `400` — the wire format is base64 of armor |
| 4 | A plain-text request body | `400`, and the backend is never called |
| 5 | base64(armored) inbound | `200`, and the backend received the plain content |
| 6 | The statement, decrypted | round-trips to the backend's document |

**Cases 1–4 need nothing but bash, curl and base64,** which is deliberate: they
are the ones worth running in a pipeline that holds no key material. **Case 2** is
the one that catches a `fail-open` policy quietly returning the statement
unencrypted. **Case 3** keeps the wire format documented: it asserts what is
refused. **Case 6** is the only one that proves the *right* recipient key was used —
encrypting to the wrong public key passes every other check and produces a
document the partner cannot read.

Don't assert the ciphertext itself in your own tests; it differs on every request.
Check the content type, that the body base64-decodes, and that the decoded text
starts with `-----BEGIN PGP MESSAGE-----`.

Raw fixtures, if you want to run one case by hand instead of the whole script:
[`tests/requests/`](tests/requests/) (the HTTP requests) and
[`tests/expected/`](tests/expected/) (the expected status and body for each — the
single source both `verify.sh` and the plan read from, so they can't drift apart).

## The manual tests

Run these in a **throwaway** environment.

| Case | What it proves | How to run it |
|---|---|---|
| **Wrong recipient** | A key mismatch looks like success at the gateway. | Configure the encrypt route with a public key the partner does not hold the private half of. Call it and try to decrypt. Expect a well-formed 200 and a decryption failure at the partner. Case 6 is the only automated defence. |
| **Mismatched pair** | The two directions behave independently once the fields come from different pairs — which a one-pair demo can never show. | Put a public key in the encrypt block whose private half you do **not** hold, leaving `decrypt.private_key` alone. Fetch a statement and post it straight back to the inbound route. The GET returns a well-formed 200; the POST fails with 400. |
| **Oversized body** | What happens at `max_body_size` before a real file hits it. | Send an encrypted body larger than 1 MiB. It is rejected rather than processed. Raise the limit deliberately, with the memory cost in mind. |
| **Key rotation** | The rotation procedure, before a partner's key expires. | Replace the key material in the route and deploy a new revision. It is a hard cutover: messages encrypted to the old key fail after the switch. Agree it with the partner, or move the key to a store — [solution 12](../12-key-value-map/). |

Full procedures, plus the exact assertions each one makes:
[`tests/test-plan.yaml`](tests/test-plan.yaml).

## Coverage

| Type | Cases |
|---|---|
| Positive | statement encrypted, inbound decrypted, statement round trip |
| Negative | no plaintext survives, armored body, plain-text body |
| Boundary | oversized body, key rotation |
| Failure | wrong recipient, mismatched pair |
