# Configuration — Solution 06 — Signed requests: prove who is calling without sending a secret

[Overview](readme.md) · [Business need](business-need.md) · [How it works](how-it-works.md) · [Install](install.md) · **Configuration** · [Test & verify](testing.md) · [Changelog](changelog.md)

---

## Configuration

Two routes, two different signed sets, and that is the point.

| Route | `signed_headers` | `validate_request_body` | Why |
|---|---|---|---|
| `POST /posts` | `@request-target`, `date`, `digest` | `true` | There is a body, so the signature must cover it |
| `GET /posts/{postId}` | `@request-target`, `date` | `false` | No body. Requiring a digest of the empty string is ceremony, not security |

`hmac-auth` is therefore **per route, not at the document root** — a single root
block cannot express both. The cost is real: **a route added later with no
`x-helix-gateway` block is unauthenticated.** If you would rather fail safe, hoist
the `POST` block to the root and have bodyless callers send the digest of the
empty string, which is the constant
`SHA-256=47DEQpj8HBSa+/TImW+5JCeuQeRkm5NMpJWZG3hSuFU=`.

### `signed_headers` is the field that makes this secure

Everything else on the route is tuning. This one is load-bearing.

**Omit it and the *client* decides what its own signature covers.** A signature
over a base consisting of nothing but the `keyId` is valid, and that single
signature then authenticates **any body, any path, indefinitely** — `clock_skew`
does not even apply, because with no `date` in the signed set there is no `Date`
header to check.

`validate_request_body` does not save you. It compares `Digest` to the body it
received — but if `digest` is not in the signing base, the caller supplies the
body *and* the matching `Digest`, and both checks pass.

With `signed_headers` set, a request whose `headers` field omits any required
name is rejected *before the signature is checked*.
