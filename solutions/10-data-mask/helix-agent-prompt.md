# Agent-mode prompt — mask PII in responses and logs

> [Overview](README.md) · [Business need](business-need.md) · [Architecture](architecture.md) · [Guides](guides.md) · **Agent prompt** · [Tests](tests.md) · [API reference](api-reference.md)

---

Paste this to the Helix Agent as one message, replacing the `{{...}}` values. It
works from a fresh, empty org on a public upstream whose customer records carry
email, phone and coordinates, so the masking is visible with nothing of your own.

When it finishes, read the stored revision back before you deploy: both routes
should be there, every masking filter should apply to every match (`scope:
global`), the single-record route should carry the customer id through to the
backend, and no logger should have been added. Then run
[`example/verify.sh`](example/verify.sh) against it. See
[Troubleshooting](guides.md#troubleshooting) if something looks off.

## Prompt

```text
Step 1:
Create a REST API called "{{api_name}}" in the {{environment}} environment, proxying
https://jsonplaceholder.typicode.com. Two routes: GET /support/customers, which the
upstream serves at /users, and GET /support/customers/:customerId, which it serves
at /users/:customerId. Keep my paths.

Step 2:
Support agents use these routes and must not see customers' personal details.
Update both routes so that, in every record of every response, not just the first:
- each email keeps its domain but has the part before the @ replaced with ***,
  so Sincere@april.biz reads ***@april.biz.
- each phone number, latitude and longitude reads [redacted].
- every other field is unchanged.
Masking must match a field however it is spaced.

Don't add a logger now. But if one is added to these routes later, the entries it
writes have email and phone redacted and no Authorization header.
```
