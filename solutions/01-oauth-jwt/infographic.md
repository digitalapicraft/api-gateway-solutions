# Infographic spec — Solution 01, OAuth 2.0 with JWT

**Status:** specification only. `assets/infographic.html` is **not yet built** for
this package — this file is the brief a designer or a generator works from.
**Test before shipping:** shrink the render to 300px wide. If the before/after
contrast isn't readable at that size, it fails — that's how it appears in a feed.

**Headline:** `Your API needs OAuth. Your backend doesn't need to know.`
**Sub:** `Issue and verify tokens at the edge — a config change, not a release`

---

### Panel 1 — BEFORE (muted / legacy)

A single API box labelled **Partner API**, with a static key travelling on every
arrow into it. Draw **four** partner icons, each holding an identical key glyph,
and label the arrows with one chip repeated: **`apikey: static — never expires`**.

Beneath the API box, a small stack of muted artefacts showing where that key ended
up: an email icon, a config file, a CI log. Not alarming, just *everywhere*.

The honest point this encodes: the credential isn't secret in any meaningful
sense, because it was copied four times and nobody knows all the copies.

Caption beneath: *"Six weeks of backend work to fix. So it goes on the risk
register instead."*

### Panel 2 — AFTER (signal / healthy)

The same API box, **unchanged** — this matters, render it identically to panel 1 —
now behind a gateway band. Two clearly separated lanes pass through the band:

| Lane | At the edge | Partner sees |
|---|---|---|
| `POST /oauth/token` | `helix-auth` **generate** — verifies client id **and secret** | `{ access_token, token_type, expires_in: 900 }` |
| `GET /posts` | `helix-auth` **validate** (jwt-auth) — signature + expiry | `200`, or `401` before the backend |

Show a small **clock chip** on the token — `expires in 15 min` — because the
bounded lifetime is the whole security argument. The partner icons now hold a
`client_id` + `client_secret` pair rather than a bare key, and the arrows into the
backend carry a short-lived token glyph.

One rejection arrow bounces off the gateway band and never reaches the API box.
Label it `401 — access phase`. That the request stops *at the band* is the visual
point.

Verdict line: **The backend never changed. The credential now expires.**

### Panel 2b — THE EXPOSURE WINDOW (the one number that matters)

A single horizontal bar, the pitch in one line:

```
static key    ├──────────────────────────────────────────────────────►  indefinite
JWT (900s)    ├──┤  15 minutes
```

Two bars, wildly different lengths, same starting point. The static key bar runs
off the edge of the panel — deliberately, it has no end. Caption: *"You haven't
removed the risk of a leaked credential. You've bounded it — from indefinite to
the number you chose."*

This is the hero panel. Give it room.

### Panel 3 — THE THREE THINGS TO GET RIGHT (dark, diff-style)

```
+ helix-auth (generate)  on POST /oauth/token      issues the JWT
+ helix-auth (validate)  on the protected routes   checks the JWT
                         ↳ SAME signing_secret on both, or every token 401s

- jwt-auth               (that's for an EXTERNAL issuer's tokens)
+ helix-auth generate    the gateway is the issuer here

- validate API-wide      would protect /oauth/token too
+ validate per route     ↳ or nobody can ever get a first token
```

Three pairs, tight. The third one is the funniest and least known — an API where
*every* request 401s including the one that issues tokens.

### Footer

`helix-auth (generate + validate) · request-id · cors` · `~15 min` ·
`no backend change` · Solution 01 · repo URL.

---

## Design notes

- **Colour:** structural blue as the "signal/fix" colour, green for healthy, red
  reserved for the single thing that breaks (here: the `401` when secrets
  mismatch, in panel 3). The legacy static key in panel 1 is rendered in muted
  slate, **never red** — it isn't a villain, it's just unbounded.
- **Panel 1 and panel 2 must show the same backend box, drawn identically.** The
  entire claim is "nothing behind the gateway moved." If a designer redraws or
  recolours it, the claim is visually contradicted.
- **The clock chip on the token is non-negotiable.** Expiry is the security
  control. An infographic that shows OAuth without showing the lifetime is
  showing ceremony.
- **Panel 2b is the hero.** Everything else is mechanism; the exposure window is
  the outcome.
- Don't draw the JWT's internal structure. Nobody reads header/payload/signature
  at feed size, and it invites questions the piece doesn't answer.
- **Do not imply rate limiting, quota or metering.** This solution applies no
  `api-product-enforcer` and no `limit-count`. It authenticates; it does not
  meter. Claiming a quota the validated config doesn't enforce would break the
  rule that the infographic describes the actual implementation.
- **Do not imply end-user login.** Client credentials authenticates an
  *application*. No person icons with padlocks, no "sign in" affordance — that's
  the authorization code flow and this isn't it.
- **Do not imply revocation.** There's no revocation list; expiry is the
  mechanism. A "revoke" button in the art would be a claim the package explicitly
  disowns.
- Keep the underlying gateway/runtime unnamed.
- Placeholders only in any rendered text — no real hosts, org ids or partner
  names.
