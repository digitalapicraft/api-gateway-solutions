# Business need — identity for connections, not just for calls

## The situation

Some of your traffic is not requests. It is connections.

A timing unit at a race, a payment terminal, a telemetry agent, a trading feed —
these open a gRPC stream and hold it for hours. Messages flow both ways inside
that one connection, and from the outside there is nothing to count, nothing to
attribute, and nothing to stop.

Everything your platform does for ordinary APIs — who is calling, are they
allowed, how many of them are there — was built for request/response traffic. So
for streaming services, each team builds it again inside the service: its own key
check, its own notion of which units are connected, its own way to cut one off.
Three teams, three implementations, and none of them visible to the platform.

## What changes

Authentication moves to the edge, and it happens at the moment the connection
opens.

The unit presents a credential in its gRPC metadata. The gateway resolves it to
an app, accepts or refuses the connection, and proxies the stream to the service.
The service implements nothing and does not change. A unit that should no longer
connect stops being able to, by disabling its credential rather than by shipping
code.

## The mechanism that matters

One stream is one request to the gateway. Every policy on the route evaluates
exactly once, at initiation — which is what makes authenticating a *connection*
possible at all, rather than authenticating each message inside it.

That single fact is also the thing most likely to break an assumption:

**Quota counts streams, not messages.** A connection carrying a million messages
consumes one unit. If you were planning to charge per message at the gateway,
that model does not survive contact with streaming, and no setting changes it.

And because policy runs once, **revocation does not reach a connection that is
already open**. Disabling a credential stops the next connection, not the current
one. For hours-long streams, that gap is a real control question and should be
answered deliberately — a maximum stream lifetime enforced by the service, or an
out-of-band disconnect.

## Business outcomes

- **Auth for streaming services ships as configuration**, not as a change to each
  service that has one.
- **One implementation instead of N.** The check that admits a unit is the same
  check that admits an API caller, resolved against the same credentials.
- **Cutting off a misbehaving client is an administrative act**, not a deploy.
- **Connection duration becomes visible per caller** — how long each stream stayed
  open, attributable to the app that opened it, without the service reporting it.

## What this does not buy you

**It does not inspect messages.** The gateway authenticates and proxies the
stream; it does not read what flows inside it, and anything that tried to would
break the stream.

## Success criteria

- A streaming service that had no authentication gains it without a code change.
- An unauthorised unit cannot open a stream, and the refusal happens before the
  service is contacted.
- A stream held open for the duration of a real session survives, carries traffic
  both ways, and terminates cleanly.
- Per-connection duration is attributable to a caller in telemetry the service
  does not produce.
