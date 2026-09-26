# Test & verify — Solution 08 — API keys for callers that can't run a token exchange

[Overview](readme.md) · [Business need](business-need.md) · [How it works](how-it-works.md) · [Install](install.md) · [Configuration](configuration.md) · **Test & verify** · [Changelog](changelog.md)

---

## Testing

```bash
GATEWAY=https://<YOUR_GATEWAY_HOST> \
DEVICE_KEY=<DEVICE_API_KEY> APP_SECRET=<APP_SECRET> ./gateway/verify.sh
```

Exit 0 means all seven cases held:

| # | Case | Expected |
|---|---|---|
| 1 | No key | `401` *Missing API key in request* |
| 2 | A live app's key | `200` + the upstream's payload |
| 3 | An unknown key | `401` *Invalid API key in request* |
| 4 | **The right key in an `apikey:` header** | `401` |
| 5 | **The right key as a query parameter** | `401` |
| 6 | **The app's secret sent as the key** | `401` |
| 7 | The key on the write route | `201` |

**Cases 4-6 are the ones not to skip.** Each proves the contract is narrower than
it looks — the header name is part of it, `source: header` means header and
nothing else, and the credential's secret is not a second accepted credential.
Case 3 matters in the other direction: if an unknown key returns 200, the route
isn't resolving anything — it's passing traffic through while looking configured.

Revocation, rotation and the `secret_validation` variant are manual cases in
[`tests/test-plan.yaml`](tests/test-plan.yaml): the first two mutate
control-plane state and the third needs a configuration this package
deliberately does not ship.
