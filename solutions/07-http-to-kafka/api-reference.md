# API reference — HTTP to Kafka at the edge

> [Overview](README.md) · [Business need](business-need.md) · [Architecture](architecture.md) · [Guides](guides.md) · [Agent prompt](helix-agent-prompt.md) · [Tests](tests.md) · **API reference**

---

The raw control-plane calls behind
[Install it directly](guides.md#install-it-directly), listed for lookup rather than
as a walkthrough. None of it requires custom code. Each step links to its page in
the
[control-plane API reference](https://docs.digitalapi.ai/api-gateway/api-reference/api-reference);
plugin fields are in the
[plugin reference](https://docs.digitalapi.ai/api-gateway/plugin-reference/plugin-reference).

The Kafka topic is created on your broker with your own Kafka tooling, before any
of these calls. The gateway doesn't create it, and auto-creation drops the first
message.

| Step | Call | Body | Notes |
|---|---|---|---|
| [Check the plugins exist](https://docs.digitalapi.ai/api-gateway/api-reference/api-spec/plugin-schema-management) | `GET /api/orgs/{orgId}/plugin-schemas?page=1&size=300` | — | Confirm `kafka-logger`, `mocking` and `request-validation` are in the list before you import. |
| [Import the spec](https://docs.digitalapi.ai/api-gateway/api-reference/api-spec/api-import) | `POST /api/orgs/{orgId}/apis/from-spec` | `multipart/form-data`, part `file` — or a JSON body `{"spec": <document>}` | Edit `<YOUR_KAFKA_BROKER>` and `kafka_topic` first. Creates the API and its first revision with all four plugins. Response is `{"api", "revision"}` — keep both ids. A raw `application/yaml` body is rejected with 415. |
| [Create an upstream](https://docs.digitalapi.ai/api-gateway/api-reference/api-spec/upstreams) | `POST /api/orgs/{orgId}/envs/{envId}/upstreams` | `{"name","specification":{"scheme","pass_host":"rewrite","upstream_host","nodes":[{"host","port","weight"}], ...}}` | Any host will do: the `/events` route never contacts it, but a revision won't deploy without a binding. Set `pass_host` to `rewrite` and `upstream_host` to the backend's host: without them the backend gets the gateway's host and every call returns HTTP 502 (bad gateway). |
| [Bind the upstream to the revision](https://docs.digitalapi.ai/api-gateway/api-reference/api-spec/revisions) | `PUT /api/orgs/{orgId}/apis/{apiId}/revisions/{revisionId}/envs/{envId}/bind-upstream` | `{"upstreamId"}` | Must succeed before the deploy call below. |
| [Deploy the revision](https://docs.digitalapi.ai/api-gateway/api-reference/api-spec/revisions) | `POST /api/orgs/{orgId}/apis/{apiId}/revisions/{revisionId}/envs/{envId}/deploy` | `{"force":false}` | This is what makes the route live. `force: true` replaces an existing deployment of the same revision. |
| [List APIs (to get `<API_ID>`)](https://docs.digitalapi.ai/api-gateway/api-reference/api-spec/apis) | `GET /api/orgs/{orgId}/apis` | — | Find the id of the imported "Event Ingest API" here, if you didn't keep it from the import response. |

No products, developers or apps are created: the route ships unauthenticated. To
close it, see [Guides → Variations](guides.md#variations).

An upstream's `specification` has more optional fields (load balancing, health
checks, TLS) than the minimum shown. Confirm against your org's live schema before
scripting this for real.
