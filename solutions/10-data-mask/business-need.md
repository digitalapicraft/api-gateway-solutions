# API data masking for PII in responses and logs

> [Overview](README.md) · **Business need** · [Architecture](architecture.md) · [Guides](guides.md) · [Agent prompt](helix-agent-prompt.md) · [Tests](tests.md) · [API reference](api-reference.md)

---

> An audit flags customer personal data in your log store, so a ticket is raised
> to mask the logs. Meanwhile the support console shows two hundred agents every
> customer's full email, phone number and home coordinates — a bigger audience,
> weaker access control, and nobody thinks of a screen as storage.
>
> **The logs are where the finding was made. The screen is where the exposure
> is.**

- **Each consumer gets what it needs**, not the whole record, without waiting for
  a backend release that nobody can schedule.
- **The logged copy is redacted, and credentials are stripped from it**, so the
  record in the log store is clean even where the response isn't.
- **"Is it masked?" is answered by a test** over every record in a real response,
  not by reading configuration.

Two things decide whether the control survives:

| | Fails when… | This package… |
|---|---|---|
| Usefulness | the mask removes what the job needs, so it gets an exception and then a rollback | keeps the email domain, removes the personal part |
| Verification | the default masks only the **first** record, which looks right in every screenshot | sets `scope: global` and tests every record |

No figures here are measured savings; they are the reasoning. It isn't access
control, isn't reversible, and can't find a value it wasn't told the name of.
[What it does not do is in Architecture](architecture.md#what-it-does-not-do).

*Also searched as: API data masking · mask PII in API response · redact
personal data in logs · GDPR API gateway · hide email and phone in API ·
log redaction · sensitive data masking.*
