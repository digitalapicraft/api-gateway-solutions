# Configuration — Solution 03 — Serve a SOAP backend as REST/JSON

[Overview](readme.md) · [Business need](business-need.md) · [How it works](how-it-works.md) · [Install](install.md) · **Configuration** · [Test & verify](testing.md) · [Changelog](changelog.md)

---

## Configuration

Source of truth: [`gateway/api-spec.yaml`](gateway/api-spec.yaml). Three blocks on
`/locations` carry the mediation:

```yaml
# 1. reject first — no point transforming a body you're about to discard
helix-auth:
  mode: validate
  validate_auth_type: jwt-auth
  signing_secret: "<YOUR_JWT_SIGNING_SECRET>"

# 2. path only — NO Content-Type override (it runs before the transform and defeats it)
proxy-rewrite:
  uri: <SOAP_HANDLER_PATH>

# 3. request conversion is OFF by default — turn it on; response fires on Accept: application/json
xml-to-json:
  transform_request: true
  transform_response: true
```

`xml-to-json` needs `transform_request: true` explicitly — the default is
`false`, so an empty block converts the response only (verified). The response
side additionally requires the client to send `Accept: application/json`. For
namespaced or attribute-heavy envelopes there are more fields
(`property_naming`, `array_item_name`, `content_types`, …) — get them from
`get_plugin_config` in your own org.

## Never apply `validate` API-wide

`helix-auth` validate is applied per route, deliberately. Hoisting it to the
document root is the change an editor is most likely to make for tidiness, and
it protects `POST /oauth/token` as well — so obtaining a first token requires
already having one, and every request on the API returns 401 including the one
that is supposed to fix that.

The spec is correct as written. This note exists because the wrong version
looks tidier.
