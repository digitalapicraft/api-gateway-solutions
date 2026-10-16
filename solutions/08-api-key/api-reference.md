# API reference — API-key identity at the edge

> [Overview](README.md) · [Business need](business-need.md) · [Architecture](architecture.md) · [Guides](guides.md) · [Agent prompt](helix-agent-prompt.md) · [Tests](tests.md) · **API reference**

---

The raw control-plane calls behind [Install it directly](guides.md#install-it-directly),
listed for lookup rather than as a walkthrough. Every call below is part of this
package's own setup — none of it requires custom code. The full control-plane and
plugin documentation is at [docs.digitalapi.ai/api-gateway](https://docs.digitalapi.ai/api-gateway).

The API itself needs an upstream bound and its revision deployed **before**
anything is reachable. The spec import doesn't do either for you, and nothing
fails loudly if you skip them.

| Step | Call | Body | Notes |
|---|---|---|---|
| Import the spec | `POST /api/orgs/{orgId}/apis/from-spec` | `multipart/form-data`, part `file` — or a JSON body `{"spec": <document>}` | Nothing to fill in. Attaches `helix-auth` and `proxy-rewrite` to each route and `request-id` API-wide. Response is `{"api", "revision"}` — keep both ids. A raw `application/yaml` body is rejected with 415. |
| Create an upstream | `POST /api/orgs/{orgId}/envs/{envId}/upstreams` | `{"name","specification":{"scheme","nodes":[{"host","port","weight"}], ...}}` | Upstreams are created **per environment**. |
| Bind the upstream to the revision | `PATCH /api/orgs/{orgId}/apis/{apiId}/revisions/{revisionId}/upstream-bindings/add` | `{"environmentUpstreams":[{"environmentId","upstreamId"}]}` | Must succeed before the deploy call below. |
| Deploy the revision | `POST /api/orgs/{orgId}/apis/{apiId}/revisions/{revisionId}/deploy` | `{"environmentId","force":false}` | This is what makes the routes live. An ACTIVE revision won't accept spec edits (`Only INACTIVE revisions can be updated`). |
| List APIs (to get `<API_ID>`) | `GET /api/orgs/{orgId}/apis` | — | Find the id of the imported "Terminal API" here, if you didn't keep it from the import response. |
| Create a product | `POST /api/orgs/{orgId}/products` | `{"name","displayName","apiIds","quota":{"limit","interval","interval_unit"}}` | The product must include this API, or a valid key gets 403. Every product needs a `quota`; this solution does not enforce it. |
| Deploy a product to an environment | `POST /api/orgs/{orgId}/envs/{envId}/products/{productId}/deploy` | — | A different deploy from the revision's. Creating a product isn't enough. |
| Create a developer | `POST /api/orgs/{orgId}/developers` | `{"firstName","lastName","email"}` | Returns the developer's `id`. |
| Create an app | `POST /api/orgs/{orgId}/developers/{developerId}/envs/{envId}/apps` | `{"name","products":{"<productId>":<rank>},"plugins":{"helix-auth":{}}}` | `developerId` and the environment are **path segments**, not body fields. An empty `{"helix-auth":{}}` asks for auto-generated credentials; the key is what the caller sends in `X-Device-Key`. **One app per caller.** |

Not fully nailed down here — confirm against your org's live schema before
scripting this for real: an upstream's `specification` has many more optional
fields (load balancing, health checks, TLS) beyond the minimum shown; and
`plugins`' exact shape beyond an empty auto-generate object.
