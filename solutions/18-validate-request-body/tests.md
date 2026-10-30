# Tests — Validate the request body

> [Overview](README.md) · [Business need](business-need.md) · [Architecture](architecture.md) · [Guides](guides.md) · [Agent prompt](helix-agent-prompt.md) · **Tests** · [API reference](api-reference.md)

---

11 test cases in total: **7 automated**, run by `example/verify.sh` against a
live deployment, and **4 manual**, for behaviour that needs a trace session or
shows what the sample rule lets through. The full machine-readable plan is
[`tests/test-plan.yaml`](tests/test-plan.yaml); this page is the readable
walkthrough.

## Running the automated tests

```bash
GATEWAY=https://<YOUR_GATEWAY_HOST> ./example/verify.sh
```

Exit code 0 means all seven held:

| # | Case | Expected |
|---|---|---|
| 1 | A valid new ticket | `201` from the backend |
| 2 | No `priority` | `400` from the gateway, naming `priority` |
| 3 | `title` is `null` | `400` from the gateway, naming `title` |
| 4 | `priority` is `urgent` | `400` from the gateway, naming `priority` |
| 5 | A body that isn't JSON | `400` from the gateway |
| 6 | A change sending only `priority` | `200` from the backend: nothing is required on `PATCH` |
| 7 | A change with `priority` `urgent` | `400` from the gateway, naming `priority` |

**How the script knows who answered.** The sample backend adds
`X-Powered-By: Express` to every response, and never answers these calls with
a 400. Cases 1 and 6 must carry that header; the 400s must not. The script
checks the header on case 1 first, so its absence later means something. If
your backend sends a different header on every response, set `BACKEND_HEADER`.
`TICKETS_PATH` and `TICKET_ID` change the paths.

Raw fixtures, to run one case by hand: [`tests/requests/`](tests/requests/) and
[`tests/expected/`](tests/expected/). The script reads its expected statuses
from the fixtures, so the two can't drift apart.

## The manual tests

| Case | What it proves | How to run it |
|---|---|---|
| **A trace shows the gateway answered** | The backend was never called. | Open a trace session ([solution 16](../16-request-tracing/)) and send case 2. The outcome is **Upstream not called**, answered by `request-validation`, with no backend status. Case 1's record shows backend status `201`. |
| **No body** | A request with no body is refused. | `POST /tickets` with no body. Expect `400` and a short HTML error page with no message. |
| **One field at a time** | The message names the first failure only. | `POST /tickets` with `{}`. Expect `400` naming `title`. Add a title: the next `400` names `priority`. |
| **What the sample rule lets through** | The limits in [Architecture](architecture.md#what-the-check-does-not-catch) are real. | Send a title of only spaces, an extra unlisted field, and a form-encoded body with the right fields: each gets `201`. `PATCH` with `{}` gets `200`. Each has a fix in [Variations](guides.md#variations). |

## Coverage

| Type | Cases |
|---|---|
| Positive | a valid ticket reaches the backend |
| Negative | missing field, wrong type, value outside the list, not JSON, no body, a bad field on a change |
| Boundary | nothing required on a change, one field named at a time, what the rule lets through |
| Proof the backend never saw it | the missing backend header on every 400, and a trace record |
