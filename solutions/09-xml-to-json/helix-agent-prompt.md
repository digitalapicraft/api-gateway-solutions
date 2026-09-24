# Agent-mode prompt — a JSON front door on an XML backend

Paste this into **Helix Agent Mode**. It works from a **fresh, empty org**: the
agent *creates* the API, binds a public upstream that both serves XML and echoes
requests, configures both conversion directions, dry-runs, and stops.

Replace the `<<...>>` values. Everything else is deliberate — the table below
says why each block earns its place. Read [AGENT-GUIDE.md](../../AGENT-GUIDE.md)
first if you haven't.

> **If your backend is SOAP, this is the wrong prompt.** Use
> [solution 03](../03-soap-to-rest/helix-agent-prompt.md). The two produce
> incompatible documents.

---

## The prompt

> **Run it in steps, not as one mega-prompt.** These are the exact prompts
> verified on the **default agent model**. Paste **Step 1**, let the agent build
> and stop at the dry-run; confirm; then paste **Step 2**.

**Step 1 — create the API and configure both directions**

```text
Create a new REST API called "<<Catalog API>>" that puts a JSON front door on a
backend that speaks XML. This is a fresh org — I have no existing API.

Upstream: https://httpbin.org (public; its /xml returns an XML document and its
/post echoes whatever it received, so I can see both directions work). Deploy to
the "test" environment.

Routes: GET /catalog/items and POST /catalog/orders. Add proxy-rewrite on each:
/catalog/items -> /xml and /catalog/orders -> /post. Do NOT set a Content-Type in
proxy-rewrite — it runs before xml-to-json and would break the request transform.

Use the xml-to-json plugin. On the GET route, response conversion only. On the
POST route, set transform_request true as well — it defaults to false, so an empty
block converts responses only. Set request_content_types to application/json,
content_types to application/xml and text/xml, request_root_name "order",
array_item_name "item", and root_attributes xmlns "urn:example:catalog".

Do not set pretty — on this build it makes the route return 503.

Put request-id and cors in the SERVICE spec so they apply API-wide; cors must
allow the accept header, because the response conversion is content-negotiated.

Check get_plugin_config for xml-to-json before writing config. We are editing a LIVE route object, not authoring an OpenAPI document — so do not
follow the spec-generator examples for plugin placement. Each route object in
routeSpec takes "plugins" as a TOP-LEVEL key, and inside it each plugin is
keyed by its own NAME:
  { "name": ..., "uri": ..., "methods": [...], "service_id": ...,
    "plugins": { "<plugin-name>": { <that plugin's own fields> } } }
Do not promote a plugin's fields into the plugins map: "plugins":
{"response_status": 202, "content_type": ...} is four broken plugins, not one
working one — the plugin name level is mandatory.
There must be no "x-helix-gateway" key anywhere in a route object: a live route
silently discards that wrapper, the write still reports success, and the route
deploys with no plugins at all. Set only the plugin fields you actually need — an empty
headers {} or a regex_uri of nulls is rejected at dry-run. Skip validate_route —
use dry_run_deploy for validation. Show me the spec, run dry_run_deploy, then call
get_revision and show me the stored routeSpec so I can see the plugins landed.
Wait before deploying.
```

**Step 2 — prove both directions** (same session, after Step 1 deploys)

```text
Now give me curl commands that show, in order: GET /catalog/items with
Accept: application/json returning JSON; the same call with
Accept: application/xml returning the backend's XML untouched; a JSON POST to
/catalog/orders whose echo shows the XML the backend received; and the same POST
sent as text/plain, which passes through unconverted with no error.
```

---

## Why the prompt is shaped this way

