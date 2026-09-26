# Test & verify — Solution 11 — the lookup every service re-implements, done once at the edge

[Overview](readme.md) · [Business need](business-need.md) · [How it works](how-it-works.md) · [Install](install.md) · [Configuration](configuration.md) · **Test & verify** · [Changelog](changelog.md)

---

## Testing

Exit 0 means all five cases held:

| # | Case | Expected |
|---|---|---|
| 1 | The read route | `200`, and the backend received `X-Tenant-Plan` |
| 2 | The second mapped field | present at the backend |
| 3 | `X-Profile-Status` | `200` — the **callout's** status, not the route's |
| 4 | **A client sending its own `X-Tenant-Plan`** | overwritten by the gateway |
| 5 | The write route | `200`, body forwarded, and enriched too |

**Case 4 is the one not to skip**, and case 3 is quietly useful: mapping the
callout's own status lets a backend tell a real answer from a fail-open miss.

The failure-policy and phase-ordering cases are manual — each needs a route
deliberately pointed at an unreachable callout. All three were reproduced during
validation; the procedures are in [`tests/test-plan.yaml`](tests/test-plan.yaml).
