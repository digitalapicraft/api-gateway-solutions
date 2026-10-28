# Guides — XML and JSON mediation at the edge

> [Overview](README.md) · [Business need](business-need.md) · [Architecture](architecture.md) · **Guides** · [Agent prompt](helix-agent-prompt.md) · [Tests](tests.md) · [API reference](api-reference.md)

---

Three ways to build the same thing, then how to see it work. Whichever way you
pick, the result is one API with two routes on a public test backend:
`GET /catalog/items` returns the backend's XML as JSON, and `POST /catalog/orders`
turns a JSON body into XML before the backend sees it.

## Pick your path

| | Choose this if you… | Go to |
|---|---|---|
| **1. Helix Agent** | want the quickest result and are happy to paste a prompt | [Build it with the Helix Agent](#build-it-with-the-helix-agent) |
| **2. Helix control plane** | prefer clicking through screens | [Build it in the UI](#build-it-in-the-ui) |
| **3. API script** | are scripting this, or wiring it into a pipeline | [Install it directly](#install-it-directly) |

Then, for everyone: [See it work](#see-it-work) · [Variations](#variations) ·
[Configuration reference](#configuration-reference) · [Troubleshooting](#troubleshooting)

## Build it with the Helix Agent

The fastest path, and it works on a **fresh, empty org**. One prompt does the
whole build: [`helix-agent-prompt.md`](helix-agent-prompt.md) has it as two
numbered steps — Step 1 creates the API and its two routes, Step 2 adds the
conversion in both directions and lets browsers call it. Paste the whole thing as
one message, then run the checks under [See it work](#see-it-work). If your
backend is SOAP, use [solution 03](../03-soap-to-rest/) instead.

See [AGENT-GUIDE.md](../../AGENT-GUIDE.md) for the ground rules these prompts
assume.

## Build it in the UI

Screen and button names below are the real ones. The API lives under
**API Gateway** in the left sidebar.

**Before you start:**

- **You have an account.** If you don't, register for a free trial at
  [trial.digitalapi.ai](https://trial.digitalapi.ai/). A new trial org comes with
  a `test` environment, which is all this walkthrough needs.
- **You can create APIs.** If you don't see an **Add API** button, ask your org
  admin.

**1. Create the API**

Pick one of the two ways below. Both give you the same thing: an API called
`Catalog API` with two routes and no plugins yet.

*Option A — from scratch*
1. Go to **API Gateway → APIs**, click **Add API** (or **Create your first API**).
2. Choose **Create from scratch**. Set **Display name** to `Catalog API`, then
   **Create**.
3. On the API's page, open **Configuration → Routes** and add two routes:
   - `GET /catalog/items`, the list of catalog items
   - `POST /catalog/orders`, placing an order

   The route form opens already filled in with the name *New* and the path
   `/new-route`. Clear both fields first, then type your own.

*Option B — from an OpenAPI spec*
1. Go to **API Gateway → APIs**, click **Add API** (or **Create your first API**).
2. Set **Method** to **Import an OpenAPI spec**.
3. Drag in your own OpenAPI 3.0 file, or use our example,
   [`example/api-spec-basic.yaml`](example/api-spec-basic.yaml): the same two
   routes, no plugins. Then click **Import**.

If an API with the same name already exists in your org, the import fails with
*API with name '<name>' already exists*. Type another name in the form's
**Display name** field, which overrides the name in the spec, and import again.

> **A spec can carry the plugins too.** Add an `x-helix-gateway` block that
> lists them. At the top level of the file it covers every route; under one
> path and method it covers that route only:
>
> ```yaml
> paths:
>   /catalog/orders:
>     post:
>       x-helix-gateway:
>         plugins:
>           xml-to-json:
>             transform_request: true
>             transform_response: true
>           proxy-rewrite:
>             uri: /post
> ```
>
> [`example/api-spec.yaml`](example/api-spec.yaml) is this API with all its
> plugins already in place. Import that instead and you can skip step 2.

Either way, the API is not live yet: it has no upstream and isn't deployed.
That comes in step 3.

**2. Add the plugins**

Two plugins on each route do the work: one converts between XML and JSON, the
other sends the call to the right backend path. Add them **before** you deploy:
a live revision can't be changed.

Both routes get their own settings, so each plugin goes on one route, not on
the whole API.

On the API's page, open **Configuration → Plugins** and click **Configure
plugin**. A short wizard opens:

1. **Plugin** — pick the plugin from the catalog.
2. **Scope** — choose **Specific endpoint** and pick the route. (**Entire
   Revision** would apply it to every route.)
3. **Configure** — the JSON editor and the Properties list sit side by side.
   Paste the JSON below, or fill in the fields. Then **Next**. The tables show
   the simple fields; lists and nested settings are easiest to paste as JSON.
4. **Review** — shows the configuration before and after. Click **Apply**.

Run the wizard once for each plugin on each route: four times in all.

On the `GET /catalog/items` route (Scope: **Specific endpoint**, that route):

1. **`xml-to-json` — turns the backend's XML reply into JSON.** It only does so
   when the caller sends `Accept: application/json`, and only for the reply
   types listed in `content_types`.

   | Field | Value |
   |---|---|
   | **transform_response** | `true` |

   ```json
   {"transform_response":true,"content_types":["application/xml","text/xml"]}
   ```

2. **`proxy-rewrite` — sends the call to the backend's path.** Here, `/xml` on
   the test backend.

   | Field | Value |
   |---|---|
   | **uri** | `/xml` |

   ```json
   {"uri":"/xml"}
   ```

On the `POST /catalog/orders` route (Scope: **Specific endpoint**, that route):

1. **`xml-to-json` — converts in both directions.** The caller's JSON body is
   turned into XML (wrapped in an `<order>` element with the namespace your
   backend expects) before the backend sees it. An XML reply would be turned
   back into JSON too, but the test backend replies to `POST /post` in JSON,
   which passes through unchanged; only `GET /catalog/items` shows the reply
   being converted. **`transform_request` must be `true`**: it defaults to
   `false`, and then the backend receives the JSON unchanged. Leave `pretty`
   unset: on this build it makes the route fail with HTTP 503 (service
   unavailable).

   | Field | Value |
   |---|---|
   | **transform_request** | `true` |
   | **transform_response** | `true` |
   | **request_root_name** | `order` |
   | **array_item_name** | `item` |
   | **max_body_size** | `1048576` |

   ```json
   {"transform_request":true,"transform_response":true,"request_content_types":["application/json"],"content_types":["application/xml","text/xml"],"request_root_name":"order","array_item_name":"item","root_attributes":{"xmlns":"urn:example:catalog"},"max_body_size":1048576}
   ```

2. **`proxy-rewrite` — sends the call to the backend's path.** Here, `/post`,
   which echoes back what it received so you can see the generated XML. Set the
   path only: a `Content-Type` set here would stop the request conversion from
   recognising the body.

   | Field | Value |
   |---|---|
   | **uri** | `/post` |

   ```json
   {"uri":"/post"}
   ```

Repeat for each plugin and route.

Then, on the **Entire Revision**:

1. **`request-id` — a tracking id on every call (recommended).** It adds an
   `X-Request-Id` header to each response. Conversion problems show up as errors
   from your backend, not the gateway, and this id is how you find the call they
   came from. Without it, responses carry no `X-Request-Id`.

   ```json
   {"algorithm":"uuid","header_name":"X-Request-Id"}
   ```

What every field means, and the optional `cors` the full spec also adds:
[Configuration reference](#configuration-reference).

**Using your own backend?** In this step, set each `proxy-rewrite` `uri` to your
backend's path instead of `/xml` and `/post`, and make `content_types` match the
`Content-Type` your backend actually sends.

**3. Give it an upstream, then deploy it**
1. Go to **API Gateway → Upstreams → Add Upstream**. Name it, pick environment
   `test`, and add a node at `httpbin.org`, port `443`, scheme HTTPS (or your
   own XML backend). If you switch the scheme to HTTP, the port stays at `443`:
   change it to `80` by hand.
2. **Pass Host** is set to **Rewrite**, which makes **Upstream Host** required.
   It fills in from the node's host; check it reads `httpbin.org`.
3. Click **Next** through the remaining tabs, then **Add Upstream**.
4. Back on the API's page, click **Deploy** on the revision. The dialog asks you
   to map an upstream for `test`. Pick the one you just created, then click
   **Map & Deploy**. (The button reads **Map & Deploy** while no upstream is
   mapped yet, and **Deploy** once one is.)

**Changing it later.** A change to the upstream's host or port applies to the
live API straight away, with no new deploy. A change to its scheme does not:
undeploy the revision and deploy it again. A change to routes or plugins does
need one, because a live revision can't be edited: use **Clone Revision**, make
your change on the copy, then **Force Deploy** it. Rolling back needs no copy:
click **Deploy**, pick the older revision (for example `r1`), and click **Force
Deploy**.

No products, developers or apps are needed: the package ships unauthenticated.

## Install it directly

To script it, call the control plane instead. `BASE` is the API address the
portal calls (it usually starts with `api-`), not the portal page and not the
gateway's address:

```bash
export ORG=<ORG_ID>
export TOKEN=<control-plane bearer token>      # short-lived
export BASE=https://<YOUR_CONTROL_PLANE_API>/api
H=(-H "authorization: Bearer $TOKEN" -H 'content-type: application/json')

# 1. Import the spec. Nothing in it needs filling in. Keep both ids it returns.
#    For your own backend, first adjust the proxy-rewrite paths and content_types
#    (check what it sends — text/html and application/soap+xml don't match the
#    defaults).
curl -s -H "authorization: Bearer $TOKEN" \
  -F "file=@example/api-spec.yaml" "$BASE/orgs/$ORG/apis/from-spec"
# → {"api":{"id":"<API_ID>", ...}, "revision":{"id":"<REVISION_ID>", ...}}

# 2. Import does NOT make the routes live. Create an upstream, bind it
#    to the revision, then deploy the revision.
# pass_host + upstream_host: without them the backend gets the gateway's host
# and every call returns 502.
curl -s "${H[@]}" -X POST "$BASE/orgs/$ORG/envs/<TEST_ENV_ID>/upstreams" \
  -d '{"name":"httpbin","specification":{"scheme":"https","pass_host":"rewrite","upstream_host":"httpbin.org","nodes":[{"host":"httpbin.org","port":443,"weight":1}]}}'
# → {"id":"<UPSTREAM_ID>", ...}

curl -s "${H[@]}" -X PATCH "$BASE/orgs/$ORG/apis/<API_ID>/revisions/<REVISION_ID>/upstream-bindings/add" \
  -d '{"environmentUpstreams":[{"environmentId":"<TEST_ENV_ID>","upstreamId":"<UPSTREAM_ID>"}]}'
curl -s "${H[@]}" -X POST "$BASE/orgs/$ORG/apis/<API_ID>/revisions/<REVISION_ID>/deploy" \
  -d '{"environmentId":"<TEST_ENV_ID>","force":false}'
```

> Revisions must be **INACTIVE** to accept a spec change. If it's live, undeploy
> first, or clone the revision so you keep a rollback target.

The same calls without narration: [API reference](api-reference.md).

## See it work

Ask for JSON, then for XML, on the same route:

```bash
curl -s "https://<YOUR_GATEWAY_HOST>/catalog/items" -H "Accept: application/json"
# JSON — the backend's XML document, converted

curl -s "https://<YOUR_GATEWAY_HOST>/catalog/items" -H "Accept: application/xml"
# the backend's XML, untouched
```

Send a JSON order. The test backend echoes what it received, so you can see the
XML the gateway generated:

```bash
curl -s -X POST "https://<YOUR_GATEWAY_HOST>/catalog/orders" \
  -H "content-type: application/json" -H "Accept: application/json" \
  -d '{"orderId":"SO-88120","lines":[{"sku":"BRK-2100","qty":4},{"sku":"FLT-0090","qty":1}]}'
# the echo's "data" field shows <order xmlns="urn:example:catalog">…</order>,
# with the array as two sibling <lines> elements, and Content-Type application/xml
```

To run all five checks as a script:

```bash
GATEWAY=https://<YOUR_GATEWAY_HOST> ./example/verify.sh
# Against your own backend, which probably doesn't echo requests:
GATEWAY=https://<YOUR_GATEWAY_HOST> ECHOES_REQUEST=0 ./example/verify.sh
```

`READ_PATH`, `WRITE_PATH`, `ROOT_ELEMENT` and `NAMESPACE` override the defaults
if your routes or root element differ. Exit code 0 means both directions work and
both silent passthroughs behave as documented. What each check proves, plus the
manual tests: [Tests](tests.md).

## Variations

Follow-ups you can paste to the agent in the same chat, once the build is
standing. Say what you want to be true.

**My backend sends a different Content-Type**
```text
My backend replies with {{backend_content_type}}, not application/xml. Make the
conversion recognise it on both routes, and tell me what else assumes the default.
```

**I need a stable JSON contract, not a mirror of the XML**
```text
This JSON mirrors the backend's element names, and I need a contract that survives
a backend refactor. Show me a template-based transform for the GET route instead,
and be explicit about what I take on by maintaining the template.
```

**My backend validates a strict xs:sequence**
```text
My backend's schema is an xs:sequence, so element order matters. Tell me plainly
whether the request conversion can guarantee order, and if not, show me a
template-based alternative for the POST route only.
```

**Put identity in front of it** — that's [solution 08](../08-api-key/).
```text
Require an app's API key in the X-Api-Key header on both routes, and keep the
conversion exactly as it is. Then create a developer, a product and an app, and
give me the key.
```

## Configuration reference

Source of truth: [`example/api-spec.yaml`](example/api-spec.yaml).
[`example/api-spec-basic.yaml`](example/api-spec-basic.yaml) is the same routes
with no plugins, for adding them yourself.

The read route — response direction only, the minimum useful block:

```yaml
xml-to-json:
  transform_response: true
  content_types: [application/xml, text/xml]
proxy-rewrite:
  uri: /xml
```

The write route — both directions:

```yaml
xml-to-json:
  transform_request: true
  transform_response: true
  request_content_types: [application/json]
  content_types: [application/xml, text/xml]
  request_root_name: order
  array_item_name: item
  root_attributes:
    xmlns: "urn:example:catalog"
  max_body_size: 1048576
proxy-rewrite:
  uri: /post
```

| Plugin | Field | Value here | What it means |
|---|---|---|---|
| `xml-to-json` | `transform_response` | `true` | Convert the backend's XML to JSON — only when the client sends `Accept: application/json`. |
| `xml-to-json` | `content_types` | `application/xml`, `text/xml` | The backend `Content-Type` values that get converted. Anything else passes through. |
| `xml-to-json` | `transform_request` | `true` (POST route only) | Convert JSON request bodies to XML. **Defaults to `false`.** |
| `xml-to-json` | `request_content_types` | `application/json` | Request bodies with any other type are forwarded unchanged, with no error. |
| `xml-to-json` | `request_root_name` | `order` | The root element of the XML you generate. Your backend's parser almost certainly cares. |
| `xml-to-json` | `array_item_name` | `item` | The element name for children of a top-level JSON array. A nested array becomes repeated siblings named after its key. |
| `xml-to-json` | `root_attributes.xmlns` | `urn:example:catalog` | The namespace on the generated root. Without it, a namespace-aware backend rejects an otherwise-correct document, usually with a message that doesn't mention namespaces. |
| `xml-to-json` | `max_body_size` | `1048576` | Bodies larger than this are forwarded **unchanged**, not rejected. |
| `proxy-rewrite` | `uri` | `/xml`, `/post` | Path only. Your test backend accepts what `xml-to-json` sends, so nothing else is needed. If your own backend wants a different `Content-Type` (for example `text/xml`), set it here with `"_meta":{"priority":900}`, so this plugin runs after the conversion. At its usual priority it runs first and the request is never converted. [Solution 03](../03-soap-to-rest/guides.md#configuration-reference) does exactly this. |
| `request-id` | `algorithm` / `header_name` | `uuid` / `X-Request-Id` | API-wide. Conversion failures are reported by the backend, so this id is what ties its complaint to a request. |
| `cors` | `allow_origins` / `allow_methods` / `allow_headers` | `*` / `GET,POST,OPTIONS` / `accept,content-type` | API-wide, with `allow_credential: false`. `accept` must be allowed or a browser can't ask for JSON. Tighten `allow_origins` before using your own backend. |

Fields this package leaves at their defaults: `root_name` (the root element's
name), `enable_decl` (adds an `<?xml ...?>` line), and `ctx_namespace` (where the
plugin shares values with other plugins on the route). Confirm them with
`get_plugin_config` in your own org.

Two formatting options worth knowing:

- **Don't set `pretty: true`.** On this build a route with it returns **503** and
  the connection is closed before headers. `root_name` and `property_naming` are
  fine.
- **`property_naming: camelCase` is left off.** It would lower-case the first
  letter of every key — a change to your published contract — so it isn't applied
  by reflex. Keys come out exactly as the XML names them, with hyphens turned into
  underscores.

Placeholders in this package: `<ORG_ID>`, `<API_ID>`, `<REVISION_ID>`,
`<UPSTREAM_ID>`, `<TEST_ENV_ID>`, `<YOUR_GATEWAY_HOST>`. Replace all of them
before you deploy.

Every field of every plugin, and the wider product docs:
[docs.digitalapi.ai/api-gateway](https://docs.digitalapi.ai/api-gateway).

## Troubleshooting

- **No `Accept: application/json`, no conversion.** The first thing to check.
- **`transform_request` defaults to `false`.** An empty block converts responses
  only.
- **A content type outside `request_content_types` passes through silently.** So
  does a body over `max_body_size`. Neither produces an error.
- **`pretty: true` returns 503 on this build.** Leave it off.
- **Setting `Content-Type` in `proxy-rewrite` breaks the conversion, unless it
  runs second.** At its usual priority `proxy-rewrite` runs before `xml-to-json`,
  so the body is relabelled and never converted. Give it `"_meta":{"priority":900}`
  and it runs after: see [solution 03](../03-soap-to-rest/guides.md#configuration-reference).
- **Check what your backend actually sends.** `content_types` defaults to
  `application/xml` and `text/xml`. A backend replying `text/html` or
  `application/soap+xml` matches neither.
- **A single occurrence of a repeatable element is an object, not an array.**
  Write clients that accept both, or normalise in your own layer. The plugin has
  no "always array" option.
- **Fields go to the backend in alphabetical order.** When a JSON object with
  several fields becomes XML, its fields are sorted A–Z. A problem for a backend
  with a strict `xs:sequence` schema, invisible otherwise.
- **Don't rely on field order in the JSON response.** It can change from one call
  to the next.
- **Prefixes and namespace declarations come through.** Prefixed elements keep
  their prefix in the JSON key, and `xmlns:*` attributes appear as fields. They
  become part of what partners see.
- **An empty collection converts to `null`, not `{}`.**
- **The `Accept` check is a simple match.** It ignores preference weights, so
  `application/xml;q=0.9, application/json;q=0.1` still gets JSON.
- **Conversion failures are reported by the *backend*, not the gateway.** That is
  why the full spec puts `request-id` on every route. If you built it in the UI
  and responses have no `X-Request-Id`, add it on the **Entire Revision** (end of step 2).
- **Your backend receives the caller's other headers too**, including a
  browser's cookies. That's normal for a proxy, but check what your own backend
  logs.
- **Attributes on child elements are dropped.** `<slide type="all">` comes back
  without `type`. Attributes on the root element are kept as ordinary fields.
- **Mixed text loses its word order.** `Why <em>WonderWidgets</em> are great`
  becomes `{"em":"WonderWidgets","text":"Why are great"}`, and the sentence can't
  be rebuilt.
- **`transform_request` also changes the outgoing headers.** The backend receives
  `Content-Type` and `Accept` both set to `application/xml`, not the client's.
- **Confirm `xml-to-json` exists in your org** before you design around it.
- **Everything returns 200 and the backend still complains.** Both conversion
  switches fail open, so a 200 from the gateway doesn't prove the conversion
  happened. Read the backend's own log.
- **Built with the agent: the routes exist but have no plugins.** The agent nested
  them under `x-helix-gateway`, which a live route silently ignores. Read the
  revision back, and ask for them again if they're missing.
- **Built with the agent: the dry-run fails while it adds a browser preflight
  route.** A separate catch-all `OPTIONS` route may be refused. The `cors` plugin on
  the API is enough on its own; read the revision back once the dry-run passes.
- **Built with the agent: the dry-run fails on `proxy-rewrite`.** The agent added
  empty optional fields (`headers: {}`, a `regex_uri` of nulls). Ask it to set only
  `uri`.
- **Deploy fails with `Only INACTIVE revisions can be updated`.** Clone the
  revision or undeploy it, then apply the change.
- **Use the trace inspector to see each step.** On the API's page, open the
  **Observability** tab and click **Start trace session**. It shows the headers
  each plugin changes and the request body at every stage, which is the fastest
  way to see what each plugin did to a call. A session stops after 10 requests,
  so use **Advanced: filter which requests to capture** to record only the ones
  you care about (skipped requests don't count). The list doesn't refresh by
  itself: click **Refresh**. The **Inspector** shows API keys and cookies in
  plain text, so don't share your screen or paste a trace into a ticket without
  removing them. A compressed response, which browsers always ask for, is
  unreadable in the **Response** tab, so call the API with curl to read it. The
  **Upstream** tab's **Total** adds connect time to response time, so it can be
  larger than the request's own total.
- **See what changed, and when, in Audit Logs.** **Observability → Audit Logs**
  lists every clone, plugin change and deploy. Its times are in your local time,
  while analytics uses UTC. Anything done with your token, including scripts and
  the Helix Agent, appears under your name.
