# Tests — two masks, two audiences

> [Overview](README.md) · [Business need](business-need.md) · [Architecture](architecture.md) · [Guides](guides.md) · [Agent prompt](helix-agent-prompt.md) · **Tests** · [API reference](api-reference.md)

---

The response side is checked by `example/verify.sh` against a live deployment —
six assertions over four test cases. The log side and the failure cases are
**4 manual** procedures, because no client-side check can see what a logger
wrote. The full machine-readable plan is
[`tests/test-plan.yaml`](tests/test-plan.yaml); this page is the readable
walkthrough of what it checks and why.

## Running the automated tests

```bash
GATEWAY=https://<YOUR_GATEWAY_HOST> ./example/verify.sh
# defaults: LIST_PATH=/support/customers  ONE_PATH=/support/customers/3  MASK=[redacted]
```

Exit code 0 means all six held:

| # | Check | Expected |
|---|---|---|
| 1 | **Every** record in the list | the email's personal part is masked — not just the first record's |
| 2 | The email domain | still readable |
| 3 | Every phone number | `[redacted]` |
| 4 | Every coordinate | `[redacted]` |
| 5 | A field the filters don't name | untouched |
| 6 | The single-record route | masked the same way |

**Check 1 is the one that matters.** It is the `scope: once` trap, checked rather
than hoped for: if exactly one record is masked, a filter is missing
`scope: global`. Check 5 is its mirror — proof the patterns are tied to their
field names and aren't quietly damaging fields nobody asked to mask.

In the test plan these are four cases: **list masked** (checks 1, 3, 4),
**domain survives** (check 2), **no over-masking** (check 5) and **single record**
(check 6). A 404 on the single-record route is a routing fault, not a masking
one — `proxy-rewrite`'s `regex_uri` carries the id. Filters are per route, so it is
easy to update one route and forget the other; this case catches that.

Raw fixtures, if you want to run one case by hand instead of the whole script:
[`tests/requests/`](tests/requests/) (the HTTP requests) and
[`tests/expected/`](tests/expected/) (the expected status and body for each — the
single source both `verify.sh` and the plan read from, so they can't drift apart).
The list fixture shows one record for brevity; the check is over all of them.

## The manual tests

| Case | What it proves | How to run it |
|---|---|---|
| **Log mask applied** | `log-data-mask` really changes what a logger writes — something no response check can show. | Add a logger (`http-logger` is easiest) pointing at a destination whose received body you can read, with `include_resp_body: true` and `batch_max_size: 1`. Call the route with an `Authorization` header and read what arrived. Then remove `log-data-mask` and compare. With it: every configured field replaced and the removed headers absent. Without it: the real values and the `Authorization` header, word for word. |
| **Log mask doesn't change the response** | The two masks are independent, so nobody ships `log-data-mask` believing the caller is protected. | Deploy a route with `log-data-mask` and **no** `response-rewrite`, and call it. The caller receives the sensitive fields in full. |
| **The `scope: once` trap** | What the most dangerous misconfiguration looks like, so you recognise it in review. | In a **throwaway** environment only, remove `scope: global` from one filter and call a route that returns many records. Only the first occurrence is masked — 1 of 10 records, 9 in the clear. Reviewing by eye won't catch it, because the record people look at first is the masked one. |
| **Encoded and renamed fields** | Where regex masking stops, against your own payloads. | Find a response where the same value appears under a different key, inside a base64 or URL-encoded string, or in free text, and call the route. Those copies are **not** masked. Use real payloads: error messages and audit-trail fields are where copies usually hide. |

Full procedures, plus the exact assertions each one makes:
[`tests/test-plan.yaml`](tests/test-plan.yaml).

## Coverage

| Type | Cases |
|---|---|
| Positive | list masked, single record, log mask applied |
| Negative | — |
| Boundary | domain survives, no over-masking, log mask doesn't change the response |
| Failure | `scope: once` trap, encoded and renamed fields |
