# Changelog — 02-oauth-jwt

[Overview](readme.md) · [Business need](business-need.md) · [How it works](how-it-works.md) · [Install](install.md) · [Configuration](configuration.md) · [Test & verify](testing.md) · **Changelog**

---

Tags: **Breaking** · **Feature** · **Fix** · **Docs**. Versions match
[`solution.yaml`](solution.yaml).

## 1.1.0 — 2026-09-25

- **Fix** — corrected three places that described `signing_secret` as an
  environment variable resolved at deploy. This build uses the field verbatim, so
  an unreplaced placeholder becomes a publicly-known HMAC key. The spec and the
  agent prompt were already correct; the architecture and overview pages were not.
- **Docs** — split into seven pages from one 398-line document. Two recorded
  caveats that had never actually been written down — the CORS wildcard being
  safe only while `allow_credential` is false, and the upstream being bound to
  the service at import rather than declared here — are now documented.

## 1.0.0 — 2026-08-18

- **Feature** — Initial published solution.
