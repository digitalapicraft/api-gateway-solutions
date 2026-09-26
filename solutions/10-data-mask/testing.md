# Test & verify — Solution 10 — mask the values, not just the log line

[Overview](readme.md) · [Business need](business-need.md) · [How it works](how-it-works.md) · [Install](install.md) · [Configuration](configuration.md) · **Test & verify** · [Changelog](changelog.md)

---

## Testing

Exit 0 means all six response-side cases held:

| # | Case | Expected |
|---|---|---|
| 1 | **Every** record in the list | email local part masked — not just the first |
| 2 | The email domain | still readable |
| 3 | Every phone number | `[redacted]` |
| 4 | Every coordinate | `[redacted]` |
| 5 | A field the filters don't name | untouched |
| 6 | The single-record route | masked identically |

**Case 1 is the one that matters.** It is the `scope: once` trap, asserted rather
than hoped for. Case 5 is its mirror: proof the patterns are anchored and are not
quietly corrupting fields nobody asked to mask.

`verify.sh` cannot check the log half — no client-side assertion can see what a
logger wrote. [`tests/test-plan.yaml`](tests/test-plan.yaml) carries the
procedure, and this package's validation run executed it: a logger on the route,
a sink whose received body was read back, and the same route with `log-data-mask`
removed for comparison.
