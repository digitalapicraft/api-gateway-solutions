# Agent-mode prompt — HTTP to Kafka ingest

> [Overview](README.md) · [Business need](business-need.md) · [Architecture](architecture.md) · [Guides](guides.md) · **Agent prompt** · [Tests](tests.md) · [API reference](api-reference.md)

---

**Create the Kafka topic first** — auto-creation drops the message that triggers
it, and the caller still gets a 202. Then paste step 1, replacing the `{{...}}`
values and leaving the route JSON exactly as written, and paste step 2 once the
revision has been read back.

The optional prompts at the end are independent of each other; paste one after
step 2 only if you need it. See [Guides](guides.md#build-it-with-the-helix-agent)
if something looks off.

## Prompt

### Step 1 — create the ingest route

```text
Create a REST API "{{api_name}}" with a single route POST /events that
validates an event, answers 202 from the gateway itself, and publishes the body to
Kafka. There is no backend service for this route. Fresh org — nothing exists yet.

Bind any upstream (https://jsonplaceholder.typicode.com will do) — the route never
reaches it, but a revision won't deploy without a binding. Environment: test.

Don't compose the plugin config yourself, and don't add hmac-auth or any auth
plugin — I know the route is open, and signing conflicts with request-validation.
Send routeSpec as a JSON array containing exactly this one route object,
reproduced verbatim except for service_id, which is the API id:

[
  {
    "name": "event-ingest",
    "uri": "/events",
    "methods": ["POST"],
    "service_id": "<THE API ID>",
    "plugins": {
      "request-validation": {
        "body_schema": {
          "type": "object",
          "required": ["event_id", "event_type", "occurred_at"]
        },
        "rejected_code": 400,
        "rejected_msg": "the event failed schema validation"
      },
      "mocking": {
        "response_status": 202,
        "content_type": "application/json",
        "response_example": "{\"accepted\":true}",
        "with_mock_header": false
      },
      "kafka-logger": {
        "brokers": [{"host": "{{kafka_broker_host}}", "port": 9092}],
        "kafka_topic": "{{kafka_topic}}",
        "_meta": {"filter": [["status", "==", 202]]},
        "include_req_body": true,
        "log_format": {
          "event": "$request_body",
          "request_id": "$apisix_request_id",
          "received_at": "$time_iso8601"
        },
        "producer_type": "sync",
        "batch_max_size": 1,
        "required_acks": -1,
        "max_retry_count": 3,
        "retry_delay": 1
      }
    }
  }
]

Two nesting levels matter: each plugin is keyed by its own NAME inside "plugins",
and "_meta" sits inside kafka-logger. No "x-helix-gateway" wrapper anywhere — a
live route discards it silently and still reports success.

That is $apisix_request_id, NOT $request_id. $request_id is nginx's own id and
never equals the X-Request-Id the request-id plugin returns to the caller.

Also add request-id at the API level with header_name X-Request-Id, so the
response and the Kafka message share a correlation id.

Dry-run it, then read the revision back so I can see which plugins actually
landed. Wait before deploying.
```

### Step 2 — prove the edge contract

```text
Give me curl commands showing, in order: a valid event → 202 {"accepted":true}
with an X-Request-Id header; an event missing event_id → 400; and confirm the 202
carries no x-mock-by header.

Then tell me exactly what to look for in my Kafka topic browser: which field
carries my payload, and which field I match against the X-Request-Id from the 202.

Do not tell me the event reached Kafka based on the 202. kafka-logger publishes in
the log phase, after the response is flushed, so a 202 comes back whether or not
the broker is reachable.
```

### Optional — add signing (it replaces request-validation)

```text
Add hmac-auth to POST /events with signed_headers ["@request-target","date",
"digest"], validate_request_body true, clock_skew 300, allowed_algorithms
["hmac-sha256","hmac-sha512"], hide_credentials true.

REMOVE request-validation at the same time. Both run in the rewrite phase and
request-validation (2800) re-encodes the body before hmac-auth (2530) hashes it,
so every digest comparison fails with a bare 401. The Kafka payload is complete
either way.

Then create a product with authMethods ["hmac-auth"], a developer, and an app with
plugins {"hmac-auth": {}} so I get a key_id and secret_key.
```

### Optional — identity without touching the body (keeps request-validation)

```text
Instead of hmac-auth, add helix-auth in validate mode so callers are identified by
their app credential. It doesn't touch the body, so request-validation can stay.
```

### Optional — a real acknowledgement instead of at-most-once

```text
Replace mocking and kafka-logger with a service-callout to our Kafka REST Proxy at
{{kafka_rest_url}}, access phase, synchronous,
error_handling.policy fail-close — so the caller gets a 503 when Kafka rejects the
message rather than a 202 it cannot trust.
```

### Optional — a second event type

```text
Add POST /events/telemetry with the same three plugins but kafka_topic
"{{telemetry_topic}}" and a body_schema whose required list is ["device_id","reading"].
Keep the body_schema to type and required only — no properties map.
```
