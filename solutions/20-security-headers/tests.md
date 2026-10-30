# Tests — Security headers

> [Overview](README.md) · [Business need](business-need.md) · [Architecture](architecture.md) · [Guides](guides.md) · [Agent prompt](helix-agent-prompt.md) · **Tests** · [API reference](api-reference.md)

---

8 test cases in total: **4 automated**, run by `example/verify.sh` against a live
deployment, and **4 manual**, for behaviour that needs a different configuration
or a path no other API serves. The full machine-readable plan is
[`tests/test-plan.yaml`](tests/test-plan.yaml); this page is the readable
walkthrough.

## Running the automated tests

```bash
GATEWAY=https://<YOUR_GATEWAY_HOST> ./example/verify.sh
```

It calls the backend directly too, for the "before" picture and the body
comparison. That is the public sample backend unless you set `BACKEND` to your
own. No credentials needed. Exit code 0 means every check held:

| # | Case | Expected |
|---|---|---|
| 1 | The backend, called directly | `200`, with `X-Powered-By: Express` and `Cache-Control: max-age=43200`: what the pen test saw |
| 2 | `GET /users/1` through the gateway | `200` · the five headers, each **once**, with the configured value · no stack header · an `X-Request-Id` · the body **byte-identical** to the backend's |
| 3 | `GET /users` | `200` · the same headers · the 5.6 KB list byte-identical |
| 4 | `GET /users/999999` | `404` from the backend · **the same headers on the error** · the body byte-identical |

**Case 1 is what makes the others mean something.** "No `X-Powered-By` after the
gateway" proves nothing unless the backend sent one. **"Once" matters too:** the
backend already sends `X-Content-Type-Options` and `Cache-Control`, and a rule
that added a second copy instead of replacing would still look right to a quick
check.

The script reads the expected statuses and header values from
[`tests/expected/`](tests/expected/), so the two can't drift apart. Each request,
to run by hand: [`tests/requests/`](tests/requests/).

## The manual tests

| Case | What it proves | How to run it |
|---|---|---|
| **No route** | A path the API doesn't have gets the gateway's plain `404 Route Not Found`, without these headers. | `curl -sI $GATEWAY/users-no-such-route`. Expect `404` and none of the five headers. |
| **A route with its own rule** | A route-level `response-rewrite` replaces the API-wide one on that route. | Give one route a `response-rewrite` with only `filters`, and deploy. That route has none of the five headers; `X-Request-Id` is still there. Copy the `headers` block in beside the `filters`, deploy again: all five return. |
| **`add` instead of `set`** | `add` puts a second header beside the backend's. | Use `add: ["Cache-Control: no-store"]` instead of `set`. A backend that sends `Cache-Control: max-age=600` now produces both headers. |
| **Who owns HSTS** | Whether something in front of the gateway already sets `Strict-Transport-Security`. | `curl -sI` the API before adding it. See [Add HSTS](guides.md#add-hsts). |

## Coverage

| Type | Cases |
|---|---|
| Positive | one record, the list |
| Negative | the backend's own 404, `add` instead of `set` |
| Boundary | a path with no route, a route with its own rule, HSTS ownership |
| Safety | the body is byte-identical to the backend's in every automated case |
