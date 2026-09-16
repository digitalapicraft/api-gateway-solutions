# Architecture — HTTP to Kafka at the edge

Three stock plugins, on one route, in three different phases. The design is
entirely about **which phase each one runs in**, and it does not survive being
reasoned about as a list of features.

## The chain

| Plugin | Phase | Priority | Does |
|---|---|---|---|
| `request-validation` | **rewrite** | 2800 | Validates against a JSON Schema, and re-encodes the body |
| `mocking` | **access** | 1999 | Returns `202 {"accepted":true}` and short-circuits |
| `kafka-logger` | **access** (skipped) + **log** | 403 | Publishes the body that was read |
| `request-id` | service-scoped | — | Correlation id, on the response and in the message |

Phases run in order — rewrite, then access, then log — and priority only orders
plugins *within* a phase.

```mermaid
sequenceDiagram
    autonumber
    participant C as Caller
    participant RV as request-validation<br/>rewrite · 2800
    participant M as mocking<br/>access · 1999
    participant KL as kafka-logger<br/>access · 403, then log
    participant K as Kafka

    C->>RV: POST /events
    RV->>RV: validate against body_schema
    alt invalid
        RV--xC: 400 · mocking never runs · _meta.filter blocks the publish
    else valid
        RV->>RV: read the request body
        RV->>M: continue to the access phase
        Note over M,KL: mocking runs FIRST (1999 > 403)<br/>and ends the request
        M-->>C: 202 {"accepted":true} + X-Request-Id
        Note over M,KL: kafka-logger's ACCESS handler never runs
        M->>KL: log phase
        KL->>K: {event, request_id, received_at}
        Note over KL,K: the caller is already gone
    end
```

## What the phase model does and does not decide

`mocking` short-circuits the access phase, so `kafka-logger`'s access handler —
where `include_req_body` calls `read_body()` — never runs. That much is real, and
readable in the plugin sources.

**It does not follow that the body goes unpublished, and it doesn't.**
`$request_body` in `log_format` resolves correctly anyway. Tested against a
deployed route, twice over: the `event` field is complete with
`request-validation` removed, and complete again with `include_req_body: false`.

An earlier version of this document argued the opposite and called
`request-validation` "load-bearing" for the body read. The argument was
mechanically plausible and empirically false. It is recorded here rather than
quietly deleted, because the shape of the mistake is instructive: every step was
read from source, and the conclusion still did not survive one request.

What `request-validation` actually contributes:

- **Rejection at the edge.** With `kafka-logger`'s `_meta.filter` on
  `status == 202`, a malformed event is neither acknowledged nor published.
- **A re-encoded body**, as a side effect. `set_body_data` re-serialises the
  parsed JSON as a defence against parser-differential attacks, and you can see it
  — the key order of the published `event` is the re-encoding's, not the caller's.
  Harmless here, and the reason this plugin cannot share a route with `hmac-auth`.

## Correlation: `$apisix_request_id`, not `$request_id`

| Variable | What it is | Matches the caller's `X-Request-Id`? |
|---|---|---|
| `$request_id` | nginx's own request id, 32 hex chars | **No** |
| `$apisix_request_id` | seeded from `$request_id`, then overwritten by the `request-id` plugin with the UUID it returns | **Yes** |
| `$http_x_request_id` | the request header the plugin set | Yes, but tied to `header_name` |

The `request-id` plugin sets the request header *and* overwrites
`$apisix_request_id`; it never touches `$request_id`. A `log_format` built on
`$request_id` therefore produces a correlation id that correlates with nothing,
which is what the first version of this package shipped. Confirmed by logging all
three and comparing against the returned header.

## Delivery semantics

```mermaid
flowchart TD
    A["mocking returns 202"] --> B["response flushed to the caller"]
    B --> C["log phase begins"]
    C --> D{"produce to Kafka"}
    D -->|"ok"| E[("message on topic")]
    D -->|"broker down,<br/>topic missing,<br/>buffer overflow"| F["gateway error log"]
    F -.->|"no channel back —<br/>the caller left at step 2"| G["event lost"]
```

**At most once.** The acknowledgement precedes the publish, so no publish outcome
can reach the caller. Three settings improve the odds without changing the
semantics:

