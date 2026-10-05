# API reference — API Products with enforced quota

> [Overview](README.md) · [Business need](business-need.md) · [Architecture](architecture.md) · [Guides](guides.md) · [Agent prompt](helix-agent-prompt.md) · [Tests](tests.md) · **API reference**

---

The raw control-plane calls behind [Install it directly](guides.md#install-it-directly),
listed for lookup rather than as a walkthrough. Every call below is exercised by this
package's own setup — none of it requires custom code. The full control-plane and
plugin documentation is at [docs.digitalapi.ai/api-gateway](https://docs.digitalapi.ai/api-gateway).

The API itself needs an upstream bound and its revision deployed **before**
any of this is reachable — that's three calls the spec import doesn't do for
you, easy to miss since nothing fails loudly if you skip them.

| Step | Call | Body | Notes |
|---|---|---|---|
| Import the spec | `POST /api/orgs/{orgId}/apis/from-spec` | `multipart/form-data`, part `file` — or a JSON body `{"spec": <document>}` | Attaches `helix-auth` and `api-product-enforcer` to the routes. Response is `{"api", "revision"}` — keep both ids. A raw `application/yaml` body is rejected with 415. |
| Create an upstream | `POST /orgs/{orgId}/envs/{envId}/upstreams` | `{"name","specification":{"scheme","nodes":[{"host","port","weight"}], ...}}` | No `/api` prefix on this one — that's a real inconsistency in the platform, not a typo. Upstreams are created **per environment**. |
| Bind the upstream to the revision | `PATCH /api/orgs/{orgId}/apis/{apiId}/revisions/{revisionId}/upstream-bindings/add` | `{"environmentUpstreams":[{"environmentId","upstreamId"}]}` | Must succeed before the deploy call below — the two are never combined into one request. |
| Deploy the revision | `POST /api/orgs/{orgId}/apis/{apiId}/revisions/{revisionId}/deploy` | `{"environmentId","force":false}` | This is what makes the routes live. `force: true` replaces an existing deployment of the same revision. |
| List APIs (to get `<API_ID>`) | `GET /api/orgs/{orgId}/apis` | — | Find the id of the imported "Posts API" here, if you didn't keep it from the import response. |
| Create a product | `POST /api/orgs/{orgId}/products` | `{"name","displayName","apiIds","quota":{"limit","interval","interval_unit"}}` — see [Guides → Install it directly](guides.md#install-it-directly) for the Free/Pro bodies | Repeat once per product (Free, Pro, …); there's no bulk-create call. |
| Deploy a product to an environment | `POST /api/orgs/{orgId}/envs/{envId}/products/{productId}/deploy` | — | A different deploy than the revision's above — creating a product isn't enough, it has to be deployed too before it's enforced. |
| Create a developer | `POST /api/orgs/{orgId}/developers` | `{"firstName","lastName","email"}` | Returns the developer's `id` — you'll need it for the next call. |
| Create an app | `POST /api/orgs/{orgId}/developers/{developerId}/envs/{envId}/apps` | `{"name","products":{"<productId>":<rank>},"plugins":{"<authMethod>":{}}}` | `developerId` and the environment are **path segments**, not body fields. `products` is the `{productId: rank}` subscription map. `plugins` selects the app's auth method (matching what the product allows); an empty object requests auto-generated credentials. Repeat once per app — **two separate apps**, each subscribed to a different product, is the whole point. |

Two things not fully nailed down here — confirm both against your org's live
schema before scripting this for real: an upstream's `specification` has a lot
more optional fields (load balancing, health checks, TLS) beyond the minimum
shown; and `plugins`' exact shape beyond an empty auto-generate object.
