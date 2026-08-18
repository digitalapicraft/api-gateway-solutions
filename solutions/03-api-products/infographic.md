# Infographic spec — Solution 03, API Products

**Status:** specification only. `assets/infographic.html` is **not yet built** for
this package — this file is the brief a designer or a generator works from.
**Test before shipping:** shrink the render to 300px wide. If the blast-radius
contrast isn't readable at that size, it fails — that's how it appears in a feed.

**Headline:** `One partner's bug used to be everyone's outage`
**Sub:** `Quota on the product, counted per app — so the blast radius is the app that misbehaved`

---

### Panel 1 — BEFORE (muted, with one red actor)

A single API box labelled **Orders API**, sized `3,000 rpm`. Four partner apps feed
into it. One of them — and only one — is rendered in **red**, labelled
`retry loop · 40,000 rpm`.

The other three are drawn in the healthy palette but **all three are receiving
`503`**. That's the point of the panel: the failure is on the wrong parties.

Caption beneath: *"The offender is fine. Everyone else is down. You found out from
Twitter."*

### Panel 1b — WHY A GLOBAL LIMIT DOESN'T FIX IT (small, muted, optional but valuable)

The same picture with a `limit: 3000 rpm` band across the front. The red app still
fills the bucket; the other three now receive `429` instead of `503`.

Caption: *"A global limit rejects whoever is calling when the bucket fills. One
partner's bug becomes everyone's degraded service — less severe, same shape."*

This panel is what stops a reader concluding they already have this. If space is
tight it can be dropped, but the piece is weaker without it.

### Panel 2 — AFTER (signal / healthy)

Same **Orders API** box, drawn identically. Now behind a gateway band containing two
chips in order:

| Stage | Chip |
|---|---|
| 1 | `helix-auth` — *which app is this?* |
| 2 | `api-product-enforcer` — *what did they buy?* |

Four lanes through the band, each labelled with its product and quota:

```
red app      Free        60/min    ──►  429  {"error":"quota exceeded"}   ✗ stops here
partner B    Pro       1,000/min   ──►  200                               ✓
partner C    Pro       1,000/min   ──►  200                               ✓
partner D    Enterprise 10,000/min ──►  200                               ✓
```

**The three green 200s next to the one red 429, at the same moment, are the entire
message.** Not "we survived the spike" — *the offender was contained and nobody else
noticed.*

Verdict line: **Blast radius: one app.**

### Panel 2b — QUOTA LIVES ON THE THING YOU SELL (the hero)

The model, as a single left-to-right chain:

```
Developer  ──►  App  ──►  subscribes to  ──►  PRODUCT
                                               │
                                          APIs + QUOTA
                                               │
                                    counted PER APP ◄── emphasise this
```

Emphasise the **PRODUCT** node — it's the offering. Then one line beneath, which is
the commercial punchline:

*"Changing what a tier is worth is a product edit, not a deployment."*

This is the hero panel. It's the difference between "we added rate limiting" and "our
pricing page is now enforceable."

### Panel 3 — THE THREE THINGS TO GET RIGHT (dark, diff-style)

```
+ helix-auth              resolves the app AND its product subscription
- key-auth                authenticates but resolves NO subscription
                          ↳ the enforcer then 403s every request

+ api-product-enforcer:   error_policy only
- policy / redis_host     ← not in its schema. The quota BACKEND lives in
                            plugin_attr, and on >1 node it MUST be redis
                            ↳ default `local` counts per node: 3 nodes = 3x
                              the quota you sold

- limit-count on consumer_name    ← the generic-gateway reflex
+ the product quota               ← already counts per app
```

Three pairs. The middle one is the most valuable thing in the whole piece — it's
invisible from the route config and silently multiplies your quota by your node count.

### Footer

`helix-auth · api-product-enforcer · API Products · request-id` · `~20 min` ·
`no backend change` · Solution 03 · repo URL.

---

## Design notes

- **Colour:** structural blue for the gateway/fix, green for the healthy 200s, red
  used **twice and only twice** — the misbehaving app in panel 1, and its 429 in
  panel 2. Everything else muted. Red is the scarce resource in this piece; spending
  it on anything else weakens both uses.
- **The Orders API box must be drawn identically in panels 1, 1b and 2.** The claim
  is that the backend didn't change; a redrawn box contradicts it visually.
- **The single most important visual is the vertical stack in panel 2**: one red 429
  adjacent to three green 200s, simultaneously. If a reader takes one thing from the
  graphic, it's that adjacency. Do not separate them into different rows or panels.
- **Panel 2b is the hero.** Panel 2 is the mechanism; 2b is why anyone should care
  commercially.
- **Show real numbers.** `60/min`, `1,000/min`, `10,000/min` communicate tiering far
  better than "low / medium / high". Label them *illustrative* in the footer if
  there's room.
- **Do NOT show `X-RateLimit-*` or `Retry-After` headers anywhere.**
  `api-product-enforcer` emits neither, on success or on rejection. Drawing them
  would be the piece's one dishonest moment, and it's exactly the expectation that
  causes a partner escalation later. The 429 shows a status and a body. That's all it
  has.
- **Do not imply the client can see its remaining budget.** No gauges, no
  "847/1000 remaining" meters next to the partner apps. That number is not available
  to a client from any response.
- **Do not imply per-request pricing or billing.** This meters request counts; it is
  not a cost model, and a cheap read and an expensive report consume one unit each.
  No currency symbols, no invoices.
- **Do not imply burst shaping.** No smoothed-traffic waveforms. Quota counts within
  a window; a caller can spend a minute's budget in two seconds.
- **Do not draw the per-IP `limit-count` layer.** It exists on one route in the spec
  and is genuinely useful, but adding it here dilutes the per-app story into an
  inventory of limiters. It belongs in the README.
- **Do not imply end-user metering.** The unit is the app. No person icons.
- Keep the underlying gateway/runtime unnamed.
- Placeholders only in any rendered text — no real hosts, org ids or partner names.
  "partner B / C / D" is right; a recognisable company name is not.
