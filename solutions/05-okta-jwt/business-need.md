# Business need — bringing APIs under the identity provider you already own

## The situation

The organisation runs Okta. Joiners, movers and leavers flow through it. Access
reviews are run against it. Auditors are shown it.

The APIs are not in it. They authenticate with static keys handed out by email or
ticket, held in wikis, config files, Postman collections and a partner's CI
system. Nobody can say with confidence how many are live, who holds them, or
which ones stopped being needed in 2023.

The gap is not ideological. Every team agrees the APIs should check Okta tokens.
It requires JWKS fetching, key caching, signature verification, issuer and expiry
checking — in every service, in every language, maintained forever. So it is
scheduled, deferred, and scheduled again.

## What changes

| | Before | After |
|---|---|---|
| Who authenticates the caller | each service, separately | the gateway, once |
| Credential | a static key with no expiry | an Okta token measured in minutes |
| Deprovisioning | find every copy of the key | disable the app in Okta |
| Adding a caller | issue and email a key | an Okta assignment |
| Access review evidence | a spreadsheet | the existing Okta review |
| Rotating a signing key | not a concept | Okta's schedule, absorbed by the gateway |
| Code to change to adopt it | every service | none |
| Where auth bugs live | N services, N implementations | one configuration block |

## The mechanism that matters

Strip away the standards vocabulary and one thing changes:

> **The credential stops being a secret you distribute and starts being a token
> the identity provider mints on demand.**

Everything else follows. You cannot lose track of a token that expires in an
hour. You cannot fail to deprovision a caller whose tokens stop being issued. You
do not have to find every copy of a thing that was never copied.

## Business outcomes

- **Deprovisioning becomes real.** Today the honest answer to "is that 2021 key
  still live?" is usually "probably". After, revoking access is an Okta action
  bounded by the token lifetime.
- **Access review covers the API estate.** The APIs join the review that already
  runs, rather than needing a separate one that does not exist.
- **The static-key backlog can actually be closed.** Retiring keys stops being
  per-service work and becomes one gateway change.
- **No backend release.** The services do not learn that authentication changed.
- **Crypto is not written N times.** Signature verification, JWKS caching and
  clock handling are configuration, not code you own and patch.

## What this does not buy you

No numbers are claimed here. The costs above are the ones teams describe, not
measured figures, and this document quantifies the *mechanism* — credential
lifetime, number of implementations, deprovisioning path — rather than inventing
an ROI.

Specifically out of scope:

- **Authorization.** The token proves identity. It does not decide which caller
  may do what. That is `required_scopes` or a policy engine, and it is a separate
  piece of work.
- **Metering and quotas.** An Okta-issued token does not resolve an app
  credential, so per-caller quotas do not follow from this. That is solution 01's
  model, and the two do not compose for free.
- **Revocation before expiry.** Disabling a caller in Okta stops new tokens. The
  one it already holds stays valid until it expires. Closing that gap means
  introspection, which puts the identity provider on the request path and changes
  the availability and latency story.
- **End-user identity, if you use client credentials.** That grant authenticates
  an application, not a person.

## Success criteria

You'd call this done when:

- A call with no token returns **401** — and specifically not a 302 to a login
  page (`verify.sh` case 1).
- A token minted by Okta seconds earlier returns **200** (case 3).
- A token with a tampered signature returns **401** (case 4).
- A token from a *different* Okta authorization server returns **401** (case 7).
  This is the one that proves the token is specific to this API.
- No service in the estate has had a line of code changed.
- A caller disabled in Okta stops working within one token lifetime, and someone
  has actually observed that rather than assumed it.
