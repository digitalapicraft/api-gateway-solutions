# Business need — one conversion at the edge instead of four in the clients

[Overview](readme.md) · **Business need** · [How it works](how-it-works.md) · [Install](install.md) · [Configuration](configuration.md) · [Test & verify](testing.md) · [Changelog](changelog.md)

---

## The risk today

An XML backend with JSON clients does not produce one problem. It produces one
problem per client, and they drift.

**The conversion exists N times.** Web wrote a parser. iOS wrote a different one.
Android found a library. The partner team gave up and asked for a nightly file.
Each implementation encodes its own answer to the same ambiguities: what an empty
element means, whether a single occurrence of a repeatable element is a list,
what happens to an attribute. They agree until the data changes.

**The bugs are intermittent and land on the wrong team.** The failure mode is not
"the parser is broken". It is a client that works for months and breaks the first
day a customer has exactly one item in their basket, because the element stopped
being an array. That ticket arrives at the client team, who did nothing wrong, and
is diagnosed by whoever knows the XML best — who is on a different team again.

**Every new client pays the toll again.** The cost of integrating is not calling
the endpoint; it is writing parser number five. That shows up as partner
onboarding time, which is a number the business already watches.

**Nobody can change the backend.** It is the system of record, it has been stable
for fifteen years, and rewriting its representation layer is not a project anyone
will fund to make a JSON payload nicer.

## What the gateway changes

The conversion moves to the one place every client already passes through, and
becomes configuration rather than code. The backend is untouched — it keeps
receiving and returning the XML it always has.

Two consequences do the commercial work:

**A new client costs nothing.** It calls a JSON endpoint. There is no parser to
write, so integration time stops scaling with the number of consumers.

**The old clients do not have to move.** Because the response conversion is
content-negotiated — it happens only when the caller asks for JSON — the existing
XML consumers keep working through the same route, unchanged and unmigrated. The
new front door does not require a migration project to open, which is usually the
difference between "approved" and "next year".

## The business outcome

| Before | After |
|---|---|
| One conversion implementation per client | One, in configuration |
| A new consumer writes a parser first | A new consumer calls an endpoint |
| Representation bugs land on client teams | They land in one place, with one owner |
| Adding JSON means migrating everyone | XML consumers keep working through the same route |
| Backend rewrite is the only "real" fix | Backend untouched; the change is a revision deploy |

## What it does not buy you

- **It is not an API redesign.** The JSON mirrors the XML, element for element.
  If the XML is awkward, you now have awkward JSON. A stable, versioned JSON
  contract that outlives the backend's structure needs a template-based transform
  on top.
- **It is not lossless.** Attributes on child elements, mixed content and the
  single-vs-many ambiguity are all places where XML carries something JSON has no
  natural home for. The package states exactly what happened to each in a real
  document rather than claiming fidelity.
- **It does not authenticate anything.** This package ships open on purpose so
  the mediation is the only thing being demonstrated.
- **The request direction is not a schema-conformance tool.** JSON object key
  order is not preserved, so a backend validating a strict `xs:sequence` can
  reject a document containing every field it required. Check that before
  promising it.
