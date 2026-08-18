# Solution 02 — Serve a SOAP backend as REST/JSON

**Partners send JSON. A twenty-year-old system answers. Neither knows about the
other.**

| | |
|---|---|
| **Setup time** | ~25 minutes |
| **Difficulty** | 🟡 Intermediate |
| **Needs** | A SOAP endpoint reachable from the gateway · `JWT_SIGNING_SECRET` on the environment · one developer + app · `xml-to-json` present in your org |
| **Plugins** | `xml-to-json` (**bidirectional**) · `proxy-rewrite` · `helix-auth` (generate + validate) · `request-id` · `cors` |
| **Build it with** | 🤖 **[the Helix Agent](helix-agent-prompt.md)** — recommended · or import [`gateway/api-spec.yaml`](gateway/api-spec.yaml) |
| **Assets** | ✅ [Agent prompt](helix-agent-prompt.md) · ✅ [Architecture](architecture.md) · ✅ [Business need](business-need.md) · ✅ [Spec](gateway/) · ✅ [Tests](tests/) · ✅ [Validation](validation/) · ✅ [Infographic](infographic.md) · ✅ [Blog](blog.md) · ✅ [Manifest](solution.yaml) |

---

## The problem

> *"Our system of record is SOAP. It has been SOAP since 2004, it is correct, it
> is fast, and it has never lost a transaction. Every fintech partner who wants to
> integrate asks for JSON and OAuth, and every one of them is a project: write an
> adapter service, deploy it, monitor it, keep it in step with the WSDL. We now
> have four adapters, two of which nobody owns. The alternative is rewriting the
> system of record, which nobody will sign off, correctly."*

Three bad options, which is why this sits still:

1. **Rewrite the backend.** A quarter of engineering, a migration, and a real risk
   of losing behaviour nobody documented. Nobody signs this off, and they're right
   not to.
2. **Write an adapter per partner.** Now you have N services to run, each one a
   thin translation layer with its own deployment, monitoring, on-call rotation
   and drift. The fourth one is where you notice the pattern.
3. **Make partners speak SOAP.** Hand them a WSDL and ask them to construct
   envelopes. Some will. Most will quietly deprioritise the integration, and
   you'll never be told that's what happened.

**Root cause:** protocol translation is being treated as application work. It
isn't — it's a mediation concern, and mediation is what an edge is for. The
mismatch is between the *wire format* your backend speaks and the one your
partners speak. Nothing about resolving it requires knowing what a location is.

## Business need

Full version: [`business-need.md`](business-need.md).

| Dimension | Adapter-per-partner | Mediated at the edge |
|---|---|---|
| **New services to operate** | One per integration pattern, each with deploys and on-call | Zero |
| **Time to onboard a partner** | An adapter project | Create an app; they call the existing endpoint |
| **Backend risk** | None from the adapter, but the rewrite alternative is severe | None. The SOAP service is byte-for-byte unchanged |
| **Where the translation lives** | N codebases, drifting | One configuration block |
| **Auth** | Implemented per adapter, subtly differently each time | Once, at the edge — see [solution 01](../01-oauth-jwt/) |
| **Observability** | Per-adapter, if someone built it | Every call captured, attributed per app — [solution 04](../04-analytics/) |

The structural argument: **the number of things you operate stops growing with the
number of partners you onboard.** That's not a performance claim, it's a topology
claim, and it's the one that compounds.

## How a request flows

```
Partner                        Gateway                          SOAP system
  │                                                              (unchanged)
  │  POST /locations
  │  Authorization: Bearer eyJ...
  │  content-type: application/json
  │  {"region":"EMEA","activeOnly":true}
  ▼
  ├─► helix-auth (validate, jwt-auth)          [access phase]
  │     valid?  no  ──► 401, stops here. No transform, no SOAP call.
  │              yes ▼
  │
  ├─► proxy-rewrite                            [rewrite phase]
  │     uri: /locations ──► /GetData.ashx
  │     Content-Type: text/xml
  │              ▼
  │
  ├─► xml-to-json  (request direction)
  │     {"region":"EMEA"} ──► <region>EMEA</region>
  │              │
  │              └──────────────────────────────────► POST /GetData.ashx
  │                                                    text/xml
  │                                                        │
  │                                                   ◄────┘
  │                                                   <Locations>
  │                                                     <Site>...</Site>
  │                                                   </Locations>
  ├─◄ xml-to-json  (response direction)
  │     <Locations>...  ──► {"Locations":{"Site":[...]}}
  ▼
  200 application/json
  {"Locations":{"Site":[...]}}
```

