# Agent-mode prompt — answer an agreed contract before the backend exists

> [Overview](README.md) · [Business need](business-need.md) · [Architecture](architecture.md) · [Guides](guides.md) · **Agent prompt** · [Tests](tests.md) · [API reference](api-reference.md)

---

Paste this to the Helix Agent as one message, replacing the `{{...}}` values. It
builds and deploys the mocked API. When it finishes, read the deployed revision
back and check that `/shipments/:shipmentId` was stored with a colon, not
braces, and that both routes carry the mock. See
[Troubleshooting](guides.md#troubleshooting) if something looks off.

## Prompt

```text
Step 1:
Create a REST API called "{{api_name}}" in the {{environment}} environment. Its
backend will be https://jsonplaceholder.typicode.com, which only answers
requests addressed to its own host name. Two routes:
GET /shipments/:shipmentId to track one shipment, and POST /shipments to create one.

Step 2:
The backend for these routes doesn't exist yet. Until it does, the gateway must
answer both routes itself and never call the backend.
GET /shipments/:shipmentId answers 200 with exactly this JSON, whatever the id:
{"shipmentId":"SHP-1001","status":"IN_TRANSIT","carrier":"Acme Freight","eta":"2026-11-04T17:00:00Z","events":[{"at":"2026-10-28T09:12:00Z","status":"PICKED_UP","location":"Rotterdam"},{"at":"2026-10-29T22:40:00Z","status":"DEPARTED_HUB","location":"Rotterdam"},{"at":"2026-10-30T06:05:00Z","status":"ARRIVED_HUB","location":"Leeds"}]}
POST /shipments answers 201 with the header Location: /shipments/SHP-1001 and exactly this JSON:
{"shipmentId":"SHP-1001","status":"LABEL_CREATED","carrier":"Acme Freight","eta":"2026-11-04T17:00:00Z","events":[]}
Both answers are application/json. Each answer must carry a header that tells
the frontend it is talking to a mock.
Put a request id on every response. Deploy it.
```
