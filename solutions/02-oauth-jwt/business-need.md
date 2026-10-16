# OAuth 2.0 client credentials and JWT authentication at the API gateway

> [Overview](README.md) · **Business need** · [Architecture](architecture.md) · [Guides](guides.md) · [Agent prompt](helix-agent-prompt.md) · [Tests](tests.md) · [API reference](api-reference.md)

---

> Your partner API sits behind a static key that never expires — or behind
> nothing. Everyone agrees it needs auth; nobody ships it, because "add OAuth"
> means a backend release and a migration for every integrator.
>
> **At the edge it's a configuration change.**

- **How long a stolen credential works: indefinitely → minutes.** The long-lived
  secret is used once per token lifetime, against one endpoint. Everything else on
  the wire expires on its own.
- **Backend code changed: none.** Checking who is calling needs no knowledge of
  your business logic.
- **Every call tied to a named app** — which is what metering, quotas, analytics
  and incident response all rely on.

The token lifetime is the security control, and the one real decision here:

| Token lifetime | A leaked token is usable for | Token requests per client, per hour |
|---|---|---|
| 300s | up to 5 minutes | ~12 |
| 900s | up to 15 minutes | ~4 — this package's default |
| 3600s | up to 1 hour | ~1 |
| 24h | up to a day | almost none — and you've rebuilt the static key |

## Before and after

| | Public or static-key API | With gateway-issued tokens |
|---|---|---|
| **Time to ship auth** | A backend release, plus a coordinated partner migration | A configuration change and a deploy |
| **How long a leaked credential works** | Until someone revokes the key — often years | Minutes; the long-lived secret never travels on API calls |
| **Backend changes** | Every handler touched; auth bugs become application bugs | None; a bad token never reaches your code |
| **Partner security review** | "We use an API key in a header" | Standards-based OAuth 2.0 client credentials |
| **Revoking access** | Find every place the key was configured | Disable the app; its next token request fails and existing tokens expire on their own |

You haven't removed the risk of a leaked credential. You have put a time limit on
it, and you chose the number.

No return-on-investment figure is claimed anywhere in this package. The six weeks
in the quote on the [Overview](README.md) is the reasoning teams give, not a
measurement; what is quantified is the mechanism — how long a token lasts and how
much token traffic that costs. Use your own release schedule and your own list of
credentials in use.

It authenticates **applications, not end users**, and it proves who is calling,
not what they may do. [What this does not buy you is on the Architecture
page](architecture.md#limitations).

*Also searched as: OAuth2 client credentials flow · JWT API authentication ·
machine-to-machine (M2M) API auth · replace API keys with OAuth · API gateway
token endpoint · secure a public REST API · partner API authentication.*
