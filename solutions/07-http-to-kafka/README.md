# Solution 07 — HTTP to Kafka: accept events over HTTP and publish them, with no ingest service

> **Overview** · [Business need](business-need.md) · [Architecture](architecture.md) · [Guides](guides.md) · [Agent prompt](helix-agent-prompt.md) · [Tests](tests.md) · [API reference](api-reference.md)

**In short:** let partners POST events to your gateway, check each one, answer
straight away, and publish it to a Kafka topic, without writing or running an
ingest service in between.

| | |
|---|---|
| **Time to try it** | About 20 minutes, once you have a Kafka broker |
| **Difficulty** | 🟡 Intermediate — needs a Kafka broker the gateway can reach |
| **What you'll need** | A test account whose org includes the `kafka-logger`, `mocking` and `request-validation` plugins, a Kafka broker and topic, and a topic browser such as [Kafka UI](https://github.com/provectus/kafka-ui) or [Redpanda Console](https://github.com/redpanda-data/console) to check the result. New to Kafka? [Kafka quickstart](https://kafka.apache.org/quickstart) |

---

## What is HTTP-to-Kafka at the edge?

Kafka is a system that stores streams of events, such as order updates or device
readings, so that other systems can read them. Most partners can't write to Kafka
directly. They can send an ordinary HTTP request.

Usually a small service sits in between. It has three jobs: check who is calling,
check the event is well-formed, and hand it to Kafka. This solution gives those
jobs to the gateway, which is already on the request path. The gateway checks the
event, answers the caller with **HTTP 202 (accepted)**, and then publishes the
event to your topic. There is no backend service for this route at all.

## The use case

> *"Our partners want to POST us events — order updates, delivery scans, device
> telemetry. Downstream everything is already Kafka. In between there is a
> service that has been on the roadmap for three quarters: it authenticates the
> caller, checks the payload isn't garbage, and calls `producer.send()`. That's
> it. That's the whole service. And it needs a repo, a pipeline, a Dockerfile, an
> on-call rotation, autoscaling, and a service owner."*

The logic is three lines. Everything around it — the repository, the pipeline,
the deployment, the on-call rota — is what keeps it on the roadmap, and partner
integrations wait behind it.

## What this gives you

- **An event endpoint with no service behind it.** The gateway answers the caller
  itself and publishes the event to Kafka.
- **Bad events stopped at the edge.** An event that fails the JSON Schema check
  gets **HTTP 400 (bad request)** and is never published.
- **A correlation id.** Every 202 carries an `X-Request-Id` header, and the same
  id is written into the Kafka message, so you can match any request to its
  message.
- **One important trade-off, stated up front.** A 202 means the gateway accepted
  the event. It does **not** mean Kafka has it. The publish happens after the
  caller has been answered, so if Kafka is down the event is lost and the caller
  can't tell. This is called *at-most-once* delivery.

## Benefits

- **Nothing new to deploy.** No repository, pipeline, image, autoscaling or
  on-call rota for code that would only have called Kafka.
- **A new event type is a configuration change**, not a new service.
- **One less component that can fail** on a path that already goes through the
  gateway.
- **Consumers stop re-checking the same payloads**, because malformed events never
  reach the topic.

## Example

Before you build, decide whether losing an occasional event is acceptable **for
this data**:

| If losing an occasional event is… | Then |
|---|---|
| Acceptable — analytics, audit trails, telemetry, activity feeds | Use this solution as written |
| Not acceptable — payments, orders, anything a customer would notice | Use one of the alternatives in [Architecture](architecture.md#when-to-use-this) |

Once it is set up: a partner POSTs `{"event_id":"…","event_type":"order.created","occurred_at":"…"}`
to `/events` and gets `202 {"accepted":true}` with an `X-Request-Id`. A few
moments later the event is on your Kafka topic, carrying that same id. A POST
missing `event_id` gets a 400 and nothing is published.

**Setting this up in the gateway's UI takes four short steps:** create the Kafka
topic, put your broker and topic into the spec file, import it, then give the API
an upstream and deploy it.
[Full click-by-click walkthrough →](guides.md#build-it-in-the-ui)

[Build it any of three ways, then see it work →](guides.md)

## Where to go next

- **Want the business case first?** [Business need](business-need.md) explains why
  this matters, in plain terms.
- **Want to understand how it works?** [Architecture](architecture.md) covers the
  three plugins, the order they run in, and why a 202 is not a delivery receipt.
- **Ready to build it?** [Guides](guides.md) walks you through it step by step.
- **Want the full product documentation?** Every plugin, screen and API call is
  covered at [docs.digitalapi.ai/api-gateway](https://docs.digitalapi.ai/api-gateway).

## Related solutions

- **[06 — Signed requests](../06-hmac-auth/)** — how to close this endpoint to
  unknown callers, and what that costs. The route ships open.
- **[01 — API Products](../01-api-products/)** — per-app quotas, once callers are
  authenticated. An open endpoint can't be metered per caller.
- **[03 — SOAP to REST](../03-soap-to-rest/)** — the other solution where the
  gateway does more than pass the request through.
- **[11 — Service callout](../11-service-callout/)** — the plugin behind the
  "real acknowledgement" alternative, for events you can't afford to lose.
