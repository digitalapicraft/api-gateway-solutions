# Tests — HMAC request signing at the edge

> [Overview](README.md) · [Business need](business-need.md) · [Architecture](architecture.md) · [Guides](guides.md) · [Agent prompt](helix-agent-prompt.md) · **Tests** · [API reference](api-reference.md)

---

10 test cases in total: **8 automated**, run by `example/verify.sh` against a live
deployment, and **2 manual**, for things the script can't do on its own (a second
signing library, and changing the route's configuration). The full
machine-readable plan is [`tests/test-plan.yaml`](tests/test-plan.yaml); this page
is the readable walkthrough of what it checks and why.

## Running the automated tests

```bash
GATEWAY=https://<YOUR_GATEWAY_HOST> \
KEY_ID=<KEY_ID> \
SECRET_KEY=<SECRET_KEY> \
./example/verify.sh
```

`KEY_ID` and `SECRET_KEY` come from the app credential the control plane
generated (see [Guides](guides.md#install-it-directly)). They are never in the
spec. Optional: `WRITE_PATH` (default `/posts`) and `READ_PATH` (default
`/posts/1`). The script needs only `bash`, `curl` and `openssl`.

Exit code 0 means all eight held:

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

**Case 6 is the one that matters most.** Remove `signed_headers` from the route
and this request succeeds, while every other case still passes and the API is
wide open. It is the only case that tests your *configuration* rather than the
plugin.

**Case 7 is expected to succeed.** The plugin has no replay protection: a copied
request works again until its `Date` leaves the 300-second window. The script
asserts this rather than just describing it, so that if replay protection ever
appears on your build, the case fails and you notice. See
[Architecture](architecture.md#limits-worth-knowing).

Case 2 is also the check that the signing steps in this package are the ones the
gateway rebuilds. Case 5 matters most if it fails: a wrong secret being accepted
would mean the signature is decorative. Case 8 confirms the read route's
no-digest signed set. Separately, a signature made for `GET /posts/1` returns 200
there and 401 on `/posts/2`, because the path is part of what is signed.

Raw fixtures, if you want to run one case by hand instead of the whole script:
[`tests/requests/`](tests/requests/) (the HTTP requests) and
[`tests/expected/`](tests/expected/) (the expected status and body for each — the
single source of truth both `verify.sh` and the plan read from, so they can't
drift apart).

## The manual tests

| Case | What it proves | How to run it |
|---|---|---|
| **A draft-cavage client** | An off-the-shelf HTTP Signatures library does **not** work with this, so the failure is recognised as a format mismatch rather than chased as a credential problem. | Sign the same request with any draft-cavage library, using the same `key_id` and secret, and send it. Expect `401`: the library leaves out the `keyId` line, adds no final newline, and writes `(request-target): post /posts` in lowercase. Each difference alone changes the signature. Worth running once per integration. |
| **`signed_headers` removed** | What leaving out `signed_headers` costs, so it is never treated as optional. | In a **throwaway** environment only, remove `signed_headers` from the write route. Sign a base made of the `keyId` alone (`headers=""`, no `Date`, no `Digest`). Send that one `Authorization` header with several different bodies and paths. Expect every one to be accepted: one signature, copied once, works for any request indefinitely. |

Full procedures, plus the exact assertions each one makes:
[`tests/test-plan.yaml`](tests/test-plan.yaml).

## Coverage

| Type | Cases |
|---|---|
| Positive | signed POST, signed GET |
| Negative | no signature, body changed, wrong secret, weak signed set |
| Boundary | stale `Date` |
| Failure | replay, draft-cavage client, `signed_headers` removed |
