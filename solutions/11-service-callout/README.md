# Solution 11 — Service callout: do the shared lookup once at the gateway, and hand the answer to your backend

> **Overview** · [Business need](business-need.md) · [Architecture](architecture.md) · [Guides](guides.md) · [Agent prompt](helix-agent-prompt.md) · [Tests](tests.md) · [API reference](api-reference.md)

**In short:** before a request reaches your backend, have the gateway call your
customer-profile service once and pass the answer along as headers — so no
service has to make that lookup itself.

| | |
|---|---|
| **Time to try it** | About 15 minutes |
| **Difficulty** | 🟢 Beginner — no coding needed |
| **What you'll need** | A free test account (its default `test` environment). Nothing to fill in: the example backend echoes the headers it receives, and the profile service is a public sample standing in for your own |

---

## What is a service callout?

A **service callout** is an extra HTTP call the gateway makes on its own, in the
middle of handling a request. Here, before passing the request on, the gateway:

1. calls a customer-profile service,
2. picks a few fields out of the answer (the tenant's plan, a contact email, and
   whether the lookup worked), and
3. adds them to the request as headers — `X-Tenant-Plan`, `X-Tenant-Contact`,
   `X-Profile-Status` — so the backend reads a header instead of making the call.

The headers are *set*, not added, so a caller can't send its own `X-Tenant-Plan`
and have the backend believe it.

## The use case

> *"Every service we own starts the same way: call the customer-profile service,
> find out what plan this tenant is on and whether the account is in arrears, then
> get on with the actual work. Orders caches it for five minutes. Billing caches it
> for an hour. Notifications doesn't cache it at all and is the reason profile
> gets paged. When profile is slow, all three are slow in three different ways, and
> when we changed the field name last quarter we found the seventh copy of that
> call in a service nobody had touched since 2023."*

The lookup isn't hard. Having it in many places is: as many caching strategies,
as many failure behaviours, as many places to change when the profile service's
contract moves, and that many times the traffic on the profile service.

## What this gives you

- **One lookup per request**, made by the gateway, instead of one per service.
- **The answer as headers** the backend can read on any request method.
- **Headers the caller can't forge.** A client-supplied `X-Tenant-Plan` is
  overwritten with the real value.
- **A failure policy you choose per route.** The example reads with *fail-open*
  (carry on without the headers) and writes with *fail-close* (refuse with
  **HTTP 503, service unavailable**, and never call the backend).

## Benefits

- **New services start with the answer.** A service behind the route reads a
  header on day one instead of building the lookup first. This is the part that
  pays for the work.
- **One place to change** when the profile service's contract moves.
- **Failure behaviour becomes a visible decision** in one file, rather than
  whatever each team chose on the day.
- **Less load on the profile service**: one call per request, not one per service
  per request.

## Example

A client calls `GET /storefront/orders`. The gateway calls the profile service
first, then forwards the request with:

| Header the backend receives | Taken from the profile response |
|---|---|
| `X-Tenant-Plan` | `body.company.name` |
| `X-Tenant-Contact` | `body.email` |
| `X-Profile-Status` | the profile call's own HTTP status, e.g. `200` |

If the client had sent `X-Tenant-Plan: Enterprise-Unlimited`, the backend still
sees the profile service's value. If the profile service is down, the read route
still reaches the backend — without the headers — while `POST /storefront/checkout`
returns 503 with `tenant profile unavailable`.

**Setting this up in the gateway's UI takes two short steps:** import the API,
then give it an upstream and deploy it. The callout and the headers come with the
imported spec. [Full click-by-click walkthrough →](guides.md#build-it-in-the-ui)

[Build it any of three ways, then see it work →](guides.md)

## Where to go next

- **Want the business case first?** [Business need](business-need.md) explains why
  this matters, in plain terms.
- **Want to understand how it works?** [Architecture](architecture.md) covers the
  two settings that decide whether it works at all, and the failure policies.
- **Ready to build it?** [Guides](guides.md) walks you through it step by step.
- **Want the full product documentation?** Every plugin, screen and API call is
  covered at [docs.digitalapi.ai/api-gateway](https://docs.digitalapi.ai/api-gateway).

## Related solutions

- **[12 — Key-value map](../12-key-value-map/)** — the other way to get
  per-request data into a route, when the value is key material rather than a
  service's answer.
- **[08 — API keys](../08-api-key/)** — identify the caller first; this package
  ships unauthenticated so the callout is the only thing being shown.
- **[10 — Data masking](../10-data-mask/)** — if the profile response contains
  more than the backend should hold, map fewer fields rather than masking later.
