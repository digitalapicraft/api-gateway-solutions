# Tests — OAuth 2.0 with gateway-issued JWTs

> [Overview](README.md) · [Business need](business-need.md) · [Architecture](architecture.md) · [Guides](guides.md) · [Agent prompt](helix-agent-prompt.md) · **Tests** · [API reference](api-reference.md)

---

9 test cases in total: **6 automated**, run by `example/verify.sh` against a live
deployment, and **3 manual**, for behaviour a single quick request can't prove
(waiting out a token's lifetime, a deliberately broken secret, a browser
preflight). The full machine-readable plan is
[`tests/test-plan.yaml`](tests/test-plan.yaml); this page is the readable
walkthrough of what it checks and why.

## Running the automated tests

```bash
GATEWAY=https://<YOUR_GATEWAY_HOST> \
CLIENT_ID=<CLIENT_ID> CLIENT_SECRET=<CLIENT_SECRET> EXPECT_TTL=900 \
./example/verify.sh          # defaults to /posts and /oauth/token
```

`CLIENT_ID` is the app's key; `CLIENT_SECRET` is its secret. `EXPECT_TTL` is
optional — set it to your `token_ttl` and the script also checks the token's
`expires_in`. `TOKEN_PATH` and `API_PATH` change the two paths if yours differ.

Exit code 0 means all six held:

| # | Case | Expected |
|---|---|---|
| 1 | No token on a protected route | `401` |
| 2 | Valid client id and secret at the token endpoint | `200` + a three-part JWT |
| 3 | Valid `Bearer` token on a protected route | `200` |
| 4 | Forged token (right shape, wrong signature) | `401` |
| 5 | **Correct client id, wrong client secret** | `401` |
| 6 | Token sent without the `Bearer ` prefix | `401` |

**Case 5 is the one not to skip.** It is what separates a real credentials flow
from a static key dressed up as a token. If a wrong secret still gets a token, the
secret isn't being checked and the whole design is for show.

**Case 4 matters for the same reason in the other direction.** If a made-up token
returns 200, the route isn't checking at all — it is passing traffic through while
looking configured. That is the most serious way this solution can fail.

When a case fails, the script says what usually causes it: a 401 on case 3 almost
always means the signing secret differs between the token route and the protected
route; a 403 there means the app is identified but not subscribed to a product
that covers the API.

Raw fixtures, if you want to run one case by hand instead of the whole script:
[`tests/requests/`](tests/requests/) (the HTTP requests) and
[`tests/expected/`](tests/expected/) (the expected status for each — the single
source both `verify.sh` and the plan read from, so they can't drift apart).

## The manual tests

These need something `verify.sh` can't do on its own — waiting, or changing
configuration — so they're a checklist, not a script.

| Case | What it proves | How to run it |
|---|---|---|
| **Expired token** | The token's lifetime is enforced, not just advertised in `expires_in`. The lifetime is the only limit on a leaked token, so this is worth running once per environment. | Get a token and confirm it returns 200. Wait longer than `token_ttl` (900s here; shorten it temporarily in a test environment if you'd rather not wait). Send the **same** token again — expect `401`. |
| **Signing secret mismatch** | What the most common misconfiguration looks like, so you recognise it: tokens are issued fine and then rejected straight away. | In a **throwaway** test environment only, give the protected route a different signing secret from the token route. Request a token (still `200`), then use it — expect `401`. |
| **Browser preflight** | A browser is allowed to send the `authorization` header. If not, browser clients fail before the request is made, and the symptom is a CORS error rather than a 401. | Send an `OPTIONS` request to a protected route with an `Origin` header and `Access-Control-Request-Headers: authorization`. Check the response's `Access-Control-Allow-Headers` includes `authorization`. Only relevant if browsers call this API directly. |

Full procedures, plus the exact assertions each one makes:
[`tests/test-plan.yaml`](tests/test-plan.yaml).

## Coverage

| Type | Cases |
|---|---|
| Positive | token issued, valid token accepted |
| Negative | no token, forged token, wrong secret |
| Boundary | missing `Bearer ` prefix, expired token, browser preflight |
| Failure | signing secret mismatch |
