# Building with the Helix Agent

Every solution in this library was designed to be built by describing the
outcome, not by writing configuration. This is how to do that well.

The agent has access to your organisation: it can list your APIs, read the real
plugin schemas your build ships, generate a spec, validate it, dry-run a
deployment, deploy a revision, and create developers, apps and products. That
makes it fast, and it also means the difference between a good prompt and a bad
one is the difference between a working API and a broken revision.

---

## 1. Prompt at the level of outcomes, not fields

The single most useful habit: **say what you want to be true, and let the agent
fetch the schema.**

> ✅ *"Use a plugin to transform the upstream requests and responses to JSON."*
>
> ❌ *"Add `xml-to-json` with `mode: bidirectional` and `preserve_attributes: true`."*

The second version looks more precise and is worse. Plugin schemas differ between
builds, and a model asked for specific fields will pattern-match them from
memory of other gateways rather than reading what your org actually has. Asked
for an outcome, it calls `get_plugin_config` and writes fields that exist.

Reserve field-level precision for the things you genuinely have an opinion about
— a token lifetime, a quota number, an error policy — and say *why*:

> *"Token TTL 900 seconds. A leaked token should be worthless within fifteen
> minutes, so don't default it to an hour."*

The "because" matters. It survives into the agent's summary and into whatever it
does next, and it stops a later prompt from quietly undoing the decision.

## 2. Structure the prompt so it can be acted on

Every prompt in this library follows roughly the same shape. It isn't
ceremony — each block prevents a specific failure.

```text
OBJECTIVE      One sentence. What should be true when this is done.

CONTEXT        Which API, which environment, which upstream. How the agent
               should find them ("find it with list_apis; if more than one
               matches, ask me before changing anything").

WHAT I WANT    Numbered outcomes, in the order a request encounters them.

CONSTRAINTS    Known platform behaviour to respect, and the wrong turns to
               avoid — each with a reason.

BEFORE YOU     Show me the spec. Run validate_route and dry_run_deploy. Wait
DEPLOY         for my confirmation.

AFTER YOU      What to hand back: credentials, a curl command that proves it,
DEPLOY         and a plain-language description of what a rejected caller sees.
```

The **CONTEXT** block is what stops the agent from guessing. "Find it with
`list_apis`; if more than one matches, ask me" costs you one line and removes an
entire category of accident.

The **AFTER YOU DEPLOY** block is what turns a deployment into something you can
demo. An agent that has just built a rate limit can also hand you the two app
keys and the loop that makes the 429 appear — but only if you ask.

## 3. Keep the confirm gate

The order that works, every time:

```
validate_route  →  dry_run_deploy  →  show me the spec  →  [you confirm]  →  deploy_revision
```

Put this in the prompt explicitly, and add the sentence that matters most:

> *"If either validation fails, show me the error and your proposed fix rather
> than retrying blindly."*

Without it, a model that hits a schema error will often try three variations of
the same wrong field and report success on the one that validated for the wrong
reason. With it, you see the error, and you usually recognise the cause faster
than the agent does.

**Never let the first gateway interaction be a deploy.** Dry-run is
non-destructive and tells you almost everything a deploy would.

## 4. Build in acts, not in one shot

Long prompts that do six things produce revisions you can't reason about. Split
the work the way the request path is split, and deploy between acts:

```text
Act 1   Create the API, bind the upstream, get the transform working.
        → deploy, confirm you get a response at all
Act 2   Add the token endpoint and put validation on the protected routes.
        → new revision, confirm 401 without a token and 200 with one
Act 3   Create the developer, the app and the product; share the credentials.
        → confirm a real call from a real app
Act 4   Ask for the usage you just generated.
```

Each act is independently verifiable, and when something breaks you know which
act broke it. This is also why the agent prompts in this repo are written as
acts — solution 02 is act 1 plus act 2, solution 03 is act 3, solution 04 is
act 4.

One thing to know before act 2: **an ACTIVE revision will not accept edits.**
You'll get `Only INACTIVE revisions can be updated`. Tell the agent to clone the
revision (keeping the live one as a rollback target) or undeploy first.

## 5. Give the agent the platform's opinions

This is the highest-value part of any Helix prompt, because a general-purpose
model brings generic API-gateway habits with it. Each of these is a real wrong
turn, not a hypothetical:

