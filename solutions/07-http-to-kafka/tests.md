# Tests — HTTP to Kafka at the edge

> [Overview](README.md) · [Business need](business-need.md) · [Architecture](architecture.md) · [Guides](guides.md) · [Agent prompt](helix-agent-prompt.md) · **Tests** · [API reference](api-reference.md)

---

8 test cases in total: **4 automated**, run by `example/verify.sh` against a live
deployment, and **4 manual**, checked in your own Kafka topic browser. The full
machine-readable plan is [`tests/test-plan.yaml`](tests/test-plan.yaml); this page
is the readable walkthrough of what it checks and why.

That split is the honest shape of this solution, not a gap in the tooling. The
gateway publishes after the response has gone, so no response can ever show
whether the event reached Kafka.

## Running the automated tests

```bash
GATEWAY=https://<YOUR_GATEWAY_HOST> ./example/verify.sh     # defaults to /events
```

Set `EVENTS_PATH` if your route lives somewhere else. Exit code 0 means all four
held:

| # | Case | Expected |
|---|---|---|
| 1 | A valid event | `202` with the gateway's own body, `{"accepted":true}` |
| 2 | Correlation | the 202 carries an `X-Request-Id` header |
| 3 | An event missing required fields | `400`, and nothing is published |
| 4 | The response headers | no `x-mock-by` header |

**Read case 1 as "the gateway accepted the event", not "Kafka has the event".**
Those are different claims and only the first is being made. If the body is
anything other than `{"accepted":true}`, something other than `mocking` answered,
and the route is passing the request on when it should be answering itself.

Case 3 tests two things at once: `request-validation` rejects the event, and
`kafka-logger`'s `_meta.filter` keeps the 400 off the topic. Case 6 below checks
the second half in your topic browser.

When it finishes, `verify.sh` prints the `event_id` and `X-Request-Id` of the
event it posted. You need them for the manual tests.

Raw fixtures, if you want to run one case by hand instead of the whole script:
[`tests/requests/`](tests/requests/) (the HTTP requests) and
[`tests/expected/`](tests/expected/) (the expected status and body for each — the
single source both `verify.sh` and the plan read from, so they can't drift apart).

## The manual tests

These need a running broker and a topic browser, and two of them need the broker
or topic deliberately broken, so they're a checklist, not a script.

| Case | What it proves | How to run it |
|---|---|---|
| **5. Message on the topic** | The event actually reached Kafka with a **complete** body — the one thing this solution exists to do, and the one thing no status code can tell you. | Run `verify.sh` and keep the `event_id` and `X-Request-Id` it prints. Open the topic and find the message whose `request_id` matches. Expect `{"event":"<the JSON you posted>","request_id":"<the same id>","received_at":"<gateway time>"}`. The key order inside `event` will be the re-encoded order, not yours — that is expected. |
| **6. Rejected event not published** | `_meta.filter` really keeps a rejected event off the topic. | Post the malformed event from case 3, note the time, and check the topic for any message at that moment. Expect none. Remove `_meta.filter` and repeat to see the alternative: the 400 is published too. |
| **7. Broker down, still 202** | The main limitation, shown rather than described: with the broker unreachable, the caller can't tell. | Stop the broker, or point `brokers[].host` at an address that doesn't answer, and post a valid event. Expect a 202 with the same body and the same speed. The failure shows only in the gateway error log, and the event is gone. **Run this once in front of whoever decides whether this design suits the data.** |
| **8. Topic auto-creation drops the first message** | A topic that doesn't exist yet loses the message that triggers its creation. | Against a broker with `auto.create.topics.enable=true`, point `kafka_topic` at a name that doesn't exist. Post one event, then a second. Expect two 202s, and a topic containing only the **second** message; the first shows as `not found topic ... retryable: true` in the gateway log. |

Full procedures, plus the exact assertions each one makes:
[`tests/test-plan.yaml`](tests/test-plan.yaml).

## Coverage

| Type | Cases |
|---|---|
| Positive | valid event, correlation id, message on the topic |
| Negative | schema rejected, rejected event not published |
| Boundary | no `x-mock-by` header |
| Failure | broker down still 202, topic auto-creation drops the first message |
