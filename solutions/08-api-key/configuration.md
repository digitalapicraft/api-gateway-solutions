# Configuration — Solution 08 — API keys for callers that can't run a token exchange

[Overview](readme.md) · [Business need](business-need.md) · [How it works](how-it-works.md) · [Install](install.md) · **Configuration** · [Test & verify](testing.md) · [Changelog](changelog.md)

---

## Configuration

Source of truth: [`gateway/api-spec.yaml`](gateway/api-spec.yaml). One block
carries the whole solution, and it is on every protected route:

```yaml
helix-auth:
  mode: validate
  validate_auth_type: key-auth
  apikey:
    source: header
    key: X-Device-Key
```

**Read what that block does not contain.** There is no key and no secret. The
route names the *header the key arrives in*; the key itself is issued on the app
credential by the control plane. Unlike the signing secret in
[solution 02](../02-oauth-jwt/), there is nothing here to fill in and nothing to
leak — the same property [solution 06](../06-hmac-auth/) has, for the same
structural reason.

**`apikey` with `source` is mandatory, whatever the schema says.** The published
JSON schema marks it optional. The plugin's own check does not, and a dry-run
rejects the configuration:

```text
property "apikey" with "source" is required when mode is validate
and validate_auth_type is key-auth
```

That is a dry-run catching a real error before deploy, which is the workflow
working — but it costs an hour if you are reading the schema and expecting a
default.

## `secret_validation` is not a second factor

The one field in this plugin whose name will mislead you. From the plugin's own
schema in your org:

> *Key-auth validate only. When true, the credential secret is accepted as an
> **alternative** credential if the api key is absent.*

It **widens** what is accepted. It does not require more. Turning it on so that
"the device must send both the key and the secret" produces the opposite of the
intent: a caller holding only the secret now authenticates too. This package
ships it off, and [`tests/test-plan.yaml`](tests/test-plan.yaml) carries the
manual case that demonstrates the behaviour if you want to see it for yourself.

If you want two independent factors on a route, this is not the plugin —
[solution 06](../06-hmac-auth/) is, because a signature proves possession of a
secret that never travels.

## Header or query parameter

`apikey.source` accepts `header` or `query`. Choose `header`, and treat `query`
as a compatibility escape hatch for a caller that genuinely cannot set one.

A key in a URL is copied into every access log, every proxy log, every referrer
header and every browser history the request passes through, and none of those
were designed to hold credentials. The test plan asserts that a key in the query
string is **rejected** by this configuration — that assertion is the difference
between "we chose headers" and "we assumed headers".
