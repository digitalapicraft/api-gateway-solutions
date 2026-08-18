# Your SOAP backend is fine. Your partners just can't reach it.

There is a system in your estate that speaks SOAP. It was built in 2004, or maybe
2007. It has years of accumulated business rules encoded in it, several of which
exist nowhere else and two of which nobody remembers writing. It is fast. It is
correct. It has never lost a transaction.

And every single fintech partner who wants to integrate with it asks for JSON.

So you have three options, and they're all bad.

**Rewrite the system of record.** A quarter of engineering, a data migration, and a
real chance of losing behaviour that lives only in the code. Nobody signs this off.
They're right not to.

**Write an adapter service per integration pattern.** Individually reasonable — a
thin translation layer, a week of work, ship it. Collectively you now run a fleet.
Four adapters, each with a deployment, a monitoring story, an on-call rotation, and
a dependency on the WSDL it can drift from. Two of them are owned by people who
changed teams. You notice the pattern around number three.

**Make partners speak SOAP.** Hand them the WSDL and ask them to construct
envelopes. A few will. Most will quietly deprioritise the integration and never
tell you, and you'll conclude something vague about enterprise sales cycles.

## The framing is the problem

None of those options is wrong given the premise. The premise is wrong.

Protocol translation is being treated as application work. It isn't. Ask what
converting JSON to XML actually requires: read a body, restructure it, write it
back. It does not need to know what a location is. It does not touch a business
rule. It has no opinion about your domain model.

It's a *mediation* concern. And mediation is the one thing an API gateway is
unambiguously for.

## What we're building

A partner sends JSON to `POST /locations`. The gateway converts that body to XML,
calls the SOAP handler on its real path, converts the XML response back to JSON,
and returns it. The SOAP service is not modified and does not know a REST client
exists.

Three blocks on one route:

```yaml
# 1. reject first — no point transforming a body you're about to discard
helix-auth:
  mode: validate
  validate_auth_type: jwt-auth
  signing_secret: "<ENV:JWT_SIGNING_SECRET>"

# 2. the client called /locations; the handler only answers on /GetData.ashx
proxy-rewrite:
  uri: /GetData.ashx
  headers:
    set:
      Content-Type: text/xml

# 3. BOTH directions. One plugin.
xml-to-json: {}
```

That's the solution. The [full document](./gateway/api-spec.yaml) has the routes and
the token endpoint and the correlation id, but those three blocks are the idea.

Notice the ordering. Authentication is in the access phase, which means an
unauthenticated request costs one signature check and stops — no body conversion, no
SOAP call. If you ever catch yourself transforming a body you're about to reject,
the plugins are on the wrong route.

## Now let me tell you about that empty block

`xml-to-json: {}`. Two characters of configuration, and the single most
misunderstood thing in this entire solution.

**It is bidirectional.** One plugin converts the JSON request body to XML *and*
converts the XML response body to JSON. There is no `json-to-xml` in this solution.
Adding one breaks it.

The name reads like a one-way street, which is why everybody — every engineer,
every model you ask — reaches for a second plugin to handle the request direction.
It feels symmetrical. It feels *thorough*.

Here's what you get:

```
correct:
  client JSON  ──[xml-to-json, request dir.]──►  XML  ──►  handler ✓

wrong:
  client JSON  ──[json-to-xml]──►  XML
               ──[xml-to-json, request dir.]──►  JSON again
               ──►  handler receives JSON labelled text/xml  ──►  500 ✗
```

The body gets converted twice and arrives back where it started. The handler
receives JSON with a `text/xml` content type and returns a 500.

And this is a genuinely nasty bug to chase, for three reasons that compound:

1. **The config looks more complete, not less.** Both directions handled. Reviewers
   nod.
2. **The error is a 500 from the backend**, which points every instinct at the
   backend.
3. **Curling the handler directly works fine**, which confirms the wrong hypothesis.

One plugin. Both directions. Nothing else.

## Build it in two acts

