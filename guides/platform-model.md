# The platform model

Read this before configuring anything. The mental model from other gateways does not transfer, and these five points are where it diverges.

---

The mental model from other API gateways does not transfer cleanly. Four things
account for most early mistakes:

- **The importable artifact is an OpenAPI 3.0.3 document.** Gateway policy rides
  along inside it as `x-helix-gateway.plugins` — at the document root for
  API-wide policy, under `paths.<path>.<method>` for a single route. You don't
  hand-write route JSON, and you don't keep the spec and the config in two
  places.
- **Plugin execution is priority-ordered, not document-ordered.** A plugin can
  only read a `ctx.*` value that a *higher-priority* plugin on the same route
  already produced. Listing plugins in the order you want them to run does
  nothing.
- **Identity is `helix-auth` — for tokens the gateway itself issues.** In
  `validate` mode it resolves the calling app *and* the product it's subscribed
  to. It takes a `validate_auth_type` of `key-auth` (static app key) or `jwt-auth`
  (a JWT the gateway signed in `generate` mode). Note: `key-auth` and `jwt-auth`
  are **not** standalone plugins on this build — they exist only as
  `validate_auth_type` values of `helix-auth`.
- **When an external IdP issues the tokens, it's `openid-connect` instead.**
  `helix-auth` has no JWKS URL, issuer or audience field — and its schema is
  `additionalProperties: false`, so one cannot be added. It cannot verify a token
  it did not mint. For Okta, Entra ID, Auth0 or Keycloak use `openid-connect` with
  `discovery`, and set `unauth_action: deny` — the default is `auth`, which
  answers an unauthenticated API call with a **302 redirect to the IdP's login
  page**. `openid-connect` is not on every build; check
  `GET /orgs/{orgId}/plugin-schemas` first. See
  [solution 05](solutions/05-okta-jwt/).
- **Per-caller metering is API Products, counted per app.** The quota lives on
  the product, not on the route, and is keyed on the credential — not on an IP,
  not on `consumer_name`. Solution 01 covers this in full.

The platform's own words for developers, apps, products and services are in **[Vocabulary](vocabulary.md)**.
