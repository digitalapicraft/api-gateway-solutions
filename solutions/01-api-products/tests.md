# Tests — API Products with enforced quota

[Overview](README.md) · [Business need](business-need.md) · [Architecture](architecture.md) ·
[Guides](guides.md) · [Examples](examples.md) · [Agent prompt](helix-agent-prompt.md) ·
**Tests** · [Configuration reference](configuration-reference.md) ·
[API reference](api-reference.md)

---

11 test cases in total: **5 automated**, run by `example/verify.sh` against a live
deployment, and **6 manual**, for behaviour no single HTTP request can prove on its
own (multi-node counting, a backend outage, and so on). The full machine-readable
plan is [`tests/test-plan.yaml`](tests/test-plan.yaml); this page is the readable
walkthrough of what it checks and why.

## Running the automated tests

```bash
GATEWAY=https://<YOUR_GATEWAY_HOST> \
FREE_KEY=<free app client id> PRO_KEY=<pro app client id> FREE_LIMIT=5 \
./example/verify.sh          # defaults to /posts
```

Exit code 0 means all five held:

| # | Case | Expected |
|---|---|---|
| 1 | No key | `401` |
| 2 | Unknown key | `401` |
| 3 | Valid Free key | `200` |
| 4 | Past the window | `429` `{"error":"quota exceeded"}` |
| 5 | **A second app on a different product, at that same moment** | still `200` |

**Case 5 is the whole point.** Cases 1–4 only prove that *a* rate limit exists —
any limiter can do that. Case 5 proves the limit stays with the *offending app*
instead of spreading to everyone else, which is the entire reason this solution
exists. Don't skip it.

The two keys **must come from two separate apps.** Quota is counted per app, so
two keys from one app share a bucket, and correct isolation will look broken.
`verify.sh` refuses to run if you pass the same key twice.

Raw fixtures, if you want to run one case by hand instead of the whole script:
[`tests/requests/`](tests/requests/) (the HTTP requests) and
[`tests/expected/`](tests/expected/) (the expected status/body for each — the
single source of truth both `verify.sh` and the plan read from, so they can't
drift apart).

## The manual tests

These need something `verify.sh` can't do on its own — changing gateway-level
config, or observing behaviour across nodes — so they're a checklist, not a
script.

| Case | What it proves | How to run it |
|---|---|---|
| **Unlimited product** | An app on a product with `limit: -1` is never throttled, but is still authenticated and attributed — unlimited must not mean unidentified. | Subscribe a third app to an Internal product (`limit: -1`). Send more calls than any metered tier allows. Confirm no `429` ever, then confirm the calls still show up in analytics attributed to that app. |
| **Product with no quota** | A product with no `quota` object is a `403`, not "unlimited" — the opposite of what most people assume. | In a **throwaway** test environment only, create a product with no `quota` object, subscribe an app to it, and call the API. Expect `403`. |
| **Quota backend unreachable** *(optional)* | With `error_policy: fail_close` (the default), a backend outage returns `503` instead of silently serving unmetered traffic. | Make the quota backend unreachable (stop Redis, or point `plugin_attr` at an unreachable host) and call with a valid key — expect `503`. Then flip to `fail_open` and repeat — expect success, unmetered. Run both halves once, deliberately; which behaviour you want is a business decision, not a bug. |
| **Multi-node counting** | The quota is counted globally, not per gateway node. This is the single most common way the solution fails to deliver its promise, and it's invisible from the route config. | On a gateway with more than one node, send requests through the load balancer until `429`. If it arrives at roughly N× the configured limit on N nodes, `quota_policy` is `local` and each node is counting on its own — fix by setting it to `redis` in `plugin_attr.api-product-enforcer`. |
| **Developer-scope pooling** | What `quota_key_scope: developer` actually changes, since it's a real trade-off, not just a tidier default. | Give one developer two apps on the same product. Under the default (`app`) scope, confirm each has its own bucket. Set `quota_key_scope: developer` on the product and confirm the two apps now share one. |

Full procedures, plus the exact assertions each one makes:
[`tests/test-plan.yaml`](tests/test-plan.yaml).

## Coverage

| Type | Cases |
|---|---|
| Positive | valid Free call, isolation |
| Negative | unauthenticated, unknown key |
| Boundary | quota exhausted, unlimited product, developer-scope pooling |
| Failure | product with no quota, quota backend unreachable, multi-node counting |