You could write that YAML. Don't — describe the outcome instead, and let the agent
read your org's actual plugin schema. That matters more here than anywhere, because
`xml-to-json`'s fields genuinely vary by build, and a model asked for specific
fields will confidently invent them from another gateway's documentation.

Act one. Nothing in the way. One thing to prove:

```text
Create a REST API that fronts a SOAP/XML backend, so partners can send and receive
JSON without ever seeing an envelope or needing the WSDL.

POST /locations should proxy to the upstream path /GetData.ashx, and a plugin
should transform the request and response bodies so the client sends JSON and the
handler keeps speaking XML.

The transform plugin is BIDIRECTIONAL — one plugin handles both directions. Do not
add a second plugin for the other direction.

Check get_plugin_config for the transform plugin before writing config. I want the
schema this org actually has, not field names from another gateway.

Show me the spec, dry-run it, and wait for me to confirm.
```

Deploy that. Confirm you get JSON back at all. *Then* act two adds the token
endpoint and the validation.

Two acts, not one, and this isn't fussiness. Mediation failures and auth failures
look alike from outside — a 500 or a 401 with a config that reads fine. Split at the
seam and each act is independently verifiable. When something breaks you know which
half broke it.

(An ACTIVE revision won't accept edits, so act two needs a cloned revision or an
undeploy first. Tell the agent which you want; cloning keeps you a rollback target.)

The [full prompt](./helix-agent-prompt.md) carries both acts, the constraints that
prevent the double-transform, and the failure modes we hit running it.

## The part that will surprise your API designer

You get JSON. You do not get *good* JSON.

```json
{"Locations":{"Site":[{"id":"1","name":"Frankfurt"},{"id":"2","name":"Dublin"}]}}
```

Not `{"locations": [...]}`. The gateway is translating a representation, not
implementing a contract, so the shape is a mechanical projection of whatever XML
your handler emitted. `PascalCase` element names come through. Vendor prefixes come
through. The envelope's nesting comes through.

Which means: **your internal element names are now your public contract.** Once
eleven partners have integrated against `Locations.Site`, renaming it is a breaking
change. Decide before you publish whether you're happy putting the vocabulary of a
2004 system on your developer portal, because you can't quietly take it back.

And then there's the one that actually causes incidents.

**XML has no arrays.**

`<Site>` appearing once and `<Site>` appearing twice are structurally different
documents. A transform can't reliably know whether one element is "an item" or "a
list containing one thing". So a single result may come through as an object where
two results come through as a list.

Think about when that bites. Your partner integrates against the example you gave
them, which naturally showed several results. Their client iterates the array. It
works in testing, works in staging, works for weeks — and then some query legitimately
matches one location, and their code breaks. In production. On their side. On the
edge case rather than the common path, which is the worst possible time to discover
a shape difference.

Publish **both** example payloads. Single-result and multi-result. Not one
representative example. This is the highest-value thing in the
[test plan](./tests/test-plan.yaml), and it's a manual case because it needs a
handler you can coax into each shape.

## The test everybody writes wrong

`verify.sh` asserts five things. Four are ordinary — 401 without a token, a token
exchange, a 200 with a token, a 401 with a forged one.

The fifth is the one that matters:

```bash
if grep -qE '<[A-Za-z_?/]' "$BODY_FILE"; then
  fail "the response body still contains XML markup despite an
        application/json content-type. The transform did NOT run."
fi
```

**The response body must contain no angle brackets.**

Because here's a configuration that passes every naive check: `proxy-rewrite` sets a
JSON content type, and the transform silently isn't running on the response. Status
200. Header says `application/json`. Body is XML.

That's success-shaped failure. Nothing in your monitoring notices. Your partner's
JSON parser notices, and its error message points nowhere near your gateway.

A content-type header is a *claim the gateway makes*. A body with no angle brackets
is *evidence*. Never assert the header alone — that's the difference between a test
and a formality.

## Things that will go wrong, in likelihood order

