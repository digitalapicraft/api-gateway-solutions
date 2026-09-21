# Business need — API keys for callers that can't run a token exchange

## The risk today

An endpoint whose only protection is an unpublished URL is unprotected. That is
not a rhetorical position; it is what the incident review will say. Three things
follow from it, and all three are operational rather than theoretical.

**You cannot answer "who".** When one caller starts hammering the endpoint, or
sends malformed data, or gets stolen out of a forecourt, the first question is
which one. Source IP does not answer it — field devices sit behind carrier NAT,
partner jobs move between build agents, and a shared key is by definition shared.
Every minute spent establishing identity is a minute the incident is still open.

**You cannot stop one caller.** With no per-caller credential, the only lever is
the endpoint itself: change the URL or take it down. Both stop every caller. For
a fleet, "revoke one device" and "outage" are the same action.

**The exposure has no end date.** Nothing expires, so nothing self-heals. A
credential — or a URL — leaked three years ago is still valid today unless
someone noticed and acted.

## What the gateway changes

Identity moves to the edge and becomes a property of the caller rather than of
the network. Each caller gets its own app credential; the gateway resolves the
key to that app in the access phase and rejects everything else before the
request reaches the backend.

The change that matters commercially is not cryptographic. It is that
**revocation stops being a deployment.** Killing one caller becomes a
control-plane action taken by whoever is on call, in seconds, with no config
change, no redeploy, and nothing shipped to the device. That is the whole trade
this solution makes: the credential is long-lived and visible on every request,
and in exchange it is cheap to destroy.

## Why not simply require OAuth

Because for this class of caller, OAuth is not on the menu at any security level.
Client credentials assumes a client that can keep a usable clock, cache a token,
notice it is about to expire, and exchange for a new one — all without human
intervention and without losing the ability to retry. A payment terminal on a
service-station forecourt, a twenty-year-old middleware box, or a partner's
overnight `curl` in a shell script can set a header. That is the budget.

Insisting on tokens here does not produce tokens. It produces an endpoint that
stays open because the secure option was unimplementable, which is the actual
status quo being described.

Where the caller *can* run an exchange, it should — see
[solution 01](../01-oauth-jwt/). The two are not competing designs; they are the
same decision made about different callers.

## The business outcome

| Before | After |
|---|---|
| "Which terminal is calling?" is a research project | It is a field on the request, resolved before the backend sees it |
| Revoking one caller means changing the endpoint for all of them | Delete one app; the next request from that caller is rejected |
| A stolen device is an open-ended exposure | A stolen device is a five-minute control-plane action |
| One shared key across the estate | One credential per caller, independently killable |
| Metering and attribution are impossible — nothing to key on | Both become available, because identity now exists |

Two second-order effects usually decide whether the work gets funded:

- **Attribution becomes possible at all.** Per-app analytics and per-app quotas
  need an app to attribute to. This solution is the step that creates one — which
  is why [solution 03](../03-api-products/) and [solution 04](../04-analytics/)
  both depend on something like it having happened first.
- **The backend is not in the change.** No handler is touched, no release train
  is joined, and the team that owns the service does not need a slot in its
  roadmap. The work is a configuration change and a revision deploy.

## What it does not buy you

Stated plainly, because a package that oversells this is worse than none:

- **No expiry.** The credential is valid until someone removes it. Time does not
  clean up after you; a quarterly review of live apps does.
- **No protection against observation.** The key travels on every request. A
  proxy, a TLS-terminating middlebox, or a log with headers enabled can capture
  and replay it. If that is your threat model, the caller needs to hold a secret
  it never sends — [solution 06](../06-hmac-auth/).
- **No integrity.** The key says who sent the request. It says nothing about
  whether the body arrived as it left.
- **No end-user identity.** An app is not a person.
