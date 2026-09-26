# Test & verify — Solution 15 — A bidirectional gRPC stream, authenticated at the edge

[Overview](readme.md) · [Business need](business-need.md) · [How it works](how-it-works.md) · [Install](install.md) · [Configuration](configuration.md) · **Test & verify** · [Changelog](changelog.md)

---

## What a rejection looks like

Authentication works. The *error surface* does not, and your integrators will hit
it on day one:

```
no key    -> HTTP 401, content-type text/plain, {"message":"Missing API key in request"}
bad key   -> HTTP 401, {"message":"Invalid API key in request"}
```

A gateway rejection is an ordinary HTTP response, not a gRPC one, so a client
cannot render it as an auth failure. Depending on the library it surfaces as
`Unauthenticated` wrapped in a complaint about content-type, or as an opaque
transport error — either way the caller does not see "your key is missing".

Tell your integrators to check the HTTP status directly when a stream will not
open. That is why this package's two negative tests are plain `curl` calls.

## Testing

```bash
GATEWAY=<your-gateway-host> \
UNIT_KEY=<app credential key> \
./gateway/verify.sh
```

No `.proto` file is needed — this package routes reflection, so the schema is
discovered over the connection.

Six checks: unauthenticated refused, invalid key refused, authenticated unary,
an authenticated bidirectional stream that completes with a `grpc-status`, a
held-open stream that still closes cleanly, and reflection resolving.

`HOLD_SECONDS` defaults to 20. Raise it past the longest idle gap you expect in
production and run it again before you commit to hours-long connections.

## Measuring connections

Because one stream is one request, the analytics you already have answers both
questions people ask about long-lived connections — **how many, and for how
long** — with no extra configuration.

```
POST /api/orgs/{orgId}/analytics/metrics/requests-count
POST /api/orgs/{orgId}/analytics/metrics/response-time     # aggregation: MAX
{ "dimensions": ["api_path"],                              # or ["app_name"]
  "filters": [{"column":"api_name","operator":"EQ","value":["<your api>"]}],
  "excludeTimeUnit": true }
```

**`requests-count` is your connection count** — one row per stream, broken down
by method or by app:

```
/timing.TimingUnit/Commands        1
/timing.TimingUnit/Status          2
/timing.TimingUnit/Ping            5
```

**`response-time` is the connection lifetime.** A stream held open for 25 seconds
reports ~24,000 ms. Grouped by `app_name` it tells you how long each caller held
its connections:

```
/timing.TimingUnit/Commands   24235      <- the held stream
/timing.TimingUnit/Ping           9      <- a unary call
```

The dimensions are the same ones every other API has: `app_name`, `developer`,
`product_name`, `api_path`, `route_name`, `response_status_code`. A streaming API
is a first-class citizen in the analytics you already run.

Read it at the moment it matters: a stream's row appears when the stream
**closes**, because that is when its duration becomes a fact. For counts of
connections open *right now*, `requests-count` over a recent window answers it
for every practical purpose.
