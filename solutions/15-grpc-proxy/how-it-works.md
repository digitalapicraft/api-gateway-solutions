# How it works — Solution 15 — A bidirectional gRPC stream, authenticated at the edge

[Overview](readme.md) · [Business need](business-need.md) · **How it works** · [Install](install.md) · [Configuration](configuration.md) · [Test & verify](testing.md) · [Changelog](changelog.md)

---

## One stream is one request

This is the single most important thing to understand before building on it.

Every access-phase plugin evaluates **exactly once, at stream initiation**. That
is precisely what makes "authenticate the connection" work — there is one
decision point, at the moment the unit connects.

It also means something that usually surprises people:

> **A product quota counts streams, not messages.** One connection carrying a
> million messages consumes **one** unit of quota.

Measured, not assumed: with a limit of 1, five messages on a single stream all
went through, and the *next* stream was rejected. If your commercial model
assumes per-message metering, it does not work here, and no configuration changes
that.

The same property has a security consequence: **a credential revoked while a
stream is open stays effective until that stream ends.** Nothing re-authenticates
mid-stream.

## The request path

```
Timing unit                Gateway                         gRPC service
    │                         │                                 │
    │  HTTP/2 headers         │                                 │
    │  :path /timing.TimingUnit/Status                          │
    │  metadata X-Unit-Key    │                                 │
    ├────────────────────────▶│                                 │
    │                  helix-auth (2450, access)                │
    │                  resolves the credential ONCE             │
    │                         │                                 │
    │        401 ◀────────────┤ (an HTTP response, not gRPC)    │
    │                         │                                 │
    │                         │  upstream scheme: grpc          │
    │                         ├────────────────────────────────▶│
    │◀═══════ bidirectional, stays open, both directions ══════▶│
    │                         │                                 │
    │                    log phase fires at CLOSE               │
    │                    duration = full stream lifetime        │
```

## Execution order

| Plugin | Priority | Phase | Runs |
|---|---|---|---|
| `helix-auth` | 2450 | access | **once**, at stream initiation |
| `request-id` | — | document root | once, per stream |

There is deliberately nothing else. Every plugin on a gRPC route must be one that
neither reads nor rewrites a body, because a stream has no body that ends.

## One stream is one request

The gateway treats an HTTP/2 stream as a single request. The access phase runs
when the HEADERS frame arrives; the log phase runs when the stream closes.
Nothing runs in between.

Three consequences, all of them load-bearing:

1. **Authentication at connection initiation works**, which is the whole point.
2. **Quota counts streams, not messages** — verified with a limit of 1, which
   allowed five messages on one stream and rejected the next stream.
3. **Duration is recorded at close**, because that is the moment a stream's
   lifetime becomes a fact. The log phase is where it lands, and from there it
   reaches the analytics API as an ordinary request with a long response time.

## Where the gRPC-ness lives

Not in the OpenAPI document — it cannot be. The upstream is a separate
control-plane object:

```
upstream.specification.scheme = grpc | grpcs
```

bound to a revision per environment. The document contributes the route paths and
the plugins; the upstream contributes the protocol. Both halves are required, and
**a scheme change needs an undeploy/deploy cycle** to reach a running revision.

## Observability: a stream is a request

Because one stream is one request, streaming traffic appears in the analytics API
with no extra configuration, and the dimensions are the ones every other API has.

| Question | Metric | Reads as |
|---|---|---|
| How many connections? | `requests-count` | one row per stream, by `api_path` or `app_name` |
| How long were they open? | `response-time`, aggregation `MAX` | the stream's lifetime in ms |

Measured against a stream held open for ~25 seconds:

```
requests-count   /timing.TimingUnit/Commands        1
response-time    /timing.TimingUnit/Commands    24235 ms
                 /timing.TimingUnit/Ping            9 ms
```

Grouped by `app_name`, the same traffic attributes its connections and their
durations to the calling app — which is the thing the service would otherwise
have had to report itself.

## Native vs custom

Nothing is built. One configured plugin and an upstream do the whole job.

The alternative is what teams do today: implement the credential check inside
each streaming service. That buys mid-stream revocation and message-level
policy, which the edge genuinely cannot offer. It costs a separate
implementation per service and keeps connections invisible to the platform. The
trade favours the edge for identity and admission, and favours the service for
anything that must act on a connection already open.

## Failure behaviour

| Situation | What happens |
|---|---|
| No credential | 401 at initiation, upstream never contacted. Not a valid gRPC response. |
| Invalid credential | 401, same shape. Logs distinguish it from missing; the caller cannot. |
| Credential revoked mid-stream | **Nothing.** The open stream continues until it ends. |
| Body-touching plugin on the route | The stream breaks. Do not add one. |
| Upstream scheme changed | No effect until the revision is undeployed and deployed again. |

## Prerequisites

- A gRPC backend reachable from the data plane.
- An upstream with `scheme: grpc` (or `grpcs`), bound per environment.
- **HTTP/2 to the gateway**, which every gRPC client speaks by default.
- Nothing on the client side — the routed reflection endpoints let it discover
  the schema over the connection.
