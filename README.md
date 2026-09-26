# API Gateway Solutions

A public library of **solved API problems** for the API gateway — built the
way we expect you to build them: by describing the outcome to the **Helix Agent**
and letting it generate, validate and deploy the configuration.

Each solution is a self-contained package: one real problem, one importable
gateway configuration, the agent prompt that produces it, the tests that prove
it, and an honest record of what was and wasn't validated.

> **Every solution here has been implemented and validated against our
> gateway** — imported, dry-run, deployed, and exercised with its `verify.sh`.
> Each package's `validation/` records the outcome, including the cases that are
> deliberately left manual because no response code can establish them.

---

## The solutions

| # | Solution | What it solves | Setup | Build it |
|---|---|---|---|---|
| **01** | [API Products: sell tiers you can enforce](solutions/01-api-products/) | API teams need per-caller throughput limits tied to what a customer bought, because one misbehaving integration can exhaust… | Beginner | [prompt](solutions/01-api-products/install.md) |
| **02** | [OAuth 2.0 with JWT](solutions/02-oauth-jwt/) | The gateway issues the token and verifies it, so a partner-facing API gets standards-based authentication in a configuration… | Beginner | [prompt](solutions/02-oauth-jwt/install.md) |
| **03** | [Serve a SOAP backend as REST/JSON](solutions/03-soap-to-rest/) | API teams need to open a SOAP/XML system of record to partners who require REST/JSON because every integration otherwise… | Intermediate | [prompt](solutions/03-soap-to-rest/install.md) |
| **04** | [Analytics: read what the gateway already captured](solutions/04-analytics/) | API teams need to see what's happening across their APIs — requests in the last hour by API, product or app; the slowest and… | Beginner | [prompt](solutions/04-analytics/install.md) |
| **05** | [Okta: verify the token, don't issue it](solutions/05-okta-jwt/) | An organisation already runs Okta as its identity provider, but its APIs still authenticate with static keys that never expire… | Beginner | [prompt](solutions/05-okta-jwt/install.md) |
| **06** | [Signed requests, without sending the secret](solutions/06-hmac-auth/) | A partner, device fleet or webhook sender holds a credential that travels on every request — so any copy of one request is a… | Beginner | [prompt](solutions/06-hmac-auth/install.md) |
| **07** | [HTTP to Kafka, with no service in between](solutions/07-http-to-kafka/) | Partners want to POST events to an estate whose downstream is already Kafka, but the service in between — authenticate,… | Intermediate | [prompt](solutions/07-http-to-kafka/install.md) |
| **08** | [API keys for callers that can't do a token exchange](solutions/08-api-key/) | An endpoint serving thousands of constrained callers — field devices, legacy middleware, a partner's scheduled job — is… | Beginner | [prompt](solutions/08-api-key/install.md) |
| **09** | [JSON in front of a backend that speaks XML](solutions/09-xml-to-json/) | A backend serves ordinary REST over HTTP but answers in XML, and every client team has written its own XML parser to cope. The… | Beginner | [prompt](solutions/09-xml-to-json/install.md) |
| **10** | [Mask the values, not just the log line](solutions/10-data-mask/) | A customer API returns the whole record to every consumer. Support agents read full email addresses, phone numbers and home… | Beginner | [prompt](solutions/10-data-mask/install.md) |
| **11** | [The lookup every service re-implements, done once](solutions/11-service-callout/) | Several services each begin by calling the same customer-profile service to learn the caller's plan and account status. Each… | Beginner | [prompt](solutions/11-service-callout/install.md) |
| **12** | [One route, many partners, rotation without a deploy](solutions/12-key-value-map/) | Key material written into a route works for the first counterparty and degrades from there. Fourteen partners means fourteen… | Intermediate | [prompt](solutions/12-key-value-map/install.md) |
| **13** | [PGP at the edge, so the keyring script can go](solutions/13-pgp-encryption/) | A counterparty's contract requires PGP-encrypted payloads in both directions, so a small script on a VM sits between their… | Intermediate | [prompt](solutions/13-pgp-encryption/install.md) |
| **14** | [A sandbox that answers each partner with their data](solutions/14-dynamic-mock/) | Integration teams need a sandbox that answers each partner with that partner's own values, because a single canned response… | Intermediate | [prompt](solutions/14-dynamic-mock/install.md) |
| **15** | [A bidirectional gRPC stream, authenticated](solutions/15-grpc-proxy/) | Platform teams need identity and admission control on a bidirectional-streaming gRPC service whose clients hold connections… | Intermediate | [prompt](solutions/15-grpc-proxy/install.md) |

## Which one do you need?

The library is organised by the question you are actually asking. The full decision path is in **[Choosing a solution](guides/choosing-a-solution.md)**.

- **Who is calling?** — [OAuth 2.0 with JWT](solutions/02-oauth-jwt/) · [Okta: verify the token, don't issue it](solutions/05-okta-jwt/) · [Signed requests, without sending the secret](solutions/06-hmac-auth/) · [API keys for callers that can't do a token exchange](solutions/08-api-key/)
- **How much can they call?** — [API Products: sell tiers you can enforce](solutions/01-api-products/)
- **What shape is the payload?** — [Serve a SOAP backend as REST/JSON](solutions/03-soap-to-rest/) · [JSON in front of a backend that speaks XML](solutions/09-xml-to-json/) · [One route, many partners, rotation without a deploy](solutions/12-key-value-map/) · [PGP at the edge, so the keyring script can go](solutions/13-pgp-encryption/)
- **What else must happen on the way?** — [HTTP to Kafka, with no service in between](solutions/07-http-to-kafka/) · [The lookup every service re-implements, done once](solutions/11-service-callout/) · [A sandbox that answers each partner with their data](solutions/14-dynamic-mock/)
- **What do we know about the traffic?** — [Analytics: read what the gateway already captured](solutions/04-analytics/) · [Mask the values, not just the log line](solutions/10-data-mask/)
- **What protocol is it?** — [A bidirectional gRPC stream, authenticated](solutions/15-grpc-proxy/)

## Agent-first, on purpose

Every solution here is written to be built by conversation, not by hand-editing
YAML. The gateway configuration in `gateway/api-spec.yaml` is the **source of
truth** for what the solution does — but it is the *output* you should expect,
not the input you should type.

```text
You:    Create a Posts API on jsonplaceholder that issues OAuth 2.0 access
        tokens and validates them on every other endpoint.
Agent:  [looks up the API] [fetches the real plugin schemas]
        [shows the spec it proposes] [waits]
You:    Looks right — dry-run it.
Agent:  [dry_run_deploy] [reports errors or a clean plan]
You:    Deploy it.
```

Read **[AGENT-GUIDE.md](AGENT-GUIDE.md)** first. It covers how to write a prompt
the agent can act on, the confirm-gate discipline that keeps you in control of
anything hard to undo, the platform vocabulary the agent expects, and the
handful of wrong turns a general-purpose model reliably takes on this platform.

## What's in a solution package

```
solutions/<NN>-<slug>/
├── README.md               # problem, business need, how it works, gotchas, validation
├── solution.yaml           # the manifest — one version across every artifact
├── business-need.md        # why it matters
├── architecture.md         # request flow, native-vs-custom, when not to use it
├── helix-agent-prompt.md   # the paste-into-Agent-Mode prompt, and why it's shaped that way
├── gateway/
│   ├── api-spec.yaml       # importable OpenAPI 3.0.3 + x-helix-gateway.plugins
│   ├── products.json       # API Products, where the solution needs them
│   └── verify.sh           # exits 0 against a live environment
├── tests/                  # test-plan.yaml + request fixtures + expected responses
└── validation/             # what was checked, by whom, and what wasn't
```

Diagrams live inside `README.md` as mermaid blocks, which GitHub renders inline —
there is no separate image to open, and nothing to build.

Only files that apply are present — a solution needing no API Products has no
`products.json`. Some packages carry an extra file where the subject warrants it:
solution 04 has [`charts.md`](solutions/04-analytics/charts.md), a catalogue of
the real analytics-API queries for the library, which is that package's deliverable.

Two ways in: paste `helix-agent-prompt.md` into Agent Mode, or import
`gateway/api-spec.yaml` directly through OpenAPI import. Both land in the same
place; the first one teaches you more.

## Reference

Shared across every solution, written once:

- **[Placeholders](guides/placeholders.md)**
- **[The platform model](guides/platform-model.md)**
- **[Prerequisites](guides/prerequisites.md)**
- **[Validation status — what the badges mean](guides/validation-status.md)**
- **[Vocabulary](guides/vocabulary.md)**

Every plugin these solutions configure, and which solution uses it:
**[Plugin index](plugins/readme.md)**.

## Contributing

See [CONTRIBUTING.md](CONTRIBUTING.md). The short version: the gateway
configuration is the source of truth, documentation is derived from it and never
the reverse, and a validation status you didn't produce doesn't go in.
