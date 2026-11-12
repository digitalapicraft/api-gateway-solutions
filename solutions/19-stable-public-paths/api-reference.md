# API reference — Stable public paths

> [Overview](README.md) · [Business need](business-need.md) · [Architecture](architecture.md) · [Guides](guides.md) · [Agent prompt](helix-agent-prompt.md) · [Tests](tests.md) · **API reference**

---

The raw control-plane calls behind [Install it directly](guides.md#install-it-directly),
listed for lookup rather than as a walkthrough. Every call takes
`authorization: Bearer <token>`. The full control-plane and plugin
documentation is at [docs.digitalapi.ai/api-gateway](https://docs.digitalapi.ai/api-gateway).

| Step | Call | Body | Notes |
|---|---|---|---|
| Import the spec | `POST /api/orgs/{orgId}/apis/from-spec` | `multipart/form-data`, part `file`, or a JSON body `{"spec": <document>}` | Response is `{"api", "revision"}`. Keep both ids. A raw `application/yaml` body is rejected with 415. Path parameters written `{customerId}` in the spec are stored as `:customerId`. |
| Create an upstream | `POST /api/orgs/{orgId}/envs/{envId}/upstreams` | `{"name","specification":{"scheme","pass_host":"rewrite","upstream_host","nodes":[{"host","port","weight"}]}}` | Upstreams are created **per environment**. Set `upstream_host` to the backend's own host name (`jsonplaceholder.typicode.com` for the example). Without `pass_host` and `upstream_host`, the backend receives your gateway's host name and every call returns 502. |
| Bind it to the revision | `PATCH /api/orgs/{orgId}/apis/{apiId}/revisions/{revisionId}/upstream-bindings/add` | `{"environmentUpstreams":[{"environmentId","upstreamId"}]}` | Before the deploy. |
| Check the deploy first | `POST /api/orgs/{orgId}/apis/{apiId}/revisions/{revisionId}/deploy/dry-run` | `{"environmentId"}` | Optional. Reports problems without changing anything. |
| Deploy the revision | `POST /api/orgs/{orgId}/apis/{apiId}/revisions/{revisionId}/deploy` | `{"environmentId","force":false}` | The routes answer a few seconds later. A route another deployed API already serves in this environment is refused with 409. |
| Undeploy | `POST /api/orgs/{orgId}/apis/{apiId}/revisions/{revisionId}/undeploy` | `{"environmentId"}` | |
| Delete the API | `DELETE /api/orgs/{orgId}/apis/{apiId}` | — | Undeploy first. |

The `proxy-rewrite` and `request-id` settings are described in the
[Configuration reference](guides.md#configuration-reference).
