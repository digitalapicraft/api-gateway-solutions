# API reference — OpenPGP at the edge, in both directions

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
| Import the spec | `POST /api/orgs/{orgId}/apis/from-spec` | `multipart/form-data`, part `file` — or a JSON body `{"spec": <document>}` | Import a copy with `<PGP_PRIVATE_KEY>` and `<PGP_PUBLIC_KEY>` replaced by real armored blocks — they are used verbatim. Attaches `pgp-crypto`, `proxy-rewrite` and `request-id`. Response is `{"api", "revision"}` — keep both ids. A raw `application/yaml` body is rejected with 415. |
| Create an upstream | `POST /api/orgs/{orgId}/envs/{envId}/upstreams` | `{"name","specification":{"scheme","nodes":[{"host","port","weight"}], ...}}` | Upstreams are created **per environment**. The spec expects `httpbin.org` over `https`. |
| Bind the upstream to the revision | `PATCH /api/orgs/{orgId}/apis/{apiId}/revisions/{revisionId}/upstream-bindings/add` | `{"environmentUpstreams":[{"environmentId","upstreamId"}]}` | Must succeed before the deploy call below. |
| Deploy the revision | `POST /api/orgs/{orgId}/apis/{apiId}/revisions/{revisionId}/deploy` | `{"environmentId","force":false}` | This is what makes the routes live. `force: true` replaces an existing deployment of the same revision. |
| List APIs (to get `<API_ID>`) | `GET /api/orgs/{orgId}/apis` | — | Find the id of the imported "Statements API" here, if you didn't keep it from the import response. |

Rotating a key is a spec change, so it needs an **INACTIVE** revision: undeploy
first, or clone the revision to keep a rollback target, then deploy again.

Not fully nailed down here — confirm against your org's live schema before
scripting this for real: an upstream's `specification` has more optional fields
(load balancing, health checks, TLS) beyond the minimum shown.
