# Tests — Retire an old API version in stages

> [Overview](README.md) · [Business need](business-need.md) · [Architecture](architecture.md) · [Guides](guides.md) · [Agent prompt](helix-agent-prompt.md) · **Tests** · [API reference](api-reference.md)

---

7 test cases in total: **5 automated**, run by `example/verify.sh` against a
live deployment, and **2 manual**. The full machine-readable plan is
[`tests/test-plan.yaml`](tests/test-plan.yaml); this page is the readable
walkthrough.

## Running the automated tests

```bash
GATEWAY=https://<YOUR_GATEWAY_HOST> ./example/verify.sh
```

No keys or tokens are needed: the sample API is open. Exit code 0 means all
five held:

| # | Case | Expected |
|---|---|---|
| 1 | `GET /v1/products/1` | `200`, the backend's product 1, and `Deprecation: @1777593600`, `Sunset: Wed, 31 Mar 2027 23:59:59 GMT`, `Link: </v2/products/1>; rel="successor-version"` |
| 2 | `GET /v1/products/999999` | the **backend's** `404`, still with `Deprecation` and `Sunset`, and a `Link` naming `999999` |
| 3 | `GET /v1/products/7/reviews` | `410`, JSON with `"successor":"/v2/products/7/reviews"`, `Sunset` and `Link`, and the backend **not called** |
| 4 | Follow the `Link` from case 1 | `200`, the same product, no `Deprecation` or `Sunset` |
| 5 | Follow the `successor` from case 3 | `200`, product 7's reviews, no `Deprecation` or `Sunset` |

Every response must also carry `X-Request-Id`.

**Cases 4 and 5 are the point.** They do what a caller's code would do with the
headers: read the address and go there. If the `Link` or the `successor` is
wrong, they fail even when the headers look right.

**How case 3 knows the backend wasn't called.** The test backend adds an
`X-Powered-By` header to everything it sends. Case 1 checks that header is
there; case 3 checks it is not. With your own backend, set `BACKEND_MARKER` to
a header your backend always sends.

The script compares the headers with the dates in
[`example/api-spec.yaml`](example/api-spec.yaml). If you changed them, pass
`DEPRECATION`, `SUNSET` and `RETIRED_SUNSET`. Expected statuses come from
[`tests/expected/`](tests/expected/), so the script and the fixtures can't
drift apart. To run one case by hand: [`tests/requests/`](tests/requests/).

## The manual tests

| Case | What it proves | How to run it |
|---|---|---|
| **The last stage** | After the retired route is deleted, callers get the gateway's own `404 Route Not Found`, with no `Sunset` and no `Link`. That is the answer the 410 stage exists to avoid. | Clone the revision, delete `GET /v1/products/:productId/reviews`, **Force Deploy**, call it. Roll back by deploying the previous revision. |
| **A trace shows no backend call** | The 410 never reaches the backend. | Start a trace session on the API, call `/v1/products/3/reviews` and `/v1/products/3`, click **Refresh**. The 410's outcome is **Upstream not called**, answered by `mocking`; the 200 shows `response-rewrite` and a backend status. |

## Coverage

| Type | Cases |
|---|---|
| Positive | deprecated route works and says so; the `Link` leads to a working v2 address |
| Negative | retired route answers 410 itself; removed route answers 404 |
| Boundary | the `successor` in the 410 leads to a working v2 address |
| Failure | a backend error on v1 still carries the headers |
| Safety | a trace shows the 410 never reached the backend |
