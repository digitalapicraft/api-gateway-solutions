# Solution 24 — Maintenance mode: tell callers you're down, and when to come back

> **Overview** · [Business need](business-need.md) · [Architecture](architecture.md) · [Guides](guides.md) · [Agent prompt](helix-agent-prompt.md) · [Tests](tests.md) · [API reference](api-reference.md)

**In short:** while your backend is down for planned work, the gateway answers
every call itself with "down for maintenance, try again at 03:00". You switch it
on and off by deploying a revision, not by releasing code.

| | |
|---|---|
| **Time to try it** | About 15 minutes |
| **Difficulty** | 🟢 Beginner — no coding needed |
| **What you'll need** | A free test account. The sample API in this package stands in for your own. |

---

## What is maintenance mode?

**Maintenance mode** is a second version of your API's gateway settings, kept
ready for planned outages. In it, the gateway doesn't pass calls on to your
backend. It answers each one straight away with HTTP 503 (service unavailable),
a `Retry-After` header that says when to try again, and a short JSON message.

Each version of an API's settings is a **revision**. Only one revision of an API
is live in an environment at a time. Switching maintenance on means deploying
the maintenance revision; switching it off means deploying the one you had
before. That is the same rollback the platform already gives you.

## The use case

> *"Saturday 02:00 we migrate the bookings database. The backend will be down
> for about an hour. Last time, clients got timeouts and 502s, retried in tight
> loops, and the mobile app showed 'something went wrong'. We want them told,
> cleanly: down for maintenance, try again at a stated time. And we want to
> switch it on and off without a code release."*

Without a maintenance switch, an outage looks like a failure:

- **Callers see errors they can't act on.** A timeout or a 502 (bad gateway)
  says something broke, not that the break is planned and when it ends.
- **Clients retry at once, and keep retrying.** The backend comes back to a
  queue of retries.
- **Turning a notice on takes a release.** Someone changes code to show a
  maintenance page, then changes it back afterwards.

## What maintenance mode gives you

- **One clear answer on every route.** Every call gets the same 503 with the
  same message, whatever the route or method.
- **A time to come back.** `Retry-After` carries the end of the window as a
  date. The JSON body carries it too, so an app can show it to the user.
- **No calls to your backend.** The gateway answers the call itself, so the
  backend can be fully stopped.
- **A switch, not a release.** On and off are both a deploy of a revision you
  already have. Each takes a second or two to reach the gateway.

## Benefits

- **Fewer support tickets.** Users read "back at 03:00" instead of "something
  went wrong".
- **A calmer restart.** Clients that read `Retry-After` wait until the stated
  time instead of retrying in a loop.
- **Safe to rehearse, nothing to undo.** Run the whole switch on a test
  environment first. Switching back deploys the earlier revision, unchanged.

## Example

The sample `Bookings API` has three routes. Here is what callers get in each
state:

| Call | Normal | Maintenance |
|---|---|---|
| `GET /bookings` | `200`, the list, from the backend | `503`, `Retry-After: Sat, 07 Nov 2026 03:00:00 GMT`, JSON message |
| `GET /bookings/1` | `200`, booking 1 | the same `503` |
| `POST /bookings` | `201`, the new booking | the same `503`. The backend never sees the call. |

The `503` body, as callers receive it:

```json
{"error":"maintenance","message":"Bookings is down for planned maintenance. Please try again after 03:00 UTC.","retry_after":"2026-11-07T03:00:00Z"}
```

**In the UI it takes three steps once the API is built:** use **Clone Revision**
on the live revision, add the maintenance response to the copy with
**Configure plugin**, then **Force Deploy** the copy. To switch back, deploy the
earlier revision again.
[Full walkthrough →](guides.md#build-it-in-the-ui)

[Build it any of three ways, then see it work →](guides.md)

## Where to go next

- **Want the business case first?** [Business need](business-need.md) explains why
  this matters, in plain terms.
- **Want to understand how it works?** [Architecture](architecture.md) covers the
  two states, the switch, and why `Retry-After` is a date here.
- **Ready to try it?** [Guides](guides.md) walks you through it step by step.
- **Want the full product documentation?** Every plugin, screen and API call is
  covered at [docs.digitalapi.ai/api-gateway](https://docs.digitalapi.ai/api-gateway).

## Related solutions

- **[12 — Key-value store](../12-key-value-store/)** — the same answering plugin,
  used to build a sandbox with per-partner replies.
- **[16 — Request tracing](../16-request-tracing/)** — trace a call during
  maintenance and the record says **Upstream not called**: proof the backend
  was left alone.
- **[01 — API Products](../01-api-products/)** — if your API checks keys, that
  check still runs during maintenance. See
  [Architecture](architecture.md#limits).
- **[17 — Mock before the backend exists](../17-mock-before-backend/)** — the
  same gateway answer before a backend exists, rather than while it is down.
- **[23 — Retire an old version](../23-retire-old-version/)** — a gateway answer
  for routes that are gone for good: `410` instead of `503`.
