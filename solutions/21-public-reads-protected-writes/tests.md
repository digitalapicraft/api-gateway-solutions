# Tests — Public reads, protected writes

> [Overview](README.md) · [Business need](business-need.md) · [Architecture](architecture.md) · [Guides](guides.md) · [Agent prompt](helix-agent-prompt.md) · **Tests** · [API reference](api-reference.md)

---

17 checks in total: **14 automated**, run by `example/verify.sh` against a live
deployment, and **3 manual**, for things that need a second deployment, a
second product, or a deleted app. The full machine-readable plan is
[`tests/test-plan.yaml`](tests/test-plan.yaml); this page is the readable
walkthrough.

## Running the automated tests

```bash
GATEWAY=https://<YOUR_GATEWAY_HOST> \
API_KEY=<PARTNER_API_KEY> \
./example/verify.sh
```

`API_KEY` is a partner app's credential **key**, not its secret and not the
app's id. Optional: `ITEM_ID` (default `1`), `BASE_PATH` (default
`/catalog/items`), `KEY_HEADER` (default `X-Api-Key`). It needs only bash and
curl. Exit code 0 means all fourteen held:

| # | Case | Expected |
|---|---|---|
| 1–2 | `GET` the list and one item, no key | `200` |
| 3–5 | `POST`, `PUT`, `DELETE`, no key | `401` *Missing API key in request* |
| 6–8 | `POST`, `PUT`, `DELETE`, a key no app has | `401` *Invalid API key in request* |
| 9–11 | `POST`, `PUT`, `DELETE`, the partner's key | `201`, `200`, `200` |
| 12 | `GET` one item **with** the partner's key | `200` |
| 13 | `GET` one item with a key no app has | `200` |
| 14 | `PATCH` one item, which the API doesn't list | `404` *404 Route Not Found* |

**Cases 1–5 are the point.** A 401 on case 1 or 2 means the key check is on the
whole API and the public can't read. A 2xx on any of cases 3–5 means that write
is open to anyone. The script tests each write method separately because the
check is added per route, so one can be missed while the others work.

**Cases 13 and 14 mark the edges.** A read never looks at the key, so even a
bad one is served. And a method nobody declared gets no route at all.

The sample backend answers writes as if it stored them and stores nothing, so
the script changes no data. To run one case by hand, use
[`tests/requests/`](tests/requests/) and [`tests/expected/`](tests/expected/).
The script reads its expected statuses from those files, so the two can't drift
apart.

## The manual tests

| Case | What it proves | How to run it |
|---|---|---|
| **The key check on the whole API** | Why the design puts it on the writes only. | In a throwaway environment, deploy a copy of the spec with `helix-auth` moved into the top-level `x-helix-gateway` block. Run `verify.sh`. Expect it to stop at case 1: a read with no key gets `401`. |
| **A key from another product** | The key check doesn't look at the app's product. | Create a second product **without** this API, and an app on it. `POST` with that app's key. Expect `201`. Add the product check from [solution 01](../01-api-products/) to make it `403`. |
| **Switching a partner off** | Deleting a partner's app stops its writes with no redeploy, and leaves its reads alone. | Delete the app (or click **Generate New Credentials** on it). Repeat a `POST` and a `GET` with the old key. Expect `401` on the `POST` once the gateway's short credential cache expires, and `200` on the `GET`. |

## Coverage

| Type | Cases |
|---|---|
| Positive | open reads, the three writes with a partner's key |
| Negative | each write with no key, each write with an unknown key |
| Boundary | a read with a good key, a read with a bad key, an undeclared method, a key from another product |
| Failure | the key check on the whole API, switching a partner off |
