# API reference — one outbound call, then injection

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
reachable — the spec import doesn't do either for you, and nothing fails loudly
if you skip them. The profile service the callout calls is **not** an upstream:
its address lives in the callout's `uri`, inside the spec.

| Step | Call | Body | Notes |
|---|---|---|---|
| [Import the spec](https://docs.digitalapi.ai/api-gateway/api-reference/api-spec/api-import) | `POST /api/orgs/{orgId}/apis/from-spec` | `multipart/form-data`, part `file` (`-F "file=@example/api-spec.yaml"`) — or a JSON body `{"spec": <document>}` | Creates the API and its first revision with `service-callout`, `proxy-rewrite` and `request-id`. Response is `{"api", "revision"}` — keep both ids. With the file upload, send only the `authorization` header: a JSON `content-type` header breaks it. A raw `application/yaml` body is rejected with HTTP 415 (unsupported content type). |
| [Create an upstream](https://docs.digitalapi.ai/api-gateway/api-reference/api-spec/upstreams) | `POST /api/orgs/{orgId}/envs/{envId}/upstreams` | `{"name","specification":{"scheme","pass_host":"rewrite","upstream_host","nodes":[{"host","port","weight"}], ...}}` | Point it at `httpbin.org` for the example, or at your own backend. Set `pass_host` to `rewrite` and `upstream_host` to the backend's host: without them the backend gets the gateway's host and every call returns HTTP 502 (bad gateway). |
| [Bind the upstream to the revision](https://docs.digitalapi.ai/api-gateway/api-reference/api-spec/revisions) | `PUT /api/orgs/{orgId}/apis/{apiId}/revisions/{revisionId}/envs/{envId}/bind-upstream` | `{"upstreamId"}` | Must succeed before the deploy call below. |
| [Deploy the revision](https://docs.digitalapi.ai/api-gateway/api-reference/api-spec/revisions) | `POST /api/orgs/{orgId}/apis/{apiId}/revisions/{revisionId}/envs/{envId}/deploy` | `{"force":false}` | This is what makes the routes live. `force: true` replaces an existing deployment of the same revision. |
| [List APIs (to get `<API_ID>`)](https://docs.digitalapi.ai/api-gateway/api-reference/api-spec/apis) | `GET /api/orgs/{orgId}/apis` | — | Find the id of the imported "Storefront API" here, if you didn't keep it from the import response. |

No products, developers or apps are created: the package ships unauthenticated.
To add identity, see [Guides → Variations](guides.md#variations).

An upstream's `specification` has more optional fields (load balancing, health
checks, TLS) than the minimum shown. Confirm against your org's live schema before
scripting this for real.
