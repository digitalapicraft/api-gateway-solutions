# Agent-mode prompt — a catalogue anyone can read and only partners can change

> [Overview](README.md) · [Business need](business-need.md) · [Architecture](architecture.md) · [Guides](guides.md) · **Agent prompt** · [Tests](tests.md) · [API reference](api-reference.md)

---

Paste this to the Helix Agent as one message, replacing every `{{...}}` value
first. If the run ends early, paste the three steps one at a time instead. When
it finishes, read the revision back: the key check must be on the three write
routes and **not** on the whole API, and both item paths must read
`/catalog/items/:itemId`, with a colon. See
[Troubleshooting](guides.md#troubleshooting) if something looks off.

## Prompt

```text
Step 1:
Create a REST API called "{{api_name}}" in the {{environment}} environment, proxying
https://jsonplaceholder.typicode.com. It is our product catalogue, with five
routes: GET /catalog/items and GET /catalog/items/:itemId to read it,
POST /catalog/items to add an item, PUT /catalog/items/:itemId to change one, and
DELETE /catalog/items/:itemId to remove one. Keep these public paths; the backend
serves the same data at /posts and /posts/:itemId.

Step 2:
Anyone must be able to read the catalogue with no key, including search engines
and comparison sites. Only our partners may add, change or remove items: the
three write routes must require a partner's API key in the X-Api-Key header, and
refuse a missing or unknown key with a 401 before it reaches the backend. The
reads stay open, so the key check goes on the write routes only, not on the
whole API. Put a request id on every response. Deploy it.

Step 3:
Create a product containing this API and deploy it to {{environment}}. Then create
a developer "{{developer_name}}" ({{developer_email}}) with one app,
"{{app_name}}", subscribed to that product, and give me the app's API key.
```
