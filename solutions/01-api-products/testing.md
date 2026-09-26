# Test & verify — Solution 01 — API Products: sell tiers you can actually enforce

[Overview](readme.md) · [Business need](business-need.md) · [How it works](how-it-works.md) · [Install](install.md) · [Configuration](configuration.md) · **Test & verify** · [Changelog](changelog.md)

---

## What the caller actually sees

Be honest with partners about this, because it's the part that surprises them:

```http
HTTP/1.1 429 Too Many Requests
content-type: application/json

{"error":"quota exceeded"}
```

**`api-product-enforcer` emits no `X-RateLimit-*` headers and no `Retry-After`.** A
client cannot read its remaining quota off a response. Two consequences to design
around:

- **Publish the retry contract in your docs**, since the response can't carry it.
  Tell integrators the window length and tell them to back off exponentially *with
  jitter*. Without jitter, every client retries at the same instant at the top of
  each window and you've built a thundering herd on a schedule.
- **Surface remaining quota in the portal and analytics**, not in headers. See
  [solution 04](../04-analytics/) for the queries.

If you genuinely need budget headers on the response today, that's a `limit-count`
with `show_limit_quota_header: true` — a *different* limiter with a different key.
Don't try to make the product enforcer do it.

## Testing

```bash
GATEWAY=https://<YOUR_GATEWAY_HOST> \
FREE_KEY=<free app client id> PRO_KEY=<pro app client id> FREE_LIMIT=5 \
./gateway/verify.sh          # defaults to /posts
```

Exit 0 means all five held:

| # | Case | Expected |
|---|---|---|
| 1 | No key | `401` |
| 2 | Unknown key | `401` |
| 3 | Valid Free key | `200` |
| 4 | Past the window | `429` `{"error":"quota exceeded"}` |
| 5 | **A second app on a different product, at that same moment** | still `200` |

**Case 5 is the whole point.** Cases 1–4 only prove a rate limit exists — any
limiter does that. Case 5 proves the limit is scoped to the *offending app* rather
than to your API, which is the entire business case. Don't skip it.

The two keys **must come from two separate apps.** Quota is counted per app, so two
keys on one app share a bucket and correct isolation will look broken.
`verify.sh` refuses to run if you pass the same key twice.

Full plan, including the boundary case at exactly the limit and the fail-close
behaviour:
[`tests/test-plan.yaml`](tests/test-plan.yaml).
