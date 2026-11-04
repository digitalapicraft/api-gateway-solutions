# API reference — Retire an old API version in stages

> [Overview](README.md) · [Business need](business-need.md) · [Architecture](architecture.md) · [Guides](guides.md) · [Agent prompt](helix-agent-prompt.md) · [Tests](tests.md) · **API reference**

---

The raw control-plane calls behind [Install it directly](guides.md#install-it-directly),
listed for lookup rather than as a walkthrough. Every call takes
`authorization: Bearer <token>`. The full control-plane and plugin
documentation is at [docs.digitalapi.ai/api-gateway](https://docs.digitalapi.ai/api-gateway).

| Step | Call | Body | Notes |
|---|---|---|---|
| Import the spec | `POST /api/orgs/{orgId}/apis/from-spec` | `multipart/form-data`, part `file`, or a JSON body `{"spec": <document>}` | Response is `{"api", "revision"}`. Keep both ids. A raw `application/yaml` body is rejected with 415. An API name that already exists is refused. |
| Create an upstream | `POST /api/orgs/{orgId}/envs/{envId}/upstreams` | `{"name","specification":{"scheme","pass_host":"rewrite","upstream_host","nodes":[{"host","port","weight"}]}}` | Upstreams are created **per environment**. Set `upstream_host` to the backend's own host name. Without `pass_host` and `upstream_host`, every call returns 502. |
| Bind it to the revision | `PATCH /api/orgs/{orgId}/apis/{apiId}/revisions/{revisionId}/upstream-bindings/add` | `{"environmentUpstreams":[{"environmentId","upstreamId"}]}` | Needed even though the retired route never calls the backend. |
| Check before deploying | `POST /api/orgs/{orgId}/apis/{apiId}/revisions/{revisionId}/deploy/dry-run` | `{"environmentId"}` | `{"success":true}` when it would deploy. A `mocking` `content_type` other than JSON, plain text or XML fails here with `unsupported content type!`, although the import accepted it. |
| Deploy the revision | `POST /api/orgs/{orgId}/apis/{apiId}/revisions/{revisionId}/deploy` | `{"environmentId","force":false}` | Routes answer a few seconds later. |
| Undeploy | `POST /api/orgs/{orgId}/apis/{apiId}/revisions/{revisionId}/undeploy` | `{"environmentId"}` | An empty body is refused. |
| Delete the API | `DELETE /api/orgs/{orgId}/apis/{apiId}` | — | Only once no revision is deployed. |

The plugin settings are in [Configuration reference](guides.md#configuration-reference).
