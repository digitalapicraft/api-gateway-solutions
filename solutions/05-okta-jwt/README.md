# Solution 05 — OAuth with Okta: let Okta issue the tokens, and have the gateway check them

> **Overview** · [Business need](business-need.md) · [Architecture](architecture.md) · [Guides](guides.md) · [Agent prompt](helix-agent-prompt.md) · [Tests](tests.md) · [API reference](api-reference.md)

**In short:** your company already uses Okta to manage who can sign in. This
solution makes your APIs accept the tokens Okta issues, and turn away everything
else, without changing a line of code in any backend service.

| | |
|---|---|
| **Time to try it** | About 20 minutes |
| **Difficulty** | 🟢 Beginner, *if* your org has the `openid-connect` plugin. Check that first. |
| **What you'll need** | An org that includes `openid-connect` (not every org does), an Okta tenant with an authorization server and an application, and one upstream. The example uses a public test service, so you need no backend of your own. |

---

## What is token verification at the gateway?

When a caller wants to use your API, it first asks Okta for an **access token**: a
short-lived, signed pass that says who it is. It then sends that token with every
request. Something has to check the token is genuine before the request is let
through.

This solution makes the gateway that something. The gateway **only checks**
tokens. It never issues them. Okta keeps doing everything it already does: storing
users and apps, deciding who gets a token, and deciding how long a token lasts.

Think of a concert. The ticket office (Okta) sells the tickets. The person at the
door (the gateway) checks that each ticket is real and for this venue, and does
not sell tickets of their own.

## The use case

> *"We already run Okta. Every employee, every partner, every service account is
> in there. But our APIs don't check Okta tokens — they check an API key we
> emailed someone in 2021. Security keeps asking when the APIs will 'join SSO'
> and the answer is always 'after the next release'."*

Three things are true at once, which is why this stays unsolved for years:

- **Okta is not the problem.** It is already deployed and already issuing tokens.
- **The APIs are the problem.** Checking a token properly means fetching Okta's
  public keys, caching them, and checking the signature, issuer and expiry, in
  every service and every language.
- **Nobody wants to write that code**, so it gets put off and the old key stays.

## What it gives you

- **One place that checks every token**, configured once, in front of every route.
- **Okta-issued tokens accepted, everything else refused** before your backend
  sees the request.
- **No change to your services.** They never learn that authentication changed.
- **Okta stays off the request path.** The gateway caches Okta's public keys and
  checks tokens itself, so a slow moment at Okta does not slow your API.

## Benefits

- **Removing access actually works.** Disable an app in Okta and it stops getting
  tokens. Its current token stops working when it expires.
- **One answer to "who can call this?"** Access is an Okta assignment, not a
  spreadsheet of keys.
- **A leaked credential is worth minutes, not years.** A token expires on its own.
  A static key works until someone notices.
- **Your APIs join the access reviews you already run** against Okta.

## Example

Say you have a partner posts API and Okta already knows your partners' apps.

| A caller sends… | It gets back |
|---|---|
| No token | HTTP 401 (not authenticated) |
| A valid token from your Okta | 200 and the data |
| A forged or unsigned token | 401 |
| A real token from a *different* Okta authorization server | 401 |

**Setting this up in the gateway's UI takes four short steps:** check the
`openid-connect` plugin is in your org, fill your four Okta values into the
example spec, import it, then give it an upstream and deploy it.
[Full click-by-click walkthrough →](guides.md#build-it-in-the-ui)

[Build it any of three ways, then see it work →](guides.md)

## Where to go next

- **Want the business case first?** [Business need](business-need.md) explains why
  this matters, in plain terms.
- **Want to understand how it works?** [Architecture](architecture.md) covers who
  issues the token, who checks it, and why the built-in `helix-auth` plugin can't
  do this job.
- **Ready to build it?** [Guides](guides.md) walks you through it step by step.
- **Want the full product documentation?** Every plugin, screen and API call is
  covered at [docs.digitalapi.ai/api-gateway](https://docs.digitalapi.ai/api-gateway).

## Related solutions

- **[02 — OAuth 2.0 with JWT](../02-oauth-jwt/)** — the mirror image: there is no
  identity provider, so the gateway *issues* the tokens itself. Pick one; you do
  not want both on the same route.
- **[01 — API Products](../01-api-products/)** — usage limits per app. Note that a
  token Okta issued does not identify a gateway app, so quotas do not follow from
  this solution on their own.
- **[04 — Analytics](../04-analytics/)** — every call is recorded, whichever plugin
  checked it.
