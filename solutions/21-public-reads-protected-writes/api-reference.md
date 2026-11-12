# API reference — Public reads, protected writes

> [Overview](README.md) · [Business need](business-need.md) · [Architecture](architecture.md) · [Guides](guides.md) · [Agent prompt](helix-agent-prompt.md) · [Tests](tests.md) · **API reference**

---

The raw control-plane calls behind [Install it directly](guides.md#install-it-directly),
listed for lookup rather than as a walkthrough. Every call takes
`authorization: Bearer <token>`. None of it needs custom code. The full
control-plane and plugin documentation is at
[docs.digitalapi.ai/api-gateway](https://docs.digitalapi.ai/api-gateway).

| Step | Call | Body | Notes |
|---|---|---|---|
| Import the spec | `POST /api/orgs/{orgId}/apis/from-spec` | `multipart/form-data`, part `file`, or a JSON body `{"spec": <document>}` | Nothing to fill in first: the spec holds no key. Puts `helix-auth` on the three write routes, `proxy-rewrite` and `request-id` on the whole API. Response is `{"api", "revision"}`; keep both ids. A raw `application/yaml` body is rejected with 415. |
| Create an upstream | `POST /api/orgs/{orgId}/envs/{envId}/upstreams` | `{"name","specification":{"scheme","pass_host":"rewrite","upstream_host","nodes":[{"host","port","weight"}]}}` | Upstreams belong to one environment. Without `pass_host` and `upstream_host`, the backend receives your gateway's host name and every call returns 502. |
| Link it to the revision | `PATCH /api/orgs/{orgId}/apis/{apiId}/revisions/{revisionId}/upstream-bindings/add` | `{"environmentUpstreams":[{"environmentId","upstreamId"}]}` | Before the deploy. |
| Check the deploy first (optional) | `POST /api/orgs/{orgId}/apis/{apiId}/revisions/{revisionId}/deploy/dry-run` | `{"environmentId"}` | Checks the configuration without changing anything live. |
| Deploy the revision | `POST /api/orgs/{orgId}/apis/{apiId}/revisions/{revisionId}/deploy` | `{"environmentId","force":false}` | Makes the routes live, a few seconds later. A deployed revision can't be edited: `Only INACTIVE revisions can be updated`. |
| Create a product | `POST /api/orgs/{orgId}/products` | `{"name","displayName","apiIds","quota":{"limit","interval","interval_unit"}}` | An app needs a product to get its key. Every product needs a `quota`; this solution does not enforce it. |
| Deploy the product | `POST /api/orgs/{orgId}/envs/{envId}/products/{productId}/deploy` | — | A separate deploy from the revision's. |
| Create a developer | `POST /api/orgs/{orgId}/developers` | `{"firstName","lastName","email"}` | Returns the developer's `id`. |
| Create an app | `POST /api/orgs/{orgId}/developers/{developerId}/envs/{envId}/apps` | `{"name","displayName","products":{"<productId>":1},"plugins":{"helix-auth":{}}}` | `displayName` is required. An empty `{"helix-auth":{}}` asks for a key and secret to be created; the key is at `credential.plugins.helix-auth.key` in the response. **One app per partner.** |
| Delete an app | `DELETE /api/orgs/{orgId}/envs/{envId}/apps/{appId}` | — | Switches that partner off. Its key stops opening the writes. |
| Undeploy, then delete the API | `POST .../revisions/{revisionId}/undeploy` `{"environmentId"}`, then `DELETE /api/orgs/{orgId}/apis/{apiId}` | — | An API that is still in a product can't be deleted (`409`). Remove it from the product, or delete the product first. |
