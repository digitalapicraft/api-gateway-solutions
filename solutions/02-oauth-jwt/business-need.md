# OAuth 2.0 client credentials and JWT authentication at the API gateway

> Your partner API sits behind a static key that never expires — or behind
> nothing. Everyone agrees it needs auth; nobody ships it, because "add OAuth"
> means a backend release and a migration for every integrator.
>
> **At the edge it's a configuration change.**

- **Exposure window: indefinite → minutes.** The long-lived secret is used once
  per token lifetime, against one endpoint. Everything else on the wire expires
  on its own.
- **Backend code changed: none.** Verifying who is calling needs no knowledge of
  your domain model.
- **Every call attributable to a named app** — what metering, quotas, analytics
  and incident response all read.

The token lifetime is the security control, and the one real decision here:

| TTL | A leaked token is usable for | Token requests per client, per hour |
|---|---|---|
| 300s | up to 5 minutes | ~12 |
| 900s | up to 15 minutes | ~4 — this package's default |
| 3600s | up to 1 hour | ~1 |
| 24h | up to a day | negligible — and you've rebuilt the static key |

It authenticates **applications, not end users**, and it is authentication, not
authorization. [Before/after, the mechanism, and what this does not buy you are
in the README](README.md#business-need).

*Also searched as: OAuth2 client credentials flow · JWT API authentication ·
machine-to-machine (M2M) API auth · replace API keys with OAuth · API gateway
token endpoint · secure a public REST API · partner API authentication.*
