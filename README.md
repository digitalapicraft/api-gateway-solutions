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

## The thirteen solutions

| # | Solution | The problem it solves | Build it with the Agent |
|---|---|---|---|
| **01** | [API Products](solutions/01-api-products/) | *"We sell an 'Enterprise tier' with no way to enforce it, and one partner's retry loop can take down everyone."* Bundle APIs into products with quotas, enforced per app. | [prompt](solutions/01-api-products/helix-agent-prompt.md) |
| **02** | [OAuth 2.0 with JWT](solutions/02-oauth-jwt/) | *"Partners want OAuth. Adding it to the backend is a six-week release."* Issue and validate JWTs at the edge — the backend never learns about auth. | [prompt](solutions/02-oauth-jwt/helix-agent-prompt.md) |
| **03** | [SOAP to REST](solutions/03-soap-to-rest/) | *"Our core system speaks SOAP/XML and every partner wants JSON."* Mediate both directions at the gateway; the SOAP service is untouched. | [prompt](solutions/03-soap-to-rest/helix-agent-prompt.md) |
| **04** | [Analytics](solutions/04-analytics/) | *"We can't tell which of our 400 integrations caused the 3am pager."* Analytics is already capturing every call — this is how you query it, through the metrics API, for the answers that matter. | [prompt](solutions/04-analytics/helix-agent-prompt.md) · [charts](solutions/04-analytics/charts.md) · [script](solutions/04-analytics/scripts/query-analytics.sh) |
| **05** | [OAuth with Okta](solutions/05-okta-jwt/) | *"We already run Okta, but our APIs still check a static key from 2021."* Verify the IdP's own tokens at the edge — the mirror of 02, for when someone else is the issuer. | [prompt](solutions/05-okta-jwt/helix-agent-prompt.md) |
| **06** | [Signed requests](solutions/06-hmac-auth/) | *"We gave a partner an API key in 2021. It's in their runbook, their CI, and a Jira ticket — and it tells us nothing about the payload it arrived with."* Prove the caller holds a secret without ever sending it, and bind the proof to the request body. | [prompt](solutions/06-hmac-auth/helix-agent-prompt.md) |
| **07** | [HTTP to Kafka](solutions/07-http-to-kafka/) | *"Partners want to POST us events. The service in between is three lines long and has been on the roadmap for three quarters."* Validate, acknowledge and publish at the edge — no ingest service. At-most-once, and the package proves it by breaking the broker. | [prompt](solutions/07-http-to-kafka/helix-agent-prompt.md) |
| **08** | [API keys](solutions/08-api-key/) | *"Four thousand terminals in the field. They can't run a token exchange, and the only thing protecting the endpoint is that the URL isn't published."* Per-caller identity for clients that can set one header — and revocation you perform in seconds. | [prompt](solutions/08-api-key/helix-agent-prompt.md) |
| **09** | [XML to JSON](solutions/09-xml-to-json/) | *"Our stock system is REST. It just answers in XML, so four client teams each wrote their own parser."* Mediate both directions at the edge — with no SOAP envelope in sight. | [prompt](solutions/09-xml-to-json/helix-agent-prompt.md) |
| **10** | [Data masking](solutions/10-data-mask/) | *"Audit flagged PII in the logs. While we were reading the samples we noticed the support console shows agents all of it too."* Two different masks, for two different audiences — and the one most teams ship is the wrong one. | [prompt](solutions/10-data-mask/helix-agent-prompt.md) |
| **11** | [Service callout](solutions/11-service-callout/) | *"Seven services each start by calling the customer-profile service. Seven caches, seven timeouts, seven opinions about what to do when it fails."* Do the lookup once and hand the answer to the backend as a header. | [prompt](solutions/11-service-callout/helix-agent-prompt.md) |
| **12** | [Key-value map](solutions/12-key-value-map/) | *"Fourteen partners, fourteen keys in fourteen routes, and a deploy every time one of them rotates."* Fetch the key per request so rotation is a write, not a release. | [prompt](solutions/12-key-value-map/helix-agent-prompt.md) |
| **13** | [PGP encryption](solutions/13-pgp-encryption/) | *"The bank only accepts PGP-encrypted payloads. Today that's a Python script with a keyring on a VM, and it's what pages us at 2am."* Decrypt inbound and encrypt outbound at the edge; the backend never handles ciphertext. | [prompt](solutions/13-pgp-encryption/helix-agent-prompt.md) |
| **14** | [Dynamic mock](solutions/14-dynamic-mock/) | *"Every partner gets the same canned response from our sandbox, so nobody catches an integration bug until production."* Answer each caller with that caller's own stored values — one route, no backend, and changing a value is a write rather than a release. | [prompt](solutions/14-dynamic-mock/helix-agent-prompt.md) |
| **15** | [gRPC stream proxy](solutions/15-grpc-proxy/) | *"Our units hold a bidirectional gRPC stream open for hours. Anything that wants to authenticate or count them has to be built into the service."* Authenticate each stream as it opens, from gRPC metadata, without touching the service. | [prompt](solutions/15-grpc-proxy/helix-agent-prompt.md) |

They compose. 02 gives you identity, 03 gives you the protocol bridge, 01 turns
the result into something sellable, and 04 tells you what happened. Running all
four against one API takes you from *internal SOAP endpoint* to *metered,
observable, partner-facing product* without a backend change.

