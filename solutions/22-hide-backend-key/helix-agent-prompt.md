# Agent-mode prompt — keep a supplier's API key out of every client

> [Overview](README.md) · [Business need](business-need.md) · [Architecture](architecture.md) · [Guides](guides.md) · **Agent prompt** · [Tests](tests.md) · [API reference](api-reference.md)

---

Replace the `{{...}}` values, then paste the prompt to the Helix Agent as one
message. If the run ends early, paste the three steps one at a time instead.
`{{supplier_api_key}}` is your supplier's real key, or any test value if you are
trying it with postman-echo.com. When it finishes, read the deployed revision
back: the supplier key must be stored as the literal value, not as a reference
such as `<ENV:...>`, and `X-Api-Key` must be on the list of headers removed. See
[Troubleshooting](guides.md#troubleshooting) if something looks off.

## Prompt

```text
Step 1:
Create a REST API called "{{api_name}}" in the {{environment}} environment,
proxying our weather supplier at postman-echo.com over HTTPS. One route,
GET /forecast, sent to the supplier's /get path.

Step 2:
Our supplier gave us one API key, and no client app may hold it. Every call to
/forecast must carry the calling app's own key in the X-Api-Key header; a
missing or unknown key gets a 401 at the gateway. On its way to the supplier,
every request must carry X-Supplier-Key: {{supplier_api_key}}, whatever the
client sent in that header, and must no longer carry the client's X-Api-Key.
Store the supplier key exactly as written here. Put a request id on every
response. Deploy it.

Step 3:
Create a product "{{api_name}}-product" with this API and deploy it. Create a
developer with the email {{developer_email}} and an app "{{api_name}}-app" on
that product, and give me the app's key.
```
