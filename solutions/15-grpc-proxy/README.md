# Solution 15 — gRPC proxy: authenticate long-lived gRPC streams at the gateway

> **Overview** · [Business need](business-need.md) · [Architecture](architecture.md) · [Guides](guides.md) · [Agent prompt](helix-agent-prompt.md) · [Tests](tests.md) · [API reference](api-reference.md)

**In short:** put the gateway in front of a streaming gRPC service so every
connection is checked as it opens, without the service implementing any
authentication. The stream stays two-way and stays open.

| | |
|---|---|
| **Time to try it** | Depends on having a gRPC backend ready; the gateway side is an upstream, an import and a deploy |
| **Difficulty** | 🔴 Advanced — the gRPC setting lives on a separate upstream object, not in the spec |
| **What you'll need** | A gRPC backend the gateway can reach, an app key for callers to present, and [`grpcurl`](https://github.com/fullstorydev/grpcurl) to test with |

---

## What is gRPC proxying?

**gRPC** is a way for programs to call each other over HTTP/2. Besides ordinary
one-off calls, it supports **streams**: one connection that stays open for minutes
or hours, with messages flowing both ways.

Think of the difference between letters and a phone call. Most API traffic is
letters: each one is checked on its own. A gRPC stream is a phone call. The gateway
checks who is calling when the call connects, then stays out of the conversation
and keeps the line open.

**Proxying** means the gateway sits in the middle: clients connect to the gateway,
and the gateway connects on to your service.

## The use case

> *"Our units hold a gRPC stream open for hours. Anything that wants to
> authenticate or count them has to be built into the service."*

A timing unit, a trading feed, a telemetry agent — anything that holds a gRPC
stream open for hours — is a connection your platform cannot see:

- **Every service builds its own authentication**, because nothing in front of it
  can take part in a stream it does not understand.
- **Every team builds it slightly differently**, and none of it is visible to the
  platform.
- **Connections cannot be counted or attributed** without the service reporting
  them itself.

## What a gRPC proxy gives you

- **Authentication at the moment a stream opens.** The client presents a key in its
  gRPC metadata; the gateway accepts or refuses the connection before your service
  is contacted.
- **A stream that stays two-way and open.** The service sees an ordinary gRPC
  connection.
- **Schema discovery through the gateway.** Clients can list and describe your
  service over the connection, so you don't have to hand out `.proto` files.
- **Connection counts and durations per app**, from the analytics you already use.

## Benefits

- **Authentication for streaming services becomes configuration**, not a change to
  each service.
- **One check instead of many.** The check that admits a unit is the same one that
  admits any API caller, against the same credentials.
- **Cutting off a misbehaving client is an admin action**, not a deploy.
- **Long-lived connections become visible**: how many, and how long each stayed
  open, attributed to the app that opened it.

## Example

A timing unit calls the `timing.TimingUnit` service through the gateway:

| Call | Key | What happens |
|---|---|---|
| Any call or stream | none | **HTTP 401 (not authenticated)** before your service is contacted |
| Any call or stream | an unknown key | HTTP 401 |
| Open a `Status` stream | a valid app key | A two-way stream that ends with a proper gRPC status |
| Call `Ping` (a one-off call) | a valid app key | A normal gRPC response |
| Open a `Commands` stream and hold it | a valid app key | The stream stays open, the server pushes messages down it, and it closes cleanly |

Afterwards, the analytics show one request per stream, and a response time equal to
how long the stream stayed open.

Two things to know before you build on this: **one stream counts as one request**,
so a quota counts connections, not messages; and **a refusal is a plain HTTP
response**, which gRPC clients report as a confusing transport error.
[Why →](architecture.md#one-stream-is-one-request)

**Setting this up takes five short steps:** create an upstream whose scheme is
`grpc`, import the API, deploy it with that upstream, then create a product, a
developer and an app, and copy the app's key.
[Full click-by-click walkthrough →](guides.md#build-it-in-the-ui)

[Build it any of three ways, then see it work →](guides.md)

## Where to go next

- **Want the business case first?** [Business need](business-need.md) explains why
  this matters, in plain terms.
- **Want to understand how it works?** [Architecture](architecture.md) covers where
  the gRPC setting lives, why one stream is one request, and how to measure
  connections.
- **Ready to build it?** [Guides](guides.md) walks you through it step by step.
- **Want the full product documentation?** Every plugin, screen and API call is
  covered at [docs.digitalapi.ai/api-gateway](https://docs.digitalapi.ai/api-gateway).

## Related solutions

- **[08 — API keys](../08-api-key/)** — the same `helix-auth` key check on ordinary
  HTTP routes.
- **[01 — API Products](../01-api-products/)** — the product, developer and app
  model the key comes from, and what a quota counts.
- **[04 — Analytics](../04-analytics/)** — the analytics that report stream counts
  and durations here.
