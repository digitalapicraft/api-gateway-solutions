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

---

## Act 1 — get the mediation working

Nothing in the way yet. One thing to prove: JSON in, JSON out, XML in the middle.

```text
Create a REST API that fronts a SOAP/XML backend, so partners can send and
receive JSON without ever seeing an envelope or needing the WSDL. The SOAP
service must not be modified.

CONTEXT
- API name: <<Partner Locations API>>
- Environment: <<staging>>
- SOAP upstream: <<SOAP_UPSTREAM_URL>>
- The SOAP handler answers on the path <<GetData.ashx>> and expects
  content-type text/xml.

WHAT I WANT

1. An endpoint POST /locations that proxies to the upstream path
   <</GetData.ashx>>.

2. Use a plugin to transform the request and response bodies, so the client
   sends JSON, the handler receives XML, and the handler's XML response comes
   back to the client as JSON.

   Check get_plugin_config for the transform plugin BEFORE writing any config
   and use the schema this org actually has. Do not use field names from another
   gateway's documentation.

3. Set the upstream content type to text/xml on the proxied request.
   Tell me whether my handler is likely to also need a SOAPAction header — many
   classic SOAP 1.1 and .asmx endpoints return a 500 with an unhelpful envelope
   without one. If you can't tell, say so and ask.

4. Add request-id (uuid, header X-Request-Id) API-wide. When a partner reports a
   wrong response I need to correlate the JSON they saw with the XML the handler
   actually returned, across the gateway-to-SOAP hop.

CONSTRAINTS — known platform behaviour, please respect these
- The transform plugin is BIDIRECTIONAL. One plugin handles JSON->XML on the
  request AND XML->JSON on the response. Do NOT add a second plugin for the
  other direction. Two transforms convert the body twice, the handler receives
  nonsense, and it returns a 500 that looks like a backend fault.
- Only schema fields plus _meta are legal in a plugin block. No invented fields
  and no commentary keys — put explanation in a YAML comment.
- If the plugin's schema has fields for namespace or attribute handling, tell me
  they exist and what the defaults do, but leave them at defaults unless I say
  my envelope needs them.
- If you need a conditional match on a header or path, use filter_func (a Lua
  expression string), not vars — vars fails at deploy time.

BEFORE YOU DEPLOY
- Show me the full spec you are about to apply and wait for my confirmation.
- Run validate_route and dry_run_deploy first. If either fails, show me the
  error and your proposed fix rather than retrying blindly.
- Tell me the execution order of the plugins on this route and which phase each
  one runs in.

AFTER YOU DEPLOY
- Give me a curl command that calls POST /locations with a JSON body.
- Show me the raw response, and confirm two separate things: the content-type is
  application/json, AND the body contains no XML markup. The header is a claim;
  a body with no angle brackets is the evidence. I want both.
- Show me the JSON shape the transform actually produced, and warn me about
  anything in it I would not have designed by hand — PascalCase element names,
  vendor prefixes, or a single-element collection that came through as an object
  rather than a list.

If anything is ambiguous — the handler path, whether it needs SOAPAction, what
the request body's field names should be — ask me instead of guessing.
```

**Check before act 2.** Confirm a JSON call returns JSON with no angle brackets in
the body. If that isn't true, adding auth on top will just make the failure harder
to see.

## Act 2 — add OAuth 2.0

```text
Now deploy a NEW REVISION that puts OAuth 2.0 in front of this API.

1. Add POST /oauth/token. Use helix-auth in generate mode: it verifies an app's
   client id and secret (Authorization: Basic base64(client_id:client_secret))
   and returns a signed JWT. Token lifetime 900 seconds — a leaked token should
   be worthless within fifteen minutes, so do not default it to an hour.

2. Require a valid Bearer token on POST /locations. Use helix-auth in validate
   mode with validate_auth_type jwt-auth, referencing the SAME signing secret.

   The rejection must happen in the access phase, BEFORE the transform runs.
   There is no point converting a body we are about to discard — confirm to me
   that this is the order you have produced.

3. Both must reference the JWT_SIGNING_SECRET environment variable. Never write
   the secret into the spec. If it does not exist on <<staging>>, tell me and
   stop — I will set it.

CONSTRAINTS
- Use helix-auth generate, NOT the jwt-auth plugin, for issuing. jwt-auth
  validates tokens an EXTERNAL issuer signed; the gateway is the issuer here.
- Apply validate PER ROUTE, on /locations only. Do NOT apply it API-wide — that
  would protect /oauth/token as well, and then no caller could ever obtain a
  first token and every request would return 401.
- This is a new revision. An ACTIVE revision will not accept edits ("Only
  INACTIVE revisions can be updated") — clone the revision so I keep a rollback
  target, or undeploy first. Tell me which you did.

BEFORE YOU DEPLOY
- Show me the spec, run validate_route and dry_run_deploy, and wait.

AFTER YOU DEPLOY
- Create a developer "<<Partner Integrations>>" with ONE app subscribed to this
  API and give me its client id and client secret.
- Give me curl commands showing, in order: no token → 401; client credentials →
  200 with an access_token; that token → 200 with a JSON body; and a garbage
  token → 401.
- Confirm that the 401 case never reached the SOAP backend.
```

---

## Why the prompt is shaped this way

| Block | Why it's there |
|---|---|
| **Two acts, not one** | Mediation failures and auth failures look alike from the outside (a 500 or a 401 with a config that reads fine). Splitting at the seam means each act is independently verifiable, and you know which one broke. |
| **"The transform plugin is BIDIRECTIONAL… do NOT add a second plugin"** | The single most likely wrong turn in this solution. The name reads one-way, so a model reaches for `json-to-xml` for the request direction. The body is then converted twice and the handler 500s — while the config looks *more* thorough, not less. |
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

1. `Show me calls to the Partner Locations API in the last hour, broken down by app, and the p99 latency of the SOAP hop.`
2. `Which calls returned 5xx today? For each, tell me whether the gateway or the SOAP handler produced it.`
3. `Write the developer-portal documentation for POST /locations, including real example payloads for BOTH a single-result and a multi-result response — partners need to see the shape difference.`
4. `A partner says they're getting XML back. Walk me through what to check.`

## Known failure modes when running this prompt

- **The handler returns 500, but curling it directly works.** In order of
  likelihood: a second transform plugin got added and the body is being converted
  twice; a missing `SOAPAction` header; the request body's element names don't
  match what the handler reads. Reply: `the transform is bidirectional — remove
  the second plugin, one handles both directions.`
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
- **[Solution 04 — Analytics](../04-analytics/helix-agent-prompt.md)** — the
  questions worth asking once this is live.