| Constraint to state | What goes wrong without it |
|---|---|
| *"Use `helix-auth`, not the raw `key-auth` plugin."* | `key-auth` authenticates the caller but resolves no product subscription, so quota enforcement downstream returns 403 on every request. |
| *"Don't key any rate limit on `consumer_name`. Per-caller metering here is the product quota, counted per app."* | You get a `limit-count` that looks right, meters the wrong thing, and silently coexists with the product quota. |
| *"Don't put Redis settings in the `api-product-enforcer` block."* | The plugin's schema doesn't accept them. Either validation fails, or it passes and each gateway node counts separately — so an N-node cluster serves N× the quota you sold. |
| *"Use `helix-auth` in generate mode, not `jwt-auth`, since the gateway is the issuer."* | `jwt-auth` is for tokens an *external* IdP signed. Pointed at your own tokens it's the wrong half of the flow. |
| *"Use `filter_func` for conditional matching, not `vars`."* | `vars` is typed incompatibly between the control plane and the gateway and fails at deploy. |
| *"Only schema fields plus `_meta` are legal in a plugin block."* | Models like to add explanatory keys — `description`, `note`, `reason`. They are rejected. Explanation belongs in a YAML comment. |
| *"Check `get_plugin_config` for every plugin before writing config."* | Fields invented from another gateway's docs. This one line prevents most schema failures. |
| *"Confirm the route has a `service_id`."* | `api-product-enforcer` returns 403 with no service id, regardless of subscription, and nothing in the plugin config hints at it. |

Copy the ones relevant to what you're building. The per-solution prompts already
carry theirs.

## 6. Ask the agent to explain execution order

Because plugins run by priority rather than in the order you wrote them, "which
plugin runs first" is a real question with a real answer, and it's worth making
the agent say it out loud:

> *"Explain the execution order of the plugins on this route, and which one
> produces the context the next one reads."*

If the answer is vague, the config is probably wrong in a way that will only show
up as a 403 under load. This is also the fastest way to catch a plugin that's
been placed on the wrong route or at the wrong scope.

## 7. Read analytics by asking

Analytics is **already on**. Every request through the gateway is captured — you
don't add a plugin, and a prompt that asks you to is a prompt to correct. What
you do instead is query it:

> *"Show me calls to Orders API in the last hour, broken down by app, and tell
> me which app sent the most."*
>
> *"Which routes returned 5xx yesterday, and what was the p99 latency on each?"*
>
> *"Which apps came within 10% of their product quota this week?"*

Two things make those answers useful, and both are configuration decisions you
make earlier: **identity must be resolved** (so calls attribute to an app rather
than an IP), and **paths must be templated** (`/orders/{orderId}`, not a
thousand distinct URLs). Solution 04 is about exactly this.

## 8. What the agent won't do

Be clear-eyed about the boundary, because a prompt that assumes otherwise stalls:

- **It doesn't set environment secrets for you.** `<ENV:JWT_SIGNING_SECRET>` has
  to exist on the environment before the token flow works. The agent can tell
  you it's missing; you set it.
- **It doesn't bind upstreams that don't exist**, and it can't reach a backend
  your gateway can't reach.
- **It doesn't publish to the Marketplace.** That's a portal action.
- **It doesn't know your commercial numbers.** A quota of 1000/min is a guess
  until you tell it what your contract says and what your upstream can take.
- **It doesn't invent validation results** — and neither should you. A generated
  config is not a deployed config, and a deployed config is not a tested one.

## 9. When it goes wrong

| Symptom | Almost always |
|---|---|
| Everything returns **401** | You're sending the app's *secret* where its *key* (client id) belongs. Key-auth validate resolves on the key. |
| Everything returns **403** | The app isn't subscribed to a product covering this API, or the route has no `service_id`. Ask the agent to `get_app` and check the `products` map is non-empty. |
| **429 never arrives** | The quota is higher than you think, or the quota backend is counting per node. |
| Deploy fails: `Only INACTIVE revisions can be updated` | Clone the revision or undeploy, then apply. |
| Token is rejected immediately after being issued | The signing secret on the issue route and the validate route don't match. |
| The agent adds a field you don't recognise | Ask: *"is that field in the plugin's schema? Show me `get_plugin_config` output."* Usually it isn't. |

When you correct the agent, correct it with the reason. *"That field isn't in the
enforcer's schema — the quota backend is configured in `plugin_attr`, not on the
route. Remove it."* works. *"That's wrong"* gets you a different guess.

## 10. Before you call it done

- The spec the agent applied is the spec you read and confirmed.
- `validate_route` and `dry_run_deploy` both passed, and you saw the output.
- A real call from a real app succeeded, and a deliberately bad call failed the
  way you expected.
- You know what a rejected caller sees — the status, the body, and which headers
  are *absent* — because that's what goes in your developer documentation.
- The environment secrets the spec references actually exist.
- Nothing the agent produced contains a literal credential.

Then run the solution's `gateway/verify.sh`. That's the difference between "the
agent said it deployed" and "it works".
