# Tests — Keep a supplier's API key at the gateway

> [Overview](README.md) · [Business need](business-need.md) · [Architecture](architecture.md) · [Guides](guides.md) · [Agent prompt](helix-agent-prompt.md) · **Tests** · [API reference](api-reference.md)

---

10 test cases in total: **7 automated**, run by `example/verify.sh` against a
live deployment, and **3 manual**, which need a different configuration or
remove a key the others use. The full machine-readable plan is
[`tests/test-plan.yaml`](tests/test-plan.yaml); this page is the readable
walkthrough.

## Running the automated tests

```bash
GATEWAY=https://<YOUR_GATEWAY_HOST> \
API_KEY=<APP_API_KEY> \
SUPPLIER_KEY=<SUPPLIER_API_KEY> \
./example/verify.sh
```

`API_KEY` is an app's key. `SUPPLIER_KEY` is the value you put in place of
`<SUPPLIER_API_KEY>` in the spec. Exit code 0 means all seven held:

| # | Case | Expected |
|---|---|---|
| 1 | No key | `401`, *Missing API key in request* |
| 2 | A key no app owns | `401`, *Invalid API key in request* |
| 3 | The app's key | `200`, the supplier answered |
| 4 | What the supplier got | `X-Supplier-Key` with exactly your configured value |
| 5 | What the supplier didn't get | no `X-Api-Key`: the client's own key was removed |
| 6 | A client sends its own `X-Supplier-Key` | `200`, and the supplier still sees only your value |
| 7 | Response headers | none of them contains the supplier key |

**Cases 4 and 5 are the point.** The supplier must get its key, and must not get
the client's. Both read what the backend received, so they need an upstream that
echoes the request back: postman-echo.com, as in the example. Against a backend
that doesn't echo, the script stops after case 3 and says so.

Case 4 also catches a placeholder or a reference stored instead of the key: the
script names it if the supplier received `<SUPPLIER_API_KEY>` or `<ENV:...>`.

postman-echo.com echoes the supplier key in the response body too, so case 7
checks the response **headers** only. A real supplier doesn't send its key back.

Raw fixtures, to run one case by hand: [`tests/requests/`](tests/requests/) and
[`tests/expected/`](tests/expected/). The script reads its expected statuses
from the fixtures, so the two can't drift apart.

## The manual tests

| Case | What it proves | How to run it |
|---|---|---|
| **Without the remove** | `helix-auth` passes the client's key on: without `remove`, it reaches the supplier. | Deploy the route with `set` but no `remove`, in a test environment. Call it with an app's key. The echo lists `x-api-key` with the client's key, and `verify.sh` fails at case 5. |
| **Hide which app called** | The two ids the gateway adds can be removed too. | Add `X-Consumer-Username` and `X-Credential-Identifier` to `remove` and deploy. The echo shows neither, and `verify.sh` still exits 0. |
| **Switch off one client** | Stopping a client is a change to its app only. | With two apps, delete one (or click **Generate New Credentials** on it). Its key gets `401` *Invalid API key in request* within a few seconds; the other app's key still gets `200`. |

## Coverage

| Type | Cases |
|---|---|
| Positive | the app's key, what the supplier got, what it didn't get, response headers |
| Negative | no key, a key no app owns |
| Boundary | a client's own `X-Supplier-Key`, hide which app called |
| Failure | without the remove, switch off one client |
