# Tests — per-partner key material, fetched at request time

> [Overview](README.md) · [Business need](business-need.md) · [Architecture](architecture.md) · [Guides](guides.md) · [Agent prompt](helix-agent-prompt.md) · **Tests** · [API reference](api-reference.md)

---

9 test cases in total: **6 automated**, run by `example/verify.sh` against a live
deployment, and **3 manual**, for behaviour you have to set up deliberately (a
broken key, a typo, an open write path). The full machine-readable plan is
[`tests/test-plan.yaml`](tests/test-plan.yaml); this page is the readable
walkthrough of what it checks and why.

## Running the automated tests

```bash
GATEWAY=https://<YOUR_GATEWAY_HOST> \
PUBLIC_KEY_FILE=./partner-a-public.asc GNUPGHOME=~/.gnupg-partner-a \
SECOND_PUBLIC_KEY_FILE=./partner-a-rotated.asc SECOND_GNUPGHOME=~/.gnupg-partner-a2 \
./example/verify.sh
```

Only `GATEWAY` and `PUBLIC_KEY_FILE` are required. Checks 1–4 need nothing but
bash, curl, base64 and a public key, so they can run in a pipeline that holds no
private key material. Check 5 runs when `gpg` and `GNUPGHOME` (holding the matching
private key) are available; check 6 when the `SECOND_*` pair is set too. A skipped
check is announced, not silently passed.

**The script sends no operator key with its registration requests.** Every build
in [Guides](guides.md) protects the registration route before it is deployed, so
there check 2 gets HTTP 401 (not signed in) and the run stops. On a protected
deployment, make the same calls by hand with the operator's key, as in
[Guides → See it work](guides.md#see-it-work).

Exit code 0 means all of these held:

| # | Case | Expected |
|---|---|---|
| 1 | **A partner with no registered key** | `500` — and **no document**, in any form |
| 2 | Registering a key | `200` |
| 3 | That partner's document | `200`, body is base64 of an armored PGP message, and no readable JSON survives |
| 4 | **A different, unregistered partner** | still `500` — entries are kept per partner |
| 5 | Decrypting with that partner's private key | succeeds |
| 6 | **Re-registering, then fetching again** | the **new** key decrypts it; the old one cannot |

**Case 1 is the security case.** A 200 there means the document went out
unencrypted to a caller who was meant to receive ciphertext. **Case 6 is the whole
solution:** rotation with no revision, no route change and no deploy, checked rather
than claimed. Run it once per environment.

Case 2's status belongs to the echo upstream, not the store: the key is written
before the request is passed on. Case 3 is what actually confirms the write.

Case 5 is the only check that the *right* key was stored. Storing the wrong key
produces a response that passes every other case and that the partner cannot read.

Override the defaults with `REGISTER_PATH`, `DOCUMENT_PATH`, `PARTNER_ID`,
`ABSENT_ID` and `ID_HEADER` if your routes differ.

Raw fixtures, if you want to run one case by hand instead of the whole script:
[`tests/requests/`](tests/requests/) (the HTTP requests) and
[`tests/expected/`](tests/expected/) (the expected status and body for each — the
single source both `verify.sh` and the plan read from, so they can't drift apart).
The registration request there carries no operator key: add an `X-Admin-Key`
header with one before you send it to a protected route.

## The manual tests

| Case | What it proves | How to run it |
|---|---|---|
| **Unusable key registered** | A key that is stored but cannot encrypt returns **200 with the error body** — the same body an unregistered partner gets with a 500. A status-only check passes while no document is returned. | Make a key with no encryption subkey: `gpg --quick-generate-key <uid> rsa3072` does exactly this, as does any other named algorithm (the bare command, or `default default`, adds an encryption subkey). Register it under a fresh partner id, and fetch a document for that id. Expect 200 with `{"message":"no usable key is registered for this partner"}`. Repair with `gpg --quick-add-key <fpr> rsa3072 encr never` and register again. |
| **Reference typo** | The most likely configuration mistake gives no error anywhere. | In a **throwaway** environment, change one reference to `$request.header.x-partner-id` (singular) and call the document route. It fails exactly like "no key registered". |
| **Unauthenticated registration** | What the spec and the prompt do **not** protect, and that the protection step does. | Call the registration route with any partner id and your own public key, and no `X-Admin-Key`. Without the protection step it succeeds, and that partner's documents are then encrypted to *your* key: that is why every build adds the step before its first deploy ([Guides](guides.md#build-it-in-the-ui)). With it, expect HTTP 401, or HTTP 403 (not allowed) with an app key that isn't on the operators product, and the partner's documents unchanged. |

**Assert on the body in every test on the document route.** The automated fetch
case does, which is why it catches an unusable key and a status check would not.

Full procedures, plus the exact assertions each one makes:
[`tests/test-plan.yaml`](tests/test-plan.yaml).

## Coverage

| Type | Cases |
|---|---|
| Positive | key registered, document encrypted, decrypts with the partner's key, rotation without deploy |
| Negative | no key registered |
| Boundary | partner isolation |
| Failure | unusable key registered, reference typo, unauthenticated registration |
