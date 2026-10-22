# HMAC request signing at the API gateway

> [Overview](README.md) · **Business need** · [Architecture](architecture.md) · [Guides](guides.md) · [Agent prompt](helix-agent-prompt.md) · [Tests](tests.md) · [API reference](api-reference.md)

---

> Your payments partner sends settlement files using an API key you gave them
> three years ago. It's in their setup notes, their build scripts and a support
> ticket. Changing it means a release on their side, so nobody has. And even a
> safe key says nothing about the file: if someone changes the amount on the way,
> the key still checks out.
>
> **With signing at the gateway, the secret is never sent, and the signature
> covers the request itself.**

- **The secret is never sent.** Before: it goes out with every request. After: it
  is never sent. The caller proves it has the secret by signing. A log file or a pasted request is no longer a reason to change the key.
- **A copied request is worth far less.** Before: it gave away the key, for good.
  After: it is good for that one request, for five minutes. The signature covers
  the method, the path, the time and a fingerprint of the body. Change any of them
  and the gateway rejects it.
- **No backend code changes.** And partners know the pattern: Stripe, GitHub,
  Shopify, Slack and Twilio all sign their webhooks.

This only protects you if the *route* decides what a signature must cover. If the
caller decides, the signature gives no protection:

| The route requires the signature to cover | Someone who copies a signature can reuse it for |
|---|---|
| nothing — the caller chooses | any body, any path, for ever |
| method, path, date | that path, any body, within the 5-minute time limit |
| method, path, date, body fingerprint | that exact request, within the 5-minute time limit — this package |

It proves who is calling and that the request wasn't changed. It does not decide
what a caller is allowed to do. It does not stop someone resending a copied
request within those 5 minutes. And it is not for browsers: a secret on a user's
device is not a secret. [How it works, and what this does not buy you, are in
Architecture](architecture.md#limits-worth-knowing).

*Also searched as: HMAC authentication API gateway · signed API requests · webhook
signature verification · request signing with a shared secret · verify payload
integrity · HTTP message signatures · replace API keys for partner integrations.*
