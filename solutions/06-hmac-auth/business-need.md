# Business need — request signing at the edge

## The situation

An API receives traffic from parties you do not control: a payments partner
posting settlement files, a logistics provider posting status updates, a fleet of
devices posting telemetry, a SaaS vendor posting webhooks. Each of them holds a
credential you issued, and sends it on every request.

Two things are quietly true about that arrangement, and neither is a
mis-implementation — they are properties of bearer credentials:

> **The credential travels.** It is in the partner's CI configuration, their
> runbook, their error logs, and the support ticket where someone pasted a failing
> request. Any of those is a copy. Anyone holding a copy is indistinguishable from
> the partner, until somebody rotates — which requires a coordinated change on
> their side, which is why it has not happened.
>
> **The credential says nothing about the request.** It authenticates the caller,
> not the message. A payload altered between their process and yours arrives with
> a perfectly valid credential attached, and nothing in the request contradicts it.

The costs accrue quietly:

- **Rotation is a negotiation, not an operation.** Every rotation is a change
  request against a third party's release calendar, so credentials outlive the
  people who provisioned them.
- **You cannot prove a payload was not tampered with.** For payment,
  settlement or regulated telemetry, that is a control gap an auditor will find,
  and the remediation is the same project either way.
- **A leaked credential has no natural expiry.** Unlike a token, nothing bounds
  how long the copy stays useful.
- **Partner security reviews ask about it.** "How do you authenticate inbound
  webhooks?" answered with "a shared API key in a header" is a finding in their
  report, and it lands on your sales cycle.

## What changes

The caller proves possession of a shared secret by computing a function over the
request, rather than by transmitting the secret. The gateway recomputes the same
function and compares. The secret exists in exactly two places and moves between
them zero times.

| | Bearer credential | Signed request |
|---|---|---|
| **Secret on the wire** | Every request | Never |
| **A captured request yields** | The credential — reusable forever | One signature — valid for that request, until `clock_skew` |
| **Payload integrity** | Not addressed | Bound by the signature |
| **Detects a modified body** | No | Yes, before the upstream is contacted |
| **Backend code changed** | — | None. It never learns about authentication |
| **Blast radius of one leak** | Every request that credential can make | One request, for at most `clock_skew` seconds |
| **Cost to the caller** | Send a header | Canonicalise, hash, HMAC on every call |

## The mechanism that matters

The signature is computed over a **canonical string built from the request
itself** — method, path and query, a timestamp, and a hash of the body. Change
any of those and the signature no longer verifies.

That is what makes the proof specific. A bearer token answers "I am allowed to
call this API". A signature answers "I, holder of this secret, composed *this
exact request* at *this time*". The second statement is strictly stronger, and it
is the one an auditor is actually asking for.

Three consequences follow directly, and they are the whole business case:

1. **Interception stops being credential theft.** An attacker who captures
   traffic gets a signature over a request that has already happened.
2. **Tampering becomes detectable rather than invisible**, at the edge, before
   the request reaches anything that would act on it.
3. **The exposure window collapses from indefinite to `clock_skew` seconds** —
   and unlike a token TTL, you are not trading it off against how often callers
   must re-authenticate, because there is no re-authentication step.

## Business outcomes

- **The credential surviving observation stops being an incident.** A secret that
  never travels cannot be captured in transit, so a proxy log or a pasted request
  is no longer a rotation event.
- **Payload integrity becomes a control you can evidence.** "Requests are signed
  over method, path, timestamp and a hash of the body; unmatched signatures are
  rejected at the edge" is an answer to a questionnaire and an audit finding at
  once.
- **Per-partner isolation.** One app per integration means one `key_id` and one
  `secret_key` per integration. A compromised partner is rotated alone.
- **No backend change, and none later either.** The verification is a
  configuration property of the route. Adding a second signed endpoint is a spec
  edit.
- **Lower integration friction than it looks.** Stripe, GitHub, Shopify, Slack
  and Twilio all sign their webhooks. A partner integrating with you has usually
  written this client before — send them the worked example and they recognise it.

## What this does not buy you

- **Not authorization.** Who called, and that the message is intact. Not what
  they may do.
- **Not replay protection.** A captured request can be replayed until its `Date`
  falls outside `clock_skew`. Closing that needs idempotency upstream, not a
  gateway setting — the plugin has no nonce.
- **Not non-repudiation.** The secret is symmetric, so the verifier can forge
  what it verifies. A signature proves the message came from someone holding the
  secret; it does not prove *which* end.
- **Not a browser story.** A secret shipped to a device a user controls is not a
  secret. Browser and mobile callers need a token flow
  ([02](../02-oauth-jwt/), [05](../05-okta-jwt/)).
- **Not free for the caller.** They carry the implementation and debugging cost.
  Budget for the support load on the first two or three integrations.
- **Not credential expiry.** A `secret_key` is valid until rotated, and rotation
  is a cutover, not a rolling change.

## Success criteria

- No shared secret appears in any request, any log, or any stored artifact
  outside the two ends that hold it.
- A request whose body is altered in transit is rejected at the edge, and never
  reaches a system that would act on it.
- `signed_headers` is set on every signed route, so no caller can negotiate a
  weaker signing set than the route requires.
- Each integration has its own credential and can be rotated without touching any
  other.
- Integrators can self-diagnose a 401 from the response's `X-Request-Id` plus one
  log lookup, rather than by trial and error.
