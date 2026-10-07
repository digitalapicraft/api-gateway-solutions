# Guides — HTTP to Kafka at the edge

> [Overview](README.md) · [Business need](business-need.md) · [Architecture](architecture.md) · **Guides** · [Agent prompt](helix-agent-prompt.md) · [Tests](tests.md) · [API reference](api-reference.md)

---

Three ways to build the same thing, then how to see it work. Whichever way you
pick, the result is one API with a single route, `POST /events`, that checks an
event, answers `202 {"accepted":true}` itself, and publishes the event to your
Kafka topic.

**Before any of them: create the Kafka topic.** Don't rely on the broker creating
it automatically. The message that triggers auto-creation is dropped, and the
caller still gets a 202.

## Pick your path

| | Choose this if you… | Go to |
|---|---|---|
| **1. Helix Agent** | want the quickest result and are happy to paste a prompt | [Build it with the Helix Agent](#build-it-with-the-helix-agent) |
| **2. Helix control plane** | prefer clicking through screens | [Build it in the UI](#build-it-in-the-ui) |
| **3. API script** | are scripting this, or wiring it into a pipeline | [Install it directly](#install-it-directly) |

Then, for everyone: [See it work](#see-it-work) · [Variations](#variations) ·
[Configuration reference](#configuration-reference) · [Troubleshooting](#troubleshooting)

## Build it with the Helix Agent

Works on a **fresh, empty org**. [`helix-agent-prompt.md`](helix-agent-prompt.md)
has two steps: step 1 creates the route with all three plugins, step 2 asks the
agent for the commands that prove it. Paste step 1, check the result, then paste
step 2.

**One limitation applies only to the agent path.** The agent can't write a
`body_schema` with a `properties` map. That extra level of nesting makes the
agent's own tool call come out malformed, every time it was tried, and nothing is
written. So the prompt ships a schema that only lists the **required** fields: it
still rejects an event missing `event_id`, `event_type` or `occurred_at`, but
doesn't check their types. For the full schema in
[`example/api-spec.yaml`](example/api-spec.yaml), import the spec instead
([Build it in the UI](#build-it-in-the-ui) or [Install it directly](#install-it-directly)).
Importing a spec doesn't have this problem. The general rule: give the agent
shallow structures, and use spec import for anything deeper.

**Why the prompt is shaped the way it is:**

- **Step 1 hands the agent a literal JSON route object** instead of describing
  the outcome. This is the only prompt in the library that does. Asked to compose
  this route from a description, the agent's tool call comes out malformed and
  nothing is written. Given the object to copy, it works.
- **"Bind any upstream."** An agent that knows `mocking` answers by itself may
  decide no upstream is needed. The deploy then fails on a missing binding, with
  an error that looks unrelated.
- **`$apisix_request_id`, not `$request_id`.** The first version of this package
  got this wrong. The `request-id` plugin overwrites `$apisix_request_id` with the
  UUID the caller sees and never touches `$request_id`, so the obvious variable
  gives a correlation field that matches nothing.
- **`_meta.filter` on status 202.** Without it, `kafka-logger` also runs for a
  400, and rejected events reach the topic anyway.
- **`producer_type: sync`, `required_acks: -1`, `max_retry_count: 3`.** Three
  defaults chosen for logging rather than producing: send-and-forget, leader-only
  acknowledgement, and no retries. None looks wrong until an event goes missing.
- **`with_mock_header: false`.** It defaults to true and stamps every response
  with a header naming the plugin and the gateway version.
- **No authentication in step 1.** An agent told the route is open will helpfully
  secure it, and `hmac-auth`'s body check collides with `request-validation`.
- **"Don't tell me it reached Kafka based on the 202."** An agent summarising a
  successful test will write "the event was published". It can't know that.

**Read the revision back after step 1.** Three of the four failures below report
success at every step the agent shows you.

| What you see | What is happening | What to do |
|---|---|---|
| `stream closed with reason: error`, and the revision has **0 routes** | The agent's tool call came out as malformed JSON and never reached the control plane. Nothing was written; the API exists, empty. | Check the route object matches the one in the prompt, and keep `properties` out of `body_schema` (next row). |
| The same error every time, when `body_schema` has a `properties` map | **Reproducible, not occasional.** The extra nesting makes the agent swap its closing brackets: `…1}}]}}` where `…1}}}]}` is valid, which closes the `routeSpec` array before the route object. Removing that one level made the identical prompt succeed. | Use the required-only schema with the agent, or import [`example/api-spec.yaml`](example/api-spec.yaml) for the full one. |
| The route deploys, but `plugins` contains `response_status`, `content_type`… as if they were plugin names | The agent dropped the plugin-name level and put one plugin's fields straight into the map. The write succeeds and the dry-run passes; the route carries several plugins that don't exist and none of the real one. | Read the revision back. The prompt names that level explicitly to prevent it. |
| Success reported, dry-run passes, the route has no plugins | The route object carried an `x-helix-gateway` wrapper, which a live route silently discards. | Send again with `plugins` as a top-level key on the route. |

See [AGENT-GUIDE.md](../../AGENT-GUIDE.md) for the ground rules these prompts
assume.

## Build it in the UI

Screen and button names below are the real ones. The API lives under
**API Gateway** in the left sidebar.

**Before you start:**

- **You have an account.** If you don't, register for a free trial at
  [trial.digitalapi.ai](https://trial.digitalapi.ai/). A new trial org comes with
  a `test` environment, which is all this walkthrough needs.
- **Your org has the plugins.** `kafka-logger`, `mocking` and
  `request-validation` must be available. Ask your org admin if you're not sure.
- **You have a Kafka broker the gateway can reach**, and you have created the
  topic.

**1. Put your broker and topic into the spec**
Open [`example/api-spec.yaml`](example/api-spec.yaml). Replace
`<YOUR_KAFKA_BROKER>` with a broker hostname the **gateway** can reach (not one
only your laptop can reach), and change `kafka_topic: events` to your topic.
Neither value is a secret. If your broker needs SASL, the `brokers` entry takes a
`sasl_config` object; check the plugin's schema in your org.

**2. Import the API**
1. Go to **API Gateway → APIs**, click **Add API** (or **Create your first API**).
2. Set **Method** to **Import an OpenAPI spec**.
3. Drag in your edited `api-spec.yaml`, or paste its contents, then click
   **Import**.

This creates the API and its first revision. The imported spec already carries
all four plugins — `request-validation`, `mocking`, `kafka-logger` and
`request-id` — with the settings in the
[Configuration reference](#configuration-reference). There is no separate screen
to set them up in this walkthrough.

**3. Give it an upstream, then deploy it**
1. Go to **API Gateway → Upstreams → Add Upstream**. Name it, pick environment
   `test`, point it at any host (for example `jsonplaceholder.typicode.com`), then
   **Create Upstream**. The `/events` route never contacts it, but a revision
   won't deploy without one.
2. Back on the API's page, click **Deploy** on the revision. The dialog asks you
   to map an upstream for `test`. Pick the one you just created, then **Deploy**.

That's it. No products, developers or apps are needed, because the route ships
unauthenticated. Read [Where authentication would go](architecture.md#where-authentication-would-go)
before you point real partners at it.

## Install it directly

If you'd rather script it against the control plane:

```bash
export ORG=<ORG_ID>
export TOKEN=<control-plane bearer token>      # short-lived
export BASE=https://<YOUR_GATEWAY_HOST>/api
H=(-H "authorization: Bearer $TOKEN" -H 'content-type: application/json')

# 0. Create the topic on your broker first, with your Kafka tooling.
#    Then edit example/api-spec.yaml: replace <YOUR_KAFKA_BROKER> with a broker
#    host the GATEWAY can reach, and set kafka_topic to your topic.

# 1. Import the spec. It carries all four plugins. Keep both ids it returns.
curl -s -H "authorization: Bearer $TOKEN" \
  -F "file=@example/api-spec.yaml" "$BASE/orgs/$ORG/apis/from-spec"
# → {"api":{"id":"<API_ID>", ...}, "revision":{"id":"<REVISION_ID>", ...}}

# 2. Import does NOT make the route live. Create an upstream — any host will do, the
#    route never reaches it — bind it to the revision, then deploy the revision.
curl -s "${H[@]}" -X POST "$BASE/orgs/$ORG/envs/<TEST_ENV_ID>/upstreams" \
  -d '{"name":"ingest-upstream","specification":{"scheme":"https","nodes":[{"host":"jsonplaceholder.typicode.com","port":443,"weight":1}]}}'
# → {"id":"<UPSTREAM_ID>", ...}

curl -s "${H[@]}" -X PATCH "$BASE/orgs/$ORG/apis/<API_ID>/revisions/<REVISION_ID>/upstream-bindings/add" \
  -d '{"environmentUpstreams":[{"environmentId":"<TEST_ENV_ID>","upstreamId":"<UPSTREAM_ID>"}]}'
curl -s "${H[@]}" -X POST "$BASE/orgs/$ORG/apis/<API_ID>/revisions/<REVISION_ID>/deploy" \
  -d '{"environmentId":"<TEST_ENV_ID>","force":false}'
```

> Revisions must be **INACTIVE** to accept a spec change. If it's live, undeploy
> first, or clone the revision so you keep a rollback target.

The same calls without narration: [API reference](api-reference.md).

## See it work

Prove the part a caller can see:

```bash
GATEWAY=https://<YOUR_GATEWAY_HOST> ./example/verify.sh
```

It posts a valid event, a malformed one and checks the headers, then prints the
`event_id` and `X-Request-Id` of the event it posted. Exit code 0 means the edge
contract holds. What each check proves: [Tests](tests.md).

### Verifying the Kafka leg

`verify.sh` deliberately doesn't try to check Kafka. It can't: the publish
happens after the response, so nothing in any response shows whether it worked.
A script that took a 202 as proof of delivery would be making exactly the
assumption this solution warns against.

Take the `event_id` and `X-Request-Id` that `verify.sh` printed to your topic
browser:

1. Open the topic in Kafka UI, Redpanda Console, or
   `kafka-console-consumer.sh --from-beginning`.
2. Look at the newest messages. Find the one whose `request_id` matches the
   `X-Request-Id` that `verify.sh` printed.
3. Confirm its `event` field contains the JSON you posted.

**Step 3 is the real check.** Match on `request_id` rather than picking the newest
message: on a busy topic, timestamps can't tell apart two events posted in the
same second, and `received_at` is the gateway's clock, not yours. Published
messages also carry `route_id` and `service_id` alongside the fields in
`log_format`, so don't treat `log_format` as the complete list when you write a
consumer schema.

**Run the broker-down test once**, in front of whoever is deciding whether this
suits the data. Point `brokers[].host` at an address that doesn't answer and post
a valid event. You still get a 202, at normal speed, and the event never reaches
the topic. The caller has no way to tell. It is the quickest way to make the
limitation concrete.

## Variations

Each of these has a ready-made prompt at the end of
[`helix-agent-prompt.md`](helix-agent-prompt.md#prompt). Use one only if you need
it.

**Add signing — it replaces `request-validation`.** Add `hmac-auth` to
`POST /events` with `signed_headers ["@request-target","date","digest"]`,
`validate_request_body: true`, `clock_skew: 300`, and remove
`request-validation` at the same time. Both run in the rewrite phase and
`request-validation` (2800) re-encodes the body before `hmac-auth` (2530) checks
it, so every signature check would fail with a 401. Then create a product with
`authMethods ["hmac-auth"]`, a developer, and an app so callers get a `key_id`
and `secret_key`. Validate the event shape in your consumer instead. Full
walkthrough: [solution 06](../06-hmac-auth/).

**Know who is calling, without touching the body.** Add `helix-auth` in validate
mode so callers are identified by their app credential. It doesn't touch the body,
so `request-validation` can stay. You lose proof that the body wasn't changed.

**A real acknowledgement instead of at-most-once.** Replace `mocking` and
`kafka-logger` with a `service-callout` to a Kafka REST Proxy, in the access
phase, with `error_handling.policy: fail-close`. The caller then gets a 503 when
Kafka rejects the message, rather than a 202 it can't trust. It costs an HTTP hop,
a REST-proxy deployment and latency on every request. See
[solution 11](../11-service-callout/) for how `service-callout` behaves.

**A second event type.** Add `POST /events/telemetry` with the same three plugins,
a different `kafka_topic`, and a `body_schema` listing its own required fields.
Through the agent, keep that schema to `type` and `required` only — no
`properties` map — for the reason in
[Build it with the Helix Agent](#build-it-with-the-helix-agent).

## Configuration reference

Source of truth: [`example/api-spec.yaml`](example/api-spec.yaml). The `/events`
route carries three plugins, and `request-id` is set API-wide:

```yaml
request-validation:
  body_schema:
    type: object
    required: [event_id, event_type, occurred_at]
    properties:
      event_id:    { type: string, minLength: 1 }
      event_type:  { type: string, minLength: 1 }
      occurred_at: { type: string }
      payload:     { type: object }
  rejected_code: 400
  rejected_msg: "the event failed schema validation"

mocking:
  response_status: 202
  content_type: "application/json"
  response_example: '{"accepted":true}'
  with_mock_header: false

kafka-logger:
  brokers:
    - host: "<YOUR_KAFKA_BROKER>"
      port: 9092
  kafka_topic: events
  _meta:
    filter:
      - ["status", "==", 202]
  include_req_body: true
  log_format:
    event: "$request_body"
    request_id:  "$apisix_request_id"
    received_at: "$time_iso8601"
  producer_type: sync
  batch_max_size: 1
  required_acks: -1
  max_retry_count: 3
  retry_delay: 1
```

| Plugin | Field | Value here | What it means |
|---|---|---|---|
| `request-validation` | `body_schema` | required `event_id`, `event_type`, `occurred_at` | A JSON Schema. Keep it in step with the OpenAPI `requestBody` schema: they are two separate documents and nothing keeps them in step. The first enforces, the second documents. |
| `request-validation` | `rejected_code` / `rejected_msg` | `400` / `the event failed schema validation` | What a caller gets for a malformed event. |
| `mocking` | `response_status` / `response_example` | `202` / `{"accepted":true}` | The gateway's own answer. No backend is contacted. |
| `mocking` | `with_mock_header` | `false` | Defaults to **true**, which stamps every response with a header naming the plugin and the gateway version. |
| `kafka-logger` | `brokers` / `kafka_topic` | `<YOUR_KAFKA_BROKER>:9092` / `events` | Replace both. The broker must be reachable from the gateway. |
| `kafka-logger` | `_meta.filter` | `status == 202` | Without it a 400 is published too, and rejected events reach the topic anyway. |
| `kafka-logger` | `include_req_body` | `true` | Tested and **not** needed for the body to be published when `log_format` uses `$request_body`. Left on because it costs nothing. |
| `kafka-logger` | `log_format` | `event`, `request_id`, `received_at` | `request_id` must be `$apisix_request_id`, not `$request_id`. See [Architecture](architecture.md#correlation-matching-a-request-to-its-message). |
| `kafka-logger` | `producer_type` | `sync` | A real broker round trip, so a rejection is logged rather than vanishing. Also removes the async producer's 1-second wait. |
| `kafka-logger` | `required_acks` | `-1` | All in-sync replicas. The default, `1`, is the leader only, which loses the event if the leader fails before copying it. |
| `kafka-logger` | `max_retry_count` / `retry_delay` | `3` / `1` | The default is **0**: a failed batch is dropped, not retried. |
| `kafka-logger` | `batch_max_size` | `1` | Publish each event on its own rather than in batches. Costs ordering — see [What it does not do](architecture.md#what-it-does-not-do). |
| `request-id` | `algorithm` / `header_name` | `uuid` / `X-Request-Id` | The correlation id returned to the caller and written into every message. |

Placeholders in this package: `<YOUR_KAFKA_BROKER>`, `<ORG_ID>`, `<API_ID>`,
`<REVISION_ID>`, `<UPSTREAM_ID>`, `<TEST_ENV_ID>`, `<YOUR_GATEWAY_HOST>`. Replace
all of them before you deploy.

Every field of every plugin, and the wider product docs:
[docs.digitalapi.ai/api-gateway](https://docs.digitalapi.ai/api-gateway).

## Troubleshooting

- **A 202 is not a delivery guarantee.** The most important point on this page.
  Everything else is a detail by comparison.
- **Create topics explicitly.** With `auto.create.topics.enable`, the message that
  triggers creation is dropped: the metadata request creates the topic, and the
  message that prompted it is gone. The caller gets a 202. Every new topic costs
  exactly one event, and in production that is a real one.
- **The broker must be reachable from the gateway**, not from your laptop. A
  private broker inside a VPC needs the gateway inside that network.
- **`request-validation` re-encodes the body.** Key order in the published `event`
  is the re-encoded order, not your client's. Harmless here; it breaks `hmac-auth`
  if you add it. It is *not* needed for the body to be published — that was tested
  both ways.
- **`request-validation` and `hmac-auth`'s `validate_request_body` can't share a
  route.** See [Variations](#variations).
- **Events arrive out of order.** `batch_max_size: 1` makes each event its own
  timer, and those timers race. Order downstream on a timestamp inside the event.
- **`key` is a fixed string.** There is no variable resolution, so you can't
  partition by a field in the body.
- **Bodies over `max_req_body_bytes` (512 KB by default) are truncated** in the
  published message, not rejected.
- **The correlation id doesn't match.** `log_format` is using `$request_id`.
  Use `$apisix_request_id`.
- **`verify.sh` gets a 404.** The route isn't deployed. A 400 on a valid event
  means `request-validation` rejected it: compare `body_schema` with the payload.
- **The deploy fails on a missing binding.** Bind any upstream, even though the
  route never uses it.
- **An `x-mock-by` header appears on responses.** `with_mock_header` is still at
  its default, `true`.
- **Confirm the three plugins exist in your org** before you design around them,
  with `GET /api/orgs/{orgId}/plugin-schemas?page=1&size=300`.
