# API reference — SOAP/XML backend served as REST/JSON

> [Overview](README.md) · [Business need](business-need.md) · [Architecture](architecture.md) · [Guides](guides.md) · [Agent prompt](helix-agent-prompt.md) · [Tests](tests.md) · **API reference**

---

The raw control-plane calls behind [Install it directly](guides.md#install-it-directly),
listed for lookup rather than as a walkthrough. None of it requires custom code. The
full control-plane and plugin documentation is at
[docs.digitalapi.ai/api-gateway](https://docs.digitalapi.ai/api-gateway).

**Before the first call:** replace `<SOAP_HANDLER_PATH>` in
`example/api-spec.yaml` with your handler's path, and confirm `xml-to-json` is
available in your org (`get_plugin_config` through the agent, or the control
plane's plugin-schema listing).

| Step | Call | Body | Notes |
|---|---|---|---|
| Import the spec | `POST /api/orgs/{orgId}/apis/from-spec` | `multipart/form-data`, part `file` — or a JSON body `{"spec": <document>}` | Attaches `proxy-rewrite` and `xml-to-json` to `/locations`, plus `request-id` and `cors` API-wide. Response is `{"api", "revision"}` — keep both ids. A raw `application/yaml` body is rejected with 415. |
| Create an upstream | `POST /api/orgs/{orgId}/envs/{envId}/upstreams` | `{"name","specification":{"scheme","nodes":[{"host","port","weight"}], ...}}` | Points at your SOAP service. Upstreams are created **per environment**. |
| Bind the upstream to the revision | `PATCH /api/orgs/{orgId}/apis/{apiId}/revisions/{revisionId}/upstream-bindings/add` | `{"environmentUpstreams":[{"environmentId","upstreamId"}]}` | Must succeed before the deploy call below. |
| Deploy the revision | `POST /api/orgs/{orgId}/apis/{apiId}/revisions/{revisionId}/deploy` | `{"environmentId","force":false}` | This is what makes the route live. A live (ACTIVE) revision rejects edits — undeploy or clone it first. |
| List APIs (to get `<API_ID>`) | `GET /api/orgs/{orgId}/apis` | — | Find the imported "Partner Locations API" here, if you didn't keep the id from the import response. |

There are no product, developer or app calls: this package has no sign-in. Adding
[solution 02](../02-oauth-jwt/) brings those — see
[its API reference](../02-oauth-jwt/api-reference.md).

The call a partner makes, listed so the whole flow is in one place:

| Call | Headers | Notes |
|---|---|---|
| `POST /locations` on the gateway, JSON body | `content-type: application/json`, `accept: application/json` | Without `accept: application/json` the response comes back as XML. |

Not fully nailed down here — confirm against your org's live schema before
scripting this for real: an upstream's `specification` has more optional fields
(load balancing, health checks, TLS) than the minimum shown.
