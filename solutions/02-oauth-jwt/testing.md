# Test & verify — OAuth 2.0 with JWT

[Overview](readme.md) · [Business need](business-need.md) · [How it works](how-it-works.md) · [Install](install.md) · [Configuration](configuration.md) · **Test & verify** · [Changelog](changelog.md)

---

## What the caller actually sees

Be precise about this in your developer docs, because it's what integrators hit.

Successful exchange:

```http
POST /oauth/token
Authorization: Basic <base64(client_id:client_secret)>

HTTP/1.1 200 OK
content-type: application/json

{"access_token":"eyJhbGciOiJIUzI1NiIs...","token_type":"Bearer","expires_in":900}
```

Every rejection on a protected route is a **401**:

```http
HTTP/1.1 401 Unauthorized
```

**All four failure causes look the same to the caller** — no token, malformed
header, expired token, bad signature. That is correct security behaviour (a
verbose error tells an attacker which half of their guess was right) and it is
genuinely awkward for integrators. Two consequences to design around:

- **Document the causes**, since the response won't distinguish them. "A 401
  means one of: no `Authorization` header, no `Bearer ` prefix, an expired token,
  or a token this gateway didn't sign."
- **Use the correlation id for support.** `X-Request-Id` is stamped on every
  call including the token exchange, so when a partner reports "it just returns
  401" you have something to search on.

## Testing

```bash
GATEWAY=https://<YOUR_GATEWAY_HOST> \
CLIENT_ID=<CLIENT_ID> CLIENT_SECRET=<CLIENT_SECRET> ./gateway/verify.sh
```

Exit 0 means all six cases held:

| # | Case | Expected |
|---|---|---|
| 1 | No token on a protected route | `401` |
| 2 | Valid client credentials at the token endpoint | `200` + a three-segment JWT |
| 3 | Valid Bearer token on a protected route | `200` |
| 4 | Forged token (valid shape, wrong signature) | `401` |
| 5 | **Correct client_id, wrong client_secret** | `401` |
| 6 | Token sent without the `Bearer ` prefix | `401` |

**Case 5 is the one to not skip.** It's what separates a real credentials flow
from a static-key flow in a token's clothing. If a wrong secret still gets you a
token, the secret isn't being checked and the whole design is decorative.

Case 4 matters for the same reason in the other direction: if a garbage token
returns 200, the route isn't validating at all — it's just passing traffic
through while looking configured.

Full plan including expiry (which needs a wait, so it's a manual case):
[`tests/test-plan.yaml`](tests/test-plan.yaml).
