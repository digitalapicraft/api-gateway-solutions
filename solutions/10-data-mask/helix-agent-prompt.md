# Agent-mode prompt — mask PII in responses and logs

Paste this to the Helix Agent as one message, replacing the `{{...}}` values. It
works from a fresh, empty org on a public upstream whose customer records carry
email, phone and coordinates, so the masking is visible with nothing of your own.
Why the prompt is worded this way, what the agent decides on its own, and what to
check before you trust it are in the
[README](README.md#build-it-with-the-helix-agent).

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

Separately, if a logger is added to these routes, the entries it writes have
email and phone redacted and no Authorization or X-Api-Key header.
```
