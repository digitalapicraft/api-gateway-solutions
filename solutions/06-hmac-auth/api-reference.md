# API reference — HMAC request signing at the edge

> [Overview](README.md) · [Business need](business-need.md) · [Architecture](architecture.md) · [Guides](guides.md) · [Agent prompt](helix-agent-prompt.md) · [Tests](tests.md) · **API reference**

---

The raw control-plane calls behind [Install it directly](guides.md#install-it-directly),
listed for lookup rather than as a walkthrough. Every call below is part of this
package's own setup — none of it requires custom code. The full control-plane and
plugin documentation is at [docs.digitalapi.ai/api-gateway](https://docs.digitalapi.ai/api-gateway).

The chain is **product → developer → app → credential**. An app can only exist
under a product, and creating the app is what generates the `key_id` and
`secret_key` the caller signs with.

| Step | Call | Body | Notes |
|---|---|---|---|
| Check the plugin exists | `GET /api/orgs/{orgId}/plugin-schemas?page=1&size=300` | — | `hmac-auth` must be in the list. |
| Import the spec | `POST /api/orgs/{orgId}/apis/from-spec` | `multipart/form-data`, part `file` — or a JSON body `{"spec": <document>}` | Nothing to fill in first. Attaches `hmac-auth` to each route and `request-id` API-wide. Response is `{"api", "revision"}` — keep both ids. A raw `application/yaml` body is rejected with 415. |
| Create an upstream | `POST /api/orgs/{orgId}/envs/{envId}/upstreams` | `{"name","specification":{"scheme","nodes":[{"host","port","weight"}], ...}}` | Upstreams are created **per environment**. |
| Bind the upstream to the revision | `PATCH /api/orgs/{orgId}/apis/{apiId}/revisions/{revisionId}/upstream-bindings/add` | `{"environmentUpstreams":[{"environmentId","upstreamId"}]}` | Must succeed before the deploy call below. |
| Deploy the revision | `POST /api/orgs/{orgId}/apis/{apiId}/revisions/{revisionId}/deploy` | `{"environmentId","force":false}` | This is what makes the routes live. |
| List APIs (to get `<API_ID>`) | `GET /api/orgs/{orgId}/apis` | — | Find the id of the imported "Partner Events API" here, if you didn't keep it from the import response. |
| Create the product | `POST /api/orgs/{orgId}/products` | The product object in [`example/products.json`](example/products.json): `{"name","displayName","description","apiIds","authMethods":["hmac-auth"],"quota":{"limit","interval","interval_unit"}}` | `authMethods` **must** name `hmac-auth`; it defaults to `["helix-auth"]`. A product with no `quota` is rejected at creation. |
| Deploy the product to an environment | `POST /api/orgs/{orgId}/envs/{envId}/products/{productId}/deploy` | — | A different deploy from the revision's. |
| Create a developer | `POST /api/orgs/{orgId}/developers` | `{"firstName","lastName","email"}` | Returns the developer's `id`. |
| Create an app | `POST /api/orgs/{orgId}/developers/{developerId}/envs/{envId}/apps` | `{"name","products":{"<productId>":<rank>},"plugins":{"hmac-auth":{}}}` | An **empty** `{"hmac-auth": {}}` generates `key_id` and `secret_key`, returned **once** in this response. Supply your own values in that object to match a secret a partner already holds. One app per integration. |

Not fully nailed down here — confirm against your org's live schema before
scripting this for real: an upstream's `specification` has many more optional
fields (load balancing, health checks, TLS) beyond the minimum shown.
