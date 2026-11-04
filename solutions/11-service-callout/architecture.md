# Architecture — one outbound call, then injection

> [Overview](README.md) · [Business need](business-need.md) · **Architecture** · [Guides](guides.md) · [Agent prompt](helix-agent-prompt.md) · [Tests](tests.md) · [API reference](api-reference.md)

---

## What the gateway does here

For every request on an enriched route, the gateway:

1. makes **one** outbound HTTP call to the customer-profile service, and waits for
   it,
2. copies chosen fields from that answer into the request's context, and
3. sets them as headers on the request it forwards to your backend.

The backend reads a header instead of making the lookup. It never needs to know
the profile service exists.

For the full list of fields on every plugin mentioned here, see
[docs.digitalapi.ai/api-gateway](https://docs.digitalapi.ai/api-gateway).

## How a request flows

```mermaid
sequenceDiagram
    autonumber
    participant C as Client
    participant GW as Gateway
    participant P as Customer profile service
    participant UP as Backend

    C->>GW: GET /storefront/orders

    Note over GW: rewrite phase, priority 2003<br/>service-callout runs FIRST
    GW->>P: GET /profile
    alt profile answers
        P-->>GW: 200 {company, email, ...}
        Note over GW: map_response_to_ctx<br/>body.company.name -> tenant_plan<br/>mirrored to ctx.helix.service_callout.tenant_plan
        Note over GW: rewrite phase, priority 1008<br/>proxy-rewrite injects the headers
        GW->>UP: GET /headers<br/>X-Tenant-Plan, X-Tenant-Contact, X-Profile-Status
        UP-->>GW: 200
        GW-->>C: 200
    else profile unreachable, policy fail-open
        GW->>UP: GET /headers — no enrichment headers at all
        UP-->>GW: 200
        GW-->>C: 200
    else profile unreachable, policy fail-close
        GW--xC: 503 "tenant profile unavailable" — the backend is never called
    end
```

## Execution order

| Order | Step | What it produces | What it needs |
|---|---|---|---|
| 1 | `service-callout` (**rewrite** phase, priority 2003) | the profile service's answer, mapped into `ctx.helix.service_callout.<field>` and mirrored into a gateway variable of that exact name | the callout `uri` to be reachable from the gateway |
| 2 | `proxy-rewrite` (**rewrite** phase, priority 1008) | the backend path, and the `X-Tenant-*` headers set from `${ctx.helix.service_callout.<field>}` | step 1's variables, already in place |
| — | backend | the request, carrying the answer | — |
| — | `request-id` (API-wide) | an `X-Request-Id` header for the backend (not sent to the profile service unless you add it with `custom_headers`) | — |

## The two settings that make this work

Get either one wrong and a configuration that looks right does nothing at all.

### 1. `phase: rewrite`, not `access`

A request passes through phases in a fixed order — rewrite, then access — and
priority only orders plugins *within* one phase. `proxy-rewrite` runs in the
**rewrite** phase. A callout set to the **access** phase therefore runs *after* it,
when there is still nothing to put in the headers.

An access-phase callout returns **HTTP 200 (OK)** with **no enrichment headers
at the backend**, and no error anywhere. The headers are left out altogether, and
a header of the same name that the client sent is stripped too. Within the rewrite
phase, `service-callout` (2003) runs before `proxy-rewrite` (1008), which is the
order this needs.

**Phase beats priority.** That one sentence explains most "the plugins are in the
wrong order" confusion on this platform.

### 2. The bridge is a variable named after the namespace

Every field in `map_response_to_ctx` is copied into a gateway variable whose name
is literally `ctx.helix.<ctx_namespace>.<field>` — dots included. It is one name,
not a path to look up. So:

```yaml
service-callout:
  ctx_namespace: service_callout          # the default
  map_response_to_ctx:
    tenant_plan: body.company.name

proxy-rewrite:
  headers:
    set:
      X-Tenant-Plan: "${ctx.helix.service_callout.tenant_plan}"
```

Change `ctx_namespace` and every reference changes with it. A mapped path that
matches nothing gives no value and **no error**, so a typo in `body.company.name`
is invisible until a backend notices the header is missing. The profile service
must answer with a single object: a path into a list, such as `body.0.email`,
doesn't resolve.

## `set`, never `add`

`headers.set` **replaces** a header the client sent. `headers.add` leaves the
client's value in place alongside the gateway's.

For an enrichment header this is a security property, not a style choice. A
client that sends `X-Tenant-Plan: Enterprise-Unlimited` has it overwritten with
the callout's real value. With `add`, any caller could assert its own plan and the
backend would believe it. [`example/verify.sh`](example/verify.sh) checks this for
exactly that reason.

## Failure policy is a decision, per route

This is the most important choice in the package. Before, each service decided
for itself, whoever wrote it: one retried, one carried on, one failed the
request. Here the policy is written on each route.

| Policy | Behaviour | Fits |
|---|---|---|
| `fail-open` | The request carries on; the enrichment headers are **absent**; the error is recorded in the request's context | A read path where a missing answer is survivable |
| `fail-close` | **HTTP 503 (service unavailable)** with the configured message; the backend is never called | A write path where acting without the answer is worse than failing |
| `log-only` | From the caller's side, the same as `fail-open`. The error is only logged, not recorded in the context | Diagnostics; rarely what you want in production |

`async: true` is a separate setting, not a policy: the request doesn't wait for
the lookup and the answer is never stored for it, so the headers are absent.

The example makes opposite choices on its two routes, on purpose:

| Route | Policy | Why |
|---|---|---|
| `GET /storefront/orders` | `fail-open` | A read without the tenant's plan is survivable. If the lookup fails: 200, and the mapped headers absent, except `X-Profile-Status`, which carries the 4xx/5xx status. |
| `POST /storefront/checkout` | `fail-close` | Taking money without knowing the account's status is worse than failing. If the lookup fails: 503 with the configured message, and the backend never called. |

**What counts as a failed lookup.** The profile service can't be reached (it is
down, or DNS or TLS fails), it doesn't answer within `timeout`, or it answers with
an error status, 4xx or 5xx, such as HTTP 404 (not found) or 500 (server error).
All of these trigger the policy. Any 2xx or 3xx answer counts as success, even
with an empty body. So a tenant with no profile record gets 503 on checkout only
if the profile service answers 4xx or 5xx for a missing tenant. If it answers
`200 {}`, checkout still reaches the backend, just with no `X-Tenant-Plan`.