| Block | Why it's there |
|---|---|
| **"This is a fresh org — create one"** | On a new free-trial org there is no API to "find". The agent must create it, or it stalls looking for something that isn't there. |
| **"Upstream: httpbin … /xml … /post echoes"** | One upstream demonstrates both directions on a fresh org: a real XML document to convert, and an echo that shows the XML your backend would have received. |
| **"Do NOT set a Content-Type in proxy-rewrite"** | `proxy-rewrite` (1008) runs before `xml-to-json` (997). An override there changes the header the transform matches on, and the request direction silently stops converting. This is a recorded defect from solution 03, and it is exactly the tidy-up an agent volunteers. |
| **"transform_request true — it defaults to false"** | The single most likely wrong turn. An agent writes `xml-to-json: {}`, the response direction works, and the request direction silently never happens. |
| **"request_root_name / array_item_name / root_attributes"** | The generated document's root name and namespace are what a real backend's parser checks first. Left to the agent they get defaults, and the backend rejects a document that otherwise looks right. |
| **"Do not set pretty"** | Verified on this build: `pretty: true` makes the route return 503 with the connection terminated before headers. An agent asked for "readable JSON" will reach for it. |
| **"cors must allow the accept header"** | The conversion is content-negotiated, so a browser client that cannot send `Accept` cannot ask for JSON at all. |
| **"in the SERVICE spec"** | API-wide plugins live on the service spec. Without this the agent copies them onto every route — it works, and it drifts. |
| **"a FLAT plugins map"** | The agent's spec-generator references teach `x-helix-gateway.plugins`, which is right for an OpenAPI *document* and wrong for a live route or service object. |
| **"Set only the plugin fields you actually need"** | Verified: the agent volunteered `regex_uri: [null, null]` and `headers: {}` inside `proxy-rewrite`, and the dry-run rejected both in turn. It recovered on the third attempt, but the line saves two round trips and, on a worse day, the run. |
| **"Skip validate_route — use dry_run_deploy"** | Verified: `validate_route` fails on this build whatever you put in it — the tool posts `{"route": …}` and the control plane requires `{"routeSpec": [ … ]}`. Asked for it, the agent retries and the run dies. |
| **Step 2's "sent as text/plain … with no error"** | Makes the agent demonstrate the silent passthrough rather than describe it. It is the behaviour most likely to reach production unnoticed. |

## Tweak knobs

**My backend sends a different Content-Type**
```text
My backend replies with <<application/soap+xml>>, not application/xml. Add it to
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

**Put auth in front of it**
```text
Add API-key authentication to both routes using helix-auth validate with
validate_auth_type key-auth, reading the key from the X-Api-Key header. Keep the
conversion exactly as it is.
```
(That's [solution 08](../08-api-key/).)

## Known failure modes when running this prompt

- **The response is still XML.** The client did not send
  `Accept: application/json`, or the upstream's `Content-Type` is not in
  `content_types`.
- **The backend rejects the request body.** `transform_request` is false, or the
  client's content type is not in `request_content_types`. Reply: `set
  transform_request true on the POST route — it defaults to false.`
- **Everything returns 200 and the backend still complains.** Both passthroughs
  fail open. The gateway's status code is not evidence the conversion happened.
- **The route returns 503 with the connection dropped.** `pretty: true` is set.
  Remove it.
- **The request direction stops working after an edit.** Something added a
  `Content-Type` to `proxy-rewrite`.
- **`validate_route` errors and the agent stalls.** Not your config — the tool is
  broken against this control plane. Reply: `skip validate_route, run
  dry_run_deploy instead.`
- **The dry-run fails twice on `proxy-rewrite`.** The agent added empty optional
  fields — `regex_uri: [null, null]`, `headers: {}`. Reply: `drop the empty
  optional fields from proxy-rewrite; set only uri.`
- **`create_api` fails saying the API exists.** A previous run left one behind.
  Give it a free name.
- **Deploy fails with `Only INACTIVE revisions can be updated`.** Clone the
  revision or undeploy, then apply.

## Related

- **[Solution 03 — SOAP to REST](../03-soap-to-rest/helix-agent-prompt.md)** — the
  envelope case. Choose between them before you start.
- **[Solution 08 — API keys](../08-api-key/helix-agent-prompt.md)** — this package
  ships open; put identity in front of it.
- **[Solution 10 — Data masking](../10-data-mask/helix-agent-prompt.md)** — when
  the converted response says more than the client should see.
