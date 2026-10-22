# Tests — API keys checked at the gateway

> [Overview](README.md) · [Business need](business-need.md) · [Architecture](architecture.md) · [Guides](guides.md) · [Agent prompt](helix-agent-prompt.md) · **Tests** · [API reference](api-reference.md)

---

There are 10 test cases in total:

- **7 automated.** `example/verify.sh` runs them against a live deployment.
- **3 manual.** They change things in the control plane (where you manage APIs,
  products, developers and apps), or they need a configuration this package
  deliberately does not ship.

The full plan, in a form a script can read, is
[`tests/test-plan.yaml`](tests/test-plan.yaml). This page explains in plain words
what it checks and why.

## Running the automated tests

```bash
GATEWAY=https://<YOUR_GATEWAY_HOST> \
DEVICE_KEY=<DEVICE_API_KEY> APP_SECRET=<APP_SECRET> \
./example/verify.sh
```

`DEVICE_KEY` is the app's credential **key**. (An app's credential is the key and
secret the control plane created for it.) Use the key, not the secret and not the
app's id.
`APP_SECRET` is optional. It turns on case 6; without it, case 6 is skipped with
a note. You can also change these settings: `READ_PATH` (default
`/fleet/price-list`), `WRITE_PATH` (default `/fleet/takings`), `KEY_HEADER`
(default `X-Device-Key`).

Exit code 0 means all seven passed:

| # | Case | Expected |
|---|---|---|
| 1 | No key | `401` *Missing API key in request* |
| 2 | A live app's key | `200` + the upstream's data |
| 3 | An unknown key | `401` *Invalid API key in request* |
| 4 | **The right key in an `apikey:` header** | `401` |
| 5 | **The right key as a query parameter** | `401` |
| 6 | **The app's secret sent as the key** | `401` |
| 7 | The key on the write route | `201` |

(401 means not authenticated. 200 means OK. 201 means the item was created. The
upstream is your backend service, where the gateway forwards requests that pass.)

**Don't skip cases 4–6.** Each one proves the gateway accepts less than you might
expect:

- **Case 4:** the header *name* matters. The right key under another name is
  refused.
- **Case 5:** `source: header` means the header and nothing else. The right key in
  the URL's query string (the part after `?`) is refused.
- **Case 6:** the app's secret is not accepted in place of its key. Turning on
  `secret_validation: true` would change exactly this.

**Case 3 matters for the opposite reason.** If an unknown key returns 200, the
route isn't checking keys at all. It is letting traffic through while looking
set up. An unknown key is also what a switched-off caller looks like. That is
what makes switch-off possible to test.

To run one case by hand instead of the whole script, use the raw files:
[`tests/requests/`](tests/requests/) holds the HTTP requests, and
[`tests/expected/`](tests/expected/) holds the expected status and body for each.
Both `verify.sh` and the plan read their expected results from those files, so
the two can't drift apart.

## The manual tests

| Case | What it proves | How to run it |
|---|---|---|
| **Switch-off (revocation)** | Deleting the app stops the caller on its next request. No config change and no new deploy are needed. In this design, quick switch-off takes the place of a credential that expires on its own, so prove it once in each environment. | Check that the key returns `200`. Delete the app in the control plane (or give it new credentials). Send the **same** request with the **same** key again. Expect `401` *Invalid API key in request*, within the gateway's credential cache delay (how long the gateway keeps a short-term copy of credential details). Measure that delay and publish it as the time it takes to switch a caller off. This test is not in `verify.sh` because it destroys the credential every other case needs. |
| **Changing a key (rotation)** | How to give a caller a new key, and what goes wrong, before a real device needs it. Devices can't all be updated at once. | Create a **second** app for the same caller. Give the device the new key and check it returns `200`. Then delete the first app. Expect both keys to return `200` while both apps exist, and the old key to return `401` once its app is deleted. Giving one app a new key in place cuts over at once. |
| **`secret_validation` variant** | What `secret_validation: true` really does, so nobody turns it on expecting a second check. | In a **throwaway** environment only, add `secret_validation: true` and an `apisecret` block to the route, and deploy. Then send **only** the app's secret in the `apisecret` header, with no `X-Device-Key`. The plugin's own schema (its list of fields) says this will succeed: the secret is accepted as an *alternative* credential. This variant is not in this package's spec. The expected result is the schema's description, not a result recorded here. |

Full steps, and exactly what each one checks:
[`tests/test-plan.yaml`](tests/test-plan.yaml).

## Coverage

| Type | Cases |
|---|---|
| Positive | valid key, write route |
| Negative | no key, unknown key, secret sent as key |
| Boundary | wrong header, key in the query string, changing a key (rotation) |
| Failure | switch-off (revocation), `secret_validation` variant |