Two things to notice, because both are load-bearing:

**Authentication runs before the transform.** An unauthenticated request costs you
one signature check and nothing else — no body conversion, no SOAP call. If you
ever find yourself transforming a body you're about to reject, the plugins are on
the wrong route.

**One plugin covers both conversions.** `xml-to-json` is bidirectional. It is not
"the XML→JSON one" with a `json-to-xml` counterpart. See the next section, because
this is the mistake.

## The one thing everybody gets wrong

**`xml-to-json` is bidirectional. Do not add `json-to-xml` next to it.**

The name reads like a one-way street, so the instinct — and the instinct of any
model you ask about this — is to reach for a second plugin for the request
direction. What you get is a body converted twice:

```
{"region":"EMEA"}
   ──► json-to-xml  ──►  <region>EMEA</region>
   ──► xml-to-json  ──►  {"region":"EMEA"}          ← back where you started
   ──► the SOAP handler receives JSON and returns a 500
```

The failure is confusing because the config looks thorough. Both directions are
"handled". The symptom is a 500 from a handler that works fine when you curl it
directly, and the natural conclusion is that the SOAP service is broken.

One plugin. Both directions. Nothing else.

## Build it with the Helix Agent

This is the recommended path, and it's the one that stays at the right altitude —
you describe the outcome and let the agent read the real plugin schema, which
matters more here than anywhere because `xml-to-json`'s fields vary by build. Full
prompt: [`helix-agent-prompt.md`](helix-agent-prompt.md).

Build it in two acts. Act 1, get the mediation working with nothing in the way:

```text
Create a REST API called "Partner Locations API" that fronts a SOAP backend.

POST /locations should proxy to the upstream path /GetData.ashx, and a plugin
should transform the request and response bodies so partners send and receive
JSON while the backend keeps speaking XML.

Upstream: <SOAP_UPSTREAM_URL>

Check get_plugin_config for the transform plugin before writing config — I want
the schema this org actually has, not field names from another gateway.

Show me the spec, dry-run it, and wait for me to confirm before deploying.
```

Deploy that and confirm you get JSON back at all. Then act 2, add the auth layer:

```text
Now deploy a new revision that adds OAuth 2.0:

- POST /oauth/token issues a signed JWT from an app's client id and secret,
  15-minute lifetime
- POST /locations requires a valid Bearer token, rejected before the transform runs

Both must reference the same JWT_SIGNING_SECRET environment variable. Use
helix-auth generate and validate — the gateway is the issuer, not an external IdP.
```

Then create the app:

```text
Create a developer "Partner Integrations" with an app subscribed to this API and
give me the client id and secret.
```

**Two acts, not one.** If you ask for mediation and auth in a single prompt and
something breaks, you don't know whether it's the transform or the token. Split at
the seam and each act is independently verifiable. An ACTIVE revision won't accept
edits — tell the agent to clone the revision or undeploy first.

See [AGENT-GUIDE.md](../../AGENT-GUIDE.md) for the full reasoning on acts, the
confirm gate, and what to say when the agent adds `json-to-xml` anyway.

## Install it directly

```bash
export ORG=<ORG_ID>
export TOKEN=<control-plane bearer token>      # short-lived
export BASE=https://<YOUR_GATEWAY_HOST>/api
H=(-H "authorization: Bearer $TOKEN" -H 'content-type: application/json')

# 1. Confirm xml-to-json exists in your org and check its schema.
#    Ask the agent get_plugin_config, or query the control plane's
#    plugin-schema endpoint. Do not assume the field names in this spec.

# 2. Set JWT_SIGNING_SECRET on the environment BEFORE deploying.

# 3. Import gateway/api-spec.yaml and bind <SOAP_UPSTREAM_URL> to the service.

# 4. Deploy the revision.

# 5. Create a developer and an app; keep the client_id and client_secret.

# 6. Prove it — including that the body is really converted, not just relabelled
GATEWAY=https://<YOUR_GATEWAY_HOST> \
CLIENT_ID=<CLIENT_ID> CLIENT_SECRET=<CLIENT_SECRET> \
./gateway/verify.sh
```

