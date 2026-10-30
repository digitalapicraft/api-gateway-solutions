# API reference — Maintenance mode

> [Overview](README.md) · [Business need](business-need.md) · [Architecture](architecture.md) · [Guides](guides.md) · [Agent prompt](helix-agent-prompt.md) · [Tests](tests.md) · **API reference**

---

The raw control-plane calls behind [Install it directly](guides.md#install-it-directly)
and [the switch](guides.md#switch-maintenance-on), listed for lookup rather
than as a walkthrough. Every call takes `authorization: Bearer <token>`. The
full control-plane and plugin documentation is at
[docs.digitalapi.ai/api-gateway](https://docs.digitalapi.ai/api-gateway).

| Step | Call | Body | Notes |
|---|---|---|---|
| Import the spec | `POST /api/orgs/{orgId}/apis/from-spec` | `multipart/form-data`, part `file`, or a JSON body `{"spec": <document>}` | Response is `{"api", "revision"}`. Keep both ids. A raw `application/yaml` body is rejected with 415. |
| Create an upstream | `POST /api/orgs/{orgId}/envs/{envId}/upstreams` | `{"name","specification":{"scheme","pass_host":"rewrite","upstream_host","nodes":[{"host","port","weight"}]}}` | Upstreams are created **per environment**. Without `pass_host` and `upstream_host`, the backend receives your gateway's host name and every call returns 502. |
| Bind it to the revision | `PATCH /api/orgs/{orgId}/apis/{apiId}/revisions/{revisionId}/upstream-bindings/add` | `{"environmentUpstreams":[{"environmentId","upstreamId"}]}` | Before the first deploy. A revision needs an upstream to deploy, even one whose every call is answered by the gateway. |
| Deploy the revision | `POST /api/orgs/{orgId}/apis/{apiId}/revisions/{revisionId}/deploy` | `{"environmentId","force":false}` | Makes the routes live. With another revision of the API already live in that environment, `force:false` is refused with 409. |
| List revisions | `GET /api/orgs/{orgId}/apis/{apiId}/revisions` | — | Paged: `content[]` with `id`, `revisionNumber`, `state`. The live one is `ACTIVE`. |
| Clone a revision | `POST /api/orgs/{orgId}/apis/{apiId}/revisions/{revisionId}/clone` | — | Returns the new `INACTIVE` revision. It keeps the routes, plugins and upstream mapping of the one it copies. |
| Read a revision | `GET /api/orgs/{orgId}/apis/{apiId}/revisions/{revisionId}` | — | `serviceSpec.plugins` holds the plugins that cover every route, `mocking` among them. |
| Change its API-wide plugins | `PUT /api/orgs/{orgId}/apis/{apiId}/revisions/{revisionId}/service-spec` | `{"serviceSpec": {…}}`, the whole object | Replaces the whole service spec, so send every plugin back, not only `mocking`. Only an `INACTIVE` revision can be changed; a live one is 409 `Only INACTIVE revisions can be updated`. |
| Switch on, or back | `POST /api/orgs/{orgId}/apis/{apiId}/revisions/{revisionId}/deploy` | `{"environmentId","force":true}` | Replaces the live revision with this one. The replaced revision becomes `INACTIVE` and is kept unchanged. The UI's **Force Deploy**. |
| Dry-run a deploy | `POST /api/orgs/{orgId}/apis/{apiId}/revisions/{revisionId}/deploy/dry-run` | `{"environmentId"}` | Checks a deploy without making it. |

The `mocking` settings are described in the
[Configuration reference](guides.md#configuration-reference).
