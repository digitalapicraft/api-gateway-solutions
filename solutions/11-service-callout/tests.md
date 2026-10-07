# Tests — one outbound call, then injection

> [Overview](README.md) · [Business need](business-need.md) · [Architecture](architecture.md) · [Guides](guides.md) · [Agent prompt](helix-agent-prompt.md) · **Tests** · [API reference](api-reference.md)

---

8 test cases in total: **4 automated**, run by `example/verify.sh` against a live
deployment (five checks), and **4 manual**, because each needs a deliberately
broken route or a load test. The full machine-readable plan is
[`tests/test-plan.yaml`](tests/test-plan.yaml); this page is the readable
walkthrough of what it checks and why.

## Running the automated tests

```bash
GATEWAY=https://<YOUR_GATEWAY_HOST> ./example/verify.sh
```

Exit code 0 means all five checks held:

| # | Check | Expected |
|---|---|---|
| 1 | The read route | `200`, and the backend received `X-Tenant-Plan` with a value |
| 2 | The second mapped field | `X-Tenant-Contact` present at the backend |
| 3 | `X-Profile-Status` | `200` — the **callout's** status, not the route's |
| 4 | **A client sending its own `X-Tenant-Plan`** | overwritten by the gateway |
| 5 | The write route | `200`, the body forwarded unchanged, and enriched too |

**Check 4 is the one not to skip.** It is the difference between enrichment and a
way for callers to raise their own privileges, and it breaks silently if someone
changes `set` to `add` while tidying up. Check 3 is quietly useful: mapping the
callout's own status lets a backend tell a real answer from a fail-open miss.
Check 5 catches the plugin being per route — a route added later gets no
enrichment until someone remembers.

In the test plan these are four cases: **enriched read** (checks 1 and 3),
**second mapped field** (check 2), **spoofed header** (check 4) and **enriched
write** (check 5).

The checks look at what the **backend** received, so they need a backend that
echoes request headers. The example backend does. Against your own, run
`ECHOES_HEADERS=0 ./example/verify.sh` and read your backend's log instead.

Raw fixtures, if you want to run one case by hand instead of the whole script:
[`tests/requests/`](tests/requests/) (the HTTP requests) and
[`tests/expected/`](tests/expected/) (the expected status and body for each — the
single source both `verify.sh` and the plan read from, so they can't drift apart).

## The manual tests

| Case | What it proves | How to run it |
|---|---|---|
| **Callout down, fail-close** | On a write path, an unreachable profile service stops the request rather than letting it go ahead without the answer. | In a **throwaway** environment, point the write route's callout at a host that doesn't resolve, and call the route. Expect **503** with `tenant profile unavailable`, and the backend never called. Fixture: [`tests/requests/callout-down.http`](tests/requests/callout-down.http). |
| **Callout down, fail-open** | On a read path, an unreachable profile service does **not** stop the request — and the headers are simply absent. | Same, with the read route's `fail-open` policy. Expect 200, and the backend receives the request with the enrichment headers **absent**, not empty. This case decides whether fail-open is right for your route. |
| **Wrong phase** | What the most common misconfiguration looks like: a callout that runs too late to be read. | In a **throwaway** environment, change the callout's `phase` from `rewrite` to `access` and call the route. Expect 200 and no enrichment headers at the backend. Nothing errors. |
| **Latency budget** | What the callout costs, since the request waits for it. | Compare p50 and p99 for the route with the callout against an equivalent route without it, under representative load, then set `timeout` from the result. Expect roughly the profile service's own response time, with the worst case bounded by `timeout` (3000 ms as shipped). |

Full procedures, plus the exact assertions each one makes:
[`tests/test-plan.yaml`](tests/test-plan.yaml).

## Coverage

| Type | Cases |
|---|---|
| Positive | enriched read, second mapped field, enriched write |
| Negative | spoofed header |
| Boundary | latency budget |
| Failure | callout down with fail-close, callout down with fail-open, wrong phase |
