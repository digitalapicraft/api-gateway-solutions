# Agent-mode prompt — give an API stable public paths

> [Overview](README.md) · [Business need](business-need.md) · [Architecture](architecture.md) · [Guides](guides.md) · **Agent prompt** · [Tests](tests.md) · [API reference](api-reference.md)

---

Paste this to the Helix Agent as one message, replacing the `{{...}}` values.
When it finishes, read the deployed revision back: check that the two routes
with an id were stored as `/:customerId`, not `{customerId}`, and that each one
carries the id through to the backend. See
[Troubleshooting](guides.md#troubleshooting) if something looks off.

## Prompt

```text
Step 1:
Create a REST API called "{{api_name}}" in the {{environment}} environment, proxying
https://jsonplaceholder.typicode.com. Three routes, all GET: /v1/customers,
/v1/customers/:customerId and /v1/customers/:customerId/orders. These paths are
our public contract, and callers must never see the backend's own paths.

Step 2:
Send each public path to the backend's own path: /v1/customers to /users,
/v1/customers/:customerId to /users/ followed by that customer's id, and
/v1/customers/:customerId/orders to /users/ followed by that id and /todos.
A caller's query string, such as ?_limit=2, must reach the backend unchanged.
Put a request id on every response. Deploy it.
```
