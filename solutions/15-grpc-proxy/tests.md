# Tests — a bidirectional gRPC stream, authenticated at the edge

> [Overview](README.md) · [Business need](business-need.md) · [Architecture](architecture.md) · [Guides](guides.md) · [Agent prompt](helix-agent-prompt.md) · **Tests** · [API reference](api-reference.md)

---

6 test cases in total, **all automated**, run in order by `example/verify.sh`
against a live deployment. The full machine-readable plan is
[`tests/test-plan.yaml`](tests/test-plan.yaml); this page is the readable
walkthrough of what it checks and why.

## Running the automated tests

```bash
GATEWAY=<your-gateway-host> \
UNIT_KEY=<app credential key> \
./example/verify.sh
```

`GATEWAY` is the host **without** a scheme (for example `gw.example.com`), and
`UNIT_KEY` is the app's key from its **Credentials** tab. You need
[`grpcurl`](https://github.com/fullstorydev/grpcurl) installed. No `.proto` file is
needed, because this package routes reflection; set `PROTOSET` only if you chose
not to.

Optional overrides, whose defaults match the spec's example service:
`UNARY_METHOD`, `UNARY_BODY`, `BIDI_METHOD`, `BIDI_BODY`, `HOLD_METHOD`,
`HOLD_SECONDS` (default 20) and `KEY_HEADER` (default `X-Unit-Key`).

Exit code 0 means all six held:

| # | Case | Expected |
|---|---|---|
| 1 | No key | HTTP `401`, before the upstream is contacted |
| 2 | An unknown key | HTTP `401` — the key is really checked, not just required |
| 3 | A valid key, one-off call (`Ping`) | a clean gRPC response |
| 4 | **A valid key, two-way stream (`Status`)** | completes **and ends with a gRPC status** |
| 5 | **A stream held open (`Commands`)** | survives the hold and still closes cleanly, with a gRPC status |
| 6 | Reflection | a client lists the service over the connection, with no `.proto` |

**Cases 1 and 2 are plain HTTP calls on purpose.** A gateway rejection is an HTTP
response, not a gRPC one, so a gRPC client would report it as a vague transport
error. Checking the HTTP status directly tells you more.

**Run case 3 first when debugging.** If the one-off call works, routing, the `grpc`
upstream and the key check are all correct, and anything still failing is specific
to streaming.

**Cases 4 and 5 are the ones that matter.** They check that the stream *ends with a
gRPC status*, not only that the messages arrived. A call can deliver every byte and
still leave the client unable to tell success from failure — which is what happens
when something on the path drops HTTP/2 trailers.

**Case 5 is a smoke test, not a soak.** 20 seconds proves the shape. Messages the
server pushes during the hold show the return half of the stream is alive too. Before you
commit to hours-long connections, raise `HOLD_SECONDS` past your longest idle gap,
and keep it below the route's read timeout unless your upstream sends heartbeats.

**Case 6 passes only when both reflection versions are routed.** A client asks for
`v1` first and falls back to `v1alpha` only if `v1` gets a clean gRPC answer.

Raw fixtures, if you want to run one case by hand instead of the whole script:
[`tests/requests/`](tests/requests/) (the requests) and
[`tests/expected/`](tests/expected/) (the expected status for each — the single
source both `verify.sh` and the plan read from, so they can't drift apart). The
response bodies in the fixtures are illustrative; the script checks for the
absence of an error, not the payload.

## The manual tests

None. Failure cases are covered as assertions inside cases 4 and 5, each of which
fails if the stream ends without a gRPC status.

## Coverage

| Type | Cases |
|---|---|
| Positive | one-off call, two-way stream, reflection |
| Negative | no key, unknown key |
| Boundary | stream held open |
| Failure | covered inside the two-way and held-open stream cases |
