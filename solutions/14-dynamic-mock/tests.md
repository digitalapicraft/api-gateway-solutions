# Tests — a sandbox that answers every partner with their own values

> [Overview](README.md) · [Business need](business-need.md) · [Architecture](architecture.md) · [Guides](guides.md) · [Agent prompt](helix-agent-prompt.md) · **Tests** · [API reference](api-reference.md)

---

6 test cases in total, **all automated**, run in order by `example/verify.sh`
against a live deployment. None needs waiting or changing environment
configuration. The full machine-readable plan is
[`tests/test-plan.yaml`](tests/test-plan.yaml); this page is the readable
walkthrough of what it checks and why.

## Running the automated tests

```bash
GATEWAY=https://<YOUR_GATEWAY_HOST> ./example/verify.sh
```

Override the paths with `REGISTER_PATH`, `PROFILE_PATH` and `DIAGNOSTICS_PATH` if
yours differ. The script makes up fresh partner ids on every run, because the store
outlives the test: a re-run against the same environment would otherwise be
answered by the previous run's values.

Exit code 0 means all six held:

| # | Case | Expected |
|---|---|---|
| 1 | Register a partner | `202` |
| 2 | That partner reads its profile | `200`, carrying that partner's own tier and settlement account |
| 3 | **A second partner reads its profile** | `200`, its own values — and **not** the first partner's |
| 4 | An unregistered partner | `200` with empty values, not an error |
| 5 | **Re-register the first partner, then read** | the new values, immediately — no revision, no route change, no deploy |
| 6 | **The diagnostics route** | the bare `$ctx` form shows the value; the `${...}` form is empty |

**Case 3 checks an absence.** A shared-key bug would still return a plausible 200,
so the script asserts that the first partner's tier does **not** appear in the
second partner's response.

**Case 4 is the package's main caveat, written as a test.** The store cannot know
whether a value mattered, so nothing here fails closed. If an empty tier must not
be served, the check belongs downstream of this route.

**Case 5 is the business claim.** The write and the read are separate requests on
separate routes; the store is what connects them.

**Case 6 is the one worth keeping.** The wrong template syntax returns 200 with an
empty string and logs nothing. If the braced form ever starts working, this
package's central explanation is wrong and its guidance should change.

Case 1's `202` confirms the insert was configured, not that a value was written.
Case 2 is what confirms the write. Its fixture also records the `X-Partner-Tier`
response header, which shows that `response_headers` are filled in the same way as
the body; `verify.sh` checks the body, not the header.

Raw fixtures, if you want to run one case by hand instead of the whole script:
[`tests/requests/`](tests/requests/) (the HTTP requests) and
[`tests/expected/`](tests/expected/) (the expected status and body for each — the
single source both `verify.sh` and the plan read from, so they can't drift apart).
The partner ids in the fixtures are illustrative.

## The manual tests

None. Two behaviours are deliberately **not** covered, and are worth checking on
your own store before you rely on them: what happens when the store itself is
unreachable (`fail_action: close` is set, but no outage was simulated), and whether
values written in one environment are visible in another.

## Coverage

| Type | Cases |
|---|---|
| Positive | register, profile for a registered partner, profile for a second partner |
| Negative | profile for an unregistered partner |
| Boundary | change without deploy |
| Failure | template-syntax guard |
