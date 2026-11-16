# Tests — Maintenance mode

> [Overview](README.md) · [Business need](business-need.md) · [Architecture](architecture.md) · [Guides](guides.md) · [Agent prompt](helix-agent-prompt.md) · **Tests** · [API reference](api-reference.md)

---

12 test cases in total: **8 automated**, run by `example/verify.sh` four at a
time, one state per run, and **4 manual**, for the switch itself and for what
needs a trace or a look at the revision list. The full machine-readable plan is
[`tests/test-plan.yaml`](tests/test-plan.yaml); this page is the readable
walkthrough.

## Running the automated tests

```bash
GATEWAY=https://<YOUR_GATEWAY_HOST> ./example/verify.sh                    # cases 1-4
GATEWAY=https://<YOUR_GATEWAY_HOST> MODE=maintenance ./example/verify.sh   # cases 5-8
```

It needs only `bash` and `curl`. Exit code 0 means every case for that state
held:

| # | Mode | Call | Expected |
|---|---|---|---|
| 1 | normal | `GET /bookings` | `200` from the backend, no `Retry-After` |
| 2 | normal | `GET /bookings/1` | `200`, booking 1 |
| 3 | normal | `POST /bookings` | `201` from the backend |
| 4 | normal | `GET /bookings/999999` | `404`, the backend's own answer |
| 5 | maintenance | `GET /bookings` | `503`, `Retry-After`, a JSON body, backend not called |
| 6 | maintenance | `GET /bookings/1` | the same `503` |
| 7 | maintenance | `POST /bookings` | the same `503`; the body never reaches the backend |
| 8 | maintenance | `GET /bookings/999999` | `503`, not `404`: the gateway answers first |

Every response, in both modes, must also carry an `X-Request-Id`.

**Run it three times for a full rehearsal:** normal, then switch maintenance
on and run it with `MODE=maintenance`, then switch back and run it in normal
mode again. Each run also fails, with a hint, when pointed at the other state,
so it tells you which revision is live.

"From the backend" is checked with `X-Powered-By`, a header the sample backend
adds to every answer and the maintenance response doesn't carry. With your own
backend, set `BACKEND_HEADER` to a header it always sends. In maintenance mode
the script also prints the message callers get, and a note when the
`Retry-After` date is already in the past.

Raw fixtures, to run one case by hand: [`tests/requests/`](tests/requests/) and
[`tests/expected/`](tests/expected/). The script reads its expected statuses
from the fixtures, so the two can't drift apart.

## The manual tests

| Case | What it proves | How to run it |
|---|---|---|
| **Switch on** | Deploying the copy replaces the live revision without editing it, and calls during the switch get one answer or the other. | Call `GET /bookings/1` in a loop, then clone, switch the maintenance response on and **Force Deploy** the copy. Expect `200`s, then `503`s within a second or two, and nothing else. The old revision shows as inactive. |
| **Switch back** | Deploying the earlier revision restores the normal state exactly. | **Force Deploy** the earlier revision. Expect `200` within a second or two, and cases 1–4 to pass. |
| **Backend not called** | During maintenance nothing reaches the backend. | Start a trace session, send `POST /bookings`. The record says **Upstream not called**, answered by `mocking`, with no backend status. |
| **Only this API** | Maintenance covers this API's routes, nothing else. | Send `PUT /bookings/1`, a method the API doesn't have. Expect `404 Route Not Found` in both states. |

## Coverage

| Type | Cases |
|---|---|
| Positive | normal reads and writes, the 503 on every route, both switches, backend not called |
| Negative | the backend's own 404 passes through in the normal state |
| Boundary | an unknown booking gets the 503 during maintenance, a route outside the API |
