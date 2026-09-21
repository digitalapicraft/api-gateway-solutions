# Business need — one lookup, one cache, one failure policy

## The risk today

A shared lookup implemented N times is not N copies of the same code. It is N
different systems that happen to call the same endpoint.

**N caching strategies, of which at most one is right.** Five minutes here, an
hour there, none at all in the service nobody has touched since 2023. When the
underlying data changes, different parts of the estate act on different versions of
the truth for different lengths of time, and reconciling that during an incident is
guesswork.

**N failure behaviours, none of them written down.** One retries, one fails open,
one fails the request. Nobody chose this — each was decided by whoever wrote that
service, on the day, under a deadline. The first time the profile service is slow
you discover what the estate actually does, in production.

**N places to change.** A field rename in the profile service's contract becomes a
hunt, a coordinated release, and a long tail of services that were not found. The
seventh copy is discovered by the incident, not by the search.

**N × the load.** Every service makes its own call, so the profile service is sized
for the multiple rather than for the requests.

## What the gateway changes

The call happens once, at the edge, before the request is proxied. The answer is
handed to the backend as headers. The backend reads a header instead of making a
call — and a new service reads the same header on day one without implementing
anything.

Three things become properties of the path rather than of each service:

- **One cache and one timeout**, configured where the traffic is, rather than
  inherited from whoever wrote each service.
- **One failure policy per route, chosen deliberately.** A read path can proceed
  without the answer; a write path should not. Those are business decisions and
  they are now visible in one file instead of implied by seven codebases.
- **One place to change** when the contract moves.

## The part that pays for the work

Not the deduplication — the **onboarding**. Once the enrichment is on the route,
every new service that sits behind it starts with the answer already in hand. The
lookup stops being the first thing each team builds and becomes something they
inherit, which is the difference between a shared concern and a shared library
nobody upgrades.

## The business outcome

| Before | After |
|---|---|
| The lookup is implemented in every service | It is implemented once, in configuration |
| Each service caches differently | One cache, one timeout, set where the traffic is |
| Failure behaviour varies and is undocumented | An explicit policy per route: fail-open on reads, fail-close on writes |
| A contract change is a hunt across the estate | One place to change |
| The profile service carries N calls per request | It carries one |
| A new service implements the lookup first | A new service reads a header |

## What it does not buy you

- **It is not an authorization decision.** The callout fetches an answer; it does
  not act on it. A route that must *reject* a caller based on the response needs a
  plugin built to return a verdict.
- **It does not remove the dependency.** There is still one synchronous call in the
  request path, and its timeout is now part of your latency budget. You have
  consolidated the dependency, not eliminated it.
- **It does not cache by itself.** Every request makes the call unless you put
  caching in front of it deliberately.
- **It is not free at the backend.** Under a fail-open policy the headers can be
  absent, and every backend reading them has to decide what that means. That is a
  small amount of work in N services — but it is honest work, replacing N
  undocumented behaviours with one documented one.
