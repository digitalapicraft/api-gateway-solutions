# API reference — a sandbox that answers every partner with their own values

> [Overview](README.md) · [Business need](business-need.md) · [Architecture](architecture.md) · [Guides](guides.md) · [Agent prompt](helix-agent-prompt.md) · [Tests](tests.md) · **API reference**

---

The raw control-plane calls behind [Install it directly](guides.md#install-it-directly),
listed for lookup rather than as a walkthrough. None of it requires custom code.
The full control-plane and plugin documentation is at
[docs.digitalapi.ai/api-gateway](https://docs.digitalapi.ai/api-gateway).

The API needs an upstream bound and its revision deployed **before** any route is
reachable — three calls the spec import doesn't do for you, easy to miss since
nothing fails loudly if you skip them. The upstream is never contacted here, but
the revision cannot deploy without one.

| Step | Call | Body | Notes |
|---|---|---|---|
| Import the spec | `POST /api/orgs/{orgId}/apis/from-spec` | `multipart/form-data`, part `file` — or a JSON body `{"spec": <document>}` | Attaches `key-value-map` and `mocking` to all three routes, and `request-id` and `cors` API-wide. Response is `{"api", "revision"}` — keep both ids. A raw `application/yaml` body is rejected with 415. |
| Create an upstream | `POST /api/orgs/{orgId}/envs/{envId}/upstreams` | `{"name","specification":{"scheme","nodes":[{"host","port","weight"}], ...}}` | Upstreams are created **per environment**. Any reachable host will do; it is never called. |
| Bind the upstream to the revision | `PATCH /api/orgs/{orgId}/apis/{apiId}/revisions/{revisionId}/upstream-bindings/add` | `{"environmentUpstreams":[{"environmentId","upstreamId"}]}` | Must succeed before the deploy call below. |
| Deploy the revision | `POST /api/orgs/{orgId}/apis/{apiId}/revisions/{revisionId}/deploy` | `{"environmentId","force":false}` | This is what makes the routes live. `force: true` replaces an existing deployment of the same revision. |
| List APIs (to get `<API_ID>`) | `GET /api/orgs/{orgId}/apis` | — | Find the id of the imported "Partner Sandbox API" here, if you didn't keep it from the import response. |

**There is no control-plane call for key-value entries** on this build. Sandbox
values are written only through the package's own routes on the gateway:

| Step | Call | Headers | Notes |
|---|---|---|---|
| Register or change a partner | `POST https://<YOUR_GATEWAY_HOST>/sandbox/partners` | `x-partner-id`, `x-tier`, `x-settlement-account` | `202`. Replaces that partner's values. Administrative — protect it before exposing it. |
| Read the caller's profile | `GET https://<YOUR_GATEWAY_HOST>/sandbox/profile` | `x-partner-id` | `200` with the caller's values, or empty values if unregistered. |
| Show both template syntaxes | `GET https://<YOUR_GATEWAY_HOST>/sandbox/diagnostics` | `x-partner-id` | `200`, plain text. A teaching aid; drop it before production. |

Not fully nailed down here — confirm against your org's live schema before
scripting this for real: an upstream's `specification` has more optional fields
(load balancing, health checks, TLS) beyond the minimum shown.