**500 from a handler that works under curl.** Almost never the handler. Suspect:
double conversion (a `json-to-xml` snuck in), a missing `SOAPAction` header, or
request field names that don't match the elements the handler reads.

**`SOAPAction`.** Many classic SOAP 1.1 and `.asmx` endpoints require it and return
a 500 with an unhelpful envelope without it. Find out whether yours is one before
you start debugging the transform.

**415.** Wrong content type. `text/xml` is SOAP 1.1; SOAP 1.2 wants
`application/soap+xml`.

**A 200 with an empty result.** More often a request whose field names didn't match
what the handler reads than a genuinely empty dataset. Reads as "no data", is
actually "wrong request". `verify.sh` warns rather than fails here for exactly that
reason.

**504 on everything.** Legacy handlers built for batch use can take eight seconds.
This looks like an outage and isn't. Know your handler's real p99 before go-live.

## What this doesn't do

- **It handles bodies, not the WS-\* stack.** WS-Security, SOAP headers,
  attachments, MTOM — out of scope.
- **It doesn't give you a designed REST contract.** See above. Mediation is a step
  toward that, not the whole thing. If the public contract must be clean and stable
  independent of the backend, you need response shaping on top, possibly a real
  facade.
- **One call in, one call out.** Fanning out to several SOAP operations, or merging
  results, is composition — a different pattern.
- **It doesn't make a slow handler fast.** Mediation makes a legacy system
  *usable*, not *good*.
- **It doesn't validate the transformed request.** Bad JSON becomes bad XML and the
  handler complains with a 500 rather than the gateway rejecting it with a 400. Add
  `request-validation` if you want a clean edge.

## Why this is the one that compounds

The topology argument is the whole thing, and it's easy to miss because it isn't
about performance:

> **The number of things you operate stops growing with the number of partners you
> onboard.**

With adapters, integration count and operational surface grow together. Partner
five costs the same as partner one, forever, plus the carrying cost of the four
before it. With mediation, partner five costs an app record.

And there's a second-order effect that's often what actually unblocks the work.
Today, "can we onboard this partner" routes through a team that owns a legacy system
and has a roadmap. Afterwards it routes through configuration. The backend team
stops being the bottleneck for a decision that was never really about the backend.

Which has a pleasant consequence: **the rewrite stops being urgent.** The pressure
to modernise a SOAP system is usually not about the SOAP — it's about nobody being
able to integrate with it. Remove that, and the rewrite becomes a decision you make
on technical merit, on your own timetable. Some of these systems then never need
rewriting at all. That's the correct outcome, and it was unavailable while the
boundary was the problem.

## Where this goes next

Once the boundary speaks JSON and OAuth, the system behind it can be sold:

- **[OAuth 2.0 with JWT](../01-oauth-jwt/)** — act two on its own, properly: token
  lifetimes, the signing-secret trap, and the external-issuer fork in the road.
- **[API Products](../03-api-products/)** — package the legacy capability, attach a
  quota, and meter per app. A twenty-year-old system becomes a tiered product,
  which is not reachable from a WSDL.
- **[Analytics](../04-analytics/)** — "which partner is calling the legacy system,
  how often?" is usually the first question asked the week after this goes live.

## Try it

The full package — importable spec, two-act agent prompt, tests, and an honest
record of what has and hasn't been validated — is in
[`solutions/02-soap-to-rest/`](./).

Start with [the agent prompt](./helix-agent-prompt.md). Then run
[`verify.sh`](./gateway/verify.sh) against your own environment.

Note the package is labelled **UNVALIDATED**. The mediation-plus-auth pattern was
proven in an earlier internal build against a real SOAP backend, but this particular
document hasn't been dry-run — and the case-4 assertion, the one about angle
brackets, has never been confirmed anywhere. The
[validation record](./validation/gateway-validation.yaml) spells out exactly what
was and wasn't established, because you're going to put this in front of partners
and you should know which parts we're vouching for.

Your SOAP backend was never the problem. The boundary was.
