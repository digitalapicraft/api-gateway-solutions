# Test & verify — Solution 13 — PGP at the edge, so the keyring script can go

[Overview](readme.md) · [Business need](business-need.md) · [How it works](how-it-works.md) · [Install](install.md) · [Configuration](configuration.md) · **Test & verify** · [Changelog](changelog.md)

---

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
