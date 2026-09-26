# How it works — Solution 08 — API keys for callers that can't run a token exchange

[Overview](readme.md) · [Business need](business-need.md) · **How it works** · [Install](install.md) · [Configuration](configuration.md) · [Test & verify](testing.md) · [Changelog](changelog.md)

---

## Which credential shape fits your caller

This is the fork in the road, and it is decided by the caller, not by your
preference.

| Your caller | Use | Why |
|---|---|---|
| **Can set a header, nothing more** — embedded device, legacy middleware, a partner's cron job | **`helix-auth` validate · key-auth** — this solution | One header. The gateway resolves it to an app. Revocation is immediate. |
| **Can hold a secret and run an exchange** — a partner's backend, a server-side integration | **`helix-auth` generate + validate** — [solution 02](../02-oauth-jwt/) | The long-lived secret stops travelling; a leaked token expires on its own. |
| **Already gets tokens from your IdP** — Okta, Entra ID, Auth0, Keycloak | **`openid-connect`** — [solution 05](../05-okta-jwt/) | The gateway verifies somebody else's tokens; it must not mint its own. |
| **Can hold a secret and the payload's integrity matters** | **`hmac-auth`** — [solution 06](../06-hmac-auth/) | The credential never travels at all; the signature covers the body. |

All four answer "who is calling". You want exactly one of them on a route.

## Request path

```
Terminal ──X-Device-Key──▶ Gateway ──▶ Upstream
                             │
                             ├── request-id        (API-wide, correlation)
                             ├── helix-auth        (access phase, priority 2450)
                             │     validate · key-auth · apikey.source: header
                             │     resolve the key to an app credential
                             └── proxy-rewrite     (rewrite phase, priority 1008)
                                   retarget the upstream path
```

What happens to a request, in the order it actually happens:

1. **rewrite phase** — `proxy-rewrite` retargets the upstream path. It takes no
   part in the auth decision; it runs first because the rewrite phase runs before
   the access phase, not because it is more important.
2. **access phase** — `helix-auth` reads the configured header, resolves the value
   to an app credential in the org, and attaches that identity to the request
   context. No match, or no header at all, ends the request here with a 401. The
   upstream is never contacted.
3. **upstream** — the request is forwarded with the caller's identity already
   established. Downstream plugins that need to know who is calling — metering,
   analytics — read it from the context rather than re-deriving it.

**Phase beats priority, and priority only orders within a phase.** `helix-auth`
has the higher priority number (2450 against 1008) and still runs second, because
its phase is later. This is the single most common source of "the plugins are in
the wrong order" confusion on this platform.

## Native vs custom

Entirely native. `helix-auth` in `validate` mode with `validate_auth_type:
key-auth` is the platform's own answer to API-key identity, and it resolves the
key to the same app object that products, quotas and analytics are keyed on.

Two alternatives were considered and rejected:

- **A standalone `key-auth` plugin.** It does not exist on this build. `key-auth`
  and `jwt-auth` are `validate_auth_type` *values* of `helix-auth`. Reaching for
  a plugin by that name is the most common wrong turn here.
- **A custom policy checking a header against a list.** It would work and it would
  be wrong: the list has to live somewhere, revocation becomes a config deploy
  again, and the resolved identity would be invisible to every other plugin that
  expects the platform's app object. The whole operational benefit of this
  solution comes from the credential being a first-class control-plane resource.

No custom code is required, and none is included.

## Why the key is resolved rather than compared

A configuration that compares an incoming header to a literal value in the spec
would authenticate too — and would be a materially worse system:

| | Literal in the config | Resolved to an app credential |
|---|---|---|
| Where the secret lives | In the spec, in git, in every revision | On the credential, issued by the control plane |
| Revoking one caller | Edit and redeploy the API | Delete the app |
| Callers per key | One key, everybody shares it | One credential per caller |
| Who can see it | Anyone who can read the repo | Nobody; it is never in the document |
| Metering and analytics | Nothing to attribute to | The app is the unit both are keyed on |

This is why the shipped spec has no key in it, and why that absence is a feature
rather than an omission.

## When not to use this shape

- **The caller can run a token exchange.** Then it should — a credential that
  expires on its own is strictly better where it is available.
  [Solution 02](../02-oauth-jwt/).
- **An external IdP already issues tokens.** The gateway must be a verifier, not a
  second issuer. [Solution 05](../05-okta-jwt/).
- **The body's integrity is the point.** A key authenticates the sender and says
  nothing about the payload. [Solution 06](../06-hmac-auth/).
- **The credential cannot be kept out of public reach** — a single-page app or a
  mobile binary. A key shipped in client code is a published key, and no gateway
  configuration changes that.
- **You need per-user identity or consent.** Different problem entirely.

## Failure modes and what they look like

| Symptom | Cause |
|---|---|
| Every request 401s with *Missing API key in request* | The header name on the wire is not the one in `apikey.key`, or the key is in the query string while `source` is `header` |
| Every request 401s with *Invalid API key in request* | The value is not a credential key — usually the app id or the app secret was sent instead |
| Dry-run rejects the config, naming `apikey` | `apikey.source` is absent. It is required in practice even though the published schema marks it optional |
| A valid key returns **403** | Authentication succeeded, authorization did not: the app's product does not cover this API |
| A revoked caller keeps working for a short while | Credential state is cached at the gateway; the cache interval is your real revocation latency |
| Turning on `secret_validation` lets a caller in with only the secret | That is what the flag does — it accepts the secret as an *alternative* credential, not an additional one |
