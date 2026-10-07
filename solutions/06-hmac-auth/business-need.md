# HMAC request signing at the API gateway

> Your payments partner posts settlement files with an API key you issued three
> years ago. It's in their runbook, their CI, and a support ticket. Rotating it
> means a release on their side, so nobody has — and even a safe key says nothing
> about the payload: rewrite the amount in transit and the key still checks out.
>
> **At the edge, the secret stops travelling and the signature covers the
> request.**

- **Secret on the wire: every request → never.** The caller proves it holds the
  secret by signing; a proxy log or a pasted request is no longer a rotation event.
- **A captured request is worth: the credential, forever → that one request, for
  five minutes.** The signature binds method, path, timestamp and a hash of the
  body. Alter any of them and it fails at the edge.
- **Backend code changed: none.** And partners recognise the pattern — Stripe,
  GitHub, Shopify, Slack and Twilio all sign their webhooks.

The control is real only if the *route* decides what a signature must cover.
Leave that to the caller and it is decoration:

| The route requires the signature to cover | A captured signature can be reused for |
|---|---|
| nothing — the caller chooses | any body, any path, indefinitely |
| method, path, date | that path, any body, for the clock-skew window |
| method, path, date, body digest | that exact request, for the clock-skew window — this package |

It is authentication and integrity, not authorization, not replay protection
inside the window, and not for browsers — a secret on a user's device is not a
secret. [Before/after, the mechanism, and what this does not buy you are in the
README](README.md#business-need).

*Also searched as: HMAC authentication API gateway · signed API requests · webhook
signature verification · request signing with a shared secret · verify payload
integrity · HTTP message signatures · replace API keys for partner integrations.*
