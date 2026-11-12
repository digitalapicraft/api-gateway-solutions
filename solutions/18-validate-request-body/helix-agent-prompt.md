# Agent-mode prompt — check request bodies at the gateway

> [Overview](README.md) · [Business need](business-need.md) · [Architecture](architecture.md) · [Guides](guides.md) · **Agent prompt** · [Tests](tests.md) · [API reference](api-reference.md)

---

Paste this to the Helix Agent as one message, replacing the `{{...}}` values. It
builds and deploys the API. When it finishes, read the deployed revision back:
check that `/tickets/:ticketId` was stored with a colon, not braces, and that
each route's rule lists the fields and values you asked for. See
[Troubleshooting](guides.md#troubleshooting) if something looks off.

## Prompt

```text
Step 1:
Create a REST API called "{{api_name}}" in the {{environment}} environment, proxying
https://jsonplaceholder.typicode.com. Two routes: POST /tickets, sent to the
backend as POST /posts, and PATCH /tickets/:ticketId, sent to the backend as
PATCH /posts/:ticketId.

Step 2:
Check request bodies at the gateway, so a bad body is rejected with a 400 and
never reaches the backend. On POST /tickets the body must be a JSON object with
two required fields: "title", a non-empty string, and "priority", one of low,
normal or high. On PATCH /tickets/:ticketId, title and priority are both
optional, but each one that is sent must follow the same rules. The 400 should
say which field is wrong. Put a request id on every response. Deploy it.
```
