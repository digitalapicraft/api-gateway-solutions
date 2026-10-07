# HTTP to Kafka event ingest without an ingest service

> [Overview](README.md) · **Business need** · [Architecture](architecture.md) · [Guides](guides.md) · [Agent prompt](helix-agent-prompt.md) · [Tests](tests.md) · [API reference](api-reference.md)

---

> Partners want to send you events over HTTP, and everything downstream is already
> Kafka. The service in between has three jobs — check the caller, check the
> payload, publish — and it has sat on the roadmap for three quarters, because the three
> lines of code come with a repository, a pipeline, a deployment and an on-call
> rota.
>
> **The gateway is already on the path, already reading the request, and can
> already reach the broker.**

- **No new deployable.** The endpoint ships as a configuration change, so a
  partner integration is no longer waiting on unrelated infrastructure work.
- **One less thing that can be down.** The path is gateway and broker, not gateway,
  service and broker.
- **Bad events stop at the edge**, so the topic stays clean and consumers stop
  re-checking the same payloads.

The decision that matters is about the data, not the technology:

| If one event in ten thousand vanished, leaving only a gateway log line… | Then |
|---|---|
| Nobody would be harmed — analytics, audit trails, telemetry, activity feeds | Use this |
| Someone would notice — payments, orders, settlement | Use an alternative that waits for Kafka before answering |

The caller is answered before the event is published, so a failed publish can't
be reported back. That is the trade for not running a service. No figures here are
measured savings; they are the reasoning. [What this does not do, and the
alternatives, are in Architecture](architecture.md#what-it-does-not-do).

*Also searched as: HTTP to Kafka · REST to Kafka bridge · webhook to Kafka ·
Kafka ingest endpoint · publish events from API gateway · Kafka producer without
code · event ingestion API.*
