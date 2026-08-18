# Architecture — SOAP/XML backend served as REST/JSON

The gateway acts as a **mediation layer**: it translates wire format in both
directions and retargets the path, so a REST/JSON client and a SOAP/XML service
can talk without either being modified or being aware of the other.

This is protocol mediation, not composition and not a facade service. One inbound
call maps to exactly one backend call. The only thing that changes is the
representation.

---

## The request path

```
┌─────────┐        ┌────────────────────────────────────────────┐    ┌───────────┐
│ Partner │        │                  Gateway                   │    │   SOAP    │
│ (JSON)  │        │                                            │    │  system   │
└────┬────┘        │                                            │    │(unchanged)│
     │             │                                            │    └─────┬─────┘
     │ POST /locations                                          │          │
     │ Bearer eyJ...                                            │          │
     │ {"region":"EMEA"} │                                      │          │
     ├────────────────►  │  ┌──────── access phase ──────────┐  │          │
     │                   │  │ helix-auth (validate,jwt-auth) │  │          │
     │                   │  │ signature + expiry             │  │          │
     │  401              │  └───────┬───────────────┬────────┘  │          │
     │◄──────────────────┼──────────┘ fail          │ pass      │          │
     │  nothing was      │                          ▼           │          │
     │  transformed,     │  ┌──────── rewrite phase ─────────┐  │          │
     │  nothing was      │  │ proxy-rewrite                  │  │          │
     │  called           │  │ uri → /GetData.ashx            │  │          │
     │                   │  │ Content-Type → text/xml        │  │          │
     │                   │  └──────────────┬─────────────────┘  │          │
     │                   │                 ▼                    │          │
     │                   │  ┌─── xml-to-json, request dir. ──┐  │          │
     │                   │  │ {"region":"EMEA"}              │  │          │
     │                   │  │      ↓                         │  │          │
     │                   │  │ <region>EMEA</region>          │  │          │
     │                   │  └──────────────┬─────────────────┘  │          │
     │                   │                 └───────────────────►│ POST     │
     │                   │                                      │ /GetData │
     │                   │                                      │ .ashx    │
     │                   │  ┌── xml-to-json, response dir. ──┐  │◄─────────┤
     │                   │  │ <Locations><Site>…</Site></…>  │  │  text/   │
     │                   │  │      ↓                         │  │  xml     │
     │                   │  │ {"Locations":{"Site":[…]}}     │  │          │
     │  200              │  └──────────────┬─────────────────┘  │          │
     │◄──────────────────┼─────────────────┘                    │          │
     │ application/json  │                                      │          │
     └───────────────────┴──────────────────────────────────────┴──────────┘
```

Two structural properties, both deliberate:

**Rejection precedes translation.** `helix-auth` runs in the access phase, so an
unauthenticated request costs one signature verification and stops. No body
conversion, no SOAP call, no backend connection. If your configuration transforms
first and authenticates second, every scan against your endpoint does real work.

**One plugin performs both conversions.** `xml-to-json` is bidirectional. This is
the single most important fact in the solution and it's covered in its own section
below.

## Execution order

Plugins run by **priority**, not in the order they appear in the document.

| Order | Plugin | Phase | Does | Depends on |
|---|---|---|---|---|
| 1 | `helix-auth` (validate) | access | Verifies the JWT; resolves the calling app | the `Authorization` header, `JWT_SIGNING_SECRET` |
| 2 | `proxy-rewrite` | rewrite | Retargets `/locations` → `/GetData.ashx`; sets `Content-Type: text/xml` | nothing |
| 3 | `xml-to-json` | request body | JSON → XML | the rewritten content type being consistent with what it emits |
| 4 | *(upstream call)* | — | — | — |
| 5 | `xml-to-json` | response body | XML → JSON | the upstream having returned XML |
| — | `request-id` | rewrite/log | Stamps `X-Request-Id` | nothing |
| — | analytics | log | Per-request telemetry | identity resolved at step 1 |

The dependency worth internalising: **steps 2 and 3 must agree.** `proxy-rewrite`
declares the body is `text/xml`; `xml-to-json` is what makes that true. Configure
one without the other and you have a handler receiving JSON labelled as XML, or
XML labelled as JSON — both produce 415s or 500s that look like backend faults.

## The bidirectional transform

**`xml-to-json` handles both directions. There is no `json-to-xml` in this
solution, and adding one breaks it.**

The plugin name reads as a one-way conversion, which is why this is the most
common way the solution is built wrong — by people and by models. The instinct is
symmetrical: if XML→JSON handles the response, surely something else handles the
request.

What actually happens when you add a second transform:

```
correct:
  client JSON  ──[xml-to-json, request dir.]──►  XML  ──►  handler ✓

wrong (json-to-xml added):
  client JSON  ──[json-to-xml]──►  XML
               ──[xml-to-json, request dir.]──►  JSON again
               ──►  handler receives JSON labelled text/xml  ──►  500 ✗
```

The failure is hard to diagnose for three reasons: the configuration looks *more*
complete rather than less; the error is a 500 from the backend, which points
attention at the backend; and curling the handler directly works fine, which
confirms the wrong hypothesis.

One plugin. Both directions.

## Why the JSON shape is derived, not designed

This is the part that surprises API designers, and it's a property of the approach
rather than a limitation of the plugin.

The gateway is translating a representation, not implementing a contract. So the
JSON your partners receive is a mechanical projection of the XML the handler
produced:

| XML | Becomes | Not |
|---|---|---|
| `<Locations><Site>…</Site></Locations>` | `{"Locations":{"Site":[…]}}` | `{"locations":[…]}` |
| `<ns2:SiteName>` | a key carrying the prefix, or flattened, depending on config | `siteName` |
| One `<Site>` element | possibly an object | reliably a one-element array |
| Two `<Site>` elements | an array | — |
| `<Site id="1">` | attribute handling depends on config; may be dropped | a normal field |

