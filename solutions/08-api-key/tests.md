# Tests — API-key identity at the edge

> [Overview](README.md) · [Business need](business-need.md) · [Architecture](architecture.md) · [Guides](guides.md) · [Agent prompt](helix-agent-prompt.md) · **Tests** · [API reference](api-reference.md)

---

10 test cases in total: **7 automated**, run by `example/verify.sh` against a live
deployment, and **3 manual**, because they change control-plane state or need a
configuration this package deliberately does not ship. The full machine-readable
plan is [`tests/test-plan.yaml`](tests/test-plan.yaml); this page is the readable
walkthrough of what it checks and why.

## Running the automated tests

```bash
GATEWAY=https://<YOUR_GATEWAY_HOST> \
DEVICE_KEY=<DEVICE_API_KEY> APP_SECRET=<APP_SECRET> \
./example/verify.sh
```

`DEVICE_KEY` is the app's credential **key**, not its secret and not its id.
`APP_SECRET` is optional: it turns on case 6, which is skipped (with a note)
without it. Optional overrides: `READ_PATH` (default `/fleet/price-list`),
`WRITE_PATH` (default `/fleet/takings`), `KEY_HEADER` (default `X-Device-Key`).

Exit code 0 means all seven held:

| # | Case | Expected |
|---|---|---|
| 1 | No key | `401` *Missing API key in request* |
| 2 | A live app's key | `200` + the upstream's payload |
| 3 | An unknown key | `401` *Invalid API key in request* |
| 4 | **The right key in an `apikey:` header** | `401` |
| 5 | **The right key as a query parameter** | `401` |
| 6 | **The app's secret sent as the key** | `401` |
| 7 | The key on the write route | `201` |

**Cases 4–6 are the ones not to skip.** Each proves the contract is narrower than
it looks: the header *name* is part of it (4), `source: header` means the header
and nothing else (5), and the app's secret is not accepted in place of its key (6)
— which is exactly what `secret_validation: true` would change.

**Case 3 matters in the other direction.** If an unknown key returns 200, the
route isn't checking keys at all: it is passing traffic through while looking
configured. An unknown key is also what a switched-off caller looks like, which
is what makes switch-off testable.

Raw fixtures, if you want to run one case by hand instead of the whole script:
[`tests/requests/`](tests/requests/) (the HTTP requests) and
[`tests/expected/`](tests/expected/) (the expected status and body for each — the
single source of truth both `verify.sh` and the plan read from, so they can't
drift apart).

## The manual tests

| Case | What it proves | How to run it |
|---|---|---|
| **Switch-off (revocation)** | Deleting the app stops the caller on its next request, with no config change and no redeploy. In this design, fast switch-off stands in for a short credential lifetime, so prove it once per environment. | Confirm the key returns `200`. Delete the app in the control plane (or rotate its credentials). Replay the **same** request with the **same** key. Expect `401` *Invalid API key in request*, within the gateway's credential cache delay. Measure that delay and publish it as your revocation time. Kept out of `verify.sh` because it destroys the credential every other case needs. |
| **Rotation** | The rotation procedure and its failure mode, before a real device needs it, since a fleet can't be updated all at once. | Create a **second** app for the same caller, give the device the new key, confirm it returns `200`, then delete the first app. Expect both keys to return `200` during the overlap, and the old key to return `401` once its app is deleted. Rotating one app's key in place cuts over immediately. |
| **`secret_validation` variant** | What `secret_validation: true` actually does, so nobody turns it on expecting a second factor. | In a **throwaway** environment only, add `secret_validation: true` and an `apisecret` block to the route, deploy, then send **only** the app's secret in the `apisecret` header, with no `X-Device-Key`. The plugin's own schema says it will succeed: the secret is accepted as an *alternative* credential. This variant is not shipped in this package's spec, and the expected result is the schema's description, not a result recorded here. |

Full procedures, plus the exact assertions each one makes:
[`tests/test-plan.yaml`](tests/test-plan.yaml).

## Coverage

| Type | Cases |
|---|---|
| Positive | valid key, write route |
| Negative | no key, unknown key, secret sent as key |
| Boundary | wrong header, key in the query string, rotation |
| Failure | switch-off (revocation), `secret_validation` variant |
