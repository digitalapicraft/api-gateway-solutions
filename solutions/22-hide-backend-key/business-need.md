# Keep one supplier key out of every app

> [Overview](README.md) · **Business need** · [Architecture](architecture.md) · [Guides](guides.md) · [Agent prompt](helix-agent-prompt.md) · [Tests](tests.md) · [API reference](api-reference.md)

---

> Your weather supplier gave you one API key. It's inside the mobile app, the web
> app and two partner integrations. Changing it takes four releases, and anyone
> who downloads the app can dig it out.
>
> **The key belongs in one place: the gateway, where no client can read it.**

- **Changing the supplier key.** Before: four coordinated releases. After: one
  change at the gateway, and no client notices.
- **Who holds the supplier key.** Before: every copy of every app. After: only
  the gateway's configuration.
- **Stopping one client.** Before: impossible without changing the key for
  everyone. After: switch off that client's app; the others carry on.

| Decision | This package's choice | Why |
|---|---|---|
| Where clients send their own key | the `X-Api-Key` header | A header stays out of URLs and the logs that copy them. |
| How the supplier key is added | set, not added | A client that sends its own supplier key can't override yours. |
| The client's own key | removed before the supplier | Otherwise every client's key ends up in the supplier's logs. |

The supplier key is still stored, as plain text, in the API's configuration, so
anyone who can edit the API can read it. [Architecture](architecture.md#limits-worth-knowing)
lists that and the other limits.

*Also searched as: hide API key from frontend · keep third-party API key off
the client · API key proxy · inject API key at gateway · add header to upstream
request · secure API key in mobile app · rotate API key without app release ·
backend for frontend API key · strip client API key before upstream.*
