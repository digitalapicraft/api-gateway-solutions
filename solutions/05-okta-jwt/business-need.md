# Put your APIs behind the identity provider you already own

> [Overview](README.md) · **Business need** · [Architecture](architecture.md) · [Guides](guides.md) · [Agent prompt](helix-agent-prompt.md) · [Tests](tests.md) · [API reference](api-reference.md)

---

> Joiners, movers and leavers already flow through Okta. The APIs are not in it.
> They accept static keys handed out by email, and nobody can say how many are
> still live.
>
> **The credential should be a token Okta issues on demand, not a secret you hand
> out and lose track of.**

- **Removing access becomes real.** Disable a caller in Okta and its access ends
  when its current token expires, instead of after a hunt for every copy of a key.
- **The APIs join the access review that already runs**, rather than needing a
  separate one that doesn't exist.
- **No backend release.** The gateway checks the token once, in front of every
  route. No service changes, and nobody writes token-checking code N times.

The one decision that matters is who issues the token:

| Your situation | What to use |
|---|---|
| Okta, Entra ID, Auth0 or Keycloak already issues tokens to these callers | The gateway only checks them — this solution |
| No identity provider, and callers are your own partner apps | The gateway issues and checks — [solution 02](../02-oauth-jwt/) |

It proves *who* is calling, not *what* they may do, and an issued token stays
valid until it expires. No savings figures are claimed: the benefits describe how
the system works, not measured results. More in
[Architecture](architecture.md#when-to-use-this).

*Also searched as: Okta API gateway · verify Okta JWT · OIDC token validation ·
JWKS validation at the gateway · external identity provider JWT · Auth0 / Entra ID
access token check · replace API keys with SSO.*
