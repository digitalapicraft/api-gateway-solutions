# Business need — stop paying a release for every partner's key

[Overview](readme.md) · **Business need** · [How it works](how-it-works.md) · [Install](install.md) · [Configuration](configuration.md) · [Test & verify](testing.md) · [Changelog](changelog.md)

---

## The risk today

Key material in a route works for the first counterparty and degrades from there,
in three ways that all scale with N.

**N routes that differ by one field.** Fourteen partners means fourteen route
definitions that are identical except for a key. Any change to the *shape* — a new
failure policy, a size limit, an added header — is fourteen edits, and the
fourteenth is the one that gets missed.

**N keys inside configuration documents.** Each one is a thing that can be
committed, pasted into a ticket, or copied into a test environment. The control
plane stores them encrypted once supplied, but they travel in the document you
import, and they sit in the revision you can read back.

**Rotation is a release, on somebody else's schedule.** Counterparties rotate keys
when their policy says so, not when your change window is open. On a route the old
and new keys cannot both be live, so it is a hard cutover that has to be
coordinated — and a Friday-afternoon rotation is discovered by a failing file
rather than by a calendar invite.

## What the gateway changes

The key stops being part of the configuration and becomes data the route reads at
request time, addressed by something in the request.

- **Adding a counterparty is a write.** No new route, no review, no deploy.
- **Rotation is a write.** The next request uses the new key. Verified: after
  re-registering, the document was encrypted to the new key and the old key could
  no longer read it — with no revision involved.
- **No key material is in the configuration at all.** The registration path takes
  the value from the request body, so the document you import and the revision you
  read back contain no keys.

One route serves every counterparty, and the difference between them is data.

## What it costs

This is not free, and two of the costs are real enough to decide against it for a
single integration.

**A write path you have to protect.** There is no control-plane API for these
entries on this build, so the only way in is a route. That route can write key
material, which makes it administrative — and an unauthenticated write to your key
store is worse than a key in a configuration document. Protecting it is part of the
work, not an optional extra.

**A second moving part.** Two plugins, a store, and a reference grammar that fails
silently when it is wrong. The typo case — `header` instead of `headers` — produces
no error anywhere and looks exactly like "no key registered".

For one long-lived partner, the simpler shape wins. The crossover is the second
counterparty, and it is worth starting here if you can see one coming: migrating N
routes later is more work than starting with one.

## The business outcome

| Before | After |
|---|---|
| A route per counterparty | One route, many counterparties |
| A key in every configuration document | No key material in the configuration |
| Rotation is a change request and a deploy | Rotation is a write, effective on the next request |
| A partner's rotation schedule is your release schedule | The two are decoupled |
| Onboarding a partner is a code change | Onboarding a partner is data entry |
| A shape change is N edits | A shape change is one edit |

## What it does not buy you

- **It is not access control.** The partner id arrives in a header the caller
  controls. Any caller can request any partner's document — they receive something
  encrypted to that partner's key and cannot read it, which is a reason not to
  panic and not a reason to call it authorization. Bind the id to an authenticated
  identity.
- **It does not version keys.** Registration replaces the entry. There is no
  history, no staged rollout, and a bad write destroys the previous value.
- **It does not validate what you store.** A malformed or simply wrong key is
  accepted and only discovered when a counterparty cannot read a document — which
  is invisible from the gateway's side.
- **It does not change the crypto.** Everything about the wire format, the error
  messages and the body-size limits is the same as the single-key version, and is
  documented there.
