# Tests — Stable public paths

> [Overview](README.md) · [Business need](business-need.md) · [Architecture](architecture.md) · [Guides](guides.md) · [Agent prompt](helix-agent-prompt.md) · **Tests** · [API reference](api-reference.md)

---

13 test cases in total: **10 automated**, run by `example/verify.sh` against a
live deployment, and **3 manual**, for a backend move and for near-miss paths.
The full machine-readable plan is [`tests/test-plan.yaml`](tests/test-plan.yaml);
this page is the readable walkthrough.

## Running the automated tests

```bash
GATEWAY=https://<YOUR_GATEWAY_HOST> ./example/verify.sh
```

Exit code 0 means all ten held:

| # | Case | Expected |
|---|---|---|
| 1 | `GET /v1/customers` | `200`, 10 customers, an `X-Request-Id` header |
| 2 | `GET /v1/customers?_limit=2` | `200`, exactly 2: the query string reached the backend |
| 3 | `GET /v1/customers/3` | `200`, customer 3 (`Samantha`): the id was carried |
| 4 | `GET /v1/customers/1/orders` | `200`, 20 orders, every one customer 1's |
| 5 | `GET /v1/customers/1/orders?_limit=3` | `200`, exactly 3, all customer 1's |
| 6 | `GET /v1/customers/1/orders?userId=2` | `200`, still only customer 1's orders |
| 7 | `GET /v1/customers/999` | `404` from the **backend** (`{}`): no such customer |
| 8 | `GET /v1/accounts` | `404 Route Not Found` from the **gateway**: not in the contract |
| 9 | `GET /users`, `/users/1`, `/users/1/todos` | `404 Route Not Found`: the backend's own paths aren't reachable |
| 10 | `GET /v1/customers/../../users/1/todos`, sent as-is | `404 Route Not Found`: `../` can't climb out |

**Each case checks which record came back, not just the status.** A rewrite
that sends every caller to the same customer still answers 200.

**Case 6 is the one to watch after a backend move.** It holds because the id
travels in the backend's path. If the backend moves the id into its query
string, the caller's extra parameter reaches the backend too, and this case
fails. See [The backend moved](guides.md#the-backend-moved).

**Cases 7 and 8 are both 404s with different owners.** The backend's 404 has
its own body and an `X-Request-Id`; the gateway's is `{"error_msg":"404 Route
Not Found"}`.

APIs in the same environment share one host. If another API serves one of the
backend paths in case 9, the script stops and says so; leave that path out
with `BACKEND_PATHS="/users/1/todos"`. [Solution 20](../20-security-headers/)
serves `/users` and `/users/1`, so use that whenever 20 is deployed alongside.

Raw fixtures, to run one case by hand: [`tests/requests/`](tests/requests/) and
[`tests/expected/`](tests/expected/). The script reads its expected statuses
from the fixtures, so the two can't drift apart.

## The manual tests

| Case | What it proves | How to run it |
|---|---|---|
| **The backend moved** | Only the rewrite changes, and callers get the same answers. | Set the orders route to `{"regex_uri":["^/v1/customers/([0-9]+)/orders$","/todos?userId=$1"]}` on a cloned revision and deploy it. Run `verify.sh`: cases 1 to 5 pass with the same responses as before, and case 6 fails with 40 orders from customers 1 and 2. |
| **An id copied into a query string** | A digits-only pattern stops a caller adding parameters inside the id. | With the moved orders route, call `/v1/customers/1&userId=2/orders`. With `([^/]+)`: 40 orders. With `([0-9]+)`: the backend's 404, because nothing was rewritten. |
| **Near-miss paths** | Paths are matched exactly. | Call `/V1/customers`, `/v1/Customers/1`, `/v1/customers/`, `/v1/customers/1/` and `/v1/customers/1%2Ftodos`. Expect `404 Route Not Found` for all five. |

## Coverage

| Type | Cases |
|---|---|
| Positive | the list, one customer, one customer's orders, the backend moved |
| Query string | kept through `uri`, kept through `regex_uri`, an added parameter |
| Negative | the backend's 404, a path outside the contract, the backend's own paths |
| Boundary | `../` segments, near-miss paths, an id copied into a query string |
