# Architecture — policy at stream initiation

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
    │        401 ◀────────────┤ (no grpc-status trailer)        │
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
3. **Duration is only known at close.** The log phase is where a stream's
   lifetime is recorded, so a connection open for three days contributes nothing
   to per-route telemetry until it ends.

## Where the gRPC-ness lives

Not in the OpenAPI document — it cannot be. The upstream is a separate
control-plane object:

```
upstream.specification.scheme = grpc | grpcs
```

bound to a revision per environment. The document contributes the route paths and
the plugins; the upstream contributes the protocol. Both halves are required, and
**a scheme change needs an undeploy/deploy cycle** to reach a running revision.

## Why trailers decide everything

gRPC carries its result — `grpc-status` — in **HTTP/2 trailers**, sent after the
body. A client that receives every message but no trailer treats the call as
failed, because it has no way to know it succeeded.

HTTP/1.1 has no trailers. So any hop between the client and the data plane that
speaks HTTP/1.1 silently converts a working stream into a broken one, while
leaving the payload perfectly intact. This is invisible to every tool that
measures bodies and status codes.

```
client ──h2──▶ [ HTTP/1.1 proxy ] ──h1──▶ gateway ──grpc──▶ service
                       ▲
             trailers are dropped here
```

Detection is one header: `via: 1.1 <name>` on any ordinary response from the
host. The remedy is an HTTP/2 backend protocol on that proxy — an infrastructure
change, outside anything this package controls.

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
| HTTP/1.1 hop in the path | Payload arrives, trailers stripped, every call reports `Internal`. |
| Body-touching plugin on the route | The stream breaks. Do not add one. |
| Upstream scheme changed | No effect until the revision is undeployed and deployed again. |

## Prerequisites

- A gRPC backend reachable from the data plane.
- An upstream with `scheme: grpc` (or `grpcs`), bound per environment.
- A path with **no HTTP/1.1 intermediary** in front of the data plane.
- Clients that hold a proto or protoset — reflection is not proxied by default.
