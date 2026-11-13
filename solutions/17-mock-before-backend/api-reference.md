# API reference — Mock before the backend

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
| [Import the mocked spec](https://docs.digitalapi.ai/api-gateway/api-reference/api-spec/api-import) | `POST /api/orgs/{orgId}/apis/from-spec` | `multipart/form-data`, part `file`, or a JSON body `{"spec": <document>}` | Response is `{"api", "revision"}`. Keep both ids. A raw `application/yaml` body is rejected with 415. |
| [Create an upstream](https://docs.digitalapi.ai/api-gateway/api-reference/api-spec/upstreams) | `POST /api/orgs/{orgId}/envs/{envId}/upstreams` | `{"name","specification":{"scheme","pass_host":"rewrite","upstream_host","nodes":[{"host","port","weight"}]}}` | Upstreams are created **per environment**. Point it at the backend you will switch to. Without `pass_host` and `upstream_host`, the backend receives your gateway's host name and every call returns 502. |
| [Bind it to the revision](https://docs.digitalapi.ai/api-gateway/api-reference/api-spec/revisions) | `PUT /api/orgs/{orgId}/apis/{apiId}/revisions/{revisionId}/envs/{envId}/bind-upstream` | `{"upstreamId"}` | Required even though the mock never calls it. Without it, deploy and dry-run answer `400` *"Upstream not configured for environment …"*. |
| [Check before deploying](https://docs.digitalapi.ai/api-gateway/api-reference/api-spec/revisions) | `POST /api/orgs/{orgId}/apis/{apiId}/revisions/{revisionId}/envs/{envId}/deploy/dry-run` | `{}` | `200` `"Dry-run validation successful"`. Changes nothing. |
| [Deploy the revision](https://docs.digitalapi.ai/api-gateway/api-reference/api-spec/revisions) | `POST /api/orgs/{orgId}/apis/{apiId}/revisions/{revisionId}/envs/{envId}/deploy` | `{"force":false}` | Routes answer a few seconds later. |
| [Create the switched-over revision](https://docs.digitalapi.ai/api-gateway/api-reference/api-spec/revision-specs) | `POST /api/orgs/{orgId}/apis/{apiId}/revisions/from-spec` | `multipart/form-data`, part `file` (`example/api-spec-basic.yaml`) | A new `INACTIVE` revision of the **same** API, with no upstream bound. Bind one before deploying. |
| [Switch over, or roll back](https://docs.digitalapi.ai/api-gateway/api-reference/api-spec/revisions) | `POST /api/orgs/{orgId}/apis/{apiId}/revisions/{revisionId}/envs/{envId}/deploy` | `{"force":true}` | Replaces the live revision of this API in that environment. With `"force":false` it is refused with `409` *"… already has revision … deployed for this API"*. |
| [Undeploy](https://docs.digitalapi.ai/api-gateway/api-reference/api-spec/revisions) | `POST /api/orgs/{orgId}/apis/{apiId}/revisions/{revisionId}/envs/{envId}/undeploy` | — | The routes stop answering. |
| [Delete the API](https://docs.digitalapi.ai/api-gateway/api-reference/api-spec/apis) | `DELETE /api/orgs/{orgId}/apis/{apiId}` | — | `204`. Undeploy first. |

The plugin settings themselves are described in the
[Configuration reference](guides.md#configuration-reference).
