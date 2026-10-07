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

Works on a **fresh, empty org**. [`helix-agent-prompt.md`](helix-agent-prompt.md)
has two steps: step 1 creates the API and configures both directions, step 2 asks
for the commands that prove it. Paste step 1, check the revision, then paste
step 2 in the same session.

**If your backend is SOAP, this is the wrong prompt.** Use
[solution 03](../03-soap-to-rest/) — the two produce incompatible documents.

**Why the prompt is shaped the way it is:**

- **`transform_request: true`, stated as a change from the default.** The most
  likely wrong turn. An agent writes `xml-to-json: {}`, the response direction
  works, and the request direction quietly never happens.
- **No `Content-Type` in `proxy-rewrite`.** It runs at 1008 and `xml-to-json` at
  997, so a change there alters the header the conversion matches on. A recorded
  defect from [solution 03](../03-soap-to-rest/), and exactly the tidy-up an agent
  offers.
- **No `pretty`.** On this build `pretty: true` returns a 503 with the connection
  dropped before any headers. An agent asked for "readable JSON" reaches for it.
- **Root name, array item name, namespace.** The root element and namespace are
  what a real backend's parser checks first. Left to defaults, the backend rejects
  a document that otherwise looks right.
- **`cors` must allow `accept`.** The conversion depends on the `Accept` header,
  so a browser client that can't send it can't ask for JSON at all.
- **"Only the fields you need."** The agent offered `regex_uri: [null, null]` and
  `headers: {}`, and the dry-run rejected both in turn. That line saves two round
  trips.
- **Step 2's `text/plain` case.** It makes the agent show the silent passthrough
  rather than describe it — the behaviour most likely to reach production
  unnoticed.

**If the agent run goes wrong:**

| Symptom | Cause |
|---|---|
| The response is still XML | The client didn't send `Accept: application/json`, or the backend's `Content-Type` isn't in `content_types`. |
| The backend rejects the request body | `transform_request` is false, or the client's content type isn't in `request_content_types`. |
| Everything returns 200 and the backend still complains | Both passthroughs fail **open**. The gateway's status code is not evidence the conversion happened. |
| 503 with the connection dropped | `pretty: true` is set. Remove it. |
| The request direction stops working after an edit | Something added a `Content-Type` to `proxy-rewrite`. |
| The dry-run fails twice on `proxy-rewrite` | The agent added empty optional fields. Set only `uri`. |
| `create_api` fails saying the API exists | A previous run left one behind. Use a free name. |
| Deploy fails: `Only INACTIVE revisions can be updated` | Clone the revision or undeploy, then apply. |
| Success reported, but the routes have no plugins | The plugins were nested under `x-helix-gateway`, which a live route silently discards. Read the revision back. |

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

**1. Import the API**
1. Go to **API Gateway → APIs**, click **Add API** (or **Create your first API**).
2. Set **Method** to **Import an OpenAPI spec**.
3. Drag in [`example/api-spec.yaml`](example/api-spec.yaml), or paste its
   contents, then click **Import**. Nothing in it needs filling in.

This creates the API and its first revision. The imported spec already carries
`xml-to-json` (both directions on the POST route), `proxy-rewrite`, `request-id`
and `cors`, with the settings in the
[Configuration reference](#configuration-reference). There is no separate screen
to set them up in this walkthrough.

**2. Give it an upstream, then deploy it**
1. Go to **API Gateway → Upstreams → Add Upstream**. Name it, pick environment
   `test`, point it at `httpbin.org` (or your own XML backend), then
   **Create Upstream**.
2. Back on the API's page, click **Deploy** on the revision. The dialog asks you
   to map an upstream for `test`. Pick the one you just created, then **Deploy**.

No products, developers or apps are needed: the package ships unauthenticated.

**Using your own backend?** Before importing, change the `proxy-rewrite` paths in
the spec (`/xml`, `/post`) to your backend's, and make `content_types` match the
`Content-Type` your backend actually sends.

## Install it directly

If you'd rather script it against the control plane:

```bash
export ORG=<ORG_ID>
export TOKEN=<control-plane bearer token>      # short-lived
export BASE=https://<YOUR_GATEWAY_HOST>/api
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
curl -s "${H[@]}" -X POST "$BASE/orgs/$ORG/envs/<TEST_ENV_ID>/upstreams" \
  -d '{"name":"httpbin","specification":{"scheme":"https","nodes":[{"host":"httpbin.org","port":443,"weight":1}]}}'
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

Each of these is a follow-up you can paste to the agent after step 2.

**My backend sends a different Content-Type**
```text
My backend replies with {{backend_content_type}}, not application/xml. Add it to
content_types on both routes and tell me what else in the config assumes the
default.
```

**I need a stable JSON contract, not a mirror of the XML**
```text
This JSON mirrors the backend's element names, and I need a contract that survives
a backend refactor. Show me what body-transformer would look like for the GET
route instead, and be explicit about what I'm taking on by maintaining a template.
```

**My backend validates a strict xs:sequence**
```text
My backend's schema is an xs:sequence, so element order matters. Tell me plainly
whether the request direction of xml-to-json can guarantee order, and if not, show
me the body-transformer alternative for the POST route only — keep the response
direction as it is.
```

**Put authentication in front of it** — that's [solution 08](../08-api-key/).
```text
Add API-key authentication to both routes using helix-auth validate with
validate_auth_type key-auth, reading the key from the X-Api-Key header. Keep the
conversion exactly as it is.
```

## Configuration reference

Source of truth: [`example/api-spec.yaml`](example/api-spec.yaml).

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
| `proxy-rewrite` | `uri` | `/xml`, `/post` | Path only. **Never set `Content-Type` here** on a route that converts requests. |
| `request-id` | `algorithm` / `header_name` | `uuid` / `X-Request-Id` | API-wide. Conversion failures are reported by the backend, so this id is what ties its complaint to a request. |
| `cors` | `allow_origins` / `allow_methods` / `allow_headers` | `*` / `GET,POST,OPTIONS` / `accept,content-type` | API-wide, with `allow_credential: false`. `accept` must be allowed or a browser can't ask for JSON. Tighten `allow_origins` before using your own backend. |

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
- **Never set `Content-Type` in `proxy-rewrite` on a route that converts
  requests.** It runs first and breaks the match.
- **Check what your backend actually sends.** `content_types` defaults to
  `application/xml` and `text/xml`. A backend replying `text/html` or
  `application/soap+xml` matches neither.
- **A single occurrence of a repeatable element is an object, not an array.**
  Write clients that accept both, or normalise in your own layer. The plugin has
  no "always array" option.
- **JSON key order isn't kept on the way to XML.** A problem with a strict
  `xs:sequence` schema, invisible otherwise.
- **Conversion failures are reported by the *backend*, not the gateway.** That is
  why `request-id` is on every route.
- **`transform_request` also changes the outgoing `Content-Type`.** The backend
  receives `application/xml`, not the client's type.
- **Confirm `xml-to-json` exists in your org** before you design around it.
