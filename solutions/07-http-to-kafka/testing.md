# Test & verify — Solution 07 — HTTP to Kafka: accept events at the edge, publish them without an ingest service

[Overview](readme.md) · [Business need](business-need.md) · [How it works](how-it-works.md) · [Install](install.md) · [Configuration](configuration.md) · **Test & verify** · [Changelog](changelog.md)

---

## Verifying the Kafka leg

`verify.sh` deliberately does not try to check Kafka. It cannot: the publish
happens after the response is flushed, so nothing in any response reflects it. A
script that inferred delivery from a 202 would be making exactly the assumption
this solution warns against.

Instead, `verify.sh` prints the `event_id` and `X-Request-Id` of the event it
posted. Take them to your topic browser:

```text
1. Open the configured topic in Kafka UI (or Redpanda Console, or
   kafka-console-consumer.sh --from-beginning).
2. Look at the newest messages. Find the one whose request_id matches the
   X-Request-Id that verify.sh printed.
3. Confirm its "event" field contains the JSON you posted.
```

**Step 3 is the real assertion.** A message with an *empty* `event` field is the
failure this design is most likely to hit, and it looks like success from every
other angle — see *Why `request-validation` is not optional*.

Matching on `request_id` rather than eyeballing the newest message is the point of
having `request-id` on the API. On a busy topic, timestamps cannot distinguish two
events posted in the same second, and `received_at` is the gateway's clock.

## Testing

[`gateway/verify.sh`](gateway/verify.sh) exits 0 only if all four hold:

| # | Case | Expect |
|---|---|---|
| 1 | Valid event | 202 `{"accepted":true}` from the gateway itself |
| 2 | Correlation | `X-Request-Id` on the 202 |
| 3 | Event missing required fields | 400, nothing published |
| 4 | Response headers | No `x-mock-by` |

Four further cases are **manual**, because no response can establish them. Three
were run against a real broker and passed: the message is on the topic with its
body complete; a rejected event is *not* on the topic; and with the broker
unreachable the caller still gets 202 while the event is lost. The fourth — a
topic that does not exist yet losing the message that creates it — was not run.
All four in [tests/test-plan.yaml](tests/test-plan.yaml).

**Run the broker-down case once**, in front of whoever is deciding whether this
shape suits the data. It is the fastest way to make the limitation concrete.
