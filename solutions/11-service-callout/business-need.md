# API request enrichment with a gateway service callout

> [Overview](README.md) · **Business need** · [Architecture](architecture.md) · [Guides](guides.md) · [Agent prompt](helix-agent-prompt.md) · [Tests](tests.md) · [API reference](api-reference.md)

---

> Every service starts the same way: call the customer-profile service to find
> the caller's plan and account status. One caches it for five minutes, one for an
> hour, one not at all. One retries, one carries on, one fails the request. When
> the profile service changes a field name, the seventh copy of the call is found
> by an incident, not by the search.
>
> **It isn't one lookup written several times. It's several different systems
> that happen to call the same endpoint.**

- **One call, one cache, one timeout**, configured where the traffic is, instead
  of inherited from whoever wrote each service.
- **One failure policy per route, chosen on purpose.** A read can carry on without
  the answer; a write shouldn't. Those are business decisions, now visible in one
  file.
- **New services start with the answer.** They read a header instead of building
  the lookup first — the part that pays for the work.

| Before | After |
|---|---|
| The lookup is built into every service | Once, in configuration |
| Failure behaviour varies and is undocumented | Fail-open on reads, fail-close on writes |
| The profile service takes one call per service per request | One call per request |

No figures here are measured savings; they are the reasoning. It isn't an
authorization decision, and it consolidates the dependency rather than removing
it. [What it does not do is in Architecture](architecture.md#what-it-does-not-do).

*Also searched as: API request enrichment · gateway service callout · add
headers from external service · call another API before proxying · tenant
context header · API gateway lookup · upstream header injection.*
