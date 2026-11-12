# Tests — Mock before the backend

> [Overview](README.md) · [Business need](business-need.md) · [Architecture](architecture.md) · [Guides](guides.md) · [Agent prompt](helix-agent-prompt.md) · **Tests** · [API reference](api-reference.md)

---

9 test cases in total: **6 automated**, run by `example/verify.sh` in two
stages against a live deployment, and **3 manual**, for deploy behaviour that
needs the control plane. The full machine-readable plan is
[`tests/test-plan.yaml`](tests/test-plan.yaml); this page is the readable
walkthrough.

## Running the automated tests

```bash
# After deploying example/api-spec.yaml (the mock):
GATEWAY=https://<YOUR_GATEWAY_HOST> ./example/verify.sh

# After the switch-over (example/api-spec-basic.yaml as a new revision):
GATEWAY=https://<YOUR_GATEWAY_HOST> STAGE=backend ./example/verify.sh
```

Exit code 0 means every case of that stage held. It needs `jq`. If an agent
built the mock and named its marker something other than `x-mock-by`, add
`MOCK_HEADER=<that name>` to the first command.

| # | Stage | Case | Expected |
|---|---|---|---|
| 1 | mock | `GET /shipments/SHP-1001` | `200`, the sample shipment, an `x-mock-by` header, an `X-Request-Id` |
| 2 | mock | `GET /shipments/1` | `200` and **the same body** as case 1: every id gets one answer |
| 3 | mock | `POST /shipments` | `201`, `Location: /shipments/SHP-1001`, the sample body, `x-mock-by` |
| 4 | mock | `DELETE /shipments/SHP-1001` | `404` `Route Not Found`: only the agreed routes exist |
| 5 | backend | `GET /shipments/1` | `200` from the backend: no `x-mock-by`, not the sample |
| 6 | backend | `POST /shipments` | `201` from the backend: no `x-mock-by`, not the sample |

**Cases 2 and 5 are the point.** They are the same request to the same host.
Only the source of the answer changes, which is what "no client change" means.
Cases 3 and 6 show the same for a create.

Each stage also fails when the other one is deployed: `STAGE=backend` against
the mock stops at case 5 because `x-mock-by` is still there, and `STAGE=mock`
after the switch-over stops at case 1. So a run can't pass against the wrong
revision.

Raw fixtures, to run one case by hand: [`tests/requests/`](tests/requests/) and
[`tests/expected/`](tests/expected/). The script reads its expected statuses,
bodies and the `Location` value from the fixtures, so the two can't drift apart.

## The manual tests

| Case | What it proves | How to run it |
|---|---|---|
| **Roll back to the mock** | If the first backend release misbehaves, the mock comes back with one deploy and no client change. | With the switched-over revision live, deploy the first revision with **Force Deploy** (`"force": true`). Run `verify.sh` with `STAGE=mock`: it passes again. |
| **Deploy without an upstream** | A fully mocked revision still needs an upstream. | Import `example/api-spec.yaml` and deploy before binding one. Expect `400` *"Upstream not configured for environment … Set upstream binding first."* |
| **Plain deploy refused** | A switch-over can't happen by accident. | With the mock live, deploy the no-mock revision with `"force": false`. Expect `409` *"… already has revision … deployed for this API"*. |

## Coverage

| Type | Cases |
|---|---|
| Positive | the lookup and the create while mocked, the same two calls after the switch-over |
| Negative | a method outside the contract, a plain deploy over a live revision |
| Boundary | every id gets the same answer |
| Failure | rolling back to the mock, deploying with no upstream |
