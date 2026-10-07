# API reference — per-partner key material, fetched at request time

> [Overview](README.md) · [Business need](business-need.md) · [Architecture](architecture.md) · [Guides](guides.md) · [Agent prompt](helix-agent-prompt.md) · [Tests](tests.md) · **API reference**

---

The raw control-plane calls behind [Install it directly](guides.md#install-it-directly),
listed for lookup rather than as a walkthrough. None of it requires custom code.
The full control-plane and plugin documentation is at
[docs.digitalapi.ai/api-gateway](https://docs.digitalapi.ai/api-gateway).

The API needs an upstream bound and its revision deployed **before** any route is
reachable — three calls the spec import doesn't do for you, easy to miss since
nothing fails loudly if you skip them.

| Step | Call | Body | Notes |
|---|---|---|---|
| Import the spec | `POST /api/orgs/{orgId}/apis/from-spec` | `multipart/form-data`, part `file` — or a JSON body `{"spec": <document>}` | Attaches `key-value-map`, `pgp-crypto`, `proxy-rewrite` and `request-id`. Response is `{"api", "revision"}` — keep both ids. A raw `application/yaml` body is rejected with 415. |
| Create an upstream | `POST /api/orgs/{orgId}/envs/{envId}/upstreams` | `{"name","specification":{"scheme","nodes":[{"host","port","weight"}], ...}}` | Upstreams are created **per environment**. The spec expects `httpbin.org` over `https`. |
| Bind the upstream to the revision | `PATCH /api/orgs/{orgId}/apis/{apiId}/revisions/{revisionId}/upstream-bindings/add` | `{"environmentUpstreams":[{"environmentId","upstreamId"}]}` | Must succeed before the deploy call below. |
| Deploy the revision | `POST /api/orgs/{orgId}/apis/{apiId}/revisions/{revisionId}/deploy` | `{"environmentId","force":false}` | This is what makes the routes live. `force: true` replaces an existing deployment of the same revision. |
| List APIs (to get `<API_ID>`) | `GET /api/orgs/{orgId}/apis` | — | Find the id of the imported "Partner Documents API" here, if you didn't keep it from the import response. |

**There is no control-plane call for key-value entries** on this build. Entries are
written only through the package's own registration route on the gateway:

| Step | Call | Body | Notes |
|---|---|---|---|
| Register or rotate a partner's key | `POST https://<YOUR_GATEWAY_HOST>/partners/keys` with header `X-Partner-Id` | `{"public_key": "<armored OpenPGP public key>"}` | Replaces any previous value for that id. Administrative — protect it before real use. The status reflects the upstream echo, not the store write. |
| Fetch a partner's document | `GET https://<YOUR_GATEWAY_HOST>/partners/documents` with header `X-Partner-Id` | — | `200` with base64 of an armored PGP message, or `500` when no key is registered. A stored but unusable key returns `200` with the error body. |

Not fully nailed down here — confirm against your org's live schema before
scripting this for real: an upstream's `specification` has more optional fields
(load balancing, health checks, TLS) beyond the minimum shown.
