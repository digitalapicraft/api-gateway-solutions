# Mask PII in API responses and logs, at the API gateway

> [Overview](README.md) · **Business need** · [Architecture](architecture.md) · [Guides](guides.md) · [Agent prompt](helix-agent-prompt.md) · [Tests](tests.md) · [API reference](api-reference.md)

---

> Audit flagged customer PII in the log aggregator, so there is a ticket to mask
> the logs. Reading the sample lines, it became obvious the support console shows
> two hundred agents the same thing: every customer's email, phone number and home
> coordinates. The backend is a shared service on a quarterly release train, so
> "return less" is not a change anyone can make this year.
>
> **Mask at the edge, twice: once for the caller's copy, once for the logger's.**

- **What a support agent sees: the full record → only what the job needs.**
  `***@april.biz`, not the address. The domain stays, because support uses it to
  tell customer organisations apart.
- **PII copied into the log aggregator: every field → none.** The logged copy is
  redacted, and credentials are stripped from it.
- **Backend code changed: none.** Narrowing the response is a configuration change,
  not a schema change on someone else's release train.

The two masks are independent, and shipping only one is how this usually fails:

| | Changes what the caller gets | Changes what a logger writes |
|---|---|---|
| `response-rewrite` | yes | usually, as a side effect |
| `log-data-mask` | **no** | yes, and only if a logger is on the route |

It is not access control: masking narrows what a legitimate caller sees, not who
may call. It is not reversible, and it only finds the fields it was told about.
[Why masks fail in practice](architecture.md#the-scope-setting) and [what this
does not buy you](architecture.md#what-it-does-not-do) are in Architecture.

*Also searched as: mask PII at the API gateway · redact sensitive fields in API
responses · data masking API · mask email and phone in JSON · redact PII from logs ·
GDPR data minimisation at the gateway · response filtering without changing the
backend.*
