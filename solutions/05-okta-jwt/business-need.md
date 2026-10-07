# Verify Okta-issued JWTs at the API gateway

> Your company already uses Okta to sign people and apps in. Your APIs don't —
> they still check a fixed key that someone emailed out years ago, never expires,
> and is hard to take back. Everyone agrees the APIs should check Okta's tokens
> instead. It never gets done, because every service would need its own code to
> do the checking.
>
> **The gateway can check Okta's tokens for every API at once, and no service has
> to change.**

- **How long a stolen credential works: forever → minutes.** Okta hands out
  short-lived tokens on request, and they expire by themselves.
- **Cutting off a caller: track down every copy of the key → switch the app off in
  Okta.** One place decides who can call your APIs.
- **Code that checks tokens: one copy per service → one place, the gateway.** No
  service is changed.

Checking the token's signature is the easy part. The real choice is what else to
check, because out of the box the gateway behaves as if a person were logging in
through a browser, not a program calling an API:

| What to check | Out of the box | What an API needs |
|---|---|---|
| A call with no token | sent to Okta's login page | turned away with a 401 |
| Whose tokens to trust | any that pass the signature check, whichever server issued them | only your Okta server's |
| That the keys really come from Okta | not checked | checked, and refreshed hourly |
| Which API the token was meant for | **never checked** — a token for another of your APIs gets in | tell them apart with scopes |

It checks who is calling. It doesn't decide what they may do, count their calls,
or cancel a token before it expires — and your gateway needs the `openid-connect`
plugin. [The full comparison, how it works, and what this does not buy you are in
the README](README.md#business-need).

*Also searched as: Okta JWT validation at the API gateway · verify external IdP
tokens · JWKS signature verification · OIDC bearer-only API auth · Auth0 / Entra ID
/ Keycloak token verification · replace API keys with Okta · bring APIs under SSO.*
