# Install — Solution 07 — HTTP to Kafka: accept events at the edge, publish them without an ingest service

[Overview](readme.md) · [Business need](business-need.md) · [How it works](how-it-works.md) · **Install** · [Configuration](configuration.md) · [Test & verify](testing.md) · [Changelog](changelog.md)

---

## Build it with the Agent

See [helix-agent-prompt.md](helix-agent-prompt.md) for the step-by-step prompts,
verified on the default agent model.

**One limitation is specific to this solution.** The agent path installs the
route and all three plugins, but it cannot carry a property-level `body_schema` —
the nesting depth reproducibly corrupts the agent's own tool-call arguments, so
nothing gets written at all. The prompt therefore ships a required-only schema,
which still rejects events missing `event_id`, `event_type` or `occurred_at` but
does not constrain their types. For the full schema in
[`gateway/api-spec.yaml`](gateway/api-spec.yaml), import the spec as below — that
path is unaffected. The failure and the evidence are documented under *Known
failure modes* in the prompt.

## Install it directly

```text
1. Replace <YOUR_KAFKA_BROKER> in gateway/api-spec.yaml with a broker hostname
   the GATEWAY can reach — not one only your laptop can reach — and set
   kafka_topic to your topic. Neither value is a secret.

2. CREATE THE TOPIC EXPLICITLY. Do not rely on auto-creation: the message that
   triggers topic creation is dropped, and the caller still gets its 202.

3. Import gateway/api-spec.yaml and bind any upstream to the service. The /events
   route never reaches it — mocking short-circuits first — but a revision will not
   deploy without a binding.

4. Deploy the revision to the "test" environment (a free-trial org's default).

5. Prove the edge contract
   GATEWAY=https://<YOUR_GATEWAY_HOST> ./gateway/verify.sh

6. Prove the Kafka leg in your topic browser — see below. Step 5 cannot do it.
```

## Step 1 — create the ingest route

This is the one step in the library that hands the agent literal JSON rather than
an outcome. Asked to compose this route from prose, the agent's tool-call
serialiser corrupts its own arguments and writes nothing — reproducibly, 5 runs
out of 5. Handing it the object to copy is the form that was verified to work.

```text
Create a REST API "<<Event Ingest API>>" with a single route POST /events that
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
        "brokers": [{"host": "<<YOUR_BROKER_HOST>>", "port": 9092}],
        "kafka_topic": "<<events>>",
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

**The schema here is deliberately shallow** — the three fields are required but
their types aren't constrained. That is the most the agent path can carry on this
build (see the failure table below). For the full property-level schema in
[`gateway/api-spec.yaml`](gateway/api-spec.yaml), import the spec instead. Both
routes end at the same config.

## Step 2 — prove the edge contract

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

---

## Why it's shaped this way

- **The literal JSON route object.** See the failure table — composing it from
  prose fails reproducibly.
- **"Bind any upstream".** A model that understands `mocking` short-circuits will
  conclude no upstream is needed, and the deploy then fails on a missing binding
  with an error that looks unrelated.
- **`$apisix_request_id`, not `$request_id`.** The bug this package shipped in its
  first version. The `request-id` plugin overwrites `$apisix_request_id` with the
  UUID the caller sees and never touches `$request_id`, so the obvious variable
  produces a correlation field that correlates with nothing.
- **`_meta.filter` on status 202.** Without it `kafka-logger` also runs for the
  400, and rejected events reach the topic by the back door.
- **`producer_type: sync`, `required_acks: -1`, `max_retry_count: 3`.** Three
  defaults chosen for logging rather than producing — async fire-and-forget,
  leader-only acks, and zero retries. None looks wrong until an event goes missing.
- **`with_mock_header: false`.** Defaults to true and stamps every response with a
  header naming the plugin and the gateway version.
- **No auth in step 1.** An agent told the route is open will helpfully secure it,
  and `hmac-auth`'s body validation collides with `request-validation`.
- **"Don't tell me it reached Kafka based on the 202."** A model summarising a
  successful test will write "the event was published". It doesn't know that.

## Tweak knobs

**Add signing** — it replaces `request-validation`
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

**Identity without touching the body** — keeps `request-validation`
```text
Instead of hmac-auth, add helix-auth in validate mode so callers are identified by
their app credential. It doesn't touch the body, so request-validation can stay.
```

**A real acknowledgement instead of at-most-once**
```text
Replace mocking and kafka-logger with a service-callout to our Kafka REST Proxy at
<<http://kafka-rest:8082/topics/events>>, access phase, synchronous,
error_handling.policy fail-close — so the caller gets a 503 when Kafka rejects the
message rather than a 202 it cannot trust.
```

**A second event type**
```text
Add POST /events/telemetry with the same three plugins but kafka_topic
"<<telemetry>>" and a body_schema whose required list is ["device_id","reading"].
Keep the body_schema to type and required only — no properties map.
```

---

## When it goes wrong

Observed on the default agent model against a live org, 2026-09-21, seven runs.

| What you see | What is happening | What to do |
|---|---|---|
| `stream closed with reason: error`, and the revision shows **0 routes** | The serialiser emitted malformed JSON for `update_route_spec` and the call never reached the control plane. Nothing was written; the API exists, empty. | Check your route object matches the one above, and keep `properties` out of `body_schema` (next row). |
| The same error every time, when `body_schema` carries a `properties` map | **Reproducible, not intermittent — 5 of 5.** The nesting depth makes the serialiser transpose its closing delimiters: `…1}}]}}` where `…1}}}]}` is valid, closing the `routeSpec` array before the route object. Removing that one level made the identical prompt succeed. | Use the required-only schema via the agent, or import [`gateway/api-spec.yaml`](gateway/api-spec.yaml) for the full one. Spec import is unaffected. |
| The route deploys, but `plugins` contains `response_status`, `content_type`… as if they were plugin names | The agent dropped the plugin-name level and promoted one plugin's fields into the map. The write succeeds and the dry-run passes; the route carries several nonexistent plugins and none of the real one. | Read the revision back. The prompt states that level explicitly to prevent it. |
| Success reported, dry-run passes, route has no plugins | The route object carried an `x-helix-gateway` wrapper, which a live route silently discards. | Re-send with `plugins` as a top-level key. |

**Reading the revision back is not optional here.** Three of those four report
success at every step the agent shows you.
