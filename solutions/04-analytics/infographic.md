# Infographic spec — Solution 04, Analytics (read what you already have)

**Status:** specification only. `assets/infographic.html` is not built — this is the
brief. Test any render at 300px wide; if the "one query → a ranked answer" idea
isn't legible there, it fails.

**Headline:** `You already have the data. Here's the query.`
**Sub:** `Requests, latency and errors by API, product or app — read-only, nothing to install`

---

### Panel 1 — CAPTURE IS AUTOMATIC (muted, calm)

Every request through any API flows into one store, with no plugin or config on the
APIs. Draw several API boxes → a gateway band labelled `log phase — captured
automatically` → a single **analytics store**. No "turn on" switch anywhere.

Caption: *"Every request is recorded the moment it's served — you add nothing to
your APIs."*

### Panel 2 — ONE QUERY, A RANKED ANSWER (the hero)

A single request card on the left, a result table on the right:

```
POST /analytics/metrics/requests-count           Requests by API — last 1h
{ "dimensions": ["api_name"],           ─────►    orders-api        17
  "sort": {"field":"value","order":"DESC"} }      checkout-api       9
                                                  partners-api       9
```

Show the same idea for the two other headline questions as small chips:
`group by app_name → who's calling` · `response-time AVG, sort DESC → slowest API`.

Verdict line: **A question is one POST. Read-only.**

### Panel 3 — WHAT YOU CAN ASK (compact grid)

Two columns.

*Metrics:* requests · req/sec · response time · request/response/transfer size ·
upstream time.
*Group or filter by:* api · product · app · developer · route · path · method ·
status · env.

One line beneath: *"Group route-level views by `route_id`, not `api_path`. Per-app
rows need the API to resolve identity."*

### Panel 4 — WHAT IT ISN'T (dark, short)

```
✓ averages / min / max        ✗ percentiles (p95/p99)
✓ count of 429s               ✗ "% of quota used"
✓ aggregate slices            ✗ single-request lookup (that's your logs)
```

### Footer

`read-only · nothing to install · no API changes` · `scripts/query-analytics.sh` ·
Solution 04 · repo URL.

---

## Design notes

- **The whole story is "read, don't build."** Nothing in the art should imply
  adding a plugin, a spec, or a route. No `helix-analytics` block anywhere — there
  isn't one.
- **Panel 2 is the hero:** one POST → a ranked table. If a viewer takes one thing,
  it's that an answer is a single query.
- Use real-looking but generic API names (`orders-api`, `checkout-api`); no real
  hosts, org ids, or customer names.
- **Do not draw percentiles, a quota gauge, or a single-request trace** — the API
  doesn't do those, and panel 4 says so.
- **Do not imply the agent runs the query.** Analytics is the metrics API / portal;
  the agent builds APIs, it doesn't read charts.
- Colour: calm/neutral for capture (panel 1), one accent for the query→answer (panel
  2), red used only for the ✗ column in panel 4.
- Keep the underlying gateway/runtime unnamed.
