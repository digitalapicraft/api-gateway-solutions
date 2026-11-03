# Agent-mode prompt — HTTP to Kafka ingest

> [Overview](README.md) · [Business need](business-need.md) · [Architecture](architecture.md) · [Guides](guides.md) · **Agent prompt** · [Tests](tests.md) · [API reference](api-reference.md)

---

**Create the Kafka topic first**: auto-creation drops the message that triggers it,
and the caller still gets a 202. Then paste this to the Helix Agent as one message,
replacing the `{{...}}` values. What to check before you trust the result is in
[Guides](guides.md#build-it-with-the-helix-agent); if something looks off, see
[Troubleshooting](guides.md#troubleshooting).

## Prompt

```text
Step 1:
Create a REST API called "{{api_name}}" in the {{environment}} environment, proxying
https://jsonplaceholder.typicode.com. One route: POST /events. The gateway answers
this route itself; nothing reaches the upstream. Keep my path.

Step 2:
Partners post events to POST /events, and we keep them on our Kafka topic
{{kafka_topic}}, on the broker at {{kafka_broker_host}}, port 9092. Update the route
so that:
- an event without event_id, event_type or occurred_at is refused with a 400 and
  never reaches the topic.
- every other event gets a 202 with {"accepted":true} straight away, as the
  gateway's own answer with no header saying it was mocked, and its body is
  published to the topic once every replica has acknowledged it.
- each message on the topic carries the event, the time it arrived, and the
  request id the caller got back.
- every response carries a request id in X-Request-Id.
Leave the route open for now; identity comes later.
```
