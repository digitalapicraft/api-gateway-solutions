# API reference — Retire an old API version in stages

> [Overview](README.md) · [Business need](business-need.md) · [Architecture](architecture.md) · [Guides](guides.md) · [Agent prompt](helix-agent-prompt.md) · [Tests](tests.md) · **API reference**

---

The raw control-plane calls behind
[Install it directly](guides.md#install-it-directly), listed for lookup rather than
as a walkthrough. Every call takes `authorization: Bearer <token>`. Each step links
to its page in the
[control-plane API reference](https://docs.digitalapi.ai/api-gateway/api-reference/api-reference);
plugin fields are in the
[plugin reference](https://docs.digitalapi.ai/api-gateway/plugin-reference/plugin-reference).

| Step | Call | Body | Notes |
|---|---|---|---|
| [Import the spec](https://docs.digitalapi.ai/api-gateway/api-reference/api-spec/api-import) | `POST /api/orgs/{orgId}/apis/from-spec` | `multipart/form-data`, part `file`, or a JSON body `{"spec": <document>}` | Response is `{"api", "revision"}`. Keep both ids. A raw `application/yaml` body is rejected with 415. An API name that already exists is refused. |
| [Create an upstream](https://docs.digitalapi.ai/api-gateway/api-reference/api-spec/upstreams) | `POST /api/orgs/{orgId}/envs/{envId}/upstreams` | `{"name","specification":{"scheme","pass_host":"rewrite","upstream_host","nodes":[{"host","port","weight"}]}}` | Upstreams are created **per environment**. Set `upstream_host` to the backend's own host name. Without `pass_host` and `upstream_host`, every call returns 502. |
| [Bind it to the revision](https://docs.digitalapi.ai/api-gateway/api-reference/api-spec/revisions) | `PUT /api/orgs/{orgId}/apis/{apiId}/revisions/{revisionId}/envs/{envId}/bind-upstream` | `{"upstreamId"}` | Needed even though the retired route never calls the backend. |
| [Check before deploying](https://docs.digitalapi.ai/api-gateway/api-reference/api-spec/revisions) | `POST /api/orgs/{orgId}/apis/{apiId}/revisions/{revisionId}/envs/{envId}/deploy/dry-run` | `{}` | `{"success":true}` when it would deploy. A `mocking` `content_type` other than JSON, plain text or XML fails here with `unsupported content type!`, although the import accepted it. |
| [Deploy the revision](https://docs.digitalapi.ai/api-gateway/api-reference/api-spec/revisions) | `POST /api/orgs/{orgId}/apis/{apiId}/revisions/{revisionId}/envs/{envId}/deploy` | `{"force":false}` | Routes answer a few seconds later. |
| [Undeploy](https://docs.digitalapi.ai/api-gateway/api-reference/api-spec/revisions) | `POST /api/orgs/{orgId}/apis/{apiId}/revisions/{revisionId}/envs/{envId}/undeploy` | — | No body needed. |
| [Delete the API](https://docs.digitalapi.ai/api-gateway/api-reference/api-spec/apis) | `DELETE /api/orgs/{orgId}/apis/{apiId}` | — | Only once no revision is deployed. |

The plugin settings are in [Configuration reference](guides.md#configuration-reference).
