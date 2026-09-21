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

> **Why this step hands the agent literal JSON.** Asked to compose this route from
> prose, the agent's tool-call serialiser corrupts the arguments and writes nothing
> — reproducibly, not occasionally. See *Known failure modes* below. Handing it the
> object to copy is the form that was verified to work.

```text
Create a new REST API called "<<Event Ingest API>>" with a single route,
POST /events, that validates an event, answers 202 from the gateway itself, and
publishes the body to Kafka. There is no backend service for this route. This is
a fresh org — I have no existing API.

Bind any upstream (use https://jsonplaceholder.typicode.com) — the route never
reaches it, but a revision will not deploy without a binding. Deploy to the
"test" environment.

Do NOT compose the plugin config yourself and do NOT add hmac-auth or any auth
plugin — I know the route is open; I am adding signing separately and it
conflicts with request-validation. Send routeSpec as a JSON array containing
exactly this one route object, reproduced verbatim except for service_id, which
is the API id:

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

Note the two nesting levels that matter: each plugin is keyed by its own NAME
inside "plugins", and "_meta" sits inside kafka-logger.

In log_format that is $apisix_request_id, NOT $request_id. $request_id is
nginx's own id and never equals the X-Request-Id the request-id plugin returns
to the caller, so a message logged with it cannot be correlated to a request.

Also add request-id at the API level with header_name X-Request-Id, so the
response and the Kafka message share a correlation id.

We are editing a LIVE route object, not authoring an OpenAPI document — so do not
follow the spec-generator examples for plugin placement. There must be no
"x-helix-gateway" key anywhere in a route object: a live route silently discards
that wrapper, the write still reports success, and the route deploys with no
plugins at all.

Skip validate_route (it fails on this build whatever you put in it) and run
dry_run_deploy, then call get_revision and show me the stored routeSpec so I can
see the plugins landed. Wait before deploying.
```

**The schema this step installs is deliberately shallow** — it requires the three
fields but does not constrain their types. That is not a simplification for
readability; it is the most the agent path can carry on this build (again, see
*Known failure modes*). To get the full property-level schema in
[`gateway/api-spec.yaml`](gateway/api-spec.yaml) — types and `minLength` — import
the spec instead, per [Install it directly](README.md#install-it-directly). Both
routes end at the same config; only the agent path is limited.

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
| **The literal JSON route object** | Verified over seven runs: asked to compose this route from prose, the agent corrupts its own tool arguments and writes nothing — 5 failures out of 5 while a `properties`-level `body_schema` was in play. Given the object to copy, and with that one level removed, it reproduced it exactly. |
| **"each plugin is keyed by its own NAME"** | Verified: in one run the agent dropped that level and wrote `plugins: {response_status, content_type, …}` — four nonexistent plugins, no `mocking`, and a passing dry-run. |
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
"<<telemetry>>" and a body_schema whose required list is ["device_id","reading"].
Keep the body_schema to type and required only — no properties map.
```

---

## Known failure modes when running this prompt

Observed on the default agent model against a live org on 2026-09-21, seven runs.

| What you see | What is happening | What to do |
|---|---|---|
| `stream closed with reason: error`, and `get_revision` shows **0 routes** | The agent's tool-call serialiser emitted malformed JSON for `update_route_spec` and the call never reached the control plane. Nothing was written — the API exists, empty. | Confirm the route object in your prompt matches the one above. Do **not** ask for a property-level `body_schema` (next row). |
| The same error, every time, when `request-validation.body_schema` carries a `properties` map | **Reproducible, not intermittent — 5 runs out of 5.** Deep object nesting in the tool argument makes the serialiser transpose its closing delimiters: it emits `…1}}]}}` where the valid text is `…1}}}]}`, closing the `routeSpec` array before the route object. Dropping the single `properties` level made the identical prompt succeed. | Install the required-only schema shown above via the agent, or import [`gateway/api-spec.yaml`](gateway/api-spec.yaml) to get the full schema. The spec-import path is unaffected. |
| The route deploys, but `plugins` contains `response_status`, `content_type`, `with_mock_header`… as if they were plugin names | The agent dropped the **plugin-name** level and promoted one plugin's fields into the `plugins` map. The write succeeds and the dry-run passes; the route ends up with several nonexistent plugins and none of the real one. | Read the revision back. The prompt above states the plugin-name level explicitly to prevent this. |
| The write reports success and the dry-run passes, but the route has no plugins | The route object carried an `x-helix-gateway` wrapper, which a live route silently discards. | Re-send with `plugins` as a top-level key of the route object. |

**`get_revision` is not optional here.** Three of the four failures above report
success at every step the agent shows you. Reading the stored `routeSpec` back is
the only point in the toolchain where they become visible.
