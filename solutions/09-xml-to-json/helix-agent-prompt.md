# Agent-mode prompt — a JSON front door on an XML backend

> [Overview](README.md) · [Business need](business-need.md) · [Architecture](architecture.md) · [Guides](guides.md) · **Agent prompt** · [Tests](tests.md) · [API reference](api-reference.md)

---

Paste step 1, replacing the `{{...}}` value, and wait for the agent to read the
revision back. Then paste step 2 in the same session.

**If your backend is SOAP, this is the wrong prompt** — use
[solution 03](../03-soap-to-rest/helix-agent-prompt.md). See
[Guides](guides.md#build-it-with-the-helix-agent) if something looks off.

## Prompt

### Step 1 — create the API and configure both directions

```text
Create a REST API "{{api_name}}" putting a JSON front door on an XML backend.
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

### Step 2 — prove both directions

```text
Now curl commands showing, in order: GET /catalog/items with
Accept: application/json returning JSON; the same call with Accept:
application/xml returning the backend's XML untouched; a JSON POST to
/catalog/orders whose echo shows the XML the backend received; and the same POST
sent as text/plain, which passes through unconverted with no error.
```