## Configuration

Source of truth: [`gateway/api-spec.yaml`](gateway/api-spec.yaml). Three blocks on
`/locations` carry the mediation:

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

# 3. BOTH directions. One plugin. No json-to-xml.
xml-to-json: {}
```

`xml-to-json` is deliberately an **empty block**. That takes the plugin's
defaults, which is correct for a straightforward element-to-object mapping. If
your envelope is namespaced or attribute-heavy you will need fields here — get
them from `get_plugin_config` in your own org rather than from this file, because
they vary by build.

## What the caller actually sees

Request — plain JSON, no envelope, no WSDL:

```http
POST /locations
Authorization: Bearer eyJ...
content-type: application/json

{"region":"EMEA","activeOnly":true}
```

Response — JSON, shaped by how the XML was structured:

```http
HTTP/1.1 200 OK
content-type: application/json
X-Request-Id: 7f3c...

{"Locations":{"Site":[{"id":"1","name":"Frankfurt"},{"id":"2","name":"Dublin"}]}}
```

**The JSON shape is derived from the XML, not designed.** This is the honest part
that surprises people:

- **Element names come through as-is**, including `PascalCase` and any vendor
  prefixes. You get `{"Locations":{"Site":[...]}}`, not the `{"locations":[...]}`
  a REST API designer would have written.
- **Single-element collections may not be arrays.** XML has no notion of an array,
  so one `<Site>` can transform to an object where two transform to a list. This
  breaks partner code that assumes a list, and it breaks it on the edge case
  rather than the common one — which is the worst time to find out.
- **Namespaces and attributes need handling.** Default settings often flatten or
  drop them.

Tell integrators this is a *mediated* API and publish real example payloads for
both the single-result and multi-result cases. If you need a hand-designed REST
contract instead of a derived one, that's a response-shaping layer on top of this,
not a setting in it.

## Testing

```bash
GATEWAY=https://<YOUR_GATEWAY_HOST> \
CLIENT_ID=<CLIENT_ID> CLIENT_SECRET=<CLIENT_SECRET> ./gateway/verify.sh
```

Exit 0 means all five held:

| # | Case | Expected |
|---|---|---|
| 1 | No token | `401` — before the transform, before the SOAP call |
| 2 | Client credentials | `200` + `access_token` |
| 3 | Valid token | `200` + `content-type: application/json` |
| 4 | **The body contains no XML markup** | proof the transform actually ran |
| 5 | Forged token | `401` |

**Case 4 is the one that matters and the one people skip.** A content-type header
is a *claim*; a body with no angle brackets is *evidence*. Relabelling unconverted
XML as `application/json` is a real and easy misconfiguration, and it sails past
any check that only looks at headers. Partners then receive XML with a JSON
content-type, and their parser's error message won't point anywhere near your
gateway.

`verify.sh` also warns (rather than fails) when the JSON parses but is empty —
usually the handler returned an empty envelope because your request body's element
names didn't match what it reads.

Full plan, including the XML-edge cases worth checking by hand:
[`tests/test-plan.yaml`](tests/test-plan.yaml).

## Gotchas

- **`xml-to-json` is bidirectional. Never add `json-to-xml` alongside it.** The
  body gets converted twice and the handler receives nonsense. See § *The one
  thing everybody gets wrong*.
- **Your handler may require a `SOAPAction` header.** Many classic SOAP 1.1 and
  `.asmx` endpoints return a 500 with an unhelpful envelope without it. Add it in
  `proxy-rewrite.headers.set`. Check what your handler wants rather than assuming
  it wants nothing.
- **Single-element collections may not be arrays.** XML can't distinguish one item
  from a list of one. Test both cases explicitly, and warn integrators.
- **Namespaced or attribute-heavy envelopes need configuration.** The empty
  `xml-to-json` block takes defaults, which often flatten namespaces or drop
  attributes. Confirm the fields available in your build.
- **Confirm `xml-to-json` exists in your org before designing around it.** Builds
  differ, and this plugin is the one the whole solution rests on.
- **A 500 from a handler that works under curl is almost never the handler.**
  Suspect, in order: double conversion, a missing `SOAPAction`, or request field
  names that don't match the elements the handler reads.
- **Legacy handlers are often slow.** SOAP systems built for batch use can take
  seconds. Check the gateway timeout before you conclude the upstream is down —
  the symptom is a 504 that looks like an outage.
- **Element names leak into your public contract.** Your partner-facing JSON now
  contains the internal element names of a 2004 system. Renaming them later is a
  breaking change for partners, so decide now whether you're happy publishing them.
- **The signing secret must match** on `/oauth/token` and `/locations`. See
  [solution 01](../01-oauth-jwt/) § *Gotchas*.

## When to use it

Use it when:

- **A SOAP system of record is correct and stable and you have no mandate to
  rewrite it.** That's most of them.
- **Partners want JSON**, and the number of partners is growing.
- **You're on adapter number two or three** and can see where this goes.
- **You want to expose a legacy system without exposing the legacy system** — auth,
  mediation and metering all land at the edge.

Don't use it when:

- **You need a hand-designed REST contract.** The JSON shape here is *derived*
  from the XML. If the public contract must be clean and stable independent of
  the backend's element names, you need a response-shaping layer, and possibly a
  real facade service.
- **The SOAP operation is genuinely complex** — multi-part MIME, WS-Security
  headers, attachments, stateful sessions. Mediation handles body translation, not
  the whole WS-* stack.
- **One partner call needs several backend calls.** That's composition, not
  mediation.
- **The backend is being replaced anyway.** If a REST service ships next quarter,
  a facade you'll delete may not be worth the configuration.

## Limitations

- **The JSON shape is derived, not designed.** Element names, casing and structure
  come from the XML. Publishing them makes them part of your public contract.
- **XML has no arrays.** One-element collections may transform to objects rather
  than lists. Design your client guidance around this.
- **Namespaces and attributes need explicit configuration** and may be flattened
  or dropped by default.
- **Body translation only.** WS-Security, SOAP headers, attachments and MTOM are
  not addressed.
- **No schema validation of the transformed request.** A partner can send JSON
  that converts to XML the handler rejects; the error surfaces as a 500 from the
  handler rather than a 400 from the gateway. Add `request-validation` if you want
  a clean rejection at the edge.
- **`xml-to-json`'s schema varies by build**, and the empty block here takes
  defaults. Confirm with `get_plugin_config`.
- **Latency is added.** Two conversions per request. Small, but not zero, and it
  compounds on large payloads.

Full list: [`solution.yaml`](solution.yaml) § `limitations`.

## Validation status

| Stage | Status | Provenance |
|---|---|---|
| Configuration generated | **YES** | [`gateway/api-spec.yaml`](gateway/api-spec.yaml) |
| Local validation | **PASS WITH WARNINGS** | Structural review — `xml-to-json` left as a default block. [`validation/local-validation.yaml`](validation/local-validation.yaml) |
| Gateway dry-run | **NOT RUN for this package** | An equivalent SOAP→REST + OAuth configuration was dry-run and deployed via Agent Mode in an earlier internal build. This repackaged, placeholder-parameterised spec has **not** itself been dry-run. |
| Gateway deployed | **NOT RUN for this package** | — |
| Functional tests | **NOT RUN for this package** | `verify.sh` is written and reviewed; not executed from this package |

Overall: **UNVALIDATED** — generated and structurally reviewed, with the
mediation-plus-auth pattern proven in an earlier internal build against a real
SOAP backend. **Run [`gateway/verify.sh`](gateway/verify.sh) against your own
environment before you rely on this**, and pay particular attention to case 4.
Full record of what the prior build did and did not establish:
[`validation/gateway-validation.yaml`](validation/gateway-validation.yaml).

## Related solutions

- **[01 — OAuth 2.0 with JWT](../01-oauth-jwt/)** — the auth layer used here,
  covered properly: token lifetimes, the signing-secret trap, the external-issuer
  fork.
- **[03 — API Products](../03-api-products/)** — meter the partners now calling
  your legacy system, and sell tiers. Add `api-product-enforcer` behind the
  `helix-auth` block.
- **[04 — Analytics](../04-analytics/)** — find out which partner is calling the
  legacy system how often, which is usually the first question asked after this
  goes live.