**Under `fail-open` the headers are absent, not empty.** Every backend must decide
explicitly what a missing header means. One that assumes it is always there fails in a way that
is hard to trace back. Mapping the callout's own status
(`X-Profile-Status`) helps, with one gap: after a 4xx or 5xx answer it still
arrives, carrying that status, but when the service can't be reached at all
(down, DNS, TLS or a timeout) it is missing like the others.

## Why headers

The mapped values leave the gateway as request headers. That keeps them to plain
strings, and makes them visible to anything on the path to the backend.

| | Headers | A rewritten request body |
|---|---|---|
| Backend change needed | Read a header | Parse a changed body |
| Works for GET | Yes | No |
| Structured data | Must be flattened | Natural |
| Visible along the way | Yes | Yes, but less obviously |
| Interacts with body transforms | No | Yes, and the ordering is subtle |

Headers are the right default: they work on every method and cost the backend
almost nothing to adopt. Map what the backend needs, not the whole profile.

## Reading the result

| Symptom | Cause |
|---|---|
| 200, and no enrichment headers at all | `phase: access` instead of `rewrite` (a client's own header of the same name is stripped too); or the profile service couldn't be reached under `fail-open` |
| 200, and only `X-Profile-Status`, carrying a 4xx or 5xx | The profile service answered with an error under `fail-open`. The mapped headers are absent, except `X-Profile-Status` |
| One header missing, the others present | That mapped path didn't match anything (a path into a list never does). No value, no error |
| A header is missing, and a client's own header of that name is stripped too | The variable name doesn't match `ctx.helix.<ctx_namespace>.<field>` exactly — usually after `ctx_namespace` was changed — or names a field `map_response_to_ctx` doesn't define |
| A caller's own value reaches the backend | `headers.add` where `headers.set` belongs |
| No enrichment headers, and a caller's own `X-Tenant-Plan` reaches the backend | Nothing sets the headers: the callout stored its answer and no `proxy-rewrite` reads it |
| 503 with the callout's message | `fail-close` doing its job; the profile service can't be reached from the gateway |
| The route got slower by exactly the timeout | The callout is timing out on every request, and the request waits for it |
| A new route isn't enriched | `service-callout` is set per route |

## No custom code needed

Native. Three plugins were considered:

- **`service-callout`** — this solution. Fetches, maps, and leaves the result for
  another plugin to use. The right shape when the answer is *data the backend
  needs*.
- **`forward-auth`** — calls an external service and acts on its verdict, allowing
  or rejecting the request. The right shape when the answer decides whether the
  request goes ahead.
- **`opa`** — policy evaluation against a decision service, for the same kind of
  problem as `forward-auth`, with a richer policy language.

All three make an HTTP call. The difference is what happens to the answer:
`service-callout` stores it; the other two act on it.

## When to use this

Use it when:

- several services make the same lookup before doing their own work,
- the answer depends on the caller or the request, so it can't be fixed
  configuration,
- you want one timeout and one failure policy instead of many, or
- you're adding services that would otherwise build the lookup first.

Do not use it when:

- **the answer decides whether the request is allowed.** Use `forward-auth` or
  `opa`, which are built to return a verdict.
- **the data is static enough to be configuration.** A call per request to fetch
  something that changes monthly is cost with no benefit.
- **the profile service can't take one call per request.** This consolidates the
  calls; it doesn't remove them.
- **the backend needs the whole profile document.** Headers are the wrong shape;
  let the backend make its own call.
- **latency is already at budget.** The callout adds a network round trip to every
  request on the route.

## What it does not do

- **Decide access.** The answer is stored, never acted on.
- **Remove the dependency.** There is still one call in the request path, and its
  `timeout` is now part of your worst-case latency. The request waits for it
  (`async: true` exists, but then the answer is never stored for the request and
  the headers are absent, which defeats the purpose here).
- **Cache by itself.** The plugin has no response cache; every request makes the
  call. `proxy-cache` is a separate consideration.
- **Cover new routes automatically.** It is configured per route.
- **Carry structured data.** Mapped values become string headers.
- **Hide what it injects.** Injected headers are visible downstream; don't map
  anything the backend shouldn't hold.
- **Spare the backends all work.** Under `fail-open` the headers can be absent,
  and each backend has to decide what that means: one documented behaviour
  instead of many undocumented ones.

## Prerequisites

- An org whose build includes `service-callout` and `proxy-rewrite`. Confirm with
  your org's plugin list before you design around them.
- A profile service the **gateway** can reach, answering with a single object
  rather than a list (the example uses a public sample service).
- A backend willing to read the headers and to handle them being absent under
  `fail-open`.
