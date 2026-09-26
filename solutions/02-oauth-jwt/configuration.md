# Configuration — OAuth 2.0 with JWT

[Overview](readme.md) · [Business need](business-need.md) · [How it works](how-it-works.md) · [Install](install.md) · **Configuration** · [Test & verify](testing.md) · [Changelog](changelog.md)

---

## The two plugin blocks

Source of truth: [`gateway/api-spec.yaml`](gateway/api-spec.yaml). Two blocks
carry the whole solution.

On the token endpoint:

```yaml
helix-auth:
  mode: generate
  token_ttl: 900
  signing_secret: "<YOUR_JWT_SIGNING_SECRET>"
```

On every protected route:

```yaml
helix-auth:
  mode: validate
  validate_auth_type: jwt-auth
  signing_secret: "<YOUR_JWT_SIGNING_SECRET>"
```

**Note what isn't there.** `validate` is applied per route, not at the document
root. Applying it API-wide would protect `/oauth/token` too — and then no caller
could ever obtain a first token, because getting one would require already having
one. The symptom is an API where literally every request returns 401, including
the one that's supposed to fix that.

## CORS — the wildcard is only safe because credentials are off

`cors.allow_origins` is `"*"` in this spec. That is right for a public partner
API and wrong for anything carrying browser session state.

What makes the wildcard safe here is `allow_credential: false` — the browser
will not attach cookies or HTTP-auth to a cross-origin call, so a hostile page
cannot ride a visitor's session. **Do not set `allow_credential: true` without
first narrowing `allow_origins` to an explicit list.** The two settings are only
safe in combination; flipping one without the other is the mistake.

`authorization` must stay in `allow_headers` either way, or browsers fail at
preflight and you get a CORS error rather than a 401.

## Choosing a token lifetime

`token_ttl` is the only number in this solution with a real trade-off, so choose
it rather than inheriting a default.

| TTL | Buys you | Costs you |
|---|---|---|
| **300s** (5 min) | A leaked token is worthless almost immediately | A token request every five minutes per client; clients that don't cache will hammer the endpoint |
| **900s** (15 min) | Short exposure window, modest token traffic | Reasonable for most partner integrations — this is the default in this spec |
| **3600s** (1 hour) | Minimal token traffic | A leaked token is usable for up to an hour |
| **24h+** | Nothing worth having | You have reinvented the static API key, with extra steps |

The thing to tell integrators: **cache the token and reuse it until shortly
before it expires.** Refresh at around 80% of the lifetime. A client that
requests a fresh token per API call turns your token endpoint into your busiest
route and doubles the latency of everything.
