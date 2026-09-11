# Infographic spec — Solution 05, OAuth with Okta

**Status:** specification only. `assets/infographic.html` is not yet built; this
is the brief a designer or a generator works from.

**Test before shipping:** shrink the render to 300px wide. If the four-defaults
panel is unreadable, cut rows rather than shrink type.

**Headline:** `Okta already issues your tokens.`
**Sub:** `The gateway's job is to verify them — and its defaults are wrong for an API.`

---

### Panel 1 — BEFORE (muted / legacy)

A service box with a key glyph taped to it. Around it, scattered copies of the
same key: an envelope, a wiki page, a CI config, a laptop. A small Okta logo sits
off to one side, greyed, connected to nothing.

Caption: *"Okta governs every human. The APIs check a key someone emailed in
2021."*

Verdict line: **No expiry. No owner. No review.**

### Panel 2 — AFTER (signal / healthy)

Okta now connects to the client with a short arrow labelled `RS256 JWT`. A second
arrow goes from client to a gateway boundary. From the gateway, one thin dashed
arrow reaches back to Okta labelled `JWKS · fetched once, cached`.

The key glyphs are gone.

Caption: *"Okta mints. The gateway verifies. The backend never learns that
anything changed."*

Verdict line: **One config block. Zero backend releases.**

### Panel 2b — THE DIRECTION THAT MATTERS (the one idea)

A single horizontal rule with the issuer boundary marked:

```
   OKTA ISSUES  │  GATEWAY VERIFIES
   private key  │  public keys only
   never leaves │  fetched from JWKS
```

Caption: *"The gateway never holds a key that can mint a token."*

### Panel 3 — THE FOUR DEFAULTS TO CHANGE (dark, diff-style)

```
- unauth_action: auth        → redirects API clients to a login page
+ unauth_action: deny

- ssl_verify: false          → fetches the root of trust unverified
+ ssl_verify: true

- accept_unsupported_alg: true   → "ignore signature to accept unsupported alg"
+ accept_unsupported_alg: false

- (no claim_validator)       → any issuer that signs correctly is accepted
+ claim_validator.issuer.valid_issuers: [ your Okta authorization server ]
```

Verdict line: **All four are defaults. All four are wrong for an API.**

### Footer

`openid-connect · request-id · cors` · verified against a live plugin schema ·
spec imports and dry-runs clean

---

## Design notes

- **Do not imply rate limiting, quota or metering.** This solution applies no
  `api-product-enforcer` and no `limit-count`. It authenticates; it does not
  meter. Claiming a quota the validated config does not enforce would break the
  rule that the infographic describes the actual implementation.
- **Do not imply authorization.** No scopes are enforced in this configuration.
  `required_scopes` exists and is deliberately unused.
- **Do not imply the audience is checked against a value.** It is not, and cannot
  be — see the README. If a panel mentions claims, say *issuer*, not *audience*.
- **Do not imply revocation.** A disabled Okta app stops new tokens; existing ones
  live out their expiry.
- **Do not draw Okta on the request path.** The dashed JWKS arrow must be visibly
  different from the request arrows, or the whole latency argument inverts.
- Keep the underlying gateway/runtime unnamed.
- Placeholders only in any rendered text — no real Okta domains, hosts, org ids
  or partner names.
