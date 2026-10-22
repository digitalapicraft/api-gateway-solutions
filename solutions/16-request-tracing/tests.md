# Tests — Request tracing

> [Overview](README.md) · [Business need](business-need.md) · [Architecture](architecture.md) · [Guides](guides.md) · [Agent prompt](helix-agent-prompt.md) · **Tests** · [API reference](api-reference.md)

---

12 test cases in total: **7 automated**, run by `example/verify.sh` against a
live deployment in a single trace session, and **5 manual**, for behaviour that
needs more traffic, more time, or a look at the UI. The full machine-readable
plan is [`tests/test-plan.yaml`](tests/test-plan.yaml); this page is the
readable walkthrough.

## Running the automated tests

```bash
GATEWAY=https://<YOUR_GATEWAY_HOST> \
CONTROL_PLANE=https://<YOUR_CONTROL_PLANE_HOST> \
TOKEN=<control-plane bearer token> \
ORG=<ORG_ID> API_ID=<API_ID> ENV_ID=<ENV_ID> \
./example/verify.sh
```

Exit code 0 means all seven held:

| # | Case | Expected |
|---|---|---|
| 1 | Start a session | `200`, a session id, status `active` |
| 2 | Start it again | the **same** session id |
| 3 | `POST /posts` with no title | `400`, and the record says **the gateway** answered: outcome `short_circuit`, plugin `request-validation`, no backend status |
| 4 | `GET /posts/1` | `200`, and the record shows `proxy-rewrite` adding `x-partner-channel: api` |
| 5 | `GET /posts/999999` | `404`, and the record says **the backend** answered: backend status `404`, no short circuit |
| 6 | Tracing changes nothing | the traced response body is identical to an untraced one |
| 7 | Stop | `200`, and a request sent afterwards is not recorded |

**Cases 3 and 5 are the point.** To the caller they are the same thing: an
error. A status code can't tell you whose error it was. The record can, and if
either case attributes its error to the wrong side, the trace can't do its job.

The script uses 3 of the session's 10 recorded requests and always stops the
session on exit, even when a check fails. If a session is already open on the
API with a filter or records of its own, the script refuses to run rather than
reuse it.

Raw fixtures, to run one case by hand: [`tests/requests/`](tests/requests/) and
[`tests/expected/`](tests/expected/). The script reads its expected statuses
from the fixtures, so the two can't drift apart.

## The manual tests

| Case | What it proves | How to run it |
|---|---|---|
| **The recording cap** | A session stops recording after its cap (10 by default), and a new start then opens a **new** session. | Start a session with no filter, send 14 requests, wait 20 seconds. Expect 10 records. Start again: expect a different session id. |
| **Failures-only filter** | Requests that don't match the filter are neither recorded nor counted toward the cap. | Start with `status >= 400`. Send 3 good calls and 2 failing ones. Expect exactly the 2 failures. |
| **Your-header filter** | Only requests carrying your test header are recorded, so other callers' traffic stays out of the trace. | Start with `http_x_debug_trace == me`. Send 3 calls without the header and 2 with `X-Debug-Trace: me`. Expect exactly the 2. |
| **A rejected filter** | The gateway refuses a filter on a variable that identifies the route, and says which. | Start with `[["route_id", "==", "x"]]`. Expect `400` naming `route_id`. |
| **Credentials in a record** | Headers are recorded unredacted, so the team knows what a trace holds before using it on live traffic. | Send a request with `apikey: TEST-VALUE`. Open its record and find the value under **Headers**. |

## Coverage

| Type | Cases |
|---|---|
| Positive | start, a changed request recorded, stop |
| Negative | gateway rejection attributed to the gateway, backend rejection attributed to the backend, rejected filter |
| Boundary | one session per API and environment, the recording cap, both filters |
| Safety | tracing does not change the response, credentials are visible in records |
