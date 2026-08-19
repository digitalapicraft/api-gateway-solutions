# Agent-mode prompt — Serve a SOAP backend as REST/JSON

Paste this into **Helix Agent Mode**. It works from a blank organisation: the
agent creates the API, binds the SOAP upstream, fetches the *real* transform
plugin schema from your org, gets the mediation working, then adds OAuth in a
second revision.

**Build it in two acts.** Deploy and check between them. If you ask for mediation
and authentication in one prompt and something breaks, you won't know whether it's
the transform or the token — and the two fail in ways that look alike.

Read [AGENT-GUIDE.md](../../AGENT-GUIDE.md) first if you haven't. Prompting at the
level of outcomes matters more here than anywhere else in this library, because
`xml-to-json`'s fields genuinely vary by build and a model asked for specific
fields will invent them.

> **On this build:** `transform_request` defaults to **false**, the response
> transform is content-negotiated (`Accept: application/json`), and a `Content-Type`
> override in `proxy-rewrite` defeats the request direction. The constraints below
> account for all three.

---

> **Run each act as its own prompt on the default agent model** — the prompts
> below are the ones verified there. Deploy and check between acts; don't fold
> mediation and auth into one prompt. Beyond making a failure diagnosable, one
> bounded ask per act keeps a smaller model from attempting an oversized change
> and stalling. Replace the `<<...>>` values.

## Act 1 — get the mediation working

Nothing in the way yet. One thing to prove: JSON in, JSON out, XML in the middle.

```text
Create a REST API called "<<Partner Locations API>>" that fronts a SOAP backend.

POST /locations should proxy to the upstream path <<SOAP_HANDLER_PATH>>, and a
plugin should transform the request and response bodies so partners send and
receive JSON while the backend keeps speaking XML.

Upstream: <<SOAP_UPSTREAM_URL>>

Check get_plugin_config for the transform plugin before writing config — I want
the schema this org actually has, not field names from another gateway. On this
build transform_request defaults to false, so set it true explicitly, and the
response direction only fires when the client sends Accept: application/json.
Do not set Content-Type in proxy-rewrite — it runs before the transform and would
hide the JSON body. Do not add json-to-xml; it is the opposite job.

Show me the spec, dry-run it, and wait for me to confirm before deploying.
```

**Check before act 2.** Confirm a JSON call returns JSON with no angle brackets in
the body. If that isn't true, adding auth on top just makes the failure harder to
see.

## Act 2 — add OAuth 2.0

```text
Now deploy a NEW REVISION that adds OAuth 2.0:

- POST /oauth/token issues a signed JWT from an app's client id and secret,
  15-minute lifetime (helix-auth generate)
- POST /locations requires a valid Bearer token, rejected in the access phase
  BEFORE the transform runs (helix-auth validate, validate_auth_type jwt-auth)

Both must use the SAME signing secret — a literal value (this build does not
resolve <ENV:...>). Apply validate on /locations only, never API-wide, or
/oauth/token would be protected and nobody could get a first token. This is a new
revision — clone the active one (so I keep a rollback) or undeploy first.
```

Then create the app:

```text
Create a developer "<<Partner Integrations>>" with an app subscribed to this API
and give me the client id and secret. Then give me curl commands showing, in
order: no token → 401; client credentials → 200 with an access_token; that token
→ 200 with a JSON body; a garbage token → 401 — and confirm the 401 never reached
the SOAP backend.
```

**Two acts, not one.** If you ask for mediation and auth in a single prompt and
something breaks, you don't know whether it's the transform or the token. Split at
the seam and each act is independently verifiable.

---

## Why the prompt is shaped this way

| Block | Why it's there |
|---|---|
| **Two acts, not one** | Mediation failures and auth failures look alike from the outside (a 500 or a 401 with a config that reads fine). Splitting at the seam means each act is independently verifiable, and you know which one broke. |
| **"transform_request defaults to false; response needs Accept; no Content-Type in proxy-rewrite"** | The three real defects found in a live run. A model reaches for `json-to-xml` (wrong plugin), leaves `transform_request` at its false default, or sets `Content-Type` in `proxy-rewrite` — any one leaves the request unconverted and the handler rejecting JSON. |
| **"Check get_plugin_config BEFORE writing any config"** | This plugin's fields vary by build more than most. Asked for an outcome the agent reads your schema; asked for fields it recalls someone else's. |
| **"Use a plugin to transform the requests and responses"** — outcome, not field names | Deliberately high altitude. This phrasing is what makes the agent go and look rather than pattern-match. |
| **"Tell me whether my handler needs SOAPAction"** | A missing `SOAPAction` is the second most common cause of a 500 from a handler that works under curl. Asking the agent to raise it surfaces the question before you're debugging. |
| **"the content-type is application/json AND the body contains no XML markup"** | A content-type header is a claim the gateway makes. Relabelling unconverted XML as JSON is a real misconfiguration that passes any header-only check, and partners discover it via their parser. Demanding both is what makes the check real. |
| **"warn me about anything I would not have designed by hand"** | The JSON shape is *derived* from the XML, not designed. PascalCase names and single-element-collections-as-objects will become part of your public contract if nobody flags them now. |
| **"BEFORE the transform runs"** | Ordering is by priority, not document order. Transforming a body you're about to reject is wasted work on every unauthenticated request — and an easy way to get a surprising load profile under a scan. |
| **"Apply validate PER ROUTE"** | An agent tidying up will hoist the auth block to the document root, which protects the token endpoint. Every request then 401s, including the one that issues tokens. |
| **"clone the revision… tell me which you did"** | ACTIVE revisions reject edits. Cloning keeps a rollback target; undeploying doesn't. You want to know which one you're now living with. |
| **"ask me instead of guessing"** | The handler path, the SOAPAction, and the request field names are all things only you know. A guess here produces a 500 that looks like a platform problem. |

