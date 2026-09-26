# Choosing a solution

Start from the question you are asking, not from the plugin you think you need. This page is generated from the solutions themselves, so it always lists all of them.

---

## Who is calling?

Four answers, and you pick one. What decides it is what the caller can hold: a browser can hold a token but not a secret; a payment terminal can hold neither.

### [OAuth 2.0 with JWT](../solutions/02-oauth-jwt/)

The gateway issues the token and verifies it, so a partner-facing API gets standards-based authentication in a configuration change rather than a backend release.

**Instead of:** [05-okta-jwt](../solutions/05-okta-jwt/) · [06-hmac-auth](../solutions/06-hmac-auth/) · [08-api-key](../solutions/08-api-key/) · **Pairs with:** [01-api-products](../solutions/01-api-products/) · [04-analytics](../solutions/04-analytics/)

### [Okta: verify the token, don't issue it](../solutions/05-okta-jwt/)

An organisation already runs Okta as its identity provider, but its APIs still authenticate with static keys that never expire and cannot be deprovisioned, because making each service verify Okta tokens means writing JWKS fetching, key caching and signature verification once per

**Instead of:** [02-oauth-jwt](../solutions/02-oauth-jwt/) · [06-hmac-auth](../solutions/06-hmac-auth/) · [08-api-key](../solutions/08-api-key/) · **Pairs with:** [01-api-products](../solutions/01-api-products/)

### [Signed requests, without sending the secret](../solutions/06-hmac-auth/)

A partner, device fleet or webhook sender holds a credential that travels on every request — so any copy of one request is a copy of the credential — and that credential says nothing about the payload it arrived with, so a body altered in transit is indistinguishable from a legit

**Instead of:** [02-oauth-jwt](../solutions/02-oauth-jwt/) · [05-okta-jwt](../solutions/05-okta-jwt/) · [08-api-key](../solutions/08-api-key/) · **Pairs with:** [01-api-products](../solutions/01-api-products/)

### [API keys for callers that can't do a token exchange](../solutions/08-api-key/)

An endpoint serving thousands of constrained callers — field devices, legacy middleware, a partner's scheduled job — is protected only by an unpublished URL, because those callers cannot run an OAuth token exchange and cannot be redeployed on the timescale an incident needs. The

**Instead of:** [02-oauth-jwt](../solutions/02-oauth-jwt/) · [05-okta-jwt](../solutions/05-okta-jwt/) · [06-hmac-auth](../solutions/06-hmac-auth/) · **Pairs with:** [01-api-products](../solutions/01-api-products/)

## How much can they call?

Metering and quota. This needs identity resolved first, so it sits behind one of the answers above.

### [API Products: sell tiers you can enforce](../solutions/01-api-products/)

API teams need per-caller throughput limits tied to what a customer bought, because one misbehaving integration can exhaust capacity provisioned for everyone and because plan tiers sold as "higher throughput" have no technical enforcement, without over-provisioning for an unbound

**Pairs with:** [02-oauth-jwt](../solutions/02-oauth-jwt/) · [04-analytics](../solutions/04-analytics/)

## What shape is the payload?

Mediation — the caller wants one format and the backend speaks another.

### [Serve a SOAP backend as REST/JSON](../solutions/03-soap-to-rest/)

API teams need to open a SOAP/XML system of record to partners who require REST/JSON because every integration otherwise becomes an adapter service or a rewrite, without modifying a backend that is correct, stable and unsafe to touch.

**Instead of:** [09-xml-to-json](../solutions/09-xml-to-json/) · **Pairs with:** [02-oauth-jwt](../solutions/02-oauth-jwt/)

### [JSON in front of a backend that speaks XML](../solutions/09-xml-to-json/)

A backend serves ordinary REST over HTTP but answers in XML, and every client team has written its own XML parser to cope. The conversion exists once per consumer, in a different language each time, with a different answer to the same ambiguities — so representation bugs are inte

**Instead of:** [03-soap-to-rest](../solutions/03-soap-to-rest/)

### [One route, many partners, rotation without a deploy](../solutions/12-key-value-map/)

Key material written into a route works for the first counterparty and degrades from there. Fourteen partners means fourteen near-identical routes, fourteen keys inside configuration documents, and a release every time a partner rotates on their own schedule — discovered, more of

**Pairs with:** [13-pgp-encryption](../solutions/13-pgp-encryption/) · [14-dynamic-mock](../solutions/14-dynamic-mock/)

### [PGP at the edge, so the keyring script can go](../solutions/13-pgp-encryption/)

A counterparty's contract requires PGP-encrypted payloads in both directions, so a small script on a VM sits between their endpoint and the backend, decrypting and re-encrypting. It holds the private key, it is in no deployment pipeline and no monitoring, nobody owns it, and it i

**Pairs with:** [12-key-value-map](../solutions/12-key-value-map/)

## What else must happen on the way?

Enrichment, orchestration and fan-out: work the gateway does that the backend would otherwise repeat in every service.

### [HTTP to Kafka, with no service in between](../solutions/07-http-to-kafka/)

Partners want to POST events to an estate whose downstream is already Kafka, but the service in between — authenticate, validate, produce — is three lines of logic wrapped in a repository, a pipeline, an image, an autoscaling policy and an on-call rotation, so it stays on the roa

**Pairs with:** [06-hmac-auth](../solutions/06-hmac-auth/)

### [The lookup every service re-implements, done once](../solutions/11-service-callout/)

Several services each begin by calling the same customer-profile service to learn the caller's plan and account status. Each caches it differently, each fails differently, the profile service carries one call per service per request, and a contract change becomes a hunt across th

**Pairs with:** [14-dynamic-mock](../solutions/14-dynamic-mock/)

### [A sandbox that answers each partner with their data](../solutions/14-dynamic-mock/)

Integration teams need a sandbox that answers each partner with that partner's own values, because a single canned response lets partner-specific integration bugs through to production, without standing up and operating a service behind the endpoint or shipping a release every ti

**Pairs with:** [12-key-value-map](../solutions/12-key-value-map/) · [11-service-callout](../solutions/11-service-callout/)

## What do we know about the traffic?

Attribution and redaction — who called, how often, and what must never reach a log.

### [Analytics: read what the gateway already captured](../solutions/04-analytics/)

API teams need to see what's happening across their APIs — requests in the last hour by API, product or app; the slowest and fastest APIs; error rates — without standing up their own telemetry and without changing any API. The gateway already captures every request; the gap is kn

**Pairs with:** [01-api-products](../solutions/01-api-products/) · [02-oauth-jwt](../solutions/02-oauth-jwt/)

### [Mask the values, not just the log line](../solutions/10-data-mask/)

A customer API returns the whole record to every consumer. Support agents read full email addresses, phone numbers and home coordinates they have no need for, and the same payload is copied into a log aggregator with longer retention and a wider audience — which is where an audit

**Pairs with:** [04-analytics](../solutions/04-analytics/)

## What protocol is it?

Where the transport itself, not the payload, is the problem.

### [A bidirectional gRPC stream, authenticated](../solutions/15-grpc-proxy/)

Platform teams need identity and admission control on a bidirectional-streaming gRPC service whose clients hold connections open for hours, because today every such service implements its own credential check and the connections are invisible to the platform, without modifying th

**Pairs with:** [08-api-key](../solutions/08-api-key/)

---

15 solutions in total. Every one was implemented and validated against a real gateway before it was published — see [Validation status](validation-status.md) for what each status means.
