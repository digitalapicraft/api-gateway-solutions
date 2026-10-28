# Agent-mode prompt — enrich requests from a lookup service

> [Overview](README.md) · [Business need](business-need.md) · [Architecture](architecture.md) · [Guides](guides.md) · **Agent prompt** · [Tests](tests.md) · [API reference](api-reference.md)

---

Paste this to the Helix Agent as one message, replacing the `{{...}}` values. It
works from a fresh, empty org: the upstream echoes the headers it receives, and a
public sample service stands in for your profile service, so you need nothing of
your own. What the agent decides on its own, and what to check before you trust
it, are in [Guides](guides.md#build-it-with-the-helix-agent). See
[Troubleshooting](guides.md#troubleshooting) if something looks off.

## Prompt

```text
Step 1:
Create a REST API called "{{api_name}}" in the {{environment}} environment, proxying
https://httpbin.org. Two routes: GET /storefront/orders, which the upstream serves
at /headers, and POST /storefront/checkout, which it serves at /post. Keep my paths.

Step 2:
The backend needs the calling tenant's profile on every request. Update both routes
so the gateway fetches it once from https://jsonplaceholder.typicode.com/users/1
before proxying, and hands it to the backend as headers:
- X-Tenant-Plan from the profile's company.name, X-Tenant-Contact from its email,
  and X-Profile-Status from the HTTP status of the lookup.
- the gateway's values replace any the client sent, so a client cannot assert its
  own plan.
- if the lookup fails, GET /storefront/orders goes ahead without the headers, and
  POST /storefront/checkout is refused with "tenant profile unavailable".
The lookup must finish before the headers are set.
```
