# Helix Solutions

A public library of **solved API problems** for the Helix API Gateway — built the
way we expect you to build them: by describing the outcome to the **Helix Agent**
and letting it generate, validate and deploy the configuration.

Each solution is a self-contained package: one real problem, one importable
gateway configuration, the agent prompt that produces it, the tests that prove
it, and an honest record of what was and wasn't validated.

---

## The four solutions

| # | Solution | The problem it solves | Build it with the Agent |
|---|---|---|---|
| **01** | [OAuth 2.0 with JWT](solutions/01-oauth-jwt/) | *"Partners want OAuth. Adding it to the backend is a six-week release."* Issue and validate JWTs at the edge — the backend never learns about auth. | [prompt](solutions/01-oauth-jwt/helix-agent-prompt.md) |
| **02** | [SOAP to REST](solutions/02-soap-to-rest/) | *"Our core system speaks SOAP/XML and every partner wants JSON."* Mediate both directions at the gateway; the SOAP service is untouched. | [prompt](solutions/02-soap-to-rest/helix-agent-prompt.md) |
| **03** | [API Products](solutions/03-api-products/) | *"We sell an 'Enterprise tier' with no way to enforce it, and one partner's retry loop can take down everyone."* Bundle APIs into products with quotas, enforced per app. | [prompt](solutions/03-api-products/helix-agent-prompt.md) |
| **04** | [Analytics](solutions/04-analytics/) | *"We can't tell which of our 400 integrations caused the 3am pager."* Analytics is already capturing every call — this is how you ask it the right questions. | [prompt](solutions/04-analytics/helix-agent-prompt.md) · [charts](solutions/04-analytics/charts.md) |

They compose. 01 gives you identity, 02 gives you the protocol bridge, 03 turns
the result into something sellable, and 04 tells you what happened. Running all
four against one API takes you from *internal SOAP endpoint* to *metered,
observable, partner-facing product* without a backend change.

## Agent-first, on purpose

Every solution here is written to be built by conversation, not by hand-editing
YAML. The gateway configuration in `gateway/api-spec.yaml` is the **source of
truth** for what the solution does — but it is the *output* you should expect,
not the input you should type.

```text
You:    Create a REST API called Orders API that issues OAuth 2.0 access
        tokens and validates them on every other endpoint.
Agent:  [looks up the API] [fetches the real plugin schemas]
        [shows the spec it proposes] [waits]
You:    Looks right — dry-run it.
Agent:  [validate_route] [dry_run_deploy] [reports errors or a clean plan]
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
├── blog.md                 # the long-form write-up
├── infographic.md          # panel spec for the one-glance version
├── gateway/
│   ├── api-spec.yaml       # importable OpenAPI 3.0.3 + x-helix-gateway.plugins
│   ├── products.json       # API Products, where the solution needs them
│   └── verify.sh           # exits 0 against a live environment
├── tests/                  # test-plan.yaml + request fixtures + expected responses
└── validation/             # what was checked, by whom, and what wasn't
```

Only files that apply are present — a solution needing no API Products has no
`products.json`. Some packages carry an extra file where the subject warrants it:
solution 04 has [`charts.md`](solutions/04-analytics/charts.md), a catalogue of
twelve questions worth asking, which is that package's real deliverable.

Two ways in: paste `helix-agent-prompt.md` into Agent Mode, or import
`gateway/api-spec.yaml` directly through OpenAPI import. Both land in the same
place; the first one teaches you more.

## The platform model — read this before configuring anything

The mental model from other API gateways does not transfer cleanly. Four things
account for most early mistakes:

- **The importable artifact is an OpenAPI 3.0.3 document.** Gateway policy rides
  along inside it as `x-helix-gateway.plugins` — at the document root for
  API-wide policy, under `paths.<path>.<method>` for a single route. You don't
  hand-write route JSON, and you don't keep the spec and the config in two
  places.
- **Plugin execution is priority-ordered, not document-ordered.** A plugin can
  only read a `ctx.*` value that a *higher-priority* plugin on the same route
  already produced. Listing plugins in the order you want them to run does
  nothing.
- **Identity is `helix-auth`.** In `validate` mode it resolves the calling app
  *and* the product it's subscribed to. Raw `key-auth` authenticates but resolves
  no subscription, which quietly breaks quota enforcement downstream. Use
  `jwt-auth` only when an external identity provider issues the tokens.
- **Per-caller metering is API Products, counted per app.** The quota lives on
  the product, not on the route, and is keyed on the credential — not on an IP,
  not on `consumer_name`. Solution 03 covers this in full.

Vocabulary, because the docs and the UI use both halves of each pair:

| You'll hear | It means | Underneath |
|---|---|---|
| **Developer** | The organisation or person consuming your API | a Consumer |
| **App** | One integration, with its own key/secret | a Credential |
| **Product** | A bundle of APIs plus a quota — the thing you sell | a product document |
| **API** | What you publish | a Service, deployed per environment via revisions |

## Validation status — what the badges mean

These are five different things and this library never blurs them:

`Configuration generated` · `Locally validated` · `Gateway dry-run passed` ·
`Gateway deployed` · `Functional test passed`

Every package's `validation/` directory records which of these actually happened,
who performed it, and whether it was re-run when the package was last touched.
Where a status came from an earlier run rather than the current one, it says so.
**Nothing in this repo claims a result that wasn't produced by a real gateway.**

Each solution README carries the same table:

| Stage | Status | Provenance |
|---|---|---|

Overall status is one of **READY** · **READY WITH WARNINGS** · **UNVALIDATED**
(generated and structurally reviewed, but not confirmed against a gateway) ·
**NOT READY** (a dry-run failed).

Whatever a package says, **re-run `gateway/verify.sh` against your own
environment before you rely on it.** Plugin builds differ between orgs.

## Placeholders

No secrets, hostnames, org identifiers or customer names appear anywhere in this
repo. You will see:

| Placeholder | Replace with |
|---|---|
| `<YOUR_GATEWAY_HOST>` | the host your environment serves traffic on |
| `<ORG_ID>` · `<ENV_ID>` · `<API_ID>` | identifiers from your control plane |
| `<CLIENT_ID>` · `<CLIENT_SECRET>` | your app's credentials — the control plane issues these |
| `<UPSTREAM_URL>` · `<SOAP_UPSTREAM_URL>` | your backend |
| `<ENV:JWT_SIGNING_SECRET>` | an environment variable on the gateway, never a literal |

App keys and secrets are provisioned on the credential by the control plane.
**They never belong in a spec**, and the agent should never be asked to put them
there.

## Prerequisites

- A Helix organisation, with at least one environment you can deploy to.
- The API you want to protect, reachable from the gateway.
- Access to Helix **Agent Mode**, if you're building the recommended way.
- `curl` for `verify.sh`; `jq` is optional but makes failures easier to read.
- **Confirm each plugin exists in your org before using it** — ask the agent
  `get_plugin_config` for it, or check the control plane's plugin-schema
  endpoint. Builds vary, and a plugin that isn't there fails at deploy time with
  an unhelpful message.

## Contributing

See [CONTRIBUTING.md](CONTRIBUTING.md). The short version: the gateway
configuration is the source of truth, documentation is derived from it and never
the reverse, and a validation status you didn't produce doesn't go in.
