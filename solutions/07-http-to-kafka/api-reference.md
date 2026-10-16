# API reference — HTTP to Kafka at the edge

> [Overview](README.md) · [Business need](business-need.md) · [Architecture](architecture.md) · [Guides](guides.md) · [Agent prompt](helix-agent-prompt.md) · [Tests](tests.md) · **API reference**

---

The raw control-plane calls behind [Install it directly](guides.md#install-it-directly),
listed for lookup rather than as a walkthrough. None of it requires custom code.
The full control-plane and plugin documentation is at
[docs.digitalapi.ai/api-gateway](https://docs.digitalapi.ai/api-gateway).

The Kafka topic is created on your broker with your own Kafka tooling, before any
of these calls. The gateway doesn't create it, and auto-creation drops the first
message.

| Step | Call | Body | Notes |
|---|---|---|---|
| Check the plugins exist | `GET /api/orgs/{orgId}/plugin-schemas?page=1&size=300` | — | Confirm `kafka-logger`, `mocking` and `request-validation` are in the list before you import. |
| Import the spec | `POST /api/orgs/{orgId}/apis/from-spec` | `multipart/form-data`, part `file` — or a JSON body `{"spec": <document>}` | Edit `<YOUR_KAFKA_BROKER>` and `kafka_topic` first. Creates the API and its first revision with all four plugins. Response is `{"api", "revision"}` — keep both ids. A raw `application/yaml` body is rejected with 415. |
| Create an upstream | `POST /api/orgs/{orgId}/envs/{envId}/upstreams` | `{"name","specification":{"scheme","nodes":[{"host","port","weight"}], ...}}` | Any host will do: the `/events` route never contacts it, but a revision won't deploy without a binding. |
| Bind the upstream to the revision | `PATCH /api/orgs/{orgId}/apis/{apiId}/revisions/{revisionId}/upstream-bindings/add` | `{"environmentUpstreams":[{"environmentId","upstreamId"}]}` | Must succeed before the deploy call below. |
| Deploy the revision | `POST /api/orgs/{orgId}/apis/{apiId}/revisions/{revisionId}/deploy` | `{"environmentId","force":false}` | This is what makes the route live. `force: true` replaces an existing deployment of the same revision. |
| List APIs (to get `<API_ID>`) | `GET /api/orgs/{orgId}/apis` | — | Find the id of the imported "Event Ingest API" here, if you didn't keep it from the import response. |

No products, developers or apps are created: the route ships unauthenticated. To
close it, see [Guides → Variations](guides.md#variations).

An upstream's `specification` has more optional fields (load balancing, health
checks, TLS) than the minimum shown. Confirm against your org's live schema before
scripting this for real.
