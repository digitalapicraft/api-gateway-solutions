# How it works — Solution 14 — A sandbox that answers every partner with that partner's own values

[Overview](readme.md) · [Business need](business-need.md) · **How it works** · [Install](install.md) · [Configuration](configuration.md) · [Test & verify](testing.md) · [Changelog](changelog.md)

---

## The one thing to get right: there are two substitution grammars

This is the whole solution, and getting it wrong fails **silently** — a 200, an
empty string, and nothing in any log.

| Form | What it does | Reads a stored value? |
|---|---|---|
| `${ctx.helix.<ns>.<field>}` | Looks the **whole dotted string** up as one variable *name* in a flat table. Only `service-callout` ever writes to that table. | **No.** Always empty here. |
| `$ctx.<dotted.path>` | Bare `$`, no braces. **Walks the request context** segment by segment, so it reaches anything actually present. | **Yes.** |

`key-value-map` publishes into `ctx.helix.key_value_map` all along. The second
form reaches it; the first cannot. On this build **only `mocking` resolves the
second form** — in `response_example` *and* `response_headers`.

The package ships a `/sandbox/diagnostics` route that prints the same value in
both grammars, so a team learning this can see the difference rather than read
about it:

```
bare_form   = platinum
brace_form  =
namespace   = {"tier":"platinum"}
```

`gateway/verify.sh` asserts that the brace form stays empty. If it ever starts
resolving, this package's explanation is wrong and its guidance should change.

### Where values land

```
fetched   ->  ctx.helix.<ctx_namespace>.<key>           flat
inserted  ->  ctx.helix.<ctx_namespace>.inserted.<key>  one level down
```

The default `ctx_namespace` is `key_value_map`. That asymmetry between fetched
and inserted is real, and it is why the registration route and the read route
reference their values differently.

## The two flows

```
REGISTER                                  READ
Operator ──▶ Gateway                      Partner ──▶ Gateway
               │                                        │
     key-value-map (3001, access)          key-value-map (3001, access)
       inserts:                              fetch:
         key:   tier:$request.headers          key:   tier:$request.headers
                     .x-partner-id                          .x-partner-id
         value: $request.headers.x-tier        alias: tier
         ttl:   86400                        ──▶ ctx.helix.key_value_map.tier
               │                                        │
       ctx.helix.key_value_map                 mocking (1999, access)
         .inserted.<key>                         reads $ctx.helix
               │                                   .key_value_map.tier
       mocking (1999, access)                    SHORT-CIRCUITS
         202 + the inserted table                     │
               │                                      ▼
               ▼                                 the partner
         the store                          (upstream never contacted)
```

## Execution order

Both plugins run in the **access** phase, and priority orders them within it:

| Plugin | Priority | Phase | Produces | Consumes |
|---|---|---|---|---|
| `key-value-map` | 3001 | access | `ctx.helix.key_value_map.*` | the request (header) |
| `mocking` | 1999 | access | the response | `ctx.helix.key_value_map.*` |

The store outranks the mock, which is the only reason this works. A plugin can
only read a `ctx.*` value produced by a higher-priority plugin on the same route,
and if that relationship were reversed every reference would resolve to an empty
string with no error anywhere.

`request-id` and `cors` sit at the document root and apply API-wide.

## The two substitution grammars

The platform has two, they look almost identical, and only one of them can see a
stored value.

| Form | Resolver | Reads |
|---|---|---|
| `${ctx.helix.<ns>.<field>}` | the general variable engine | a **flat** table, in which the entire dotted string is one variable *name*. Only `service-callout` writes to it. |
| `$ctx.<dotted.path>` | the ctx template engine | the **real request context**, walked segment by segment to any depth. |

`key-value-map` publishes into `ctx.helix.<ctx_namespace>` (default
`key_value_map`). Only the second form reaches it, and on this build **only
`mocking` resolves that form** — in both `response_example` and
`response_headers`.

Two consequences worth internalising:

- A `$ctx` path segment is `[A-Za-z0-9_]` only. A hyphen **ends the reference**,
  and the rest passes through as a literal. `key-value-map`'s own key grammar
  accepts hyphens, so the two are not interchangeable.
- A reference to a **table** expands to a JSON object, not a string. Inside a
  JSON body it must be embedded unquoted.

## Where values land, and why the two routes differ

```
fetched   ->  ctx.helix.key_value_map.<key>            flat
inserted  ->  ctx.helix.key_value_map.inserted.<key>   one level down
```

The registration route reads `.inserted`; the read route reads the flat
namespace. That asymmetry is a property of the plugin, not a choice this package
made.

## The key shape, and why it is not a dotted suffix

The key template is `tier:$request.headers.x-partner-id`.

The obvious shape — `$request.headers.x-partner-id.tier` — does not work.
Everything after `headers.` is taken as the header name, so that reference looks
up a header literally called `x-partner-id.tier` and resolves to nothing. A
reference cannot be suffixed with a dot.

So the discriminator goes in **front**, separated by a colon: a character outside
`[A-Za-z0-9_-]` terminates the reference, and the surrounding literal survives
because the key is a template over a string.

## Why `alias` is structural rather than cosmetic

The key is dynamic — it contains the caller's identity — so without an alias the
fetched value publishes under a field named `tier:acme-42`, which changes per
caller and which no static template can address.

`alias: tier` renames the published field to `tier`. One template then serves
every caller. This is the single line that separates a per-caller sandbox from a
static mock, and it was previously recorded in this library as *not* helping —
a claim withdrawn on evidence.

## Native vs custom

Nothing is built. Two configured plugins do the whole job.

The alternative — a small mock service with a datastore — buys schema validation,
an audit trail, and the ability to serve values to a real backend. It costs a
deployable, a pipeline, and an on-call rotation for a system whose only purpose
is to let other people test. For sandbox data, that trade is usually wrong. For
anything where the value must reach your own services, the trade flips, and this
pattern cannot do that job at all.

## Where the values live

In the gateway's key-value store, encrypted at rest and scoped per environment.
There is **no control-plane API for these entries** on this build, so the
plugin's own `inserts` is the only write path. That is why an administrative
route exists at all, and why protecting it is part of adopting this package.

## Prerequisites

- A gateway environment with the key-value store provisioned.
- An upstream bound to the revision. It is never contacted — `mocking`
  short-circuits every route here — but the binding is required to deploy.
- Nothing else. No backend, no crypto, no Enterprise plan.

## Failure behaviour

| Situation | What happens |
|---|---|
| Unregistered partner | 200 with empty values. A miss is not an error to the store. |
| Value past its TTL | Identical to unregistered. No signal. |
| Store unreachable | `fail_action: close` applies to store *errors*. Not simulated here — see `validation/gateway-validation.yaml` § `not_established_here`. |
| Wrong grammar in a template | 200, empty string, nothing logged. This is why the diagnostics route exists. |
| Registration route reachable by a partner | They can rewrite any partner's values, including their own. Protect it. |
