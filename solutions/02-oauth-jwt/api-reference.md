# API reference — OAuth 2.0 with gateway-issued JWTs

> [Overview](README.md) · [Business need](business-need.md) · [Architecture](architecture.md) · [Guides](guides.md) · [Agent prompt](helix-agent-prompt.md) · [Tests](tests.md) · **API reference**

---

The raw control-plane calls behind [Install it directly](guides.md#install-it-directly),
listed for lookup rather than as a walkthrough. None of it requires custom code. The
full control-plane and plugin documentation is at
[docs.digitalapi.ai/api-gateway](https://docs.digitalapi.ai/api-gateway).

**Before the first call:** replace every `<YOUR_JWT_SIGNING_SECRET>` in
`example/api-spec.yaml` with one long random value. The gateway uses it exactly as
written, and there is no control-plane call that sets it for you.

| Step | Call | Body | Notes |
|---|---|---|---|
| Import the spec | `POST /api/orgs/{orgId}/apis/from-spec` | `multipart/form-data`, part `file` — or a JSON body `{"spec": <document>}` | Attaches `helix-auth` (generate on `/oauth/token`, validate on the `/posts` routes), `request-id` and `cors`. Response is `{"api", "revision"}` — keep both ids. A raw `application/yaml` body is rejected with 415. |
| Create an upstream | `POST /api/orgs/{orgId}/envs/{envId}/upstreams` | `{"name","specification":{"scheme","nodes":[{"host","port","weight"}], ...}}` | Upstreams are created **per environment**. |
| Bind the upstream to the revision | `PATCH /api/orgs/{orgId}/apis/{apiId}/revisions/{revisionId}/upstream-bindings/add` | `{"environmentUpstreams":[{"environmentId","upstreamId"}]}` | Must succeed before the deploy call below. |
| Deploy the revision | `POST /api/orgs/{orgId}/apis/{apiId}/revisions/{revisionId}/deploy` | `{"environmentId","force":false}` | This is what makes the routes live. A live (ACTIVE) revision rejects edits — undeploy or clone it first. |
| List APIs (to get `<API_ID>`) | `GET /api/orgs/{orgId}/apis` | — | Find the imported "Posts API" here, if you didn't keep the id from the import response. |
| Create a product | `POST /api/orgs/{orgId}/products` | `{"name","displayName","apiIds","quota":{"limit":-1}}` | An app reaches the API through a product; without one, every call with a valid token is a 403. Every product needs a `quota` object; `limit: -1` means unlimited. |
| Deploy the product | `POST /api/orgs/{orgId}/envs/{envId}/products/{productId}/deploy` | — | A separate deploy from the revision's. |
| Create a developer | `POST /api/orgs/{orgId}/developers` | `{"firstName","lastName","email"}` | Returns the developer's `id`. |
| Create an app | `POST /api/orgs/{orgId}/developers/{developerId}/envs/{envId}/apps` | `{"name","products":{"<productId>":<rank>},"plugins":{"helix-auth":{}}}` | `developerId` and the environment are **path segments**, not body fields. An empty `helix-auth` object asks for auto-generated credentials: the client id (the credential key) and the client secret. |

Two calls a caller makes, not the control plane — listed so the whole flow is in
one place:

| Step | Call | Notes |
|---|---|---|
| Get a token | `POST /oauth/token` on the gateway, `Authorization: Basic base64(client_id:client_secret)` | Returns `{"access_token","token_type":"Bearer","expires_in":900}`. A wrong secret is a 401 and no token. |
| Call the API | `GET /posts` (or any protected route), `Authorization: Bearer <access_token>` | 401 for a missing, malformed, expired or forged token. |

Not fully nailed down here — confirm against your org's live schema before
scripting this for real: an upstream's `specification` has more optional fields
(load balancing, health checks, TLS) than the minimum shown, and the app's
`plugins` shape beyond an empty auto-generate object.
