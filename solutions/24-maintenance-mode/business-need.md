# Planned API downtime without errors or retry storms

> [Overview](README.md) · **Business need** · [Architecture](architecture.md) · [Guides](guides.md) · [Agent prompt](helix-agent-prompt.md) · [Tests](tests.md) · [API reference](api-reference.md)

---

> The database migration runs from 02:00 to 03:00 on Saturday. For that hour,
> every client gets timeouts and 502s, retries in a loop, and shows its users
> "something went wrong". On Monday, support reads the tickets.
>
> **The outage was planned. The callers should have been told so.**

- **Callers get an answer they can act on.** Before: a timeout or a 502 that
  looks like a fault. After: a 503 saying "down for maintenance, try again at
  03:00", the same on every route.
- **The backend restarts without a queue of retries.** Before: clients retry at
  once, again and again. After: `Retry-After` tells them when to come back, and
  the gateway answers every call, so none reach the backend.
- **The switch belongs to operations, not to a release.** Before: a code change
  to put a notice up and another to take it down. After: deploy one revision to
  switch on, deploy the previous one to switch off.

The one decision to get right is how to say "come back later":

| `Retry-After` value | Use it when |
|---|---|
| A date: `Sat, 07 Nov 2026 03:00:00 GMT` | the window has a known end. Every caller is given the same moment. |
| A number of seconds: `300` | the end isn't known yet. It means "check again in 5 minutes", counted from each response. |

A fixed number of seconds sent all through a known window tells each caller a
different end time, all of them too late. Your own apps also need to read the
header and show the time to the user; that part is theirs. What the gateway can
and can't cover is in [Architecture](architecture.md#limits).

*Also searched as: API maintenance mode · maintenance page for API · return
503 during deployment · Retry-After header · planned downtime API gateway ·
API outage message · take API offline temporarily · maintenance window
response.*
