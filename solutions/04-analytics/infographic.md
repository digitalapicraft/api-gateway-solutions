# Infographic spec — Solution 04, Analytics

> Note: the shipped API for this solution is minimal (two routes, no auth). Identity
> (`helix-auth`, solution 01) is a **compose-in** for per-app names; panels that show it
> illustrate that optional step, not the base API.

**Status:** specification only. `assets/infographic.html` is **not yet built** for this
package — this file is the brief a designer or a generator works from.
**Test before shipping:** shrink the render to 300px wide. If the before/after row
contrast isn't readable at that size, it fails — that's how it appears in a feed.

**Headline:** `You already have the data. It just can't answer the question.`
**Sub:** `Analytics is always on — three request-path decisions decide whether it's useful`

---

### Panel 1 — BEFORE (muted, and deliberately not "broken")

A dashboard card, rendered competently rather than dysfunctionally: **`4.2M calls`**,
**`1.8% errors`**, a clean traffic sparkline. It looks *good*. That's the point.

Beneath it, the analytics table it can actually produce:

```
route              caller            status   latency
/posts/ord_1a2b3c  203.0.113.47      200      41ms
/posts/ord_4d5e6f  203.0.113.47      200      38ms
/posts/ord_7g8h9i  198.51.100.22     500      2.1s
/posts/ord_2j3k4l  203.0.113.47      200      44ms
…
```

Every row a different route. Every caller an IP. Nothing aggregates.

Speech-bubble overlay, in the muted palette: *"Something hammered us at 3am. Which of
our 400 integrations was it?"* — with no answer beneath it.

Caption: *"Nothing is broken. Every request was captured faithfully. The question is
just unanswerable."*

### Panel 2 — AFTER (signal / healthy)

The same table, same window, transformed:

```
route                   app               calls   errors   max ms
/posts/{postId}       partner-b-prod    1,204   0.1%     52ms
/posts/{postId}       partner-c-batch     318   0.0%     61ms
/posts                 partner-b-prod      892   0.2%     44ms
/posts/report          partner-d-analytics  14   0.0%     28s
```

Four rows. Named apps. Templated routes. A max-latency that means something — and note the
report route's 28s sitting visibly apart from the 44ms reads, which is the
latency-profile point made without a word.

Same speech bubble, now answered: *"partner-b-prod, 1,204 calls, from 03:02."*

Verdict line: **Same data. Same window. Now it groups.**

### Panel 2b — THE THREE DECISIONS (the hero)

Three chips feeding one row of captured data. This is the mechanism, and it's the panel
to give room to:

```
  helix-auth        ──►  app · developer      ← without it: an IP address
  templated path    ──►  route                ← without it: one row per record
  request-id        ──►  request_id           ← without it: no way to reach one call
                              │
                              ▼
                    ┌───────────────────┐
                    │  one captured row │  ← written in the LOG phase, last.
                    └───────────────────┘     It records. It cannot investigate.
```

Then, banded across the bottom in the emphasis colour — **this is the single most
important sentence in the graphic:**

> **All three must be true BEFORE the data is captured. Nothing fixes it afterwards.**

### Panel 3 — THE ONE THING NOT TO DO (dark, diff-style)

```
- helix-analytics: {}     ← there is nothing to add. It is already global.
                            Every request is being captured right now.

+ helix-auth              identity, so rows have a name
+ /posts/{postId}       templated, so a route is one row
+ request-id              correlation, so a row leads to a request
```

One pair. Keep it stark. This is the reflex to break: on most platforms observability
*is* a plugin you enable, so both engineers and agents reach for one by name.

### Footer

`analytics: already on` · `helix-auth · request-id · templated paths` · `~10 min` ·
`real metrics-API queries → charts.md` · Solution 04 · repo URL.

---

## Design notes

- **Colour:** structural blue for the fix, green for the healthy "after" rows, red used
  **once** — the `500 / 2.1s` row in panel 1, so the eye has somewhere to land in a table
  of otherwise-fine data. The panel-1 dashboard card must be rendered in the *healthy*
  palette, not a warning one.
- **Panel 1 must look competent, not broken.** This is the most easily-lost point in the
  piece. A designer's instinct will be to make the "before" state look alarming — red
  numbers, error badges, a sad face. That inverts the argument. The before state is a
  perfectly good dashboard that cannot answer a question, and if it looks broken the
  reader concludes "we don't have that problem, ours is fine."
- **The two tables are the hero of panels 1 and 2, not the dashboard card.** Same data,
  same window, one groups and one doesn't. Set them in monospace and align the columns so
  the row-count difference (many vs four) reads instantly at thumbnail size.
- **Panel 2b is the hero of the piece.** Panels 1 and 2 show the symptom and the cure;
  2b is the mechanism and the urgency. The "BEFORE the data is captured" band is the line
  most worth someone remembering.
- **Show the templated route with braces literally** — `/posts/{postId}`. The braces
  are the whole visual difference between the two tables, so don't let a designer
  prettify them away.
- **Keep the `28s` report row in panel 2.** It makes the latency-profile-separation
  argument silently, and it stops the "after" table looking uniformly rosy.
- **Do NOT draw a helix-analytics plugin anywhere except crossed out in panel 3.** The
  entire framing is that there's nothing to enable.
- **Do not imply real-time alerting.** No bell icons, no "ALERT" badges, no threshold
  lines. This is query-and-chart; alerting is a different tool and implying otherwise sets
  up a disappointed reader.
- **Do not show request or response bodies.** Not captured, by design — drawing a payload
  would advertise something the platform deliberately doesn't do, and for a good reason.
- **Do not imply per-hop / internal tracing.** No span waterfalls inside the backend.
  Latency here is edge-measured; a waterfall diagram would promise distributed tracing.
- **Do not show quota consumption as if it came free.** There is no quota-% metric; the 429/throttle recipe needs solution 03. If a
  quota gauge appears, tag it `+ solution 03`.
- **Use placeholder IPs from the documentation ranges only** (`203.0.113.x`,
  `198.51.100.x`) and invented app names (`partner-b-prod`). No real addresses, hosts, org
  ids or customer names.
- Keep the underlying gateway/runtime unnamed.
