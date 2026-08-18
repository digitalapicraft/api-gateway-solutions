# Contributing

Thanks for wanting to add to this library. The bar here is narrower than usual:
a solution is only worth publishing if someone can import it into their own
organisation and have it work. Everything below serves that.

---

## The one rule

Work in this order, and never reverse it:

```
PROBLEM → BUSINESS NEED → DESIGN → GATEWAY SPEC → LOCAL VALIDATION →
GATEWAY DRY-RUN → TESTS → RESULTS → DOCUMENTATION
```

**The gateway configuration is the source of truth.** The README, the
architecture doc, the agent prompt and the infographic all
describe the solution that was actually generated and validated — never an
idealised one. If you find yourself editing the spec so it matches something you
already wrote, stop and re-derive the writing instead.

## What a new solution needs

Copy an existing package and replace the content. Keep the section headings —
they're what makes the library scannable.

```
solutions/<NN>-<slug>/
├── README.md               required
├── solution.yaml           required — the manifest
├── business-need.md        required
├── architecture.md         required
├── helix-agent-prompt.md   required
├── infographic.md          required
├── gateway/
│   ├── api-spec.yaml       required — the importable source of truth
│   ├── products.json       only if the solution needs API Products
│   └── verify.sh           required — must exit 0 against a live environment
├── tests/
│   ├── test-plan.yaml      required
│   ├── requests/           request fixtures
│   └── expected/           expected responses
└── validation/
    ├── local-validation.yaml    required
    └── gateway-validation.yaml  required
```

Only create files that apply. A solution that needs no products doesn't get an
empty `products.json`.

The slug is a **problem**, not a plugin. `soap-to-rest` and `api-products`, not
`xml-to-json-plugin`.

## Validation honesty

This is the part we're strict about, because it's the whole value of the library.

These five statuses mean five different things:

| Status | Means |
|---|---|
| `Configuration generated` | The YAML exists. Nothing more. |
| `Locally validated` | Syntax, schema, references and plugin ordering were reviewed. Still says nothing about gateway behaviour. |
| `Gateway dry-run passed` | A real gateway accepted the configuration in a non-destructive check. |
| `Gateway deployed` | It's live in an environment. |
| `Functional test passed` | Requests were sent and the responses matched. |

Rules:

- **Never write "works on Helix"** unless a gateway validated or executed it.
- **Never record a dry-run, deployment or test result you didn't obtain from a
  real gateway.** Not an inference, not a strong expectation.
- **If you didn't run it in the change you're submitting, say so.** Every status
  in `validation/` carries `verified_this_session` and, where it came from an
  earlier run, a `provenance` line naming who ran it and against what.
- A failed dry-run is **NOT READY** and doesn't get merged as READY with a
  footnote.

Overall status:

| Overall | When |
|---|---|
| **READY** | Everything in the quality gate below passed. |
| **READY WITH WARNINGS** | Dry-run passed, but there are caveats a user must know — and they're written down in the README. |
| **UNVALIDATED** | Generated and structurally reviewed, not confirmed against a gateway. Allowed, but must be labelled everywhere including the README table. |
| **NOT READY** | A dry-run failed. Fix it or report the blocker; don't hand-wave it. |

If a dry-run keeps failing, cap yourself at three fix-and-revalidate attempts,
then open an issue describing the blocker. A documented blocker is more useful
than a config that validates for a reason nobody understands.

## No secrets, no internal identifiers

Nothing merged here contains a real credential, hostname, organisation
identifier, customer name or internal URL. Use:

`<YOUR_GATEWAY_HOST>` · `<ORG_ID>` · `<ENV_ID>` · `<API_ID>` · `<CLIENT_ID>` ·
`<CLIENT_SECRET>` · `<UPSTREAM_URL>` · `<ENV:SOME_SECRET>`

Credentials are provisioned on the credential by the control plane and **never
appear in a spec**. If your solution seems to need one in the config, the design
is wrong.

Demo personas should be obviously fictional and generic. No real email addresses.

## Platform conventions

Get these right or the package is confidently misleading:

