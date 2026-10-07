# Tests — checking Okta-issued tokens at the gateway

> [Overview](README.md) · [Business need](business-need.md) · [Architecture](architecture.md) · [Guides](guides.md) · [Agent prompt](helix-agent-prompt.md) · **Tests** · [API reference](api-reference.md)

---

14 test cases in total: **7 automated**, run by `example/verify.sh` against a live
deployment; **4 that need a specially made token**, so you run them by hand; and
**3 manual**, for behaviour no single request can show (an expired token, a key
rotation, a browser preflight). The full machine-readable plan is
[`tests/test-plan.yaml`](tests/test-plan.yaml); this page is the readable
walkthrough of what it checks and why.

## Running the automated tests

Let the script fetch a token from Okta with client credentials:

```bash
GATEWAY=https://<YOUR_GATEWAY_HOST> \
OKTA_TOKEN_URL=https://<your-okta-domain>/oauth2/<authServerId>/v1/token \
OKTA_CLIENT_ID=<CLIENT_ID> \
OKTA_CLIENT_SECRET=<CLIENT_SECRET> \
OKTA_SCOPE=<scope> \
./example/verify.sh
```

Or bring a token you already have (any grant):
`GATEWAY=https://<YOUR_GATEWAY_HOST> ACCESS_TOKEN=<paste> ./example/verify.sh`.

| Variable | Needed for |
|---|---|
| `TOKEN_AUDIENCE` | Authorization servers that need an `audience` to issue a JWT rather than an opaque token. Auth0 always does; Okta custom authorization servers usually do. |
| `OTHER_ISSUER_TOKEN` | Case 7. A valid token from a **different** authorization server. Without it, case 7 is skipped. |
| `API_PATH` | A path other than `/posts`. |
| `PACE` | Seconds to wait between requests (default 7). Environments often limit request rates, and a burst of test calls returns 429, which looks like a failure and isn't one. Set `0` to turn it off. |

Exit code 0 means every case that ran held:

| # | Case | Expected |
|---|---|---|
| 1 | No token | `401`, and specifically **not** a 302 redirect to Okta's login page |
| 2 | Ask Okta for a token | a three-part JWT, signed RS256, carrying a `kid` |
| 3 | Valid token | `200` |
| 4 | Token with its signature replaced | `401` |
| 5 | Unsigned token (`alg: none`) | `401` |
| 6 | Valid token without the `Bearer ` prefix | `400` (rejected while reading the header, before the plugin runs; `401` is also accepted) |
| 7 | Valid token from a different issuer | `401` (only if `OTHER_ISSUER_TOKEN` is set) |

**Two cases carry most of the value.**

- **Case 1** proves you set the plugin up for an API, not a browser. A redirect
  here means it is still configured for browser sign-in.
- **Case 7** proves the token is specific to *your* issuer. Without it you have
  shown that signatures are checked, not that the right issuer is required. Run it
  at least once per environment.

Case 4 matters most if it fails: a 200 means the token's header is being read but
its signature is not being checked.

Raw fixtures, if you want to run one case by hand instead of the whole script:
[`tests/requests/`](tests/requests/) (the HTTP requests) and
[`tests/expected/`](tests/expected/) (the expected status for each — the single
source of truth both `verify.sh` and the plan read from, so they can't drift
apart).

## Cases that need a specially made token

These each need a token with one claim deliberately wrong, which Okta will not
issue for you. They are in the plan, not in `verify.sh`.

| Case | What it proves | Expected |
|---|---|---|
| **Missing audience** | A correctly signed token with **no** `aud` claim is refused, because `claim_validator.audience.required` is true. | `403` — note: not 401 |
| **Algorithm confusion** | A token signed HS256 using the issuer's *public* key as the secret (a classic attack) is refused. | `401` |
| **Issuer trailing slash** | The same token, with the trailing slash removed from the issuer, is refused. `valid_issuers` is an exact text match. | `401` |
| **Wrong audience** *(a known gap)* | A correctly signed token whose `aud` names an unrelated API is **accepted**. This is documented, not asserted, because asserting it would treat the weakness as intended. Use `required_scopes` if you need to tell APIs apart. | `200` |

## The manual tests

| Case | What it proves | How to run it |
|---|---|---|
| **Expired token** | The token's lifetime is enforced, not just advertised. | Get a token and confirm it returns `200`. Wait longer than its lifetime (commonly 3600 seconds; shorten it in a test authorization server), then replay the same token. Expect `401`. The lifetime is set in Okta, not at the gateway. |
| **Key rotation** | What happens when Okta rotates its signing key while the gateway still has the old keys cached, so you recognise the symptom in production. | In a **throwaway** Okta authorization server only, rotate the signing key, then call the API with a freshly issued token. Expect `401` until the gateway's cache expires (`jwk_expires_in`, 3600 seconds here). The sign: every token starts failing at once and nothing changed on your side. |
| **Browser preflight** | A browser can send the `Authorization` header. If not, browser clients fail with a CORS error before any request is made. | Send `OPTIONS` to a protected route with an `Origin` and `Access-Control-Request-Headers: authorization`. Confirm `Access-Control-Allow-Headers` includes `authorization`. Only relevant if browsers call this API. |

Full procedures, plus the exact assertions each one makes:
[`tests/test-plan.yaml`](tests/test-plan.yaml).

## Coverage

| Type | Cases |
|---|---|
| Positive | Okta issues a token, valid token |
| Negative | no token, forged signature, `alg: none`, wrong issuer, missing audience, algorithm confusion |
| Boundary | missing `Bearer` prefix, expired token, issuer trailing slash, browser preflight |
| Failure | key rotation, wrong audience |
