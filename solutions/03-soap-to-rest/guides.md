# Guides — SOAP/XML backend served as REST/JSON

> [Overview](README.md) · [Business need](business-need.md) · [Architecture](architecture.md) · **Guides** · [Agent prompt](helix-agent-prompt.md) · [Tests](tests.md) · [API reference](api-reference.md)

---

Three ways to build the same thing, then how to see it work. Whichever way you
pick, the result is one API with one route, `POST /locations`, that takes JSON,
calls your SOAP handler in XML, and returns JSON. It carries no sign-in; add
[solution 02](../02-oauth-jwt/) before partners call it.

**You supply the SOAP backend.** This can't run on a public sample upstream —
SOAP-to-REST needs a SOAP service. You'll need its address (`<SOAP_UPSTREAM_URL>`)
and the path its handler answers on (`<SOAP_HANDLER_PATH>`, for example
`/Service.asmx` or `/soap/endpoint`).

## Pick your path

| | Choose this if you… | Go to |
|---|---|---|
| **1. Helix Agent** | want the quickest result and are happy to paste a prompt | [Build it with the Helix Agent](#build-it-with-the-helix-agent) |
| **2. Helix control plane** | prefer clicking through screens and want to see every setting | [Build it in the UI](#build-it-in-the-ui) |
| **3. API script** | are scripting this, or wiring it into a pipeline | [Install it directly](#install-it-directly) |

Then, for everyone: [See it work](#see-it-work) · [Variations](#variations) ·
[Configuration reference](#configuration-reference) · [Troubleshooting](#troubleshooting)

## Build it with the Helix Agent

A short path. The build is **one prompt** —
[`helix-agent-prompt.md`](helix-agent-prompt.md). Paste it as a single message and
replace the `{{...}}` values.

It builds the translation and nothing else, and so does
[`example/api-spec.yaml`](example/api-spec.yaml) — the prompt and the spec
describe the same API. Sign-in is [solution 02](../02-oauth-jwt/); add it with
02's prompt once the translation works (see [Variations](#variations)). Keeping
them apart is deliberate: a translation failure and a sign-in failure look alike
from the outside, and building one at a time is how you find out which one broke.
[AGENT-GUIDE.md](../../AGENT-GUIDE.md) has the standing rules the prompt assumes.

> **Check what was stored, not what the agent said.** Three of the four known
> agent-mode problems report success at every step the agent shows you — a run can
> end "success" having deployed a route with no plugins at all. Ask for the
> plugins applied to `/locations` and read them back.
>
> **A JSON call must come back as JSON with no angle brackets in the body.** A
> content-type header is a claim; a body with no XML markup is evidence. Check that
> before you add anything on top of it.

### Why the prompt is worded the way it is

It names no plugin, no field and no secret, on purpose. Ask for an outcome and the
agent reads the real plugin settings your org has; ask for field names and it
copies them from some other gateway's documentation. That matters more here than
anywhere else in this library, because **`xml-to-json`'s settings vary between
builds more than most** — see [Architecture](architecture.md#the-one-thing-everybody-gets-wrong).

One phrase does most of the work: **"neither side changes to make that work."**
It states the whole outcome as a rule — partners get JSON, the backend keeps its
XML, and no code is written at either end — and leaves the agent to pick the
mechanism, which is the part that differs between builds.

The prompt carries **no warning about `Content-Type`**, and you should know why
that is worth checking. An earlier run, with different wording, put
`Content-Type: application/xml` in `proxy-rewrite`. That runs before the body is
converted, so the request conversion never saw a JSON body and the backend was
handed JSON it couldn't read. The route still answered **200 with
`content-type: application/json` and a JSON body**, so nothing looked wrong. A
later run of the wording shipped here built the translation in one pass. Which
wording change made the difference hasn't been measured, so read the revision back
and confirm nothing set `Content-Type` on the rewrite.

### When the agent goes wrong

| Symptom | Cause |
|---|---|
| The handler returns 500, but calling it directly works | A second conversion plugin is converting the body twice; or a missing `SOAPAction`; or the request field names don't match what the handler reads. |
| The response is still XML | The client isn't sending `Accept: application/json`, or `proxy-rewrite` is setting `Content-Type` ahead of the conversion. Both have happened. |
| An XML body with a JSON content type | The conversion is only running in the request direction. Ask for the plugins applied on that route. |
| 200, a JSON body, and the backend's own "bad input" error inside it | The agent set `Content-Type` in `proxy-rewrite`. It runs before the body is converted, so the backend received raw JSON. Everything looks healthy — 200, `application/json`, valid JSON — and the translation isn't working. Seen on a live run. |
| The JSON body is `{}` | The handler returned an empty envelope — usually the request field names don't match its elements. Ask what XML it is actually sending. |
| 415 from the handler | Do **not** fix this by setting `Content-Type` in `proxy-rewrite` — it runs first and hides the JSON body from the conversion. Check whether the handler needs a `SOAPAction` header instead. |
| 504 on every call | The handler is slower than the gateway timeout. Looks like an outage, isn't. |
| The agent adds a second plugin for the reverse direction | One plugin covers both directions here. See [Architecture](architecture.md#the-one-thing-everybody-gets-wrong). |
| The agent puts a `description` key in a plugin block | Only the plugin's own fields (plus `_meta`) are allowed. Move the note to a YAML comment. |
| Deploy fails: `Only INACTIVE revisions can be updated` | Expected on any change after the first deploy — clone the revision or undeploy first. |

## Build it in the UI

Screen and button names below are the real ones. The API and its upstream live
under **API Gateway** in the left sidebar.

**Before you start:**

- **You have an account.** If you don't, register for a free trial at
  [trial.digitalapi.ai](https://trial.digitalapi.ai/). A new trial org comes with a
  `test` environment, which is all this walkthrough needs.
- **You can create APIs.** If you don't see an **Add API** button, ask your org
  admin.
- **Your SOAP service is reachable from the gateway**, and you know its handler
  path.

**1. Put your handler path into the spec**
Open [`example/api-spec.yaml`](example/api-spec.yaml) and replace
`<SOAP_HANDLER_PATH>` with your handler's path. If your handler needs a
`SOAPAction` header, add it under `proxy-rewrite` now — see
[Troubleshooting](#troubleshooting). There is no screen for either; they travel
inside the spec you import.

**2. Import the API**
1. Go to **API Gateway → APIs**, click **Add API** (or **Create your first API**).
2. Set **Method** to **Import an OpenAPI spec**.
3. Drag in your edited `api-spec.yaml`, or paste its contents, then click
   **Import**.

This creates the API and its first revision. The imported spec already carries
`proxy-rewrite` and `xml-to-json` (both directions on) on `/locations`, plus
`request-id` and `cors` across the API. Import does **not** bind an upstream or
deploy, and nothing warns you if you skip that.

**3. Point an upstream at your SOAP service, then deploy**
1. Go to **API Gateway → Upstreams → Add Upstream**. Name it, pick environment
   `test`, point it at your SOAP service's host, then **Create Upstream**.
2. Back on the API's page, click **Deploy** on the revision. The dialog asks you to
   map an upstream for `test`. Pick the one you just created, then **Deploy**.

That's the whole build: there are no products or apps, because this package has no
sign-in. When you add [solution 02](../02-oauth-jwt/), its guide covers the
product, developer and app.

## Install it directly

If you'd rather script it against the control plane:

```bash
export ORG=<ORG_ID>
export TOKEN=<control-plane bearer token>      # short-lived
export BASE=https://<YOUR_GATEWAY_HOST>/api
H=(-H "authorization: Bearer $TOKEN" -H 'content-type: application/json')

# 1. Confirm xml-to-json exists in your org and check its fields — ask the agent
#    for get_plugin_config, or query the control plane's plugin-schema endpoint.
#    Do not assume the field names in this spec.

# 2. Replace <SOAP_HANDLER_PATH> in the spec, then import it. Keep both ids the
#    response returns.
curl -s -H "authorization: Bearer $TOKEN" -F "file=@example/api-spec.yaml" \
  "$BASE/orgs/$ORG/apis/from-spec"
# → {"api":{"id":"<API_ID>", ...}, "revision":{"id":"<REVISION_ID>", ...}}

# 3. Import does NOT make the route live. Create an upstream for your SOAP service
#    (use your service's scheme, host and port),
#    bind it to the revision, then deploy the revision.
curl -s "${H[@]}" -X POST "$BASE/orgs/$ORG/envs/<TEST_ENV_ID>/upstreams" \
  -d '{"name":"soap-upstream","specification":{"scheme":"https","nodes":[{"host":"<SOAP_HOST>","port":443,"weight":1}]}}'
# → {"id":"<UPSTREAM_ID>", ...}

curl -s "${H[@]}" -X PATCH "$BASE/orgs/$ORG/apis/<API_ID>/revisions/<REVISION_ID>/upstream-bindings/add" \
  -d '{"environmentUpstreams":[{"environmentId":"<TEST_ENV_ID>","upstreamId":"<UPSTREAM_ID>"}]}'
curl -s "${H[@]}" -X POST "$BASE/orgs/$ORG/apis/<API_ID>/revisions/<REVISION_ID>/deploy" \
  -d '{"environmentId":"<TEST_ENV_ID>","force":false}'

# 4. Prove it — including that the body is really converted, not just relabelled
GATEWAY=https://<YOUR_GATEWAY_HOST> ./example/verify.sh
```

> Revisions must be **INACTIVE** to accept a change — otherwise you get `Only
> INACTIVE revisions can be updated`. If it's live, undeploy first, or clone the
> revision so you keep one to roll back to.

The same calls without narration: [API reference](api-reference.md).

## See it work

Send plain JSON — no envelope, no WSDL:

```http
POST /locations
content-type: application/json
accept: application/json

{"region":"EMEA","activeOnly":true}
```

`accept: application/json` is not optional. The response conversion depends on
it — without that header the XML comes straight back as `text/xml`, and no gateway
setting changes that.

You get JSON back, shaped by how the XML was structured:

```http
HTTP/1.1 200 OK
content-type: application/json
X-Request-Id: 7f3c...

{"Locations":{"Site":[{"id":"1","name":"Frankfurt"},{"id":"2","name":"Dublin"}]}}
```

**The JSON shape is derived from the XML, not designed.** This surprises people:

- **Element names come through as they are**, including `PascalCase` and any
  vendor prefixes. You get `{"Locations":{"Site":[...]}}`, not the
  `{"locations":[...]}` a REST designer would have written.
- **A single item may not be a list.** One `<Site>` can become an object where two
  become a list. That breaks partner code that expects a list — on the unusual
  case rather than the common one.
- **Namespaces and attributes need handling.** Default settings often flatten or
  drop them.

Tell integrators this is a *translated* API, and publish real example payloads for
both the single-result and multi-result cases.

To run the checks as a script:

```bash
GATEWAY=https://<YOUR_GATEWAY_HOST> ./example/verify.sh
```

Set `REQ_BODY` to a real query body if your handler needs one. Exit code 0 means
the call returned JSON **and** the body contains no XML markup — proof the
conversion actually ran. What each check proves, plus the manual tests `verify.sh`
can't run for you: [Tests](tests.md).

## Variations

Paste any of these as a follow-up in the same agent session.

**Add the OAuth layer** — this is [solution 02](../02-oauth-jwt/), and the thing to
do before partners call this API. Expect the deploy to need a clone or an undeploy
first, because a live revision rejects edits. Two things that package covers and
this one does not: the signing secret is used **exactly as written**, so a
`<ENV:...>` placeholder becomes the real key; and token checking goes on
`/locations` only, never API-wide, or the token endpoint locks itself out. If
browsers will call the API, `authorization` also has to be added to `cors`
`allow_headers`, which here lists only `content-type`.
```text
Add a route POST /oauth/token, so an app can trade its client credentials for a
token generated by the gateway. Update /locations to validate the token generated
by this endpoint, and to reject an unauthenticated call before it does any work on
the body. Then create a developer, a product and an app, and give me the app's
client id and secret.
```

**Your envelope is namespaced or attribute-heavy**
```text
The upstream XML uses namespaces and puts significant data in attributes, and the
default transform is flattening them. Show me the namespace and attribute fields
this plugin actually has, explain what each does to my payload, and let me choose
before you change anything.
```

**Single-element collections are breaking partner code**
```text
One <Site> gives partners an object, several give an array, and their clients
break on the single case. Tell me honestly whether the transform can force a
consistent array, and if it can't, what my options are.
```

**Reject bad requests at the edge**
```text
Validate the body of POST /locations against a JSON Schema derived from the fields
the handler actually reads, so malformed input is a clean 400 from the gateway
instead of a 500 from the handler.
```

**The legacy handler is slow**
```text
The SOAP handler regularly takes 8-10 seconds and I'm seeing 504s. Tell me the
current gateway timeout on this route, what raising it costs me, and whether
there's a better answer than waiting longer.
```

**Add a second operation**
```text
Add POST /sites proxying to the same upstream but operation {{soap_operation}}, reusing
the same transform. Keep the routes independent so I can meter them separately
later.
```

**Meter the partners**
```text
I want to sell access to this API in tiers and enforce the limits per app.
```
(That's [solution 01](../01-api-products/). It needs sign-in first.)

**Document it**
```text
Write the developer-portal documentation for POST /locations, with real example
payloads for BOTH a single-result and a multi-result response.
```

Reading the traffic afterwards isn't a follow-up here — that's the metrics API,
covered in [solution 04](../04-analytics/).

## Configuration reference

Source of truth: [`example/api-spec.yaml`](example/api-spec.yaml). Two blocks on
`POST /locations` carry the translation:

```yaml
# 1. path only — NO Content-Type setting (it runs before the conversion and defeats it)
proxy-rewrite:
  uri: <SOAP_HANDLER_PATH>

# 2. request conversion is OFF by default — turn it on; response runs on Accept: application/json
xml-to-json:
  transform_request: true
  transform_response: true
```

| Plugin | Field | Value here | What it means |
|---|---|---|---|
| `proxy-rewrite` | `uri` | `<SOAP_HANDLER_PATH>` | The path the SOAP handler answers on. **Path only** — don't set `Content-Type` here. A `SOAPAction` header, if your handler needs one, is safe to add (under `headers.set`). |
| `xml-to-json` | `transform_request` | `true` | Convert the JSON request body to XML. **Defaults to `false`**, so it must be set. |
| `xml-to-json` | `transform_response` | `true` | Convert the XML response to JSON. On by default, but only runs when the client sends `Accept: application/json`. |
| `request-id` (API-wide) | `algorithm` / `header_name` | `uuid` / `X-Request-Id` | A tracking id on every call, so you can match the JSON a partner saw with the XML the handler returned. |
| `cors` (API-wide) | `allow_origins` / `allow_methods` / `allow_headers` / `allow_credential` | `*` / `POST,OPTIONS` / `content-type` / `false` | Browser access. Narrow `allow_origins` before going live. |

Other `xml-to-json` fields the spec documents but leaves at their defaults —
confirm them with `get_plugin_config` in your own org, because they vary by build:

| Field | Default | Use it for |
|---|---|---|
| `content_types` | `application/xml`, `text/xml` | which backend response types get converted |
| `request_content_types` | `application/json` | which request bodies get converted |
| `property_naming` | — (`camelCase` or `PascalCase`) | renaming keys in the converted JSON |
| `array_item_name` | `item` | the element name used for list items |
| `max_body_size` | `1048576` | the largest body it will convert, in bytes |

There is no analytics plugin in the spec, because analytics is on for every API by
default — see [solution 04](../04-analytics/). The SOAP host is not in this file
either: it is the upstream bound to the API when you deploy.

Placeholders in this package: `<SOAP_HANDLER_PATH>`, `<SOAP_UPSTREAM_URL>` (the
host you bind as the upstream), `<SOAP_HOST>`, `<ORG_ID>`, `<TEST_ENV_ID>`,
`<API_ID>`, `<REVISION_ID>`, `<UPSTREAM_ID>`, `<YOUR_GATEWAY_HOST>`. Replace all
of them before you deploy.

Every field of every plugin, and the wider product docs:
[docs.digitalapi.ai/api-gateway](https://docs.digitalapi.ai/api-gateway).

## Troubleshooting

- **`xml-to-json` needs `transform_request: true`, and the response needs
  `Accept: application/json`.** The defaults do neither the way you'd expect.
  `json-to-xml` is a *separate* plugin for the opposite job, not the request-side
  partner. See [Architecture](architecture.md#the-one-thing-everybody-gets-wrong).
- **Your handler may need a `SOAPAction` header.** Many classic SOAP 1.1 and
  `.asmx` services return a 500 with an unhelpful envelope without it. Add it in
  `proxy-rewrite` under `headers.set`. Check what your handler expects rather than
  assuming it needs nothing.
- **The handler expects `text/xml` here (SOAP 1.1 style).** SOAP 1.2 handlers want
  `application/soap+xml`.
- **A 500 from a handler that works when you call it directly is almost never the
  handler.** Suspect, in order: the body converted twice, a missing `SOAPAction`,
  or request field names that don't match the elements the handler reads.
- **An empty `{}` usually means the field names didn't match**, not that there's no
  data. Check what XML your JSON is producing before concluding the result is
  empty.
- **Single items may not be lists.** Test both the one-result and many-result
  cases, and warn integrators.
- **Namespaced or attribute-heavy envelopes need settings.** Defaults often
  flatten namespaces or drop attributes. Confirm the fields your build has.
- **Legacy handlers are often slow.** Some take seconds. Check the gateway timeout
  before deciding the backend is down — the symptom is a 504 that looks like an
  outage.
- **Element names become your public contract.** Partner-facing JSON now contains
  the internal names of an old system. Renaming them later breaks partners, so
  decide now whether you're happy to publish them.
- **Confirm `xml-to-json` exists in your org** before designing around it. Builds
  differ, and this plugin is the one the whole solution rests on.
- **Nothing checks who is calling.** Anyone who can reach the gateway can call your
  legacy system through it. Add [solution 02](../02-oauth-jwt/) before this faces
  partners — see [Variations](#variations).