| Setting | Default | Here | Effect |
|---|---|---|---|
| `producer_type` | `async` | `sync` | A real broker round trip, so a rejection is logged rather than disappearing into an in-process ring buffer. Also removes the 1-second `producer_time_linger` from the publish path |
| `required_acks` | `1` | `-1` | All in-sync replicas, rather than the leader alone |
| `max_retry_count` | `0` | `3` | A failed batch is retried rather than dropped |

None of them creates a path back to the caller. If the data cannot tolerate loss,
the answer is a different phase, not different settings — `service-callout` runs
in the *access* phase and can `fail-close`, which is the natural upgrade from this
design and keeps the same route shape.

## Why `mocking` rather than an upstream

`mocking` short-circuits before the upstream is consulted, so **this route needs
no backend at all**. That is the point of the solution.

Two consequences:

- **A revision still needs an upstream bound to deploy**, even though this route
  never reaches it. Bind anything.
- **`with_mock_header` defaults to `true`**, stamping responses with a header
  naming the plugin and the gateway version. For an endpoint whose whole job is to
  look like a real ingest API, that default is wrong; the spec sets it `false`.

## Where authentication would go

The route is unauthenticated as shipped — deliberately, as the smallest thing
that demonstrates the mechanism.

Adding [`hmac-auth`](../06-hmac-auth/) collides with the body read, and the
collision is worth understanding rather than working around:

| Plugin | Phase | Priority |
|---|---|---|
| `request-validation` | rewrite | **2800** |
| `hmac-auth` | rewrite | **2530** |

Both are rewrite-phase, and `request-validation` runs first. It re-encodes the
parsed JSON with `set_body_data` — deliberately, as a defence against
parser-differential attacks — so `hmac-auth` then hashes the *re-encoded* bytes
while the client hashed what it sent. Key order and whitespace differ; the
digests agree only by coincidence.

**They cannot share a route.** Pick one:

| You want | Route carries | You give up |
|---|---|---|
| Signed, integrity-checked ingest | `hmac-auth` (`validate_request_body: true`) | Edge schema validation — do it in the consumer |
| Edge schema validation | `request-validation` | Body integrity |
| Identity only, plus schema validation | `helix-auth` validate + `request-validation` | Proof the body was not modified |

The third row works because `helix-auth` does not touch the body. In all three the
published `event` is complete.

## Native vs custom

No custom code, and no deployable. What was deliberately not built:

- **A producer service.** That is the thing being avoided; see
  [business-need.md](business-need.md) for when you should build it anyway.
- **`service-callout` to a Kafka REST Proxy.** Access-phase and synchronous, so it
  *can* fail-close and tell the caller. It costs an HTTP hop, a REST-proxy
  deployment, and latency on every request. The right choice when loss is
  unacceptable, and listed in the README as the first upgrade.
- **Partitioning by event content.** `kafka-logger`'s `key` is a static string
  used verbatim, with no variable resolution, so keying by a body field is not
  possible. Without a key, records round-robin.

## Prerequisites

- An org whose build includes `kafka-logger`, `mocking` and `request-validation` —
  confirm with `GET /api/orgs/{orgId}/plugin-schemas?page=1&size=300`.
- A Kafka broker reachable **from the gateway**, not from your laptop. A broker
  inside a private network needs the gateway inside it too.
- The topic created explicitly. Auto-creation drops the message that triggers it.
- A topic browser to verify with — the Kafka leg is not observable from the
  caller's side.
- An upstream bound to the service, even though this route never uses one.

## Failure behaviour

| Condition | Caller sees | Reality |
|---|---|---|
| Valid event, broker healthy | 202 | Published |
| Event fails `body_schema` | 400 | Not published — `_meta.filter` requires status 202 |
| Broker unreachable | **202** | Lost. Gateway error log only |
| Topic does not exist, auto-create on | **202** | This message lost; the topic now exists for the next one |
| Producer buffer overflows | **202** | Dropped |
| Body larger than `max_req_body_bytes` (512 KB) | 202 | Published **truncated**, not rejected |
| `request-validation` removed | 202 | Published **in full** — and malformed events are published too |

Every row where the caller sees 202 and the reality is loss is a row where no
retry, alert or dashboard on the caller's side can help. That is the cost of the
shape, and it is why the package asks you to decide about the data first.
