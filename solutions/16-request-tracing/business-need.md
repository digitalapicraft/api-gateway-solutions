# Debug live API calls without redeploying

> [Overview](README.md) · **Business need** · [Architecture](architecture.md) · [Guides](guides.md) · [Agent prompt](helix-agent-prompt.md) · [Tests](tests.md) · [API reference](api-reference.md)

---

> A partner's integration starts failing on Friday afternoon. Your dashboards say
> "400s are up". The gateway team says it's the backend, the backend team says
> the request never arrived, and the partner says they changed nothing.
>
> **The missing piece is one fact: what happened to that request, step by step.**

- **Time to root cause: hours → minutes.** One reproduction under a trace
  replaces the ask-redeploy-wait loop. No logging change ships to production
  to find out.
- **The right team picks it up first.** Each record says whether a gateway
  plugin or the backend answered, so the incident is routed correctly the
  first time.
- **Evidence instead of opinion.** A record shows what the partner sent and
  what the backend received, so the partner conversation is about facts.

Two habits make it safe on a live API:

| Habit | Why |
|---|---|
| Filter to what you need | A session records a handful of requests. Spend them on the failing call, not on healthy traffic. |
| Trace with test credentials | Headers are recorded as sent. A production key in a trace is a production key in a log. |

Tracing is for **this request, right now**. For trends across all traffic, use
analytics ([solution 04](../04-analytics/)). [How a record is read, and what
it does not show, is in the architecture page](architecture.md).

*Also searched as: API request tracing · debug API gateway 400 · why is my API
returning 401 · API request inspector · live API debugging · gateway vs backend
error · API latency breakdown · trace a single API call.*
