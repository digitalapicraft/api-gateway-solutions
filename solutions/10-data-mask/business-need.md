# Business need — stop handing every consumer the whole record

[Overview](readme.md) · **Business need** · [How it works](how-it-works.md) · [Install](install.md) · [Configuration](configuration.md) · [Test & verify](testing.md) · [Changelog](changelog.md)

---

## The risk today

An audit finding about PII in a log aggregator is rarely just about logs. It is
the first place someone looked.

**The log aggregator is the finding; the screen is the exposure.** Logs get
flagged because they are searchable and centrally retained, so an auditor can see
them. The support console shows the same fields to two hundred agents in a
contact centre with ordinary turnover — a larger audience, less access control,
and no retention policy at all because nobody thinks of a screen as storage.

**Nobody can narrow the response.** The obvious fix is for the backend to return
less. It is a shared service on a release train, the change affects every other
consumer, and "return fewer fields to one caller" is a schema change plus a
migration. So it does not get scheduled, and the exposure is renewed at every
release.

**The exposure compounds quietly.** Every new consumer of the same endpoint
inherits the full record. Every copy of the payload — a cache, an error report,
a support ticket with a pasted response — is another place the data now lives.

## What the gateway changes

The response is narrowed at the single point every consumer already passes
through, without the backend changing anything.

Two controls, applied together, for two different audiences:

- **The caller's copy** is rewritten before it leaves the gateway. The support
  agent's screen stops carrying what the agent never needed.
- **The logger's copy** is masked independently, so the record in the aggregator
  is redacted even where the response is not.

They are independent by construction, which is the point most projects get wrong:
configuring the log mask alone — the natural response to a log-shaped audit
finding — leaves the screen exactly as it was.

## What makes this survive contact with the business

A masking project usually fails in one of two ways, and both are avoidable.

**It made the job harder.** Replace the whole email address and support can no
longer tell which customer organisation a caller belongs to. The control gets an
exception, then a rollback. This package masks the local part and keeps the
domain — the identifying half goes, the useful half stays. That distinction is
worth spending time on per field, because it is what makes the control permanent.

**It was never actually verified.** "We added masking" is a configuration claim.
The control that matters is whether *every* record in a list response is masked,
and the default setting masks only the first — while leaving the first one looking
correct in every screenshot. A masking project without an assertion over the whole
response is a masking project with an unknown status.

## The business outcome

| Before | After |
|---|---|
| Every consumer receives the full record | Each consumer receives what it needs |
| PII copied into a system with longer retention and a wider audience | The logged copy is redacted, and credentials are stripped from it |
| Narrowing the response needs a backend release | It is a configuration change and a revision deploy |
| "Is it masked?" is answered by reading config | It is answered by a test over every record in a real response |
| A new consumer inherits the full exposure | A new consumer inherits the masked view |

## What it does not buy you

- **It is not access control.** A caller who should not see the record at all must
  be stopped by identity. Masking reduces what a legitimate caller sees; it does
  not decide who is legitimate.
- **It is not tokenisation.** The masked value is not reversible and not a valid
  identifier. If a downstream system needs to correlate on the masked field, this
  is the wrong control.
- **It does not remove the data from the backend.** The upstream still returns it
  and the gateway still holds it in memory to rewrite it. If the requirement is
  that the value never leaves the system of record, this does not meet it.
- **It cannot find what it was not told about.** The same value under a different
  key, inside an encoded string, or quoted in a free-text error message is not
  masked. That is a boundary to test against real payloads, not a setting.
