# API reference — API keys checked at the gateway

> [Overview](README.md) · [Business need](business-need.md) · [Architecture](architecture.md) · [Guides](guides.md) · [Agent prompt](helix-agent-prompt.md) · [Tests](tests.md) · **API reference**

---

These are the raw control-plane calls behind [Install it directly](guides.md#install-it-directly).
(The control plane is where you manage APIs, products, developers and apps.) They
are listed so you can look one up, not as a walkthrough. Every call below is part
of this package's own setup. None of it needs custom code. The full control-plane
and plugin documentation is at [docs.digitalapi.ai/api-gateway](https://docs.digitalapi.ai/api-gateway).

Nothing can be called until two things are done. The API needs an upstream (your
backend service) linked to it, and its revision (one saved version of the API's
configuration) must be deployed. Importing the spec does neither for you. If you
skip them, nothing gives you a clear error.

| Step | Call | Body | Notes |
|---|---|---|---|
| Import the spec | `POST /api/orgs/{orgId}/apis/from-spec` | `multipart/form-data`, part `file` — or a JSON body `{"spec": <document>}` | Nothing to fill in first. Adds `helix-auth` and `proxy-rewrite` to each route and `request-id` to the whole API. The response is `{"api", "revision"}`; keep both ids. A raw `application/yaml` body is rejected with 415 (unsupported content type). |
| Create an upstream | `POST /api/orgs/{orgId}/envs/{envId}/upstreams` | `{"name","specification":{"scheme","pass_host":"rewrite","upstream_host","nodes":[{"host","port","weight"}], ...}}` | Each environment has its own upstreams. Set `pass_host` to `rewrite` and `upstream_host` to the backend's host: without them the backend gets the gateway's host and every call returns HTTP 502 (bad gateway). |
| Link the upstream to the revision | `PATCH /api/orgs/{orgId}/apis/{apiId}/revisions/{revisionId}/upstream-bindings/add` | `{"environmentUpstreams":[{"environmentId","upstreamId"}]}` | This must succeed before the deploy call below. |
| Deploy the revision | `POST /api/orgs/{orgId}/apis/{apiId}/revisions/{revisionId}/deploy` | `{"environmentId","force":false}` | This is what makes the routes live. A revision that is deployed (ACTIVE) can't be edited: it returns `Only INACTIVE revisions can be updated`. |
| List APIs (to get `<API_ID>`) | `GET /api/orgs/{orgId}/apis` | — | Find the id of the imported "Terminal API" here, if you didn't keep it from the import response. |
| Create a product | `POST /api/orgs/{orgId}/products` | `{"name","displayName","apiIds","quota":{"limit","interval","interval_unit"}}` | Every app needs a product to get its key. Which product isn't checked: a key from any app in the environment is accepted. Every product needs a `quota` (usage limit); this solution does not enforce it. |
| Deploy a product to an environment | `POST /api/orgs/{orgId}/envs/{envId}/products/{productId}/deploy` | — | This is a separate deploy from the revision's. Creating a product isn't enough. |
| Create a developer | `POST /api/orgs/{orgId}/developers` | `{"firstName","lastName","email"}` | Returns the developer's `id`. |
| Create an app | `POST /api/orgs/{orgId}/developers/{developerId}/envs/{envId}/apps` | `{"name","displayName","products":{"<productId>":<rank>},"plugins":{"helix-auth":{}}}` | `developerId` and the environment go **in the URL path**, not in the body. An empty `{"helix-auth":{}}` asks the control plane to create the credentials (the app's key and secret). The key is what the caller sends in `X-Device-Key`. **One app per caller.** |

Two things are not fully confirmed here. Check them against your org's live
schema before you script this for real:

- An upstream's `specification` has many more optional fields than the minimum
  shown (load balancing, health checks, TLS).
- The exact shape of `plugins`, beyond an empty object that asks for
  auto-generated credentials.
