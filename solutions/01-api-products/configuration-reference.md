# Configuration reference — API Products with enforced quota

> [Overview](README.md) · [Business need](business-need.md) · [Architecture](architecture.md) · [Guides](guides.md) · [Examples](examples.md) · [Agent prompt](helix-agent-prompt.md) · [Tests](tests.md) · **Configuration reference** · [API reference](api-reference.md)

---

Source of truth: [`example/api-spec.yaml`](example/api-spec.yaml) for the routes
and plugins, and the two products (Free, Pro) created via the API or the UI — see
[Examples](examples.md) for their exact fields. The spec carries four plugins
that apply to every route; two of them are what make this a metered product:

```yaml
# identity — checks the key AND looks up the app's product subscriptions
helix-auth:
  mode: validate
  validate_auth_type: key-auth
  apikey:
    source: header
    key: apikey

# enforcement — spends one unit of the resolved product's quota per request
api-product-enforcer:
  error_policy: fail_close
```

## Fields

| Plugin | Field | Value here | What it means |
|---|---|---|---|
| `helix-auth` | `mode` | `validate` | Checks an existing credential. (`generate`, for issuing new ones, isn't used here.) |
| `helix-auth` | `validate_auth_type` | `key-auth` | A mode of `helix-auth`, not its own plugin. It's also what resolves the product subscription — plain `key-auth` does not. |
| `helix-auth` | `apikey.source` / `apikey.key` | `header` / `apikey` | Where the client id is read from. |
| `api-product-enforcer` | `error_policy` | `fail_close` | The **only** other field it accepts is `ctx_namespace`. No `policy`, no `redis_host` — see below. |

The spec also carries `request-id` (gives a disputed 429 something to search on)
and `cors` (wide open here for the public demo upstream — tighten `allow_origins`
before you point this at your own backend). Both apply to every route.

Full field-by-field reference for `api-product-enforcer` and the other traffic
plugins: [docs.digitalapi.ai — Traffic plugins](https://docs.digitalapi.ai/api-gateway/plugin-reference/plugins-traffic).

A product's `quota` object accepts `limit`, `interval`, `interval_unit`, and
optionally `quota_key_scope` (defaults to `app`; set it to `developer` to pool a
developer's apps into one bucket). `limit: -1` means unlimited.

**The quota is a request count, not a cost.** A cheap read and a 30-second
report each consume exactly one unit. If cost varies a lot by endpoint, split
into separate products per endpoint group, or the quota will misprice your
expensive paths.

## The quota backend isn't in this file

This is the single most common way this solution gets deployed wrong, and nothing
in the route config hints at it.

`api-product-enforcer` doesn't take a backend setting. Whether counting happens
locally or in Redis — and the connection details — live in
`plugin_attr.api-product-enforcer`, in the **gateway's `config.yaml`**, not in the
route.

The default is `local`, which counts inside each node's own memory. So on a
three-node gateway, a product with a 1,000/min quota actually serves roughly
**3,000/min** — each node thinks it's under the limit on its own. You won't notice
this in a single-node test environment. You'll notice it in production, as a quota
that doesn't seem to work.

**More than one node → `quota_policy` must be `redis`.**

## Placeholders used in this package

`<API_ID>`, `<PRODUCT_ID>`, `<ORG_ID>`, `<ENV_ID>` / `<TEST_ENV_ID>`,
`<YOUR_GATEWAY_HOST>`. None of these are real hosts, org ids, or credentials —
replace all of them before you deploy.
