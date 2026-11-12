# API reference — API Products with enforced quota

> [Overview](README.md) · [Business need](business-need.md) · [Architecture](architecture.md) · [Guides](guides.md) · [Agent prompt](helix-agent-prompt.md) · [Tests](tests.md) · **API reference**

---

The raw control-plane calls behind
[Install it directly](guides.md#install-it-directly), listed for lookup rather than
as a walkthrough. Every call below is exercised by this package's own setup — none
of it requires custom code. Each step links to its page in the
[control-plane API reference](https://docs.digitalapi.ai/api-gateway/api-reference/api-reference);
plugin fields are in the
[plugin reference](https://docs.digitalapi.ai/api-gateway/plugin-reference/plugin-reference).

The API itself needs an upstream bound and its revision deployed **before**
any of this is reachable — that's three calls the spec import doesn't do for
you, easy to miss since nothing fails loudly if you skip them.

| Step | Call | Body | Notes |
|---|---|---|---|
| [Import the spec](https://docs.digitalapi.ai/api-gateway/api-reference/api-spec/api-import) | `POST /api/orgs/{orgId}/apis/from-spec` | `multipart/form-data`, part `file` — or a JSON body `{"spec": <document>}` | Attaches `helix-auth` and `api-product-enforcer` to the routes. Response is `{"api", "revision"}` — keep both ids. A raw `application/yaml` body is rejected with 415. |
| [Create an upstream](https://docs.digitalapi.ai/api-gateway/api-reference/api-spec/upstreams) | `POST /api/orgs/{orgId}/envs/{envId}/upstreams` | `{"name","specification":{"scheme","pass_host":"rewrite","upstream_host","nodes":[{"host","port","weight"}], ...}}` | Upstreams are created **per environment**. Set `pass_host` to `rewrite` and `upstream_host` to the backend's host: without them the backend gets the gateway's host and every call returns HTTP 502 (bad gateway). |
| [Bind the upstream to the revision](https://docs.digitalapi.ai/api-gateway/api-reference/api-spec/revisions) | `PUT /api/orgs/{orgId}/apis/{apiId}/revisions/{revisionId}/envs/{envId}/bind-upstream` | `{"upstreamId"}` | Must succeed before the deploy call below — the two are never combined into one request. |
| [Deploy the revision](https://docs.digitalapi.ai/api-gateway/api-reference/api-spec/revisions) | `POST /api/orgs/{orgId}/apis/{apiId}/revisions/{revisionId}/envs/{envId}/deploy` | `{"force":false}` | This is what makes the routes live. `force: true` replaces an existing deployment of the same revision. |
| [List APIs (to get `<API_ID>`)](https://docs.digitalapi.ai/api-gateway/api-reference/api-spec/apis) | `GET /api/orgs/{orgId}/apis` | — | Find the id of the imported "Posts API" here, if you didn't keep it from the import response. |
| [Create a product](https://docs.digitalapi.ai/api-gateway/api-reference/api-spec/products) | `POST /api/orgs/{orgId}/products` | `{"name","displayName","apiIds","quota":{"limit","interval","interval_unit"}}` — see [Guides → Install it directly](guides.md#install-it-directly) for the Free/Pro bodies | Repeat once per product (Free, Pro, …); there's no bulk-create call. |
| [Deploy a product to an environment](https://docs.digitalapi.ai/api-gateway/api-reference/api-spec/products) | `POST /api/orgs/{orgId}/envs/{envId}/products/{productId}/deploy` | — | A different deploy than the revision's above — creating a product isn't enough, it has to be deployed too before it's enforced. |
| [Create a developer](https://docs.digitalapi.ai/api-gateway/api-reference/api-spec/developers) | `POST /api/orgs/{orgId}/developers` | `{"firstName","lastName","email"}` | Returns the developer's `id` — you'll need it for the next call. |
| [Create an app](https://docs.digitalapi.ai/api-gateway/api-reference/api-spec/apps) | `POST /api/orgs/{orgId}/developers/{developerId}/envs/{envId}/apps` | `{"name","displayName","products":{"<productId>":<rank>},"plugins":{"<authMethod>":{}}}` | `developerId` and the environment are **path segments**, not body fields. `products` is the `{productId: rank}` subscription map. `plugins` selects the app's auth method (matching what the product allows); an empty object requests auto-generated credentials. Repeat once per app — **two separate apps**, each subscribed to a different product, is the whole point. |

Two things not fully nailed down here — confirm both against your org's live
schema before scripting this for real: an upstream's `specification` has a lot
more optional fields (load balancing, health checks, TLS) beyond the minimum
shown; and `plugins`' exact shape beyond an empty auto-generate object.
