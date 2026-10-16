# Enrich requests from a lookup service, at the API gateway

> Every service starts the same way: call the customer-profile service, find out
> what plan the tenant is on, then do the actual work. Orders caches it for five
> minutes, billing for an hour, and notifications not at all, which is why profile
> gets paged. When the field name changed last quarter, the seventh copy of that
> call turned up in a service nobody had touched since 2023.
>
> **Make the call once, before the request is proxied, and hand the answer to the
> backend as headers.**

- **Copies of the lookup: one per service → one, in configuration.** A new service
  reads a header instead of building the call first.
- **Failure behaviour: whatever each team chose → one policy per route, written
  down.** Reads can proceed without the answer; writes can refuse.
- **Calls on the profile service: one per service per request → one per request.**

The policy is the decision that matters, and it is made per route:

| If the lookup fails on… | Choose | The caller gets |
|---|---|---|
| a read, where acting without the answer is survivable | fail-open | a 200, and the backend gets no enrichment headers |
| a write, where acting without it is worse than failing | fail-close | a 503, and the backend is never called |

It fetches an answer; it doesn't decide whether a caller is allowed. The
dependency is consolidated, not removed: one synchronous call stays in the request
path, and nothing is cached unless you add it. [Before/after, the two settings that
make it work, and what this does not buy you are in the
README](README.md#business-need).

*Also searched as: service callout at the API gateway · enrich requests with data
from another service · inject headers from a lookup · request enrichment before
proxying · call an external service in the gateway · tenant context headers ·
remove a shared lookup from every microservice.*