## Tweak knobs

**Your envelope is namespaced or attribute-heavy**
```text
The upstream XML uses namespaces and puts significant data in attributes, and the
default transform is flattening them. Show me the transform plugin's fields for
namespace and attribute handling from get_plugin_config, explain what each one
does to my payload, and let me choose before you change anything.
```

**Single-element collections are breaking partner code**
```text
When the handler returns one <Site>, partners get an object; when it returns
several they get an array, and their clients break on the single case. Tell me
honestly whether the transform plugin can force a consistent array, and if it
can't, what my options are — including shaping the response afterwards.
```

**Reject bad requests at the edge instead of at the handler**
```text
Right now a partner sending JSON that converts to XML the handler dislikes gets a
500 from the handler. Add request-validation on POST /locations with a JSON Schema
so malformed input is a clean 400 from the gateway instead. Derive the schema from
the fields the handler actually reads.
```

**The legacy handler is slow**
```text
The SOAP handler regularly takes 8-10 seconds and I'm seeing 504s. Tell me what
the current gateway timeout is on this route, what raising it costs me, and
whether there's a better answer than waiting longer.
```

**Add a second SOAP operation**
```text
Add POST /sites that proxies to the same upstream but the operation
<<GetSites>>, reusing the same transform and the same auth. Keep the two routes
independent so I can meter them separately later.
```

**Meter the partners**
```text
Now meter these callers. Add api-product-enforcer on /locations behind the
helix-auth block, create products for the tiers I sell, and confirm the route has
a service_id. Do not add a limit-count keyed on consumer_name — the product quota
already counts per app.
```
(That's [solution 03](../03-api-products/).)

## Follow-up prompts for the same session

These are things the agent can actually do (build, document, diagnose). Note that
*reading analytics* — traffic by app, latency, 5xx counts — is not one of them:
that's the metrics API / portal, covered in
[solution 04's catalogue](../04-analytics/charts.md).

1. `Write the developer-portal documentation for POST /locations, including real example payloads for BOTH a single-result and a multi-result response — partners need to see the shape difference.`
2. `A partner says they're getting XML back. Walk me through what to check.`
3. `Add request-validation on POST /locations so malformed input is a clean 400 from the gateway instead of a 500 from the handler.`
4. `Show me the applied plugins on /locations and their execution order, so I can confirm the transform runs on both directions.`

## Known failure modes when running this prompt

- **The handler returns 500, but curling it directly works.** In order of
  likelihood: a second transform plugin got added and the body is being converted
  twice; a missing `SOAPAction` header; the request body's element names don't
  match what the handler reads. Reply: `set transform_request true, drop any
  the second plugin, one handles both directions.`
- **The response is still XML (text/xml).** Either the client isn't sending
  `Accept: application/json`, or `proxy-rewrite` is overriding `Content-Type`
  ahead of the transform. Both were real failures in the live run.
- **The agent adds `json-to-xml` alongside `xml-to-json`.** The expected wrong
  turn. Reply exactly as above.
- **The response is XML with a JSON content-type.** The transform isn't running on
  the response — the header is just being set. Ask the agent to show the applied
  plugins on that specific route, and confirm the transform is on the response
  direction rather than only the request.
- **The JSON body is `{}` or empty.** The handler returned an empty envelope,
  almost always because the request body's field names don't match the elements it
  reads. Ask the agent what XML it is actually generating from your JSON.
- **415 from the handler.** The content type isn't what it wants. Confirm
  `proxy-rewrite` sets `text/xml`, and check whether it wants
  `application/soap+xml` instead — SOAP 1.2 does.
- **504 on every call.** The handler is slower than the gateway timeout. This
  looks like an outage and isn't.
- **Everything 401s after act 2, including the token endpoint.** `validate` got
  applied API-wide. Reply: `validate is covering /oauth/token — move it to
  /locations only, or nobody can get a first token.`
- **Deploy fails with `Only INACTIVE revisions can be updated`.** Expected in act
  2. Tell the agent to clone the revision or undeploy, apply, then redeploy.
- **The agent puts a `description` key inside the plugin block.** Only schema
  fields plus `_meta` are legal. Reply: `move that to a YAML comment.`

## Related

- **[Solution 01 — OAuth 2.0 with JWT](../01-oauth-jwt/helix-agent-prompt.md)** —
  act 2 on its own, with the token lifetime and signing-secret traps covered
  properly.
- **[Solution 03 — API Products](../03-api-products/helix-agent-prompt.md)** —
  metering the partners now reaching your legacy system.
- **[Solution 04 — Analytics](../04-analytics/charts.md)** — the
  questions worth asking once this is live.
