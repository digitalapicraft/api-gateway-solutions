# API reference — Keep a supplier's API key at the gateway

> [Overview](README.md) · [Business need](business-need.md) · [Architecture](architecture.md) · [Guides](guides.md) · [Agent prompt](helix-agent-prompt.md) · [Tests](tests.md) · **API reference**

---

The raw control-plane calls behind [Install it directly](guides.md#install-it-directly).
(The control plane is where you manage APIs, products, developers and apps.) They
are listed so you can look one up, not as a walkthrough. Every call takes
`authorization: Bearer <token>`. The full control-plane and plugin documentation
is at [docs.digitalapi.ai/api-gateway](https://docs.digitalapi.ai/api-gateway).

| Step | Call | Body | Notes |
|---|---|---|---|
| Import the spec | `POST /api/orgs/{orgId}/apis/from-spec` | `multipart/form-data`, part `file`, or a JSON body `{"spec": <document>}` | **Replace `<SUPPLIER_API_KEY>` in your copy first**: the value is stored and sent exactly as written. The response is `{"api", "revision"}`; keep both ids. A raw `application/yaml` body is rejected with 415 (unsupported content type). |
| Create an upstream | `POST /api/orgs/{orgId}/envs/{envId}/upstreams` | `{"name","specification":{"scheme","pass_host":"rewrite","upstream_host","nodes":[{"host","port","weight"}]}}` | Per environment. `upstream_host` is the supplier's host (`postman-echo.com` to try it). Without `pass_host` and `upstream_host` the supplier gets the gateway's host name and every call returns 502. |
| Link it to the revision | `PATCH /api/orgs/{orgId}/apis/{apiId}/revisions/{revisionId}/upstream-bindings/add` | `{"environmentUpstreams":[{"environmentId","upstreamId"}]}` | Before the deploy. |
| Deploy the revision | `POST /api/orgs/{orgId}/apis/{apiId}/revisions/{revisionId}/deploy` | `{"environmentId","force":false}` | Makes the route live. A deployed revision can't be edited (`Only INACTIVE revisions can be updated`): clone it to change the supplier key. |
| Create a product | `POST /api/orgs/{orgId}/products` | `{"name","displayName","apiIds","quota":{"limit","interval","interval_unit"}}` | Every app needs a product to get its key. Every product needs a `quota`; this solution doesn't enforce it. |
| Deploy the product | `POST /api/orgs/{orgId}/envs/{envId}/products/{productId}/deploy` | — | A separate deploy from the revision's. |
| Create a developer | `POST /api/orgs/{orgId}/developers` | `{"firstName","lastName","email"}` | Returns the developer's `id`. |
| Create an app | `POST /api/orgs/{orgId}/developers/{developerId}/envs/{envId}/apps` | `{"name","displayName","products":{"<productId>":1},"plugins":{"helix-auth":{}}}` | Send `displayName`: without it the call can be refused with `Display name is required`. The empty `{"helix-auth":{}}` asks for a key and secret to be created. The response carries them at `credential.plugins["helix-auth"]`: `key` is what the client sends in `X-Api-Key`. One app per client. |
| Delete an app | `DELETE /api/orgs/{orgId}/envs/{envId}/apps/{appId}` | — | Its key stops working within seconds. Also deletes the app's usage history. |

The `proxy-rewrite` and `helix-auth` settings the spec carries are described in
the [Configuration reference](guides.md#configuration-reference).
