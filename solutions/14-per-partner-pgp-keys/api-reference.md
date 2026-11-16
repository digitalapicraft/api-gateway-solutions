# API reference — per-partner key material, fetched at request time

> [Overview](README.md) · [Business need](business-need.md) · [Architecture](architecture.md) · [Guides](guides.md) · [Agent prompt](helix-agent-prompt.md) · [Tests](tests.md) · **API reference**

---

The raw control-plane calls behind
[Install it directly](guides.md#install-it-directly), listed for lookup rather than
as a walkthrough. None of it requires custom code. Each step links to its page in
the
[control-plane API reference](https://docs.digitalapi.ai/api-gateway/api-reference/api-reference);
plugin fields are in the
[plugin reference](https://docs.digitalapi.ai/api-gateway/plugin-reference/plugin-reference).

The API needs an upstream bound and its revision deployed **before** any route is
reachable — three calls the spec import doesn't do for you, easy to miss since
nothing fails loudly if you skip them. Import your copy of the spec with the
registration route already protected, as
[Install it directly](guides.md#install-it-directly) describes, never
`example/api-spec.yaml` as it is.

| Step | Call | Body | Notes |
|---|---|---|---|
| [Import the spec](https://docs.digitalapi.ai/api-gateway/api-reference/api-spec/api-import) | `POST /api/orgs/{orgId}/apis/from-spec` | `multipart/form-data`, part `file` — or a JSON body `{"spec": <document>}` | Your protected copy attaches `helix-auth`, `api-product-enforcer`, `key-value-map`, `pgp-crypto`, `proxy-rewrite` and `request-id`. Response is `{"api", "revision"}` — keep both ids. A raw `application/yaml` body is rejected with 415. |
| [Create an upstream](https://docs.digitalapi.ai/api-gateway/api-reference/api-spec/upstreams) | `POST /api/orgs/{orgId}/envs/{envId}/upstreams` | `{"name","specification":{"scheme","pass_host":"rewrite","upstream_host","nodes":[{"host","port","weight"}], ...}}` | Upstreams are created **per environment**. The spec expects `httpbin.org` over `https`. Set `pass_host` to `rewrite` and `upstream_host` to the backend's host: without them the backend gets the gateway's host and every call returns HTTP 502 (bad gateway). |
| [Bind the upstream to the revision](https://docs.digitalapi.ai/api-gateway/api-reference/api-spec/revisions) | `PUT /api/orgs/{orgId}/apis/{apiId}/revisions/{revisionId}/envs/{envId}/bind-upstream` | `{"upstreamId"}` | Must succeed before the deploy call below. |
| [Deploy the revision](https://docs.digitalapi.ai/api-gateway/api-reference/api-spec/revisions) | `POST /api/orgs/{orgId}/apis/{apiId}/revisions/{revisionId}/envs/{envId}/deploy` | `{"force":false}` | This is what makes the routes live. `force: true` replaces an existing deployment of the same revision. |
| [Create the operators product](https://docs.digitalapi.ai/api-gateway/api-reference/api-spec/products) | `POST /api/orgs/{orgId}/products` | `{"name","displayName","apiIds":["<API_ID>"],"quota":{"limit","interval","interval_unit"}}` | Every product needs a quota object. Add this API to no other product: an app on any product that includes it gets through the registration route. |
| [Deploy the product](https://docs.digitalapi.ai/api-gateway/api-reference/api-spec/products) | `POST /api/orgs/{orgId}/envs/{envId}/products/{productId}/deploy` | — | A separate deploy from the API's. An app can only subscribe to a product deployed to its environment. |
| [Create a developer](https://docs.digitalapi.ai/api-gateway/api-reference/api-spec/developers) | `POST /api/orgs/{orgId}/developers` | `{"firstName","lastName","email"}` | Returns the developer's id. |
| [Create an operator app](https://docs.digitalapi.ai/api-gateway/api-reference/api-spec/apps) | `POST /api/orgs/{orgId}/developers/{developerId}/envs/{envId}/apps` | `{"name","displayName","products":{"<PRODUCT_ID>":1},"plugins":{"helix-auth":{}}}` | One per operator. `displayName` is required: without it the call is refused with 400 `Display name is required`. `products` is a `{productId: rank}` map; the empty `helix-auth` object asks the control plane to create the key and secret. The operator sends the key in `X-Admin-Key`. |
| [List APIs (to get `<API_ID>`)](https://docs.digitalapi.ai/api-gateway/api-reference/api-spec/apis) | `GET /api/orgs/{orgId}/apis` | — | Find the id of the imported "Partner Documents API" here, if you didn't keep it from the import response. |

**There is no control-plane call for key-value entries** on this build. Entries are
written only through the package's own registration route on the gateway:

| Step | Call | Body | Notes |
|---|---|---|---|
| Register or rotate a partner's key | `POST https://<YOUR_GATEWAY_HOST>/partners/keys` with headers `X-Admin-Key` (an operator app's key) and `X-Partner-Id` | `{"public_key": "<armored OpenPGP public key>"}` | Replaces any previous value for that id. No key, or one that belongs to no app: 401. An app not on the operators product: 403. Either way nothing is stored. A 200 reflects the upstream echo, not the store write. |
| Fetch a partner's document | `GET https://<YOUR_GATEWAY_HOST>/partners/documents` with header `X-Partner-Id` | — | `200` with base64 of an armored PGP message, or `500` when no key is registered. A stored but unusable key returns `200` with the error body. |

Not fully nailed down here — confirm against your org's live schema before
scripting this for real: an upstream's `specification` has more optional fields
(load balancing, health checks, TLS) beyond the minimum shown, and the app call's
`plugins` shape can differ between versions of the gateway.