The array case deserves emphasis because of *when* it bites. XML has no concept of
a collection: `<Site>` appearing once and `<Site>` appearing twice are structurally
different documents. A transform therefore cannot always know whether one element
is "an item" or "a list of one". Partner code written against a multi-result
example breaks on the single-result case — the edge case, discovered in
production, by them.

Two consequences for how you run this:

- **Publish example payloads for both the single-result and multi-result cases.**
  Not one representative example. Both.
- **Understand that internal element names are now your public contract.** Renaming
  them later is a breaking change for every partner. Decide now whether you're
  content publishing the vocabulary of a 2004 system.

If you need a clean, stable, hand-designed REST contract, mediation alone doesn't
give it to you. You need response shaping on top — or an actual facade service,
which is a different and larger decision.

## Native vs custom

Everything here is native plugin configuration. **No custom code is required.**

| Requirement | How it's met | Why not custom |
|---|---|---|
| JSON → XML on the request | `xml-to-json` (request direction) | A hand-written converter is easy to start and hard to finish — namespaces, encoding, entity escaping, CDATA. |
| XML → JSON on the response | `xml-to-json` (response direction) | Same, plus streaming and size limits. |
| Retarget the path | `proxy-rewrite` | — |
| Set the handler's content type | `proxy-rewrite.headers.set` | — |
| Reject before translating | `helix-auth` in the access phase | Custom code would run in the same phase with more ways to be wrong. |
| Correlate across the hop | `request-id` | — |

Where custom logic **would** be justified — and is deliberately out of scope here:

- **Reshaping the derived JSON into a designed contract.** Renaming keys,
  normalising single elements into arrays, flattening the envelope. This is real
  work with real value, and it's a separate layer with its own tests.
- **Constructing a full SOAP envelope with WS-Security headers.** Body translation
  is not the WS-* stack.
- **Mapping one REST call onto several SOAP operations.** That's composition.

Adding any of those to this solution would make it harder to reason about and
wouldn't make the mediation better. Keep the layers separate.

## Where the pieces live

```
Environment variable on the gateway environment
   JWT_SIGNING_SECRET  ──► helix-auth generate  on POST /oauth/token   (signs)
                       └─► helix-auth validate  on POST /locations     (verifies)

Service binding (set at import/bind time, NOT in the OpenAPI paths)
   <SOAP_UPSTREAM_URL>  ──► the SOAP system

Route configuration (in gateway/api-spec.yaml)
   proxy-rewrite  uri: /GetData.ashx      ← the handler's real path
   xml-to-json    {}                      ← defaults; confirm fields per build
```

Note that the *handler path* is in the spec while the *host* is not. That split is
intentional: the path is part of the mediation design and belongs with the route;
the host differs per environment and belongs on the service.

## When to use this

Use it when:

- **A SOAP system of record is correct, stable, and not being rewritten.** That
  describes most of them, and "it has never lost a transaction" is a real argument
  against touching it.
- **Partners want JSON and the number of partners is growing.** The topology
  argument is the whole point: mediation at the edge means the count of things you
  operate stops growing with the count of integrations.
- **You're on adapter number two or three.** Each one is individually reasonable
  and collectively a fleet.
- **You want to expose a legacy system without exposing it** — mediation, auth and
  metering all land in one layer you control.
- **One inbound call maps to one backend operation.** That's the shape mediation
  fits.

Don't use it when:

- **The public contract must be clean and stable independent of the backend.** The
  JSON here is derived. Element names, casing and collection semantics come from
  the XML.
- **The SOAP surface is genuinely complex** — WS-Security, SOAP headers,
  attachments, MTOM, stateful sessions. This translates bodies.
- **One partner call needs several backend calls**, or needs results merged.
  That's composition, a different pattern.
- **The backend is being replaced next quarter.** A facade you'll delete may not
  be worth configuring, though it can be a useful bridge during the migration.
- **The handler is so slow that translation isn't the problem.** If calls take ten
  seconds, mediation makes the API usable but not good. Fix the latency or set
  expectations.

## Prerequisites

- The SOAP endpoint is reachable from the gateway, and you know the handler path
  and whether it requires a `SOAPAction` header.
- `xml-to-json` exists in your org, and you have checked its schema with
  `get_plugin_config`. The whole solution rests on this plugin — confirm it before
  designing around it.
- `JWT_SIGNING_SECRET` exists on the environment before the revision is deployed.
- You know the element names the handler reads, so the request body's field names
  can match them.
- One developer with one app, for a `client_id`/`client_secret` to test with.

## Failure behaviour

| Condition | Result | Reached the SOAP handler? |
|---|---|---|
| No or invalid Bearer token | 401 | No — and no transform ran either |
| Handler unreachable | 502 | Attempted |
| Handler slower than the gateway timeout | 504 | Yes, but the answer arrived too late |
| Handler rejects the content type | 415 | Yes — check `text/xml` vs `application/soap+xml` |
| Missing `SOAPAction` (where required) | 500, often with an unhelpful envelope | Yes |
| Request field names don't match the elements read | 200 with an empty result, or 500 | Yes |
| A second transform plugin added | 500 — handler received JSON labelled as XML | Yes |
| Transform not applied to the response | 200 with XML body and a JSON content-type | Yes |

The last row is the dangerous one, because it looks like success. The status is
200, the content type says JSON, and the partner's parser is what discovers the
truth — with an error message pointing nowhere near your gateway. This is exactly
why [`gateway/verify.sh`](gateway/verify.sh) case 4 asserts the body contains no
XML markup rather than trusting the header.
