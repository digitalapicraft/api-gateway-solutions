# Business need — event ingest without an ingest service

## The situation

Downstream is already Kafka. Partners, devices or internal teams want to send you
events over HTTP. Between the two sits a service that does not exist yet, and its
job description is three lines long:

> Authenticate the caller. Check the payload is not garbage. Call
> `producer.send()`.

It does not get built quickly, because the three lines are not the work. The work
is a repository, a CI pipeline, a container image, a Helm chart, an autoscaling
policy, a dashboard, an alerting rule, a service owner, an on-call rotation, a
threat model, and a place in the dependency graph that somebody has to reason
about during the next incident.

So the endpoint waits. In the meantime the costs are real but diffuse:

- **Partner integrations queue behind it.** Each one is blocked on infrastructure
  work that has nothing to do with the integration.
- **Teams route around it.** Events arrive by SFTP drop, by a shared database
  table, by a nightly batch — each of which becomes its own long-lived
  obligation, and none of which was designed.
- **When it is finally built, it is built more than once.** The second event type
  gets a second service, or a shared one grows a second owner.
- **It becomes another thing that can be down**, on the path of traffic that was
  already passing through a gateway that was already up.

## What changes

The gateway is already on the request path. It is already parsing the request. It
can already reach the broker. The three lines move there, and the deployable is
never created.

| | Ingest service | Gateway-produced |
|---|---|---|
| **New deployables** | One, plus its pipeline and on-call | None |
| **Time to first event** | A sprint, optimistically | A configuration change |
| **Second event type** | A route in the same service, or a second service | A second route in the spec |
| **Hops that can fail** | Gateway + service + broker | Gateway + broker |
| **Who validates the payload** | The service, in code | The edge, from a JSON Schema |
| **Who owns availability** | A new team | The team that already owns the gateway |
| **Delivery guarantee** | Whatever you implement — can be strong | **At most once.** See below |

The last row is not a footnote. It is the trade, and it decides whether the rest
of the table is relevant.

## The mechanism that matters

The gateway answers the caller and publishes afterwards. Concretely: the
acknowledgement is generated in the access phase, and the publish happens in the
log phase — **after the response has been flushed**.

That ordering buys the property that makes this shape attractive: **the caller's
latency is decoupled from the broker's.** A slow or briefly unavailable broker
does not slow down or fail the caller.

It also buys the property that disqualifies it for some data: **the caller cannot
be told the publish failed**, because by then there is no caller. There is no
configuration that changes this — it is the shape, not a setting.

So the decision is a single question, asked about the data rather than the
technology:

> **If one event in ten thousand vanished with no trace except a gateway log
> line, would anyone be harmed?**

- **No** — analytics, audit trails, telemetry, activity feeds, click streams,
  presence, anything where the aggregate carries the meaning. Use this.
- **Yes** — payments, orders, settlement, anything a customer or a regulator can
  notice the absence of. Use one of the alternatives in the package README. The
  cheapest of them keeps this exact route shape and moves the publish into a
  phase that can still answer the caller.

## Business outcomes

- **An ingest endpoint ships in a configuration change**, so a partner
  integration is no longer blocked on infrastructure work unrelated to it.
- **No new operational surface.** Nothing to deploy, scale, patch, monitor or
  page on — the gateway's existing availability budget covers it.
- **Malformed events stop at the edge.** Consumers stop re-implementing the same
  defensive validation, and the topic stays clean enough to reason about.
- **The blast radius of the ingest path shrinks** by one service that can be
  down, on a path where every dependency is a multiplier.
- **Routing-around stops.** When an endpoint takes a day rather than a quarter,
  the SFTP drop and the shared table do not get invented.

## What this does not buy you

- **Not guaranteed delivery.** At most once. The headline, repeated because it is
  the only thing that matters when choosing.
- **Not ordering.** Events land out of order; Kafka offsets carry no ordering
  meaning here. Order downstream on a timestamp inside the event.
- **Not authentication, as shipped.** The route is open by default. Closing it is
  a documented change with a documented cost.
- **Not back-pressure.** The gateway accepts at HTTP speed regardless of what the
  broker can absorb.
- **Not deduplication.** An `event_id` is carried so the consumer can deduplicate,
  which is the only place at-least-once semantics can be recovered.
- **Not a replacement for the service you would build for critical events.** It is
  the right answer for a large class of events and the wrong one for the rest, and
  the package is explicit about which is which.

## Success criteria

- A partner can be onboarded to a new event type without a deployable being
  created.
- Malformed events are rejected at the edge and never reach the topic.
- Every acknowledgement carries a correlation id that also appears in the
  published message, so any event can be traced end to end.
- Topics are created explicitly at deploy time, not by auto-creation — which
  silently costs the first event.
- Whoever owns the data has seen the broker-down case run, and accepted
  at-most-once for this specific event type in writing.
