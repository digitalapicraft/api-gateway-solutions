# Tests — HMAC request signing at the gateway

> [Overview](README.md) · [Business need](business-need.md) · [Architecture](architecture.md) · [Guides](guides.md) · [Agent prompt](helix-agent-prompt.md) · **Tests** · [API reference](api-reference.md)

---

There are 10 test cases in total. **8 are automated**: `example/verify.sh` runs
them against a live deployment. **2 are manual**, for things the script can't do on
its own: trying a second signing library, and changing the route's settings. The
full plan, in a form scripts can read, is
[`tests/test-plan.yaml`](tests/test-plan.yaml). This page explains what it checks
and why.

## Running the automated tests

```bash
GATEWAY=https://<YOUR_GATEWAY_HOST> \
KEY_ID=<KEY_ID> \
SECRET_KEY=<SECRET_KEY> \
./example/verify.sh
```

`KEY_ID` and `SECRET_KEY` come from the app's credential. The control plane (where
you manage APIs, products and apps) creates them for you; see
[Guides](guides.md#install-it-directly). They are never in the spec. Optional
settings: `WRITE_PATH` (default `/albums`) and `READ_PATH` (default `/albums/1`).
The script needs only `bash`, `curl` and `openssl`.

Exit code 0 means all eight checks passed:

| # | Case | Expected |
|---|---|---|
| 1 | No signature | `401` |
| 2 | Correct signature | `201` |
| 3 | Body changed after signing | `401` |
| 4 | `Date` 20 minutes old | `401` |
| 5 | Correct `key_id`, wrong secret | `401` |
| 6 | **Caller signs less than the route requires** (no `digest` in `headers=`) | `401` |
| 7 | **The exact same request, sent again** | **`201` — accepted again** |
| 8 | Signed `GET` on the read route | `200` |

**Case 6 matters most.** Remove `signed_headers` from the route and this request
succeeds. Every other case still passes, but the API is wide open. It is the only
case that tests your *configuration* rather than the plugin.

**Case 7 is expected to succeed.** The plugin does not stop someone resending a
copied request. A copy works again until its `Date` is more than 300 seconds old.
The script checks that this really happens, rather than just describing it. So if
your build ever starts blocking resent requests, the case fails and you notice.
See [Architecture](architecture.md#limits-worth-knowing).

Case 2 also checks that the signing steps in this package match the ones the
gateway rebuilds. Case 5 matters most if it fails: if a wrong secret were accepted,
the signature would give no protection at all. Case 8 confirms that the read route
accepts a signature with no body fingerprint (no digest). Separately, a signature
made for `GET /albums/1` returns 200 there and 401 on `/albums/2`, because the path
is part of what is signed.

Raw fixtures, if you want to run one case by hand instead of the whole script:
[`tests/requests/`](tests/requests/) (the HTTP requests) and
[`tests/expected/`](tests/expected/) (the expected status and body for each).
Both `verify.sh` and the plan read the expected results from that one place, so
they can't drift apart.

## The manual tests

| Case | What it proves | How to run it |
|---|---|---|
| **A draft-cavage client** | A ready-made HTTP Signatures library (built for the older draft-cavage standard) does **not** work with this. Knowing that, you treat the failure as a format mismatch, not a credential problem. | Sign the same request with any draft-cavage library, using the same `key_id` and secret, and send it. Expect `401`. The library leaves out the `keyId` line, adds no final newline, and writes `(request-target): post /albums` in lowercase. Each difference alone changes the signature. Worth running once per integration. |
| **`signed_headers` removed** | Shows what leaving out `signed_headers` costs, so nobody treats it as optional. | In a **throwaway** environment only, remove `signed_headers` from the write route. Sign text made of the `keyId` alone (`headers=""`, no `Date`, no `Digest`). Send that one `Authorization` header with several different bodies and paths. Expect every one to be accepted: one signature, copied once, works for any request, for ever. |

Full steps, plus the exact checks each one makes:
[`tests/test-plan.yaml`](tests/test-plan.yaml).

## Coverage

| Type | Cases |
|---|---|
| Positive | signed POST, signed GET |
| Negative | no signature, body changed, wrong secret, signature covers too little |
| Boundary | `Date` too old |
| Failure | same request sent again, draft-cavage client, `signed_headers` removed |
