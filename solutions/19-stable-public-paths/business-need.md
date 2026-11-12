# Stop backend renames from breaking your clients

> [Overview](README.md) · **Business need** · [Architecture](architecture.md) · [Guides](guides.md) · [Agent prompt](helix-agent-prompt.md) · [Tests](tests.md) · [API reference](api-reference.md)

---

> The backend team renames `/users` to something clearer. It is a small, sensible
> change. That afternoon the mobile app stops loading customers, and every app
> version already on people's phones stays broken until they update.
>
> **The clients were never calling an API. They were calling the backend.**

- **Backend changes stop being client releases.** Before: a renamed path means
  a new app version and a broken old one. After: it means one setting on the
  gateway, and no client notices.
- **The contract is written down.** Before: the "API" is whatever paths the
  backend has today. After: `/v1/customers` is published, versioned and
  tested, and the backend's paths are an internal detail.
- **Less is exposed.** Before: a client can call any path the backend serves.
  After: only the published paths have routes, and everything else gets a 404
  from the gateway.

| When the backend… | What changes on the gateway | What clients change |
|---|---|---|
| renames a path | the rewrite on that one route | nothing |
| moves to a new host | the upstream's host | nothing |
| changes what a response looks like | nothing (this solution moves calls, not data) | publish a `/v2/...` beside `/v1/...` |

A path rewrite is not free of traps: when a backend moves an id into its query
string, a client can add the same parameter again. The
[architecture page](architecture.md#what-happens-to-the-query-string) explains
what passes through, and the included test catches the trap.

*Also searched as: API path rewrite · decouple API from backend · stable API
contract · API versioning gateway · rename endpoint without breaking clients ·
URL rewrite proxy · hide backend paths · API facade · strangler pattern
routing.*