- The importable artifact is an **OpenAPI 3.0.3 document with
  `x-helix-gateway.plugins`** — root level for API-wide policy, under
  `paths.<path>.<method>` for one route. Not hand-written route JSON.
- **Plugin blocks accept schema fields plus `_meta` only.** No commentary keys.
  Put explanation in YAML comments.
- **Execution is priority-ordered**, not document-ordered. If your solution
  depends on ordering, say so in a comment and in `architecture.md`.
- **Prefer the Helix opinion** over the generic equivalent: `helix-auth` over a
  bare static key; API Products + `api-product-enforcer` over `limit-count` on
  `consumer_name`; `helix-auth` `generate` for tokens the gateway issues, and
  `validate` with `validate_auth_type: jwt-auth` for external-IdP tokens.
  `key-auth`/`jwt-auth` are `validate_auth_type` values of `helix-auth`, **not**
  standalone plugins on this build.
- **Secrets are literals, not references.** This build does not resolve
  `<ENV:...>` — a `signing_secret` is used verbatim. Use a `<YOUR_...>`-style
  placeholder that a contributor must replace, and never commit a real one. Do not
  imply that `<ENV:...>` resolves.
- **Analytics is global.** Don't add a `helix-analytics` block to a spec and
  don't tell readers to. See [solution 04](solutions/04-analytics/).
- **Prefer the simplest native capability.** Don't write custom code where a
  stable plugin does the job. If custom really is required, explain why, handle
  failures, and document the execution phase and performance implications.
- **Confirm every plugin exists in the target org** before using it. Builds
  differ. Say in the README which plugins need confirming.
- **Don't name the underlying runtime** in reader-facing content.

## Documentation style

- **Quantify the business need.** "Reduces risk" isn't one. Describe the concrete
  failure and what it costs. Don't invent numbers — if you don't have a metric,
  describe the mechanism instead.
- **State the limitations in the package.** Every solution has some. A missing
  response header, a counting scope that surprises people, a manual step. They
  go in the README under *Limitations* and in `solution.yaml`. Trust is the
  product.
- **Show what a rejected caller actually sees** — status, body, and which headers
  are absent. This is the part readers hit in production.
- Write for someone deciding in sixty seconds whether this applies to them.

## Agent prompts

The prompt is a first-class artifact, not a convenience.

- It must work **from a blank organisation**, with no hidden conversation
  context. If it only works when you already know the answer, it's a note to
  self.
- It must produce a solution **equivalent to `gateway/api-spec.yaml`**. If the
  agent's output and the committed spec have diverged, one of them is wrong.
- Prompt at the level of outcomes; let the agent fetch real schemas. See
  [AGENT-GUIDE.md](AGENT-GUIDE.md).
- Include the confirm gate: show the spec, `validate_route`, `dry_run_deploy`,
  wait.
- Include the **known failure modes** section. What you learned the hard way
  running it is the most valuable thing in the file.

## Quality gate

A solution is mergeable when all of these hold:

- [ ] Problem stated in a customer's words
- [ ] Business need identified, and quantified where a real metric exists
- [ ] Architecture documented, matching the spec
- [ ] `gateway/api-spec.yaml` generated
- [ ] Local validation passed, recorded in `validation/local-validation.yaml`
- [ ] Gateway dry-run performed and recorded — or the package is clearly labelled UNVALIDATED
- [ ] Tests defined: at least one positive, one negative, one boundary, and one failure case where relevant
- [ ] `verify.sh` present, and its exit-0 condition described in the README
- [ ] No secrets, hostnames or internal identifiers
- [ ] Agent prompt, infographic spec and README present
- [ ] Limitations stated
- [ ] Validation status reported accurately, with provenance
- [ ] `solution.yaml` version matches every artifact in the package

## Submitting

One solution per pull request. In the description, tell us:

1. Which stages you actually ran, and against what.
2. Anything that surprised you — that usually belongs in *Gotchas*.
3. Which plugins you had to confirm existed in your org.

Fixes to existing solutions are just as welcome, especially ones that correct a
gotcha or a limitation. If the platform's behaviour has moved and a package is
now wrong, say so plainly in the issue — a package that's quietly stale is worse
than one marked broken.
