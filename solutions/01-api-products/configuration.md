# Configuration — Solution 01 — API Products: sell tiers you can actually enforce

[Overview](readme.md) · [Business need](business-need.md) · [How it works](how-it-works.md) · [Install](install.md) · **Configuration** · [Test & verify](testing.md) · [Changelog](changelog.md)

---

## Configuration

Source of truth: [`gateway/api-spec.yaml`](gateway/api-spec.yaml) and
[`gateway/products.json`](gateway/products.json). Two API-wide blocks carry the
solution:

```yaml
# identity — resolves the app AND its product subscriptions
helix-auth:
  mode: validate
  validate_auth_type: key-auth
  apikey:
    source: header
    key: apikey

# enforcement — meters against the resolved product's quota
api-product-enforcer:
  error_policy: fail_close
```

That's the entire enforcer configuration. **It accepts only `error_policy` and
`ctx_namespace`.** If you're reaching for a `policy: redis` or a `redis_host` here,
stop — see the next section.

`error_policy: fail_close` means a quota-backend outage returns 503. Switching to
`fail_open` is a deliberate commercial decision: you're choosing to serve unmetered
traffic during an incident rather than serve errors. Both are defensible. Pick one
knowingly.

## The quota backend is not in this file

**This is the single most common way the solution is deployed wrong, and nothing in
the route config hints at it.**

`api-product-enforcer` takes no backend configuration. The `local`-vs-`redis`
choice and the connection settings live in `plugin_attr.api-product-enforcer` in
the **gateway's `config.yaml`**.

The default is `local`, which counts in each node's own memory. So on a
three-node gateway, a product with a 1,000/min quota serves roughly **3,000/min** —
each node independently believes it's under the limit.

You will not notice this in a single-node test environment. You will notice it in
production, as a quota that seems not to work, and you'll spend the afternoon
inspecting the route config where the answer isn't.

**More than one node → `quota_policy` must be `redis`.**

## The tier limits are illustrative — set them commercially

The numbers in this spec are a sample, not a recommendation. Two rules decide
the real ones, and neither is a scaling exercise:

- **Free must be unusable for production.** If a free tier carries a real
  workload, nobody upgrades, and the product has no commercial ladder.
- **Enterprise must match a contractual number.** It is whatever you signed,
  not Pro multiplied by ten.

Treat every value here as one to set against what you actually sell.
