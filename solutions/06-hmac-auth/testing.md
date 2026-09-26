# Test & verify — Solution 06 — Signed requests: prove who is calling without sending a secret

[Overview](readme.md) · [Business need](business-need.md) · [How it works](how-it-works.md) · [Install](install.md) · [Configuration](configuration.md) · **Test & verify** · [Changelog](changelog.md)

---

## What the caller actually sees

Every rejection is `401` with `WWW-Authenticate: hmac realm="partner-events"`.
The body depends on **where** the failure happened, and the split is not obvious:

| Failure | Body |
|---|---|
| No `Authorization` header | `{"message":"client request can't be validated: missing Authorization header"}` |
| Header does not start with `Signature` | `…: Authorization header does not start with 'Signature'` |
| **Everything else** — `keyId`/`signature` field absent, bad signature, bad digest, clock skew, unknown `key_id`, weak signed set | **`{"message":"client request can't be validated"}`** — and nothing more |

Exactly **two** failures are explained, and they are the two raised while *parsing*
the header. Everything raised while *validating* is collapsed, including
`keyId or signature missing` — which reads like a parsing error but is raised
after parsing succeeds, and so is opaque like the rest. (Verified by request
against a deployed route.) That is correct
security behaviour — the second group must not tell an attacker which check
failed — and it is genuinely hard for an honest integrator to self-diagnose. The
detail exists only in the gateway error log:

| Log line (from the plugin) | Cause |
|---|---|
| `Invalid signature` | The base does not match. Check the trailing newline and the `keyId` line first |
| `Invalid digest` | `Digest` disagrees with the body — or something re-encoded the body (see Gotchas) |
| `Clock skew exceeded` / `Date header missing` | `Date` absent, malformed, or outside `clock_skew` |
| `expected header "x" missing in signing` | The caller signed a weaker set than `signed_headers` requires |
| `Invalid key_id` | No credential with that `key_id` — wrong app, or wrong environment |
| `Invalid algorithm` | The `algorithm` field is outside `allowed_algorithms` |

Give integrators the `X-Request-Id` from the response and the correlation is a
single log lookup. That is why `request-id` is in this spec.

## Testing

[`gateway/verify.sh`](gateway/verify.sh) exits 0 only if all eight hold:

| # | Case | Expect |
|---|---|---|
| 1 | No signature | 401 |
| 2 | Correct signature | 201 |
| 3 | Body tampered after signing | 401 |
| 4 | `Date` 20 minutes old | 401 |
| 5 | Correct `key_id`, wrong secret | 401 |
| 6 | Caller signs a weaker set than required | 401 |
| 7 | **Byte-identical replay** | **201 — accepted again** |
| 8 | Signed `GET` on the read route | 200 |

**Case 6 is the one that matters.** Delete `signed_headers` from the route and it
passes — everything else still passes too, and the API is wide open. It is the
only case that tests your *configuration* rather than the plugin.

**Case 7 is expected to succeed.** See Limitations; it is asserted rather than
described so that a build which ever changes this behaviour is noticed.

Full plan, including two manual cases (a cavage client, and removing
`signed_headers`), in [tests/test-plan.yaml](tests/test-plan.yaml).
