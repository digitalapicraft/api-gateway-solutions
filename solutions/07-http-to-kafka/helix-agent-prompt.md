# Agent-mode prompt — HTTP to Kafka ingest

Paste this into **Agent Mode**. It works from a **fresh, empty org**: the agent
*creates* the API, puts the three-plugin chain on one route, dry-runs, and stops.

Replace the `<<...>>` values. Everything else is deliberate — the table below says
why each block earns its place. Read [AGENT-GUIDE.md](../../AGENT-GUIDE.md) first
if you haven't.

**Before you start:** create the Kafka topic explicitly. Auto-creation drops the
message that triggers it, and the caller still gets a 202.

---

## The prompt

> **Run it in steps, not as one mega-prompt.** These are the exact prompts shaped
> for the **default agent model**. Paste **Step 1**, let the agent build the route
> and stop at the dry-run; confirm; then paste **Step 2**.

**Step 1 — create the ingest route**

```text
Create a new REST API called "<<Event Ingest API>>" with a single route,
POST /events, that accepts an event, answers 202 from the gateway itself, and
publishes the body to Kafka. There is no backend service for this route. This is
a fresh org — I have no existing API.

Bind any upstream (use https://jsonplaceholder.typicode.com) — the route never
reaches it, but a revision will not deploy without a binding. Deploy to the
"test" environment.

Put three plugins on POST /events, in this combination:

1. request-validation with a body_schema requiring event_id (string),
   event_type (string) and occurred_at (string), rejected_code 400.
2. mocking with response_status 202, content_type application/json,
   response_example {"accepted":true}, and with_mock_header FALSE.
3. kafka-logger with brokers [{host: "<<YOUR_BROKER_HOST>>", port: 9092}],
   kafka_topic "<<events>>", include_req_body true, producer_type sync,
   batch_max_size 1, required_acks -1, max_retry_count 3, and
   log_format {event: "$request_body", request_id: "$request_id",
   received_at: "$time_iso8601"}.
   Give it _meta.filter [["status","==",202]] so a rejected event is not
   published.

For log_format use $apisix_request_id, NOT $request_id. $request_id is nginx's
own id and never equals the X-Request-Id the request-id plugin returns to the
caller, so a message logged with it cannot be correlated to a request.

Do NOT add hmac-auth or any auth plugin in this step — I know the route is open;
I am adding signing separately and it conflicts with request-validation.

Also add request-id at the API level with header_name X-Request-Id, so the
response and the Kafka message share a correlation id.

Check get_plugin_config for kafka-logger, mocking and request-validation before
writing config. Show me the spec, run validate_route and dry_run_deploy, and
wait before deploying.
```

**Step 2 — prove the edge contract** (same session, after Step 1 deploys)

```text
Give me curl commands that show, in order: a valid event -> 202 {"accepted":true}
with an X-Request-Id header; an event missing event_id -> 400; and confirm the
202 response carries no x-mock-by header.

Then tell me exactly what to look for in my Kafka topic browser to confirm the
event arrived: which field carries my payload, and which field I match against
the X-Request-Id from the 202.

Do not tell me the event reached Kafka based on the 202. kafka-logger publishes
in the log phase, after the response is flushed, so a 202 is returned whether or
not the broker is reachable.
```

The agent creates the API, fetches the real plugin schemas from your org,
proposes the spec, and stops for your confirmation. See
[AGENT-GUIDE.md](../../AGENT-GUIDE.md) for why the prompt is shaped this way.

---

## Why the prompt is shaped this way

| Block | Why it's there |
|---|---|
| **"This is a fresh org — create one"** | On a new org there is no API to "find". The agent must create it, or it stalls. |
| **"Bind any upstream — the route never reaches it"** | A model that understands `mocking` short-circuits will conclude no upstream is needed and skip the binding, and the deploy then fails on a missing binding with an error that looks unrelated. |
| **"use $apisix_request_id, NOT $request_id"** | The bug this package shipped in its first version. `$request_id` is nginx's own id; the `request-id` plugin overwrites `$apisix_request_id` with the UUID it returns to the caller and never touches `$request_id`. A model writing "the obvious" variable produces a correlation field that correlates with nothing. |
| **"with_mock_header FALSE"** | Defaults to true and stamps every response with a header naming the mocking plugin and the gateway version. |
| **"_meta.filter [[\"status\",\"==\",202]]"** | Without it, `kafka-logger`'s log phase runs for the 400 as well, and rejected events reach the topic by the back door — defeating the validation you just configured. |
| **"producer_type sync, required_acks -1, max_retry_count 3"** | Three defaults chosen for logging, not producing: async fire-and-forget, leader-only acks, and **zero** retries. All three need overriding, and none of them is obviously wrong until an event goes missing. |
| **"Do NOT add hmac-auth in this step"** | An agent told the route is open will helpfully secure it — and `hmac-auth`'s `validate_request_body` collides with `request-validation`'s body re-encoding. Two 401s later you are debugging the wrong layer. |
| **"request-id at the API level"** | The correlation id is the only practical way to verify the Kafka half. Without it the manual check is eyeballing the newest message. |
| **"Do not tell me the event reached Kafka based on the 202"** | A model summarising a successful test will write "the event was published". It does not know that, and neither does the 202. |

## Tweak knobs

**Add signing** — note it replaces `request-validation`
```text
Add hmac-auth to POST /events with signed_headers
["@request-target","date","digest"], validate_request_body true, clock_skew 300,
allowed_algorithms ["hmac-sha256","hmac-sha512"], hide_credentials true.

REMOVE request-validation from the route at the same time. Both run in the
rewrite phase and request-validation (2800) re-encodes the body before hmac-auth
(2530) hashes it, so every digest comparison fails with a bare 401. The published
Kafka payload stays complete either way.

Then create a product with authMethods ["hmac-auth"], a developer, and an app
with plugins {"hmac-auth": {}} so I get a key_id and secret_key.
```

**Identity without touching the body** — keeps `request-validation`
```text
Instead of hmac-auth, add helix-auth in validate mode, so callers are identified
by their app credential. It does not touch the request body, so
request-validation can stay on the route.
```

**A real acknowledgement instead of at-most-once**
```text
Replace mocking and kafka-logger with a service-callout to our Kafka REST Proxy
at <<http://kafka-rest:8082/topics/events>>, in the access phase, synchronous,
with error_handling.policy fail-close so the caller gets a 503 when Kafka rejects
the message rather than a 202 it cannot trust.
```

**A second event type**
```text
Add POST /events/telemetry with the same three plugins but kafka_topic
"<<telemetry>>" and a body_schema requiring device_id and reading (number).
```
