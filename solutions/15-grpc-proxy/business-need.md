# Authentication for gRPC streams, without changing the service

> [Overview](README.md) · **Business need** · [Architecture](architecture.md) · [Guides](guides.md) · [Agent prompt](helix-agent-prompt.md) · [Tests](tests.md) · [API reference](api-reference.md)

---

> Timing units, payment terminals and telemetry agents hold a gRPC stream open for
> hours. Nothing in front of them can see the connection, so every team builds its
> own key check inside its own service.
>
> **Some of your traffic is not requests. It is connections.**

- **Authentication ships as configuration.** A streaming service that had none
  gains it with no code change, checked once as each connection opens.
- **One check instead of one per service**, against the same app credentials as
  every other API.
- **Connections become visible** — how many, and how long each stayed open — per
  app, without the service reporting anything.

One fact decides whether this fits your commercial model:

| | Ordinary API calls | gRPC streams through the gateway |
|---|---|---|
| What a policy sees | Every request | The moment each stream opens — **once** |
| What a quota counts | Requests | **Streams**, not messages. A million messages on one connection use one unit. |
| Revoking a credential | Stops the next request | Stops the next stream. An open stream carries on until it ends. |

If you planned to charge per message at the gateway, that does not work with
streams, and no setting changes it. For hours-long streams, decide deliberately
how a revoked client is cut off — a maximum stream lifetime enforced by the
service, or an out-of-band disconnect. More in
[Architecture](architecture.md#what-this-does-not-do).

*Also searched as: gRPC API gateway authentication · gRPC streaming proxy ·
authenticate gRPC metadata · bidirectional stream gateway · API key for gRPC ·
long-lived connection monitoring · gRPC reflection through a proxy.*
