# Solution 06 — Signed requests: prove who is calling without ever sending the secret

> **Overview** · [Business need](business-need.md) · [Architecture](architecture.md) · [Guides](guides.md) · [Agent prompt](helix-agent-prompt.md) · [Tests](tests.md) · [API reference](api-reference.md)

**In short:** each caller signs every request with a secret. Only the caller and
the gateway know that secret. The secret is never sent. So a copied request does
not give anyone the secret. And if someone changes a request on the way, the
gateway rejects it.

| | |
|---|---|
| **Time to try it** | About 20 minutes |
| **Difficulty** | 🟢 Beginner — one API, one product, one app, a public test service |
| **What you'll need** | An org that includes the `hmac-auth` plugin, and one upstream (the service the gateway forwards requests to). The example uses a public test service, so you need no backend of your own. |

---

## What is a signed request?

Most APIs use an API key or a token that is sent with every request. The gateway
treats whoever holds it as the caller. So anyone who copies one request also gets
the key.

A **signed request** works differently. The caller and the gateway share a secret.
For each request, the caller takes the request's method, path and date, plus a
fingerprint of its body (the data the request carries). It mixes these with the secret and gets a short code, the
**signature**. It sends only the signature, never the secret. The gateway does the
same calculation with its own copy of the secret. If the two results match, the
request is genuine and nobody changed it.

It is like signing a cheque. Your signature on one cheque doesn't let anyone write
a different cheque. And if someone changes the amount afterwards, the signature no
longer matches.

## The use case

> *"Our payment partner sends us settlement files. We gave them an API key three
> years ago. It's in their setup notes, their build scripts, and — we found out in
> March — a Jira ticket. Changing it means both teams releasing at the same time,
> so we haven't. And even if the key were safe, it tells us nothing about the file
> itself: if something changes the amount on the way, the key still checks out."*

A key or token that is sent with every request has two weaknesses:

- **It is sent every time.** A log file, a badly set-up server, or a screenshot in
  a support ticket is enough to copy it. The copy keeps working until someone
  changes the key.
- **It says nothing about the request it came with.** It proves who the caller
  is. It does not prove the body arrived as it was sent.

## What it gives you

- **A secret that is never sent over the network.** It is stored only at the
  caller and at the gateway. It is never in the API's configuration.
- **Protection for the body.** On the route that sends data (`POST /albums`),
  the signature covers a fingerprint of the body. If the body changes on the
  way, the gateway rejects the request.
- **A short time limit for copied requests.** A signature is tied to a date. After
  300 seconds (5 minutes) it no longer works.
- **One credential per partner.** You can change each partner's key on its own.

## Benefits

- **A leaked log is no longer a security incident.** There is no secret in it to
  steal.
- **Proof that a request wasn't changed**, which you can show in a security
  questionnaire or an audit.
- **No backend change.** The gateway does the checking. Your service never knows
  about it.
- **Familiar to partners.** Stripe, GitHub, Shopify, Slack and Twilio all sign
  their webhooks. Most partners have built a signing client before.

## Example

A payments partner sends settlement events to `POST /albums`. It reads them back
from `GET /albums/{albumId}`. (The example uses a public test service's album
records, so the paths say "albums".)

| The partner sends… | It gets back |
|---|---|
| No signature | HTTP 401 (not authenticated) |
| A correct signature | 201 — accepted and forwarded |
| A correct signature, but the body changed afterwards | 401 |
| A signature dated 20 minutes ago | 401 |
| The exact same signed request again, within 300 seconds | 201 — accepted again (see [Architecture](architecture.md#limits-worth-knowing)) |

**Setting this up in the gateway's UI takes eight short steps:** create the
API (from scratch, or from an OpenAPI spec), add the signing plugin to each
route, give it an upstream and deploy it, create a product that uses
`hmac-auth`, deploy the product, add a developer, create an app for them, then
copy the app's `key_id` and `secret_key`.
[Full click-by-click walkthrough →](guides.md#build-it-in-the-ui)

[Build it any of three ways, then see it work →](guides.md)

## Where to go next

- **Want the business case first?** [Business need](business-need.md) explains why
  this matters, in plain terms.
- **Want to understand how it works?** [Architecture](architecture.md) covers how
  a signature is built and checked, and when to use a token instead.
- **Ready to build it?** [Guides](guides.md) walks you through it step by step.
- **Want the full product documentation?** Every plugin, screen and API call is
  covered at [docs.digitalapi.ai/api-gateway](https://docs.digitalapi.ai/api-gateway).

## Related solutions

- **[02 — OAuth 2.0 with JWT](../02-oauth-jwt/)** — tokens instead of signatures,
  for callers that can hold one. The gateway issues and checks the token.
- **[05 — OAuth with Okta](../05-okta-jwt/)** — tokens again, when an outside
  identity provider issues them.
- **[01 — API Products](../01-api-products/)** — usage limits per app. This
  solution creates a product to give the app its credential. It is the same kind
  of product that 01 counts usage on. Adding 01's quota check to a signed route
  works.
- **[07 — HTTP to Kafka](../07-http-to-kafka/)** — an endpoint that takes in
  events with no service behind it. It ships with no check on who is calling;
  this solution is how you add one.
