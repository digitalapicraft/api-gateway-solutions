# API reference — checking Okta-issued tokens at the gateway

> [Overview](README.md) · [Business need](business-need.md) · [Architecture](architecture.md) · [Guides](guides.md) · [Agent prompt](helix-agent-prompt.md) · [Tests](tests.md) · **API reference**

---

The raw control-plane calls behind [Install it directly](guides.md#install-it-directly),
listed for lookup rather than as a walkthrough. None of it requires custom code.
The full control-plane and plugin documentation is at
[docs.digitalapi.ai/api-gateway](https://docs.digitalapi.ai/api-gateway).

This solution needs **no products, developers or apps**. Okta issues the tokens,
so the gateway side is the API alone: check the plugin, import, upstream, bind,
deploy.

| Step | Call | Body | Notes |
|---|---|---|---|
| Check the plugin exists | `GET /api/orgs/{orgId}/plugin-schemas?page=1&size=300` | — | `openid-connect` must be in the list. If it isn't, this solution cannot be deployed in that org. |
| Import the spec | `POST /api/orgs/{orgId}/apis/from-spec` | `multipart/form-data`, part `file` — or a JSON body `{"spec": <document>}` | Replace the four `<OKTA_...>` placeholders first: they are used exactly as written. Response is `{"api", "revision"}` — keep both ids. A raw `application/yaml` body is rejected with 415. |
| Create an upstream | `POST /api/orgs/{orgId}/envs/{envId}/upstreams` | `{"name","specification":{"scheme","nodes":[{"host","port","weight"}], ...}}` | Upstreams are created **per environment**. |
| Bind the upstream to the revision | `PATCH /api/orgs/{orgId}/apis/{apiId}/revisions/{revisionId}/upstream-bindings/add` | `{"environmentUpstreams":[{"environmentId","upstreamId"}]}` | The upstream must be in the same environment. One from a different environment fails the deploy with `Upstream not configured for environment`. |
| Deploy the revision | `POST /api/orgs/{orgId}/apis/{apiId}/revisions/{revisionId}/deploy` | `{"environmentId","force":false}` | This is what makes the routes live, and where a missing `bearer_only` is caught (`session.secret is required`). |
| List APIs (to get `<API_ID>`) | `GET /api/orgs/{orgId}/apis` | — | Find the id of the imported "Partner Posts API" here, if you didn't keep it from the import response. |

The token request itself goes to **Okta**, not to the gateway:
`POST https://<your-okta-domain>/oauth2/<authServerId>/v1/token` with the
application's client id and secret (HTTP Basic) and
`grant_type=client_credentials`. See [Tests](tests.md) for the full form.

Not fully nailed down here — confirm against your org's live schema before
scripting this for real: an upstream's `specification` has many more optional
fields (load balancing, health checks, TLS) beyond the minimum shown.
