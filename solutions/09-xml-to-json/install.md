# Install — Solution 09 — JSON in, JSON out, in front of a backend that only speaks XML

[Overview](readme.md) · [Business need](business-need.md) · [How it works](how-it-works.md) · **Install** · [Configuration](configuration.md) · [Test & verify](testing.md) · [Changelog](changelog.md)

---

## Build it with the Helix Agent

Two steps; confirm between them. Full prompt with the reasoning, tweak knobs and
failure modes: [`helix-agent-prompt.md`](helix-agent-prompt.md).

```text
Create a REST API "<<Catalog API>>" putting a JSON front door on an XML backend.
Upstream https://httpbin.org — its /xml returns an XML document and its /post
echoes what it received, so both directions are visible. Environment test. Fresh
org — nothing exists yet.

Routes GET /catalog/items and POST /catalog/orders, with proxy-rewrite
/catalog/items -> /xml and /catalog/orders -> /post. Do NOT set a Content-Type in
proxy-rewrite — it runs first and would break the request transform. Set only the
plugin fields you need: an empty headers {} or a regex_uri of nulls is rejected at
dry-run.

Use xml-to-json. On the GET route, response conversion only. On the POST route set
transform_request true as well — it defaults to false, so an empty block converts
responses only. Set request_content_types to application/json, content_types to
application/xml and text/xml, request_root_name "order", array_item_name "item",
and root_attributes xmlns "urn:example:catalog".

Don't set pretty — on this build it makes the route return 503.

Put request-id and cors in the SERVICE spec so they apply API-wide; cors must
allow the accept header, because the response conversion is content-negotiated.

Plugins go in a top-level "plugins" map on the route object, each under its own
plugin name. No "x-helix-gateway" wrapper — a live route discards it silently and
still reports success.

Show me the spec, run dry_run_deploy, then read the revision back so I can see
which plugins actually landed. Wait before deploying.
```

Then, in the same session:

```text
Now curl commands showing, in order: GET /catalog/items with
Accept: application/json returning JSON; the same call with Accept:
application/xml returning the backend's XML untouched; a JSON POST to
/catalog/orders whose echo shows the XML the backend received; and the same POST
sent as text/plain, which passes through unconverted with no error.
```

## Install it directly

```bash
export ORG=<ORG_ID>
export TOKEN=<control-plane bearer token>      # short-lived
export BASE=https://<YOUR_GATEWAY_HOST>/api

# 1. Import gateway/api-spec.yaml. Nothing in it needs filling in.
# 2. Bind your XML backend as the upstream and deploy the revision to "test".
# 3. Adjust the proxy-rewrite paths to your backend's, and content_types to the
#    Content-Type your backend actually sends (check it — text/html and
#    application/soap+xml do not match the defaults).
# 4. Prove it
GATEWAY=https://<YOUR_GATEWAY_HOST> ./gateway/verify.sh
#    Against your own backend (which probably does not echo requests):
GATEWAY=https://<YOUR_GATEWAY_HOST> ECHOES_REQUEST=0 ./gateway/verify.sh
```

## Step 1 — create the API and configure both directions

```text
Create a REST API "<<Catalog API>>" putting a JSON front door on an XML backend.
Upstream https://httpbin.org — its /xml returns an XML document and its /post
echoes what it received, so both directions are visible. Environment test. Fresh
org — nothing exists yet.

Routes GET /catalog/items and POST /catalog/orders, with proxy-rewrite
/catalog/items -> /xml and /catalog/orders -> /post. Do NOT set a Content-Type in
proxy-rewrite — it runs first and would break the request transform. Set only the
plugin fields you need: an empty headers {} or a regex_uri of nulls is rejected at
dry-run.

Use xml-to-json. On the GET route, response conversion only. On the POST route set
transform_request true as well — it defaults to false, so an empty block converts
responses only. Set request_content_types to application/json, content_types to
application/xml and text/xml, request_root_name "order", array_item_name "item",
and root_attributes xmlns "urn:example:catalog".

Don't set pretty — on this build it makes the route return 503.

Put request-id and cors in the SERVICE spec so they apply API-wide; cors must
allow the accept header, because the response conversion is content-negotiated.

Plugins go in a top-level "plugins" map on the route object, each under its own
plugin name. No "x-helix-gateway" wrapper — a live route discards it silently and
still reports success.

Show me the spec, run dry_run_deploy, then read the revision back so I can see
which plugins actually landed. Wait before deploying.
```

## Step 2 — prove both directions

```text
Now curl commands showing, in order: GET /catalog/items with
Accept: application/json returning JSON; the same call with Accept:
application/xml returning the backend's XML untouched; a JSON POST to
/catalog/orders whose echo shows the XML the backend received; and the same POST
sent as text/plain, which passes through unconverted with no error.
```

---

## Why it's shaped this way

- **`transform_request: true`, stated as a default override.** The single most
  likely wrong turn. An agent writes `xml-to-json: {}`, the response direction
  works, and the request direction silently never happens.
- **No `Content-Type` in `proxy-rewrite`.** It runs at 1008, `xml-to-json` at 997.
  An override there changes the header the transform matches on. A recorded defect
  from [solution 03](../03-soap-to-rest/), and exactly the tidy-up an agent
  volunteers.
- **No `pretty`.** Verified on this build: `pretty: true` returns 503 with the
  connection dropped before headers. An agent asked for "readable JSON" reaches for
  it.
- **Root name, array item name, namespace.** The generated document's root and
  namespace are what a real backend's parser checks first. Left to defaults, the
  backend rejects a document that otherwise looks right.
- **`cors` must allow `accept`.** The conversion is content-negotiated, so a
  browser client that can't send `Accept` can't ask for JSON at all.
- **"Only the fields you need".** Verified: the agent volunteered
  `regex_uri: [null, null]` and `headers: {}`, and the dry-run rejected both in
  turn. The line saves two round trips.
- **Step 2's `text/plain` case.** Makes the agent demonstrate the silent
  passthrough rather than describe it — it's the behaviour most likely to reach
  production unnoticed.

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

## When it goes wrong

| Symptom | Cause |
|---|---|
| The response is still XML | The client didn't send `Accept: application/json`, or the upstream's `Content-Type` isn't in `content_types`. |
| The backend rejects the request body | `transform_request` is false, or the client's content type isn't in `request_content_types`. |
| Everything returns 200 and the backend still complains | Both passthroughs fail **open**. The gateway's status code is not evidence the conversion happened. |
| 503 with the connection dropped | `pretty: true` is set. Remove it. |
| The request direction stops working after an edit | Something added a `Content-Type` to `proxy-rewrite`. |
| The dry-run fails twice on `proxy-rewrite` | The agent added empty optional fields. Set only `uri`. |
| `create_api` fails saying the API exists | A previous run left one behind. Use a free name. |
| Deploy fails: `Only INACTIVE revisions can be updated` | Clone the revision or undeploy, then apply. |

## Related

- **[Solution 03 — SOAP to REST](../03-soap-to-rest/helix-agent-prompt.md)** — the
  envelope case. Choose between them before you start.
- **[Solution 08 — API keys](../08-api-key/helix-agent-prompt.md)** — this package
  ships open; put identity in front of it.
- **[Solution 10 — Data masking](../10-data-mask/helix-agent-prompt.md)** — when
  the converted response says more than the client should see.
