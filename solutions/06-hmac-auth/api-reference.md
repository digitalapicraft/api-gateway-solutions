# API reference — HMAC request signing at the gateway

> [Overview](README.md) · [Business need](business-need.md) · [Architecture](architecture.md) · [Guides](guides.md) · [Agent prompt](helix-agent-prompt.md) · [Tests](tests.md) · **API reference**

---

These are the raw control-plane calls behind [Install it directly](guides.md#install-it-directly).
(The control plane is where you manage APIs, products, developers and apps.) They
are listed so you can look one up, not as a walkthrough. Every call below is part
of this package's own setup. None of it needs custom code. The full control-plane
and plugin documentation is at [docs.digitalapi.ai/api-gateway](https://docs.digitalapi.ai/api-gateway).

Things are created in this order: **product, developer, app, credential**. An app
can only exist under a product. Creating the app is what creates the `key_id` and
`secret_key` the caller signs with.

| Step | Call | Body | Notes |
|---|---|---|---|
| Check the plugin exists | `GET /api/orgs/{orgId}/plugin-schemas?page=1&size=300` | — | `hmac-auth` must be in the list. |
| Import the spec | `POST /api/orgs/{orgId}/apis/from-spec` | `multipart/form-data`, part `file` — or a JSON body `{"spec": <document>}` | Nothing to fill in first. Adds `hmac-auth` to each route and `request-id` to the whole API. The response is `{"api", "revision"}`; keep both ids. A raw `application/yaml` body is rejected with 415. |
| Create an upstream | `POST /api/orgs/{orgId}/envs/{envId}/upstreams` | `{"name","specification":{"scheme","nodes":[{"host","port","weight"}], ...}}` | An upstream is your backend service. Upstreams are created **per environment**. |
| Link the upstream to the revision | `PATCH /api/orgs/{orgId}/apis/{apiId}/revisions/{revisionId}/upstream-bindings/add` | `{"environmentUpstreams":[{"environmentId","upstreamId"}]}` | Must succeed before the deploy call below. |
| Deploy the revision | `POST /api/orgs/{orgId}/apis/{apiId}/revisions/{revisionId}/deploy` | `{"environmentId","force":false}` | This is what makes the routes live. |
| List APIs (to get `<API_ID>`) | `GET /api/orgs/{orgId}/apis` | — | Find the id of the imported "Partner Albums API" here, if you didn't keep it from the import response. |
| Create the product | `POST /api/orgs/{orgId}/products` | The product object in [`example/products.json`](example/products.json): `{"name","displayName","description","apiIds","authMethods":["hmac-auth"],"quota":{"limit","interval","interval_unit"}}` | `authMethods` **must** name `hmac-auth`; it defaults to `["helix-auth"]`. A product with no `quota` is rejected when you create it. |
| Deploy the product to an environment | `POST /api/orgs/{orgId}/envs/{envId}/products/{productId}/deploy` | — | A separate deploy from the revision's. |
| Create a developer | `POST /api/orgs/{orgId}/developers` | `{"firstName","lastName","email"}` | Returns the developer's `id`. |
| Create an app | `POST /api/orgs/{orgId}/developers/{developerId}/envs/{envId}/apps` | `{"name","products":{"<productId>":<rank>},"plugins":{"hmac-auth":{}}}` | An **empty** `{"hmac-auth": {}}` creates `key_id` and `secret_key`. They are returned **once**, in this response. To match a secret a partner already holds, put your own values in that object. One app per integration. |

Not fully pinned down here, so check against your org's live schema before you
script this for real: an upstream's `specification` has many more optional fields
(load balancing, health checks, TLS) beyond the minimum shown.
