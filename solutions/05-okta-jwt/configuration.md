# Configuration — Solution 05 — OAuth with Okta: verify the token, don't issue it

[Overview](readme.md) · [Business need](business-need.md) · [How it works](how-it-works.md) · [Install](install.md) · **Configuration** · [Test & verify](testing.md) · [Changelog](changelog.md)

---

## Configuration

Four values, all literal. **This build does not resolve `<ENV:...>` or `${...}`** —
whatever string sits in the field is used verbatim. Fill them in and keep the
completed spec out of version control.

### `use_jwks: true` is required, and is not in the plugin schema

Omit it and **every token is rejected**, including a valid one, with
`error_description="no endpoint URI for introspection"`. Without it the plugin
does not verify the JWT against the JWKS at all — it falls back to asking the IdP
to introspect the token, and neither Auth0 nor an Okta org authorization server
publishes an introspection endpoint.

The field is absent from all 49 properties `GET /orgs/{orgId}/plugin-schemas`
returns. It is accepted because `openid-connect` does not set
`additionalProperties: false`, and it is persisted on the revision. **Do not
delete it because a schema dump doesn't list it.**

| Placeholder | Where it comes from |
|---|---|
| `<OKTA_DISCOVERY_URL>` | `https://<your-okta-domain>/oauth2/<authServerId>/.well-known/openid-configuration` — or `https://<your-okta-domain>/.well-known/openid-configuration` for the org authorization server |
| `<OKTA_ISSUER_URL>` | the `issuer` value **that discovery document reports**. Fetch it and copy it; do not retype it |
| `<OKTA_CLIENT_ID>` | the Okta application's client id |
| `<OKTA_CLIENT_SECRET>` | its client secret — schema-required even though local JWKS verification never uses it |

### The four defaults you must change

The plugin's defaults are tuned for browser login. For an API, four of them are
actively wrong, and each one fails in a way that does not look like a
configuration error.

| Field | Default | Why it's wrong here | Set to |
|---|---|---|---|
| `bearer_only` | `false` | The deploy is **rejected** — `property "session.secret" is required when "bearer_only" is false`. It is also what makes an unauthenticated call return 401 rather than a 302 redirect to the IdP login page. Checked at deploy, not import | `true` |
| `unauth_action` | `auth` | Says the same thing as `bearer_only` in newer vocabulary. **Redundant** while `bearer_only: true` is set — tested: no-token still returns 401, not 302. Set for clarity, not necessity | `deny` |
| `ssl_verify` | `false` | The gateway fetches Okta's signing keys — the entire root of trust — over TLS **without verifying Okta's certificate** | `true` |
| `accept_unsupported_alg` | `true` | Documented as *"Ignore ID token signature to accept unsupported signature algorithm"* | `false` |
| `claim_validator` | *(absent)* | Nothing beyond the signature is checked. Any correctly signed token from any issuer that plugin can reach is accepted | pin `issuer.valid_issuers` |

And one more that is not wrong, only slow to hurt: `jwk_expires_in` defaults to
`86400`. If Okta rotates a signing key, a day-long cache can reject freshly
issued, perfectly valid tokens until it expires. The spec sets `3600`.