**Four answer "who is calling" and you want exactly one of them on a route:**
02 (the gateway mints the token), 05 (an external IdP does and the gateway only
verifies), 06 (the caller signs, and the credential never travels) and 08 (the
caller can set one header and nothing more). Pick by what the caller can hold.

**Three pairs are deliberately two packages rather than one.** 03 and 09 both
mediate XML, and the first table in 09 tells you which you have. 13 and 12 do the
same crypto with the key in the route and in a store respectively — read 13 first
and move to 12 at the second counterparty. 10's two masks are the third pair, and
they live in one package because shipping one without the other is the standard
way that project fails.

A browser can hold a token but not a secret; a partner's backend can hold either,
and should sign when the payload's integrity is the point; a forecourt terminal
can hold neither and gets a key you can kill in seconds.

**07 and 12 each ship a route you must protect before using.** 07 answers the
caller itself and publishes to Kafka with no authentication; 12's key-registration
route writes key material and is equally open. Both are deliberate — every package
here ships with the behaviour under test and nothing else — and both packages say
so in their own tests rather than in a footnote.

**07 is the odd one out, deliberately.** Every other solution proxies to a
backend; 07 has none — it answers the caller itself and publishes to Kafka. It
also ships unauthenticated, which is what 06 is for. Its package is explicit
about both that and its at-most-once delivery, because those are the two things
that decide whether it suits your data.

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
- **Identity is `helix-auth` — for tokens the gateway itself issues.** In
  `validate` mode it resolves the calling app *and* the product it's subscribed
  to. It takes a `validate_auth_type` of `key-auth` (static app key) or `jwt-auth`
  (a JWT the gateway signed in `generate` mode). Note: `key-auth` and `jwt-auth`
  are **not** standalone plugins on this build — they exist only as
  `validate_auth_type` values of `helix-auth`.
- **When an external IdP issues the tokens, it's `openid-connect` instead.**
  `helix-auth` has no JWKS URL, issuer or audience field — and its schema is
  `additionalProperties: false`, so one cannot be added. It cannot verify a token
  it did not mint. For Okta, Entra ID, Auth0 or Keycloak use `openid-connect` with
  `discovery`, and set `unauth_action: deny` — the default is `auth`, which
  answers an unauthenticated API call with a **302 redirect to the IdP's login
  page**. `openid-connect` is not on every build; check
  `GET /orgs/{orgId}/plugin-schemas` first. See
  [solution 05](solutions/05-okta-jwt/).
- **Per-caller metering is API Products, counted per app.** The quota lives on
  the product, not on the route, and is keyed on the credential — not on an IP,
  not on `consumer_name`. Solution 01 covers this in full.

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
| `<YOUR_JWT_SIGNING_SECRET>` · `<YOUR_REDIS_HOST>` | a **literal** value you fill in — see the warning below |
| `<OKTA_DISCOVERY_URL>` · `<OKTA_ISSUER_URL>` | your IdP's discovery document, and the `issuer` value that document reports |
| `<OKTA_CLIENT_ID>` · `<OKTA_CLIENT_SECRET>` | the IdP application's credentials — also **literals**, see the warning below |
| `<KEY_ID>` · `<SECRET_KEY>` | an app credential's HMAC key pair — the control plane generates these; they never appear in a spec |
| `<YOUR_KAFKA_BROKER>` | a broker hostname the **gateway** can reach. Not a secret |
| `<DEVICE_API_KEY>` · `<APP_SECRET>` | an app credential's key and secret — the control plane issues these; they never appear in a spec |
| `<PGP_PUBLIC_KEY>` · `<PGP_PRIVATE_KEY>` | armored OpenPGP key blocks. **Literals**, like the signing secret — see the warning below |

App **keys and secrets** (the `client_id`/`client_secret` on an app) are
provisioned on the credential by the control plane and never belong in a spec.

> **⚠️ The signing secret is different, and this matters.** Verified against a live
> gateway, this build does **not** resolve `<ENV:...>` or `${...}`
> syntax. Whatever string sits in `signing_secret` is used *verbatim* as the HMAC
> key. So `<YOUR_JWT_SIGNING_SECRET>` is a fill-in-the-blank, **not** an
> environment-variable reference — replace it with a real, high-entropy secret
> before deploy, and keep the filled-in spec out of version control. If you ship
> the placeholder literally, your signing key is a publicly known constant and
> anyone can forge tokens. The same applies to `<OKTA_CLIENT_SECRET>` in solution
> 05 — it is a literal too, and the control plane stores it encrypted only after
> you have supplied a real one.
>
> **Solution 06 has no such footgun, by construction.** `hmac-auth`'s route schema
> has no secret field at all, so there is nothing to fill in and nothing to leak —
> `key_id` and `secret_key` live only on the app credential. **Solution 08 has the
> same property** for the same structural reason: the route names the *header* an
> API key arrives in, never the key.
>
> **Solution 13 has the worst version of it.** `private_key` and `public_key` are
> literals too, and a private key outlives a signing secret and is usually shared
> with a counterparty. That limitation is the entire reason
> [solution 12](solutions/12-key-value-map/) exists: it fetches the key per request
> so no key material is in the document at all.

## Prerequisites

- A provisioned gateway, with an organisation and at least one environment you can deploy to.
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
