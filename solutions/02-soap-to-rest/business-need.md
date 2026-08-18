# Business need — serving a SOAP backend as REST/JSON

## The situation

You have a system of record that speaks SOAP. It was built in 2004, or 2007, and
it is not the problem people assume it is: it's correct, it's fast, it has years of
accumulated business rules encoded in it, and it has never lost a transaction.

The problem is entirely at the boundary. Every partner who wants to integrate asks
for JSON, and increasingly for OAuth. And each of those requests turns into a
project.

The three options on the table are all bad:

**Rewrite the system of record.** A quarter of engineering minimum, a data
migration, and a genuine risk of losing behaviour that exists only in the code and
in the heads of two people. Nobody signs this off. They are right not to.

**Write an adapter service per integration pattern.** Individually reasonable —
it's a thin translation layer, a week of work. Collectively, you now operate a
fleet. Each adapter has a deployment, a monitoring story, an on-call rotation, a
dependency on the WSDL it can drift from, and an owner who changed teams. You
notice the pattern somewhere around the third one; by then you have three.

**Make partners speak SOAP.** Hand them the WSDL and ask them to construct
envelopes. A few will. Most will quietly deprioritise the integration, and nobody
will tell you that's what happened — you'll just observe that partner onboarding is
slow and conclude something vague about enterprise sales cycles.

## What changes

The translation moves to the edge, where it is configuration rather than a service.

| | Adapter-per-partner | Mediated at the edge |
|---|---|---|
| **Services to operate** | One per integration pattern | Zero new services |
| **Deployments to maintain** | N | None |
| **On-call surface** | N adapters, some unowned | The gateway you already run |
| **Time to onboard a partner** | An adapter project | Create an app; they call the existing endpoint |
| **Drift from the WSDL** | N places to keep in step | One configuration block |
| **Backend change required** | None — but the rewrite alternative is a quarter | None |
| **Auth** | Implemented per adapter, differently each time | Once, at the edge ([solution 01](../01-oauth-jwt/)) |
| **Usage visibility** | Per adapter, if someone built it | Every call captured, attributed per app ([solution 04](../04-analytics/)) |

## The mechanism that matters

Stripped of technology, one property changes:

> **The number of things you operate stops growing with the number of partners you
> onboard.**

That's a topology claim, not a performance claim, and it's the one that compounds.
With adapters, integration count and operational surface grow together — partner
five costs the same as partner one, forever, plus the carrying cost of the four
before it. With mediation at the edge, partner five costs an app record.

The second property, quieter but often what actually unblocks the work:

> **The system of record stops being on the critical path for commercial
> decisions.**

Today, "can we onboard this partner" routes through a team that owns a legacy
system and has a roadmap. After this, it routes through configuration. The backend
team is no longer the bottleneck for a decision that was never really about the
backend.

## Business outcomes

**Integration lead time collapses to configuration time.** A partner asking for
JSON access doesn't open an engineering project. This is the outcome that shows up
in a sales cycle, because "we can have you calling it this week" is a different
conversation from "we'll scope an adapter."

**No new operational surface.** Every adapter you don't build is a deployment you
don't monitor, a dependency you don't patch, and an unowned service you don't
inherit. This is the cost that's invisible when you approve adapter number one and
obvious when you're maintaining number four.

**The rewrite stops being urgent.** The pressure to modernise a SOAP system is
usually not about the SOAP — it's about the fact that nobody can integrate with it.
Remove that and the rewrite becomes a decision you make on technical merit and your
own timetable, rather than under commercial duress. Some of these systems then
never need rewriting at all, which is the correct outcome.

**Legacy capability becomes a sellable product.** Once the boundary speaks JSON and
OAuth, the system behind it can be packaged, metered and put in a catalogue. That's
[solution 03](../03-api-products/), and it isn't reachable from a SOAP endpoint with
a WSDL.

**One place to look when something's wrong.** Every partner call passes through one
layer, carrying one correlation id, captured by one analytics pipeline. Compare
with correlating across four adapters, three of which log differently.

## What this does not buy you

Being precise, because overclaiming here wastes somebody's sprint:

- **It does not give you a designed REST contract.** The JSON is a mechanical
  projection of the XML: `PascalCase` element names, vendor prefixes, and the
  envelope's structure all come through. If your public contract must be clean and
  stable independent of the backend's vocabulary, mediation is a step toward that,
  not the whole thing.
- **XML has no arrays, and this leaks.** A collection with one member may transform
  to an object where two members transform to a list. Partner code written against
  a multi-result example breaks on the single-result case — in production, on their
  side. Publishing both example shapes is not optional.
- **Internal element names become your public contract.** Once partners integrate
  against `{"Locations":{"Site":[…]}}`, renaming those is a breaking change. Decide
  before you publish, not after.
- **It handles bodies, not the WS-\* stack.** WS-Security, SOAP headers,
  attachments and MTOM are out of scope.
- **It doesn't make a slow handler fast.** If the SOAP system takes eight seconds,
  the mediated API takes eight seconds. Mediation makes it *usable*, not *good*.
- **No numbers are claimed here.** "A quarter for a rewrite" and "a week per
  adapter" are the estimates teams give, not measured figures. Use your own. What
  this document quantifies is the *shape* of the cost — that adapter count scales
  with partner count and mediation doesn't.

## Success criteria

You'd call this done when:

- A partner can call the system of record with JSON, over OAuth, without ever
  seeing an envelope or asking for the WSDL.
- The SOAP service's code and deployment are unchanged, and its team was not on the
  critical path.
- No new service was deployed to make it work.
- The response body genuinely contains no XML — verified by
  [`gateway/verify.sh`](gateway/verify.sh) case 4, not by trusting a content-type
  header.
- Onboarding partner *n+1* requires creating an app and nothing else.
- You can answer "which partner called the legacy system how often yesterday"
  without a log hunt.
- Your developer documentation shows both the single-result and multi-result JSON
  shapes, because you know that distinction exists.
