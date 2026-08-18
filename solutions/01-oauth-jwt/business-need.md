# Business need — OAuth 2.0 with JWT at the gateway

## The situation

An API that partners depend on is protected by a static key, or by nothing at
all. Everyone agrees this should change. It doesn't change, because the fix is
scheduled against the wrong team's roadmap.

The reasoning is always the same, and it isn't wrong:

> Adding authentication touches every request handler. That makes it a
> cross-cutting change to a service on a quarterly release train, plus a
> coordinated migration for every existing integrator. Call it six weeks of
> engineering and a change-management exercise. It goes on the risk register
> instead, and the register grows.

Meanwhile the cost of *not* doing it accrues quietly:

- **Every static key in circulation is valid indefinitely.** It was emailed once,
  configured in a partner's CI, and nobody on either side knows all the places
  it now lives.
- **You cannot answer "who is calling?"** with confidence, which means you also
  cannot answer "who caused this?", "who should be billed?", or "who do we notify
  if we rotate?"
- **Each new partner is a manual credential handover.** Security review, key
  generation, an email nobody should have sent, and a spreadsheet.
- **Security questionnaires keep coming back.** "Describe your API
  authentication mechanism" answered with "a static key in a custom header"
  extends a sales cycle, and sometimes ends one.

## What changes

Authentication moves to the edge, where it always belonged. It is not application
logic — nothing about verifying a caller's identity requires knowledge of your
domain model — so it does not need to live in your domain code.

| | Before | After |
|---|---|---|
| **Time to ship** | A backend release cycle plus coordinated partner migration | A configuration change and a revision deploy |
| **Backend code changed** | Every request handler | None |
| **What travels on each request** | A credential valid until someone revokes it | A token valid for minutes |
| **Credential exposure window** | Unbounded — often years | The token lifetime, typically 5–15 minutes |
| **Revoking a partner** | Find every place the key was configured, then rotate and hope | Disable the app; new token requests fail immediately, existing tokens expire on their own |
| **Attribution** | An IP address in a log | The calling app, on every request, available to every downstream layer |
| **Security review answer** | "A static key in a header" | "OAuth 2.0 client credentials, tokens signed at the edge, 15-minute lifetime" |
| **Onboarding a partner** | Manual key handover | Create an app; the control plane issues the credentials |

## The mechanism that matters

Strip away the standards vocabulary and one thing changes:

> **The credential that can be replayed forever stops travelling on every
> request.**

A static key is a bearer credential with no expiry, sent thousands of times a day,
logged by intermediaries, stored in configuration files, and visible to anyone who
can read a request. Its blast radius is bounded only by how long it takes someone
to notice.

Under client credentials, the long-lived secret is used **once per token
lifetime, against one endpoint.** Every other request carries something that
expires on its own. You haven't eliminated the risk of a leaked credential — you
have bounded it, from *indefinite* to *the number you chose*.

That number is `token_ttl`, and it is the security control. Choosing it is the
one real decision in this solution:

| TTL | A leaked token is usable for | Token requests per client, per hour |
|---|---|---|
| 300s | up to 5 minutes | ~12 |
| 900s | up to 15 minutes | ~4 |
| 3600s | up to 1 hour | ~1 |
| 24h | up to a day | negligible — and you've rebuilt the static key |

## Business outcomes

**Risk reduction you can describe precisely.** Not "improved security" — a
specific, bounded change: the exposure window for a compromised credential goes
from indefinite to the token lifetime. That's a sentence an auditor can accept and
a risk register entry you can close.

**Delivery capacity returned.** The backend work doesn't get done faster; it
doesn't get done at all. The engineering that would have gone into threading auth
through every handler goes somewhere else, and the release train stays free for
product work.

**Sales friction removed.** "Standards-based OAuth 2.0" is a box that gets ticked
rather than a conversation that gets escalated. For partners with a formal
security review, this can be the difference between an integration and a stalled
one.

**Self-serve onboarding becomes possible.** Once credentials are issued by the
control plane against an app rather than handed over by a human, partner
onboarding stops being a ticket. That's the door to
[API Products](../03-api-products/) and a marketplace, neither of which works
without identity.

**Attribution for everything downstream.** Every layer that needs to know who is
calling — metering, quota, analytics, chargeback, incident response — reads the
identity resolved here. This solution is a prerequisite for
[metering](../03-api-products/) and for
[answering "which integration caused this?"](../04-analytics/) at all.

## What this does not buy you

Stated plainly, because overclaiming here is how a package loses trust:

- **It authenticates applications, not users.** Client credentials proves *which
  integration* is calling. It says nothing about an end user, and it is not a
  substitute for the authorization code flow.
- **It is not authorization.** You now know who is calling. What they're allowed
  to do is a separate layer, and it's the genuinely
  application-specific one.
- **Tokens are not revocable mid-life.** Disabling an app stops new tokens; issued
  ones remain valid until they expire. This is exactly why the TTL is the control.
- **It doesn't fix credentials already in the wild.** Existing static keys stay
  dangerous until you retire them. Migrating partners off them is real work — less
  than a backend release, but not zero.
- **No numbers are claimed here.** The six-week estimate above is the *reasoning
  teams give*, not a measured figure, and this document deliberately quantifies
  the mechanism (exposure window, token traffic) rather than inventing an ROI.
  Use your own release cadence and your own credential inventory.

## Success criteria

You'd call this done when:

- No request to a protected route succeeds without a token issued by the gateway.
- A forged or expired token is rejected before it reaches the backend — verifiable
  with [`gateway/verify.sh`](gateway/verify.sh) cases 1, 4 and 6.
- An app's *wrong* secret does not produce a token (case 5). Without this you have
  a static key in a token's clothing.
- Every request is attributable to a named app, and you can produce last hour's
  traffic broken down by app.
- Onboarding a new partner requires no engineer to email anything.
- The backend service's code is unchanged, and its team was not on the critical
  path.
