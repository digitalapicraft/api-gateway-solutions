# API reference — a bidirectional gRPC stream, authenticated at the edge

> [Overview](README.md) · [Business need](business-need.md) · [Architecture](architecture.md) · [Guides](guides.md) · [Agent prompt](helix-agent-prompt.md) · [Tests](tests.md) · **API reference**

---

The raw control-plane calls behind [Install it directly](guides.md#install-it-directly),
listed for lookup rather than as a walkthrough. None of it requires custom code.
The full control-plane and plugin documentation is at
[docs.digitalapi.ai/api-gateway](https://docs.digitalapi.ai/api-gateway).

The spec import is only half the configuration. The gRPC setting lives on the
upstream, and the API needs that upstream bound and its revision deployed
**before** any route is reachable.

| Step | Call | Body | Notes |
|---|---|---|---|
| Import the spec | `POST /api/orgs/{orgId}/apis/from-spec` | `multipart/form-data`, part `file` — or a JSON body `{"spec": <document>}` | Five routes, each with `helix-auth`, plus `request-id` API-wide. Response is `{"api", "revision"}` — keep both ids. A raw `application/yaml` body is rejected with 415. |
| Create the gRPC upstream | `POST /api/orgs/{orgId}/envs/{envId}/upstreams` | `{"name","specification":{"scheme":"grpc","type":"roundrobin","pass_host":"node","nodes":[{"host","port","weight":1,"priority":1}]}}` | `scheme` is `grpc`, or `grpcs` for a TLS backend. Upstreams are created **per environment**. |
| Bind the upstream to the revision | `PATCH /api/orgs/{orgId}/apis/{apiId}/revisions/{revisionId}/upstream-bindings/add` | `{"environmentUpstreams":[{"environmentId","upstreamId"}]}` | Must succeed before the deploy call below. |
| Deploy the revision | `POST /api/orgs/{orgId}/apis/{apiId}/revisions/{revisionId}/deploy` | `{"environmentId","force":false}` | A later **scheme change does not reach a deployed revision** — undeploy and deploy again. |
| Create a product | `POST /api/orgs/{orgId}/products` | `{"name","displayName","apiIds","quota":{"limit","interval","interval_unit"}}` | Every product needs a quota object. Here the quota counts streams, not messages. |
| Deploy the product | `POST /api/orgs/{orgId}/envs/{envId}/products/{productId}/deploy` | — | A different deploy from the revision's. |
| Create a developer | `POST /api/orgs/{orgId}/developers` | `{"firstName","lastName","email"}` | Returns the developer's `id`. |
| Create an app | `POST /api/orgs/{orgId}/developers/{developerId}/envs/{envId}/apps` | `{"name","products":{"<productId>":<rank>},"plugins":{"helix-auth":{}}}` | `products` is a `{productId: rank}` map, not an array. The response carries the key clients send as `X-Unit-Key`. |
| Count connections | `POST /api/orgs/{orgId}/analytics/metrics/requests-count` | `{"dimensions":["api_path"],"filters":[{"column":"api_name","operator":"EQ","value":["<your api>"]}],"excludeTimeUnit":true}` | One row per stream. Use `["app_name"]` to group by caller. |
| Time connections | `POST /api/orgs/{orgId}/analytics/metrics/response-time` | the same, with aggregation `MAX` | The stream's lifetime in milliseconds, recorded when it closes. |

Not fully nailed down here — confirm against your org's live schema before
scripting this for real: an upstream's `specification` has more optional fields
(health checks, TLS) beyond the minimum shown; the exact shape of an app's
`plugins` beyond an empty auto-generate object; and where the analytics calls take
their `MAX` aggregation.
