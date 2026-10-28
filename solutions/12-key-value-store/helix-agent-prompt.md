# Agent-mode prompt — a per-partner sandbox from the key-value store

> [Overview](README.md) · [Business need](business-need.md) · [Architecture](architecture.md) · [Guides](guides.md) · **Agent prompt** · [Tests](tests.md) · [API reference](api-reference.md)

---

Paste this to the Helix Agent as one message, replacing the `{{...}}` values. It
starts from a fresh, empty org: the gateway answers every route itself, so you need
no backend. What to check before you trust it is in
[Guides](guides.md#build-it-with-the-helix-agent). See
[Troubleshooting](guides.md#troubleshooting) if something looks off.

## Prompt

```text
Step 1:
Create a REST API called "{{api_name}}" in the {{environment}} environment, proxying
https://httpbin.org. Two routes: POST /sandbox/partners and GET /sandbox/profile.
The gateway answers both itself; nothing reaches the upstream. Keep my paths.

Step 2:
This is a partner sandbox: each partner gets its own values back, and changing
them must not need a deploy. Update the routes so that:
- POST /sandbox/partners stores the X-Tier and X-Settlement-Account header values
  for the partner named in the X-Partner-Id header, for one day, replacing
  anything stored for that partner before, and answers 202 with
  {"registered":true}.
- GET /sandbox/profile answers 200 with the calling partner's id and its stored
  values: {"partner": ..., "tier": ..., "settlement": ...}. A partner with nothing
  stored gets the same shape with empty values.
- each partner sees only its own values.
```
