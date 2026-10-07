# Request signing: authenticate partners without a secret on the wire

> [Overview](README.md) · **Business need** · [Architecture](architecture.md) · [Guides](guides.md) · [Agent prompt](helix-agent-prompt.md) · [Tests](tests.md) · [API reference](api-reference.md)

---

> A payments partner sends the key you issued on every request. It is now in
> their runbook and a support ticket, and rotating it needs a release on their
> side. And a body changed in transit still arrives with a valid key attached.
>
> **The caller should prove it holds the secret without sending it, and the proof
> should cover this exact request.**

- **Copying traffic stops being credential theft.** Someone who captures a request
  gets one signature for one request, valid for at most 300 seconds, not a key
  that works for years.
- **Tampering is caught at the edge**, before the request reaches anything that
  would act on it. "Signed over method, path, date and body" answers an audit
  question directly.
- **One credential per partner**, rotated on its own, with no backend change now
  or later.

The real decision is which callers can sign:

| Your caller | Use |
|---|---|
| A server, device fleet or partner backend that can keep a secret and run signing code | Signed requests — this solution |
| A browser or mobile app (a secret on a user's device is not a secret) | A token — [solution 02](../02-oauth-jwt/) or [05](../05-okta-jwt/) |

The caller does more work per request, and a copied request can be replayed
within the 300-second window. No savings figures are claimed: the benefits
describe how the system works, not measured results. More in
[Architecture](architecture.md#limits-worth-knowing).

*Also searched as: HMAC authentication · HTTP request signing · webhook signature
verification · API signature auth · message integrity for APIs · replace API key
with HMAC · signed partner API.*
