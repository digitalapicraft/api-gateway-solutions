# Solution 06 — Signed requests: prove who is calling without ever sending the secret

> **Overview** · [Business need](business-need.md) · [Architecture](architecture.md) · [Guides](guides.md) · [Agent prompt](helix-agent-prompt.md) · [Tests](tests.md) · [API reference](api-reference.md)

**In short:** each caller signs every request with a secret only it and the
gateway know. The secret never travels, so a copied request can't be turned into
a stolen password, and a request changed on the way is rejected.

| | |
|---|---|
| **Time to try it** | About 20 minutes |
| **Difficulty** | 🟢 Beginner — one API, one product, one app, a public test service |
| **What you'll need** | An org that includes the `hmac-auth` plugin, and one upstream. The example uses a public test service, so you need no backend of your own. |

---

## What is a signed request?

Most APIs use a **bearer credential**: an API key or a token sent with every
request. Whoever holds it is treated as the caller, so anyone who copies one
request can copy the credential.

A **signed request** works differently. The caller and the gateway share a secret.
For each request, the caller combines the secret with the request's method, path,
date and a fingerprint of its body, and sends only the result, the **signature**.
The gateway does the same calculation with its copy of the secret. If the two
results match, the request is genuine and unchanged.

It is like signing a cheque. Your signature on one cheque doesn't let anyone write
a different cheque, and changing the amount afterwards makes the signature not
match.

## The use case

> *"Our payment partner posts settlement files to us. We gave them an API key
> three years ago. It's in their runbook, their CI, and — we found out in March —
> a Jira ticket. Rotating it means a coordinated release on their side, so we
> haven't. And even if the key were safe, it tells us nothing about the payload:
> if something rewrites the amount in transit, the key still checks out."*

A bearer credential of any kind has two weaknesses:

- **It travels on every request.** A proxy log, a misconfigured server, or a
  screenshot in a support ticket is enough to copy it, and the copy works until
  someone changes the key.
- **It says nothing about the request it came with.** It proves who the caller
  is, not that the body arrived as it was sent.

## What it gives you

- **A secret that never crosses the network.** It is stored at the two ends and
  nowhere in between, and never in the API's configuration.
- **Body protection.** On the write route, the signature covers a fingerprint of
  the body, so any change on the way is rejected at the gateway.
- **A short window for copied requests.** A signature is tied to a date; after
  300 seconds it no longer works.
- **One credential per partner**, each rotated on its own.

## Benefits

- **A leaked log is no longer a security incident.** There is no secret in it to
  steal.
- **Payload integrity you can point to** in a security questionnaire or an audit.
- **No backend change.** The checking happens at the gateway; your service never
  learns about it.
- **Familiar to partners.** Stripe, GitHub, Shopify, Slack and Twilio all sign
  their webhooks, so most partners have built a signing client before.

## Example

A payments partner posts settlement events to `POST /posts` and reads them back
from `GET /posts/{postId}`.

| The partner sends… | It gets back |
|---|---|
| No signature | HTTP 401 (not authenticated) |
| A correct signature | 201 — accepted and forwarded |
| A correct signature, but the body changed afterwards | 401 |
| A signature dated 20 minutes ago | 401 |
| The exact same signed request again, within 300 seconds | 201 — accepted again (see [Architecture](architecture.md#limits-worth-knowing)) |

**Setting this up in the gateway's UI takes six short steps:** import the API,
give it an upstream and deploy it, create a product that uses `hmac-auth`, deploy
the product, add a developer, then create an app to get its `key_id` and
`secret_key`.
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

- **[02 — OAuth 2.0 with JWT](../02-oauth-jwt/)** — the token alternative, for
  callers that can hold one. The gateway issues and checks the token.
- **[05 — OAuth with Okta](../05-okta-jwt/)** — tokens again, when an outside
  identity provider issues them.
- **[01 — API Products](../01-api-products/)** — usage limits per app. The product
  this solution creates for its credential is the same thing 01 meters, and adding
  01's quota check to a signed route works.
- **[07 — HTTP to Kafka](../07-http-to-kafka/)** — an intake endpoint with no
  service behind it. It ships without authentication; this solution is how you
  add it.
