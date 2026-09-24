# Agent-mode prompt — Serve a SOAP backend as REST/JSON

Two acts from a blank organisation: get the mediation working, check it, then add
OAuth in a second revision. **Deploy and check between them** — a transform
failure and an auth failure look alike from the outside, and splitting at the seam
tells you which one broke.

Bring your own SOAP endpoint and its handler path. Replace the `<<...>>` values.
[AGENT-GUIDE.md](../../AGENT-GUIDE.md) carries the standing rules these prompts
assume.

> **Three things about this build** that the prompts below account for:
> `transform_request` defaults to **false**, the response transform is
> content-negotiated on `Accept: application/json`, and a `Content-Type` override
> in `proxy-rewrite` defeats the request direction.

---

## Act 1 — get the mediation working

```text
Create a REST API "<<Partner Locations API>>" fronting a SOAP backend at
<<SOAP_UPSTREAM_URL>>. POST /locations proxies to the upstream path
<<SOAP_HANDLER_PATH>>, and a plugin transforms request and response bodies so
partners send and receive JSON while the backend keeps speaking XML.

Read get_plugin_config for the transform plugin first — I want the schema this org
actually has, not field names from another gateway. On this build transform_request
defaults to false, so set it true explicitly; the response direction only fires
when the client sends Accept: application/json; and don't set Content-Type in
proxy-rewrite, which runs first and would hide the JSON body. One plugin handles
both directions — don't add json-to-xml alongside it.

Plugins go in a top-level "plugins" map on the route object, each under its own
plugin name. No "x-helix-gateway" wrapper — a live route discards it silently and
still reports success.

Show me the spec, run dry_run_deploy, then read the revision back so I can see
which plugins actually landed. Wait before deploying.

Tell me anything in the derived JSON shape I wouldn't have designed by hand, and
whether my handler needs a SOAPAction header. Ask me rather than guessing the
handler path or the request field names.
```

**Check before act 2.** A JSON call must return JSON with no angle brackets in the
body. If that isn't true, adding auth on top only makes the failure harder to see.

## Act 2 — add OAuth 2.0

```text
Deploy a NEW REVISION that adds OAuth 2.0:

- POST /oauth/token issues a signed JWT from an app's client id and secret,
  15-minute lifetime (helix-auth generate)
- POST /locations requires a valid Bearer token, rejected in the access phase
  BEFORE the transform runs (helix-auth validate, jwt-auth)

Both use the SAME signing secret, a literal value — this build does not resolve
<ENV:...>. Apply validate on /locations only, never API-wide, or /oauth/token
would be protected and nobody could get a first token. Clone the active revision
so I keep a rollback, or undeploy first — an ACTIVE revision rejects edits. Tell
me which you did.
```

Then create the app:

```text
Create a developer "<<Partner Integrations>>" with an app subscribed to this API
and give me the client id and secret. Then curl commands showing, in order: no
token → 401; client credentials → 200 with an access_token; that token → 200 with
a JSON body; a garbage token → 401 — and confirm the 401 never reached the SOAP
backend.
```

---

## Why it's shaped this way

- **Two acts.** Mediation and auth failures look alike — a 500, or a 401 with a
  config that reads fine. Each act is independently verifiable.
- **Outcome, not field names.** `xml-to-json`'s fields vary by build more than most.
  Asked for an outcome the agent reads your schema; asked for fields it recalls
  someone else's.
- **The three build-specific facts.** All three were real failures in a live run,
  and any one of them leaves the request unconverted with the handler rejecting it.
- **Auth before the transform.** Ordering is by priority, not document order.
  Transforming a body you are about to reject is wasted work on every
  unauthenticated request.
- **"Anything I wouldn't have designed by hand".** The JSON shape is *derived* from
  the XML. PascalCase names and single-element collections become part of your
  public contract unless someone flags them now.
- **Read the revision back.** Three of the four known agent-mode defects report
  success at every step the agent shows you.

## Tweak knobs

**Your envelope is namespaced or attribute-heavy**
```text
The upstream XML uses namespaces and puts significant data in attributes, and the
default transform is flattening them. Show me the plugin's namespace and attribute
fields from get_plugin_config, explain what each does to my payload, and let me
choose before you change anything.
```

**Single-element collections are breaking partner code**
```text
One <Site> gives partners an object, several give an array, and their clients break
on the single case. Tell me honestly whether the transform can force a consistent
array, and if it can't, what my options are.
```

**Reject bad requests at the edge**
```text
Add request-validation on POST /locations with a JSON Schema derived from the
fields the handler actually reads, so malformed input is a clean 400 from the
gateway instead of a 500 from the handler.
```

**The legacy handler is slow**
```text
The SOAP handler regularly takes 8-10 seconds and I'm seeing 504s. Tell me the
current gateway timeout on this route, what raising it costs me, and whether
there's a better answer than waiting longer.
```

**Add a second operation**
```text
Add POST /sites proxying to the same upstream but operation <<GetSites>>, reusing
the same transform and auth. Keep the routes independent so I can meter them
separately later.
```

**Meter the partners**
```text
Add api-product-enforcer on /locations behind the helix-auth block, create products
for the tiers I sell, and confirm the route has a service_id. No limit-count keyed
on consumer_name — the product quota already counts per app.
```
(That's [solution 01](../01-api-products/).)

## Follow-ups in the same session

1. `Write the developer-portal documentation for POST /locations, with real example payloads for BOTH a single-result and a multi-result response.`
2. `A partner says they're getting XML back. Walk me through what to check.`
3. `Show me the applied plugins on /locations and their execution order, so I can confirm the transform runs in both directions.`

Reading analytics is not one of them — that's the metrics API, covered in
[solution 04's catalogue](../04-analytics/charts.md).

## When it goes wrong

| Symptom | Cause |
|---|---|
| Handler 500s, but curling it directly works | A second transform plugin is converting the body twice; or a missing `SOAPAction`; or the request element names don't match what the handler reads. |
| The response is still XML | The client isn't sending `Accept: application/json`, or `proxy-rewrite` is overriding `Content-Type` ahead of the transform. Both were real failures. |
| XML body with a JSON content-type | The transform is running on the request direction only. Ask for the applied plugins on that route. |
| The JSON body is `{}` | The handler returned an empty envelope — usually the request field names don't match its elements. Ask what XML it is actually generating. |
| 415 from the handler | Confirm `proxy-rewrite` sets `text/xml`; SOAP 1.2 wants `application/soap+xml`. |
| 504 on every call | The handler is slower than the gateway timeout. Looks like an outage, isn't. |
| Everything 401s after act 2, token endpoint included | `validate` was applied API-wide. Move it to `/locations` only. |
| Deploy fails: `Only INACTIVE revisions can be updated` | Expected in act 2 — clone the revision or undeploy first. |
| The agent puts a `description` key in a plugin block | Only schema fields plus `_meta` are legal. Move it to a YAML comment. |

## Related

- **[Solution 02 — OAuth 2.0 with JWT](../02-oauth-jwt/helix-agent-prompt.md)** —
  act 2 on its own, with the token lifetime and signing-secret traps in full.
- **[Solution 01 — API Products](../01-api-products/helix-agent-prompt.md)** —
  metering the partners now reaching your legacy system.
- **[Solution 04 — Analytics](../04-analytics/charts.md)** — the questions worth
  asking once this is live.
