# Business need — a sandbox that differs per partner

## The situation

You run a partner sandbox. Every partner integrating against your API points at
it first, and every one of them gets the same response, because the response is a
fixture.

That fixture is a decision you made once, early, and it quietly became the
definition of "working". A partner whose settlement account has a different shape
integrates successfully against the sandbox and fails in production. A partner on
a tier with different limits writes client code that assumes the tier in the
fixture. The sandbox said yes, so nobody looked again until a real transaction
failed.

The fix everyone proposes is to make the sandbox dynamic, and the fix everyone
abandons is the same thing, because "dynamic" has historically meant a service:
an app to write, a datastore to run, a pipeline to deploy it, an on-call rotation
for something that exists purely so other people can test against it.

## What changes

Sandbox data becomes data rather than code.

An operator registers a partner's values with a single request. Every later call
from that partner is answered with them. Correcting a value is the same request
again. No revision, no route change, no deploy, and no service behind the
endpoint to run or patch.

## The mechanism that matters

The gateway already has a key-value store, and one plugin — `mocking` — can read
it directly when the response is composed. So the response is assembled at the
edge from values looked up per request, keyed by whoever is calling.

The part that makes it per-*caller* rather than merely dynamic is a single field:
`alias`. The lookup key is built from the caller's own identity, which means the
value would otherwise be published under a name that changes with every caller
and no template could reference it. `alias` renames it to something fixed. One
route then serves every partner, and onboarding the next one adds no
configuration at all.

## Business outcomes

- **Integration bugs surface in the sandbox instead of production**, because the
  sandbox finally differs along the dimensions that break integrations.
- **Partner onboarding stops waiting on a release.** Adding a partner to the
  sandbox is a request an operator makes, not a ticket that joins a deploy queue.
- **Correcting bad sandbox data takes seconds.** Today it takes a code change, a
  review, and a deploy — so in practice it often does not happen, and the wrong
  fixture stays.
- **There is no service to operate.** No container, no datastore, no patching, no
  pager for the sandbox.
- **Support gets shorter.** "What does the sandbox think my tier is?" is now
  answerable by calling one endpoint as that partner, rather than by reading the
  fixture in a repository.

## What this does not buy you

**It is not a backend.** Because `mocking` short-circuits the request, a stored
value can be *shown* to a caller but never forwarded to a real service. Anything
that needs the value to reach your own systems is a different pattern — see
solution 12.

**It is not a data store with guarantees.** Values carry a TTL, there is no
schema, no versioning and no audit trail of who changed what. That is
appropriate for a sandbox and inappropriate for anything else.

**It is not secure by default.** The registration route ships unauthenticated so
the package is runnable as shipped, and every stored value is readable by anyone
who can send the matching partner id. Protecting the write route is part of
adopting this, and nothing confidential belongs in the store.

**It does not validate what partners send you.** This changes what the sandbox
*answers*, not what it accepts. Pair it with `request-validation` if the sandbox
should also reject malformed requests.

## Success criteria

- A partner can be added to the sandbox without a deploy, by someone who does not
  have commit access to the API's configuration.
- Two partners calling the same sandbox endpoint receive different, correct data.
- Correcting a wrong value is measured in seconds, and takes effect on the next
  call.
- The sandbox has no service behind it, and therefore no availability of its own
  to manage beyond the gateway's.
