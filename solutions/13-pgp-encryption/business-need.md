# Business need — take the keys off the VM nobody owns

[Overview](readme.md) · **Business need** · [How it works](how-it-works.md) · [Install](install.md) · [Configuration](configuration.md) · [Test & verify](testing.md) · [Changelog](changelog.md)

---

## The risk today

The script in the middle is not a technical debt item. It is an unowned system
holding your most sensitive material.

**Nobody owns it.** It exists because two systems could not talk directly, so
somebody wrote it, and then left. It appears on no team's roadmap, in no team's
on-call rotation, and in no architecture diagram drawn after 2022.

**It holds the keys.** A private key on a VM, in a home directory, with whatever
file permissions were set the day it was created. Of every asset in the
integration this is the one an auditor will ask about, and it is the one with the
least governance around it.

**It is outside every control you have.** Not in the deployment pipeline, so
changes are manual. Not in monitoring, so failures are discovered by the
counterparty. Not in the access review, because it is not a system anyone
registered. The month-end batch is when all three facts arrive at once.

**Replacing it is nobody's project.** It works, most of the time. The cost is
carried as a 2am page a few times a year, which is cheaper than a project — right
up until the person who knows how to restart it is on holiday.

## What the gateway changes

The crypto moves onto the path the traffic already takes, and becomes configuration
rather than a deployable.

- **The keys move into the control plane**, where they are stored encrypted, sit
  behind the same access control as everything else, and appear in the same audit
  trail.
- **The change becomes a revision**, which means it is reviewed, dry-run, deployed
  and rolled back like every other change.
- **Failures become gateway failures**, on the dashboards you already watch, with
  the request id you already correlate on.
- **The backend does not change.** It handled plaintext before and it handles
  plaintext now. The counterparty does not change either — they still send and
  receive exactly what the contract says.

The work is not making PGP possible. It is making PGP *ordinary*: owned by the team
that owns the path, and covered by the controls that cover everything else on it.

## The business outcome

| Before | After |
|---|---|
| An unowned VM in the middle of a partner integration | A route, owned by whoever owns the path |
| A private key in a home directory | Key material in the control plane, encrypted at rest |
| Changes are manual and unreviewed | Changes are revisions: reviewed, dry-run, rollback-able |
| Failures are reported by the counterparty | Failures appear in the same telemetry as everything else |
| The 2am page has no runbook | The 2am page is the same one as for any route |

## The caveat that decides the design

The key material is a **literal in the route configuration**. There is no
environment-variable indirection: replace the placeholder with a real armored block
or nothing works, and keep that file out of version control.

That is fine for one counterparty. It does not scale to fourteen, because fourteen
counterparties means fourteen routes, fourteen keys in configuration documents, and
a deploy every time one of them rotates a key.

If you have more than one counterparty, budget for that from the start — the key
material belongs in a store the route reads at request time, not in the route.
[Solution 12](../12-key-value-map/) is that shape, and rotation there is a data
change rather than a deploy.

## What it does not buy you

- **It is not authentication.** Encrypting a response to a partner's key does not
  establish that the caller *is* that partner. Anyone who can reach the route gets
  a document they cannot read, which is not the same as being refused.
- **It is not a signature.** This is confidentiality. It does not prove who sent a
  message, and it gives you no non-repudiation.
- **It does not protect the payload from your own backend.** The gateway decrypts
  *for* the backend. If the backend is what you are protecting the data from, the
  crypto has to live further in.
- **It is not free.** Crypto costs CPU per request and buffers the whole body, so
  large batch files need the limit and the memory thought through rather than
  raised until one file works.
