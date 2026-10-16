# gRPC stream authentication at the API gateway

> Our timing units hold a bidirectional gRPC stream open for hours. Anything that
> wants to know who is connected, refuse one unit, or count them has to be built
> into the service, so each team that owns a streaming service builds its own key
> check, its own idea of who's connected, and its own way to cut one off.
>
> **Put the gateway in front of the stream: it authenticates each connection as it
> opens, and the service implements nothing.**

- **Auth implementations: one per streaming service → one, at the edge.** The unit
  sends a key in its gRPC metadata; the gateway resolves it to an app.
- **Cutting off one unit: a code change → disabling its credential.** Its next
  connection is refused.
- **Service code changed: none.** The stream stays bidirectional and stays open.

One stream is one request to the gateway, and that decides what you can do with it:

| You want | At the gateway |
|---|---|
| refuse a unit before it connects | yes, checked once as the stream opens |
| count or meter connections per app | yes; a quota counts streams |
| meter or inspect individual messages | no; nothing at the edge sees inside the stream |
| cut off a unit mid-stream | no; a revoked key stays effective until that stream ends |

A rejection is an HTTP 401, not a gRPC status, so clients see it as a transport
error unless they check the HTTP status. The gRPC part lives on the upstream, not
in the API spec. [Before/after, the upstream, and what this does not buy you are
in the README](README.md#business-need).

*Also searched as: gRPC authentication at the API gateway · authenticate gRPC
streams · API key for gRPC metadata · bidirectional streaming through a gateway ·
gRPC proxy with auth · long-lived connection identity · gRPC reflection through a
gateway.*
