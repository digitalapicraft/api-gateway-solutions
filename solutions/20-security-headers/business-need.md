# Close security-header findings across every API, once

> [Overview](README.md) · **Business need** · [Architecture](architecture.md) · [Guides](guides.md) · [Agent prompt](helix-agent-prompt.md) · [Tests](tests.md) · [API reference](api-reference.md)

---

> The pen test report lands with three findings that look trivial: two missing
> headers and one that says too much. Then someone counts the services. Twelve,
> owned by four teams on four release schedules, and the remediation date is two
> weeks out.
>
> **Every one of those responses already passes through the gateway.**

- **One change instead of twelve.** The headers are set in one block for the
  whole API. Teams keep their release schedules, and nobody's backlog grows.
- **The thirteenth service is covered on day one.** A route added later gets the
  same headers without anyone remembering to ask.
- **Nothing for the data owners to re-test.** Only headers change. Every
  response body is byte-for-byte what the backend sent.

The one decision to make up front is where each header belongs:

| Header | Set it at |
|---|---|
| `Cache-Control`, `X-Content-Type-Options`, `X-Frame-Options`, `Content-Security-Policy`, `Referrer-Policy` | the gateway, once per API |
| `Strict-Transport-Security` (HSTS) | where TLS ends for the host, because it covers the whole host |

This closes the header findings; it doesn't make an API secure. Authentication,
input checks and data exposure are separate findings with separate fixes.
[What it covers and what it doesn't](architecture.md#what-it-does-not-do).

*Also searched as: add security headers API gateway · remove X-Powered-By header ·
Cache-Control no-store API · OWASP secure headers REST API · hide server version
header · pen test missing security headers · X-Content-Type-Options nosniff
gateway · Content-Security-Policy for JSON API.*
