# Agent-mode prompt — API-key identity for constrained callers

> [Overview](README.md) · [Business need](business-need.md) · [Architecture](architecture.md) · [Guides](guides.md) · **Agent prompt** · [Tests](tests.md) · [API reference](api-reference.md)

---

Paste this to the Helix Agent as one message, replacing the `{{...}}` values. What
to check before you trust the result is in
[Guides](guides.md#build-it-with-the-helix-agent); if something looks off, see
[Troubleshooting](guides.md#troubleshooting).

## Prompt

```text
Step 1:
Create a REST API called "{{api_name}}" in the {{environment}} environment, proxying
https://jsonplaceholder.typicode.com. Two routes: GET /fleet/price-list, which the
upstream serves at /todos/1, and POST /fleet/takings, which it serves at /posts.
Keep my paths.

Step 2:
Our fleet's terminals call these routes, and each terminal has its own API key.
Update both routes so a call is accepted only with a valid key in the X-Device-Key
header: a key in any other header or in the query string is refused, and the
app's secret is never accepted in place of the key. The callers are devices, not
browsers. Put a request id on every response. Deploy it.

Step 3:
Create a developer "{{developer_name}}", a corresponding product and an app to work
with the above API. Give me the app's API key.
```
