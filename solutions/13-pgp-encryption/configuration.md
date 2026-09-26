# Configuration — Solution 13 — PGP at the edge, so the keyring script can go

[Overview](readme.md) · [Business need](business-need.md) · [How it works](how-it-works.md) · [Install](install.md) · **Configuration** · [Test & verify](testing.md) · [Changelog](changelog.md)

---

## The wire format will cost you an afternoon

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

## Configuration

Source of truth: [`gateway/api-spec.yaml`](gateway/api-spec.yaml).

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
instead — [solution 12](../12-key-value-map/) does exactly that and keeps key
material out of the spec entirely.
