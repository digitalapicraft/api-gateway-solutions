# Test & verify — Solution 05 — OAuth with Okta: verify the token, don't issue it

[Overview](readme.md) · [Business need](business-need.md) · [How it works](how-it-works.md) · [Install](install.md) · [Configuration](configuration.md) · **Test & verify** · [Changelog](changelog.md)

---

## What the caller actually sees

All of the following were **executed against a deployed route** — see
[Validation status](#validation-status) for exactly which configuration proved which.

| Situation | Response |
|---|---|
| No `Authorization` header | `401` (**not** a redirect) |
| **`Bearer` prefix missing** | **`400`** — rejected at header parse, before the plugin |
| Not a JWT at all | `401` |
| Signature doesn't verify | `401` |
| `alg: none` | `401` |
| Token expired | `401` |
| `iss` from a different tenant | `401` |
| `iss` missing the issuer's trailing slash | `401` |
| `iss` claim absent | `401` |
| **`aud` claim absent** | **`403`** — note the different code |
| **`aud` present but a completely unrelated API** | **`200` — accepted.** See Gotchas |
| Valid token | `200`, upstream's body untouched |

Most failures are the same opaque `401`, which is correct — distinguishing them
would tell an attacker which part they got right — and genuinely hard for
integrators to self-diagnose. Tell them to send you the `X-Request-Id`.

**There are three rejection codes here, not one.** `401` for a bad, absent,
expired or wrong-issuer token; **`403`** when the `aud` claim is missing or
`required_scopes` isn't satisfied; and **`400`** when the `Authorization` value
carries no recognised scheme — that one is rejected at header parse, before
`openid-connect` runs at all. Alerting or client error handling that keys only on
`401` will miss two of the three.

And a **wrong** `aud` is not a failure at all: it returns `200`. See Gotchas.

The 401 also carries `www-authenticate: Bearer realm="apisix"`, which names the
underlying runtime. `realm` is a settable field on the plugin if you would rather
it didn't.

The upstream receives `X-Access-Token`. It does **not** receive `X-ID-Token` or
`X-Userinfo`: those default to on and are for browser flows, and
`set_userinfo_header` in particular adds a userinfo round trip to Okta on every
single request.

## Testing

[`gateway/verify.sh`](gateway/verify.sh) — seven cases, exits 0 only if all hold.

```bash
GATEWAY=https://<YOUR_GATEWAY_HOST> \
OKTA_TOKEN_URL=https://<your-okta-domain>/oauth2/<authServerId>/v1/token \
OKTA_CLIENT_ID=<CLIENT_ID> \
OKTA_CLIENT_SECRET=<CLIENT_SECRET> \
OKTA_SCOPE=<scope> \
./gateway/verify.sh
```

If your authorization server needs an `audience` parameter to issue a **JWT**
rather than an opaque token — Auth0 always does, and Okta custom authorization
servers usually do — set `TOKEN_AUDIENCE` too.

Two cases carry most of the value:

- **Case 1, no token → 401.** Specifically asserts it is *not* a 302. This is what
  proves you configured the plugin for an API and not for a browser.
- **Case 7, wrong issuer → 401.** Supply `OTHER_ISSUER_TOKEN` from a second
  authorization server. Without it you have proved that signatures are checked,
  not that *your* issuer is required.

The script paces itself between requests: environments commonly apply their own
rate limit, and a burst of test cases can return `429` that reads like a failure.

Full matrix in [tests/test-plan.yaml](tests/test-plan.yaml).
