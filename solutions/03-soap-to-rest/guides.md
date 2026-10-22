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

The fastest path, and it works on a **fresh, empty org**. One prompt builds the
translation: the API, the JSON route, and the conversion to and from your SOAP
service. [`helix-agent-prompt.md`](helix-agent-prompt.md) has it as one message —
paste it and replace the `{{...}}` values. Sign-in is not part of it; add it
afterwards with [solution 02](../02-oauth-jwt/) (see [Variations](#variations)).

See [AGENT-GUIDE.md](../../AGENT-GUIDE.md) for the ground rules these prompts
assume.

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

**1. Create the API**

Pick one of the two ways below. Both give you the same thing: an API called
`Partner Locations API` with one route and no plugins yet.

*Option A — from scratch*
1. Go to **API Gateway → APIs**, click **Add API** (or **Create your first API**).
2. Choose **Create from scratch**. Set **Display name** to
   `Partner Locations API`, then **Create**.
3. On the API's page, open **Configuration → Routes** and add one route:
   - `POST` `/locations`, the JSON lookup partners call

   The route form opens already filled in with the name *New* and the path
   `/new-route`. Clear both fields first, then type your own.

*Option B — from an OpenAPI spec*
1. Go to **API Gateway → APIs**, click **Add API** (or **Create your first API**).
2. Set **Method** to **Import an OpenAPI spec**.
3. Drag in your own OpenAPI 3.0 file, or use our example,
   [`example/api-spec-basic.yaml`](example/api-spec-basic.yaml): the same
   route, no plugins. Then click **Import**.

> **A spec can carry the plugins too.** Add an `x-helix-gateway` block under a
> path and method, and it covers that route only:
>
> ```yaml
> /locations:
>   post:
>     x-helix-gateway:
>       plugins:
>         proxy-rewrite:
>           uri: <SOAP_HANDLER_PATH>
>           headers:
>             set:
>               Content-Type: "text/xml; charset=utf-8"
>           _meta:
>             priority: 900
>         xml-to-json:
>           transform_request: true
>           transform_response: true
>           root_attributes:
>             "xmlns:soap": "http://schemas.xmlsoap.org/soap/envelope/"
>             "xmlns:m": "<SERVICE_NS>"
> ```
>
> [`example/api-spec.yaml`](example/api-spec.yaml) is this API with all its
> plugins already in place. Replace its `<SOAP_HANDLER_PATH>` and `<SERVICE_NS>`,
> import it, and you can skip step 2.

Either way, the API is not live yet: it has no upstream and isn't deployed.
That comes in step 3.

**2. Add the plugins**

Two plugins do the translation, both on the `POST /locations` route only. Add
them **before** you deploy: a live revision can't be changed.

On the API's page, open **Configuration → Plugins** and click **Configure
plugin**. A short wizard opens:

1. **Plugin** — pick the plugin from the catalog.
2. **Scope** — **Entire Revision** applies it to every route; **Specific
   endpoint** applies it to one route.
3. **Configure** — the JSON editor and the Properties list sit side by side.
   Paste the JSON below, or fill in the fields. Then **Next**.
4. **Review** — shows the configuration before and after. Click **Apply**.

Do this once for each plugin below. Both go on **Specific endpoint**, with
`POST /locations` picked as the route.

1. **`xml-to-json` — converts in both directions.** It turns the partner's JSON
   into XML on the way in, and the service's XML reply into JSON on the way out.
   Converting the request is **off by default**, so `transform_request` must be
   set. The reply is converted only when the caller sends
   `Accept: application/json`.

   `root_attributes` adds the namespace declarations a SOAP envelope needs, so
   partners don't have to send them. Replace `<SERVICE_NS>` with your service's
   namespace (you'll find it in its WSDL).

   ```json
   {"transform_request":true,"transform_response":true,
    "root_attributes":{"xmlns:soap":"http://schemas.xmlsoap.org/soap/envelope/","xmlns:m":"<SERVICE_NS>"}}
   ```

2. **`proxy-rewrite` — sends the call to your SOAP service, labelled as SOAP.**
   Partners call `/locations`; your service answers on its own path. Replace
   `<SOAP_HANDLER_PATH>` with that path, for example `/Service.asmx`.

   ```json
   {"uri":"<SOAP_HANDLER_PATH>",
    "headers":{"set":{"Content-Type":"text/xml; charset=utf-8"}},
    "_meta":{"priority":900}}
   ```

   **Keep the `"priority":900`.** `xml-to-json` labels the converted body
   `application/xml`, and a SOAP 1.1 service (`.asmx` and similar) turns that
   down with HTTP 415 (unsupported content type). This plugin fixes the label
   to `text/xml`. It has to run *after* the conversion to do that: plugins with
   a higher priority number run first, and `xml-to-json`'s is 997. Without the
   900, this plugin runs first, relabels the JSON before it's converted, and the
   body reaches your service unconverted.

   A SOAP 1.2 service wants `application/soap+xml` instead of `text/xml`. If
   your service needs a `SOAPAction` header, add it next to `Content-Type`.

Repeat for the second plugin. What every field means, and the two optional
extras (`request-id`, `cors`) the full spec adds across the API:
[Configuration reference](#configuration-reference).

**3. Point an upstream at your SOAP service, then deploy**
1. Go to **API Gateway → Upstreams → Add Upstream**. Name it, pick environment
   `test`, and add a node with your SOAP service's host, port and scheme. If you
   switch the scheme to HTTP, the port stays at `443`: change it to `80` by hand.
2. **Pass Host** is set to **Rewrite**, which makes **Upstream Host** required.
   It fills in from the node's host; check it matches your SOAP service.
3. Click **Next** through the remaining tabs, then **Add Upstream**.
4. Back on the API's page, click **Deploy** on the revision. The dialog asks you
   to map an upstream for `test`. Pick the one you just created, then click
   **Map & Deploy**. (The button reads **Map & Deploy** while no upstream is
   mapped yet, and **Deploy** once one is.)

**Changing it later.** A change to the upstream (host, port, scheme) applies to
the live API straight away, with no new deploy. A change to routes or plugins
does need one, because a live revision can't be edited: use **Clone Revision**,
make your change on the copy, then **Force Deploy** it. The same steps roll you
back: clone the older revision and force-deploy that.

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
# pass_host + upstream_host: without them the backend gets the gateway's host
# and every call returns 502.
curl -s "${H[@]}" -X POST "$BASE/orgs/$ORG/envs/<TEST_ENV_ID>/upstreams" \
  -d '{"name":"soap-upstream","specification":{"scheme":"https","pass_host":"rewrite","upstream_host":"<SOAP_HOST>","nodes":[{"host":"<SOAP_HOST>","port":443,"weight":1}]}}'
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

Send the SOAP envelope written as JSON. Each XML element becomes a JSON key,
prefixes included; the gateway adds the namespace declarations for you:

```http
POST /locations
content-type: application/json
accept: application/json

{"soap:Envelope":{"soap:Body":{"m:Operation":{"m:param":"value"}}}}
```

Use your service's real operation and parameter names in place of
`m:Operation` and `m:param`.

`accept: application/json` is not optional. The response is converted only when
the caller asks for JSON. Without that header the XML comes straight back as
`text/xml`, and no gateway setting changes that.

You get JSON back, shaped by how the XML was structured:

```http
HTTP/1.1 200 OK
content-type: application/json
X-Request-Id: 7f3c...

{"Locations":{"Site":[{"id":"1","name":"Frankfurt"},{"id":"2","name":"Dublin"}]}}
```

`X-Request-Id` is there when the `request-id` plugin is on, as it is in
`example/api-spec.yaml`.

**The JSON shape comes from the XML, not from a design.** Tell partners this,
and publish real example payloads, because these become part of your API:

- **Element names come through as they are**, including `PascalCase` and
  prefixes. You get `{"Locations":{"Site":[...]}}`, not the
  `{"locations":[...]}` a REST designer would have written.
- **Prefixes and namespace declarations stay.** `soap:` and `m:` are kept in the
  keys, and `xmlns:*` attributes come back as JSON fields.
- **A single item may not be a list.** One `<Site>` can become an object where two
  become a list. Partner code that expects a list breaks on the single case.
- **No results come back as `null`, not `{}`.** An empty collection converts to
  `null`.
- **Don't rely on the order of fields** in the JSON response. It can change from
  one call to the next.
- **Fields are sent to the service in alphabetical order.** When a JSON object
  with several fields becomes XML, its fields are sorted A–Z. A service that
  expects a fixed order (an `xs:sequence` in its WSDL) can reject the call.
- **The `Accept` check is a simple match.** It ignores preference weights, so
  `application/xml;q=0.9, application/json;q=0.1` still gets JSON.

To run the checks as a script:

```bash
GATEWAY=https://<YOUR_GATEWAY_HOST> ./example/verify.sh
```

Set `REQ_BODY` to a real envelope for your service, written as JSON. Exit code 0 means
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

**Your envelope uses other namespaces.** Add each one to `xml-to-json`'s
`root_attributes`, as the spec does for `soap:` and `m:`. Partners then use the
prefixes in their JSON keys and never send the declarations themselves.

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

Source of truth: [`example/api-spec.yaml`](example/api-spec.yaml).
[`example/api-spec-basic.yaml`](example/api-spec-basic.yaml) is the same route
with no plugins, for adding them yourself. Two blocks on `POST /locations` carry
the translation:

```yaml
# 1. the path, plus the SOAP 1.1 content type, set AFTER the conversion (priority 900)
proxy-rewrite:
  uri: <SOAP_HANDLER_PATH>
  headers:
    set:
      Content-Type: "text/xml; charset=utf-8"
  _meta:
    priority: 900

# 2. request conversion is OFF by default — turn it on; response runs on Accept: application/json
xml-to-json:
  transform_request: true
  transform_response: true
  root_attributes:
    "xmlns:soap": "http://schemas.xmlsoap.org/soap/envelope/"
    "xmlns:m": "<SERVICE_NS>"
```

| Plugin | Field | Value here | What it means |
|---|---|---|---|
| `proxy-rewrite` | `uri` | `<SOAP_HANDLER_PATH>` | The path your SOAP service answers on. |
| `proxy-rewrite` | `headers.set.Content-Type` | `text/xml; charset=utf-8` | The content type a SOAP 1.1 service expects. Use `application/soap+xml` for SOAP 1.2. Add `SOAPAction` here too if your service needs it. |
| `proxy-rewrite` | `_meta.priority` | `900` | Runs this plugin after `xml-to-json` (997), so the body is already XML when the content type is set. Leave it out and the request is never converted. |
| `xml-to-json` | `transform_request` | `true` | Convert the JSON request body to XML. **Defaults to `false`**, so it must be set. |
| `xml-to-json` | `transform_response` | `true` | Convert the XML response to JSON. On by default, but only runs when the client sends `Accept: application/json`. |
| `xml-to-json` | `root_attributes` | `xmlns:soap`, `xmlns:m` | Attributes added to the root XML element: here, the envelope's namespace declarations. Replace `<SERVICE_NS>` with your service's namespace. |
| `request-id` (API-wide) | `algorithm` / `header_name` | `uuid` / `X-Request-Id` | A tracking id on every call, so you can match the JSON a partner saw with the XML the handler returned. |
| `cors` (API-wide) | `allow_origins` / `allow_methods` / `allow_headers` / `allow_credential` | `*` / `POST,OPTIONS` / `content-type` / `false` | Browser access. Narrow `allow_origins` before going live. |

**What `xml-to-json` does to headers.** On the way to your service it sets both
`Content-Type` and `Accept` to `application/xml`. That's why `proxy-rewrite`
sets the content type again afterwards.

Other `xml-to-json` fields the spec leaves at their defaults. Confirm them with
`get_plugin_config` in your own org, because they vary by build:

| Field | Default | Use it for |
|---|---|---|
| `content_types` | `application/xml`, `text/xml` | which backend response types get converted |
| `request_content_types` | `application/json` | which request bodies get converted |
| `root_name` | — | the name of the root element |
| `request_root_name` | `request` | the root element wrapped around a converted request |
| `enable_decl` | — | whether to add an `<?xml ...?>` declaration line |
| `pretty` | — | indented output. **Leave it off:** it returns HTTP 503 on this build |
| `property_naming` | not set | renaming keys to `camelCase` or `PascalCase`. When it's not set, names are kept, except that hyphens still become underscores |
| `array_item_name` | `item` | the element name used for list items |
| `max_body_size` | `1048576` | the largest body it will convert, in bytes |
| `ctx_namespace` | — | where the plugin shares its values with other plugins on the route |

There is no analytics plugin in the spec, because analytics is on for every API by
default — see [solution 04](../04-analytics/). The SOAP host is not in this file
either: it is the upstream bound to the API when you deploy.

Placeholders in this package: `<SOAP_HANDLER_PATH>`, `<SERVICE_NS>`, `<SOAP_UPSTREAM_URL>` (the
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
- **HTTP 415 from the SOAP service.** It wants `text/xml` and got
  `application/xml`. Set the content type in `proxy-rewrite` with
  `"priority":900`: see [step 2](#build-it-in-the-ui). SOAP 1.2 services want
  `application/soap+xml`.
- **Your service may need a `SOAPAction` header.** Many classic SOAP 1.1 and
  `.asmx` services return a 500 with an unhelpful envelope without it. Add it in
  `proxy-rewrite` under `headers.set`, next to `Content-Type`.
- **HTTP 502 on every try, with the connection failing straight away over
  HTTPS.** Check the TLS connection to your SOAP host: some older services don't
  manage HTTPS from the gateway. Try the upstream over HTTP (port `80`).
- **The 502 error page is HTML,** even for a caller that asked for JSON.
- **A 500 from a handler that works when you call it directly is almost never the
  handler.** Suspect, in order: `proxy-rewrite` running before the conversion (check
  `"priority":900` is set), a missing `SOAPAction`, or request names that don't
  match the elements the handler reads.
- **An empty result (`null`) often means the names didn't match**, not that
  there's no data. Check what XML your JSON is producing before you decide the
  result is empty.
- **Single items may not be lists.** Test both the one-result and many-result
  cases, and warn integrators.
- **Fields arrive in alphabetical order.** If your service expects a fixed order,
  check its WSDL and test a call with several fields.
- **Legacy handlers are often slow.** Some take seconds. Check the gateway timeout
  before deciding the backend is down — the symptom is a 504 that looks like an
  outage.
- **Element names become your public contract.** Partner-facing JSON now contains
  the internal names of an old system. Renaming them later breaks partners, so
  decide now whether you're happy to publish them.
- **Use the trace inspector to see each step.** On the API's page, open the
  **Observability** tab and click **Start trace session**. It shows the headers
  each plugin changes and the request body at every stage, which is the fastest
  way to see what your SOAP service actually received. A session stops after 10
  requests, so use **Advanced: filter which requests to capture** to record only
  the ones you care about (skipped requests don't count). The list doesn't
  refresh by itself: click **Refresh**. The **Inspector** shows API keys and
  cookies in plain text, so don't share your screen or paste a trace into a
  ticket without removing them. A compressed response, which browsers always ask
  for, is unreadable in the **Response** tab, so call the API with curl to read
  it. The **Upstream** tab's **Total** adds connect time to response time, so it
  can be larger than the request's own total.
- **See what changed, and when, in Audit Logs.** **Observability → Audit Logs**
  lists every clone, plugin change and deploy. Its times are in your local time,
  while analytics uses UTC. Anything done with your token, including scripts and
  the Helix Agent, appears under your name.
- **Confirm `xml-to-json` exists in your org** before designing around it. Builds
  differ, and this plugin is the one the whole solution rests on.
- **Nothing checks who is calling.** Anyone who can reach the gateway can call your
  legacy system through it. Add [solution 02](../02-oauth-jwt/) before this faces
  partners — see [Variations](#variations).
