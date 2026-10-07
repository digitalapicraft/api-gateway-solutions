# Solution 02 — OAuth 2.0 with JWT: make partners sign in, without changing your backend

> **Overview** · [Business need](business-need.md) · [Architecture](architecture.md) · [Guides](guides.md) · [Agent prompt](helix-agent-prompt.md) · [Tests](tests.md) · [API reference](api-reference.md)

**In short:** the gateway gives each partner app a short-lived token in exchange
for its client id and secret, then checks that token on every call. Your backend
does not change, and it never sees a call that failed the check.

| | |
|---|---|
| **Time to try it** | About 15 minutes |
| **Difficulty** | 🟢 Beginner — no coding needed |
| **What you'll need** | A free test account, and a long random value to use as your signing secret. The sample backend is public, so you don't need one of your own. |

---

## What is OAuth 2.0 client credentials?

**OAuth 2.0** is the standard way for one piece of software to prove who it is to
another. In the **client credentials** version, each partner app holds two values:
a **client id** and a **client secret**. The app sends them once to a token
endpoint and gets back a **token**, a signed pass that expires after a few minutes.
It then sends the token with every API call, instead of the secret.

It works like a hotel key card. You show your ID at the front desk once, you get a
card that opens your door, and the card stops working at checkout. If you lose the
card, it is only useful to someone else until it expires.

The token here is a **JWT** (JSON Web Token): a small, signed piece of text. The
gateway signs it when it issues it, and checks that signature on every call, so it
can tell a token it made from one somebody else made up.

## The use case

> *"Our partner API has been public since 2019. Everybody knows it needs auth.
> The problem isn't agreement — it's that the service is a shared monolith on a
> quarterly release train, the team that owns it has a roadmap through Q3, and
> 'add OAuth' means a six-week release plus a coordinated migration for eleven
> partners. So it stays public, and we put it on the risk register instead."*

Three things are true at once, which is why this stays stuck for years:

- **The API needs authentication.** Anyone with the URL can call it.
- **The backend cannot ship it soon.** Authentication touches every part of the
  service, and the release schedule is full.
- **Static API keys aren't enough.** They never expire, they get emailed and
  copied into code, and a leaked one stays usable until someone notices. Partners
  with a security review will ask for OAuth by name.

## What this solution gives you

- **A token endpoint** (`POST /oauth/token`) run by the gateway. It checks the
  app's client id *and* secret before it issues anything.
- **A token check on every protected route**, done before the request reaches your
  backend.
- **Short-lived tokens.** This package uses 15 minutes; you choose the number.
- **Every call tied to a named app**, which is what metering, analytics and
  support all need.

## Benefits

- **Ships as configuration, not a backend release.** Your service's code does not
  change, and its team is not on the critical path.
- **A leaked credential stops being a long-term problem.** The long-lived secret
  is only sent to the token endpoint. Everything else on the wire expires on its
  own.
- **Passes partner security reviews.** "Standards-based OAuth 2.0 client
  credentials" replaces "we use a key in a header".
- **Simple to switch off.** Disable an app and it can no longer get new tokens;
  the ones it has expire on their own.

## Example

A partner app has a client id and secret. Here is what it sees:

| The app sends | It gets back |
|---|---|
| `POST /oauth/token` with its client id and secret | `200` and a token that lasts 900 seconds |
| `GET /posts` with `Authorization: Bearer <token>` | `200` and the data from your backend |
| `GET /posts` with no token | **HTTP 401** (not authenticated). Your backend never sees the call. |
| The right client id with the wrong secret | `401`, and no token is issued |
| The same token, 15 minutes later | `401` — it fetches a new one |

**Setting this up in the gateway's UI takes eight short steps:** put your own
signing secret into the spec, import it, give it an upstream and deploy it, create
a product and deploy that too, add a developer, create an app for them, then copy
the app's client id and secret.
[Full click-by-click walkthrough →](guides.md#build-it-in-the-ui)

[Build it any of three ways, then see it work →](guides.md)

**One thing you must do:** replace `<YOUR_JWT_SIGNING_SECRET>` in the spec with a
long random value of your own. The gateway uses that text exactly as written to
sign tokens, so if you deploy the placeholder, anyone who has read this page can
make tokens your API will accept.

## Where to go next

- **Want the business case first?** [Business need](business-need.md) explains why
  this matters, in plain terms.
- **Want to understand how it works?** [Architecture](architecture.md) covers the
  two flows, the signing secret, and when *not* to use this.
- **Ready to build it?** [Guides](guides.md) walks you through it step by step.
- **Want the full product documentation?** Every plugin, screen and API call is
  covered at [docs.digitalapi.ai/api-gateway](https://docs.digitalapi.ai/api-gateway).

## Related solutions

- **[01 — API Products](../01-api-products/)** — once you know *who* is calling,
  give each caller a usage limit.
- **[03 — SOAP to REST](../03-soap-to-rest/)** — put this sign-in layer in front of
  an older SOAP system. The two fit together directly.
- **[04 — Analytics](../04-analytics/)** — see traffic per app, which works because
  this solution identifies the caller.
- **[05 — OAuth with Okta](../05-okta-jwt/)** — if a separate identity provider
  already issues your tokens, use that solution instead.
