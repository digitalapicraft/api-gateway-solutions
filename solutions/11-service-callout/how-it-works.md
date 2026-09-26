# How it works — Solution 11 — the lookup every service re-implements, done once at the edge

[Overview](readme.md) · [Business need](business-need.md) · **How it works** · [Install](install.md) · [Configuration](configuration.md) · [Test & verify](testing.md) · [Changelog](changelog.md)

---

## The two things that make this work

Both were established against a running gateway, and both are the reason a
configuration that looks right can do nothing at all.

### 1. `phase: rewrite`, not `access`

`proxy-rewrite` runs in the **rewrite** phase. A callout configured for the
**access** phase runs *after* it — so the values exist, and the injection has
already happened without them.

Reproduced deliberately: an access-phase callout returned **200 with no enrichment
headers at the backend**. Nothing errored. Within the rewrite phase,
`service-callout` (priority 2003) runs before `proxy-rewrite` (1008), which is the
order this needs.

**Phase beats priority; priority only orders within a phase.** That sentence
explains most "the plugins are in the wrong order" confusion on this platform.

### 2. The bridge is a variable named after the namespace

Every field in `map_response_to_ctx` is mirrored into a gateway variable whose
name is literally `ctx.helix.<ctx_namespace>.<field>` — dots included. So:

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

Change `ctx_namespace` and every reference changes with it. A path that resolves
to nothing yields no value and **no error** — so a typo in `body.company.name` is
invisible until a backend notices the header is missing.

## Request path

```
Client ──▶ Gateway ──────────────▶ Backend
              │
              │ rewrite phase
              ├── service-callout  (priority 2003)  ──▶ Customer profile service
              │     map_response_to_ctx
              │     -> ctx.helix.<ns>.<field>
              │     -> mirrored as the variable "ctx.helix.<ns>.<field>"
              └── proxy-rewrite    (priority 1008)
                    headers.set: X-Tenant-*: ${ctx.helix.<ns>.<field>}
```

1. **rewrite phase, priority 2003** — `service-callout` makes one outbound HTTP
   request, synchronously. The response is mapped into `ctx.helix.<namespace>`
   using dotted paths (`body.company.name`, `status`, `headers.<name>`), and each
   mapped field is also mirrored into a gateway variable of the same name.
2. **rewrite phase, priority 1008** — `proxy-rewrite` resolves
   `${ctx.helix.<namespace>.<field>}` against those variables and sets the headers
   on the upstream request.
3. **upstream** — the backend receives the answer it would otherwise have fetched.

**Phase beats priority.** Both plugins run in the rewrite phase and priority orders
them within it. Moving the callout to the access phase moves it *after*
`proxy-rewrite` entirely — the injection happens first, with nothing to inject.
Verified: 200, and no headers at the backend.

## Native vs custom

Native. Three alternatives were considered:

- **`service-callout`** — this solution. Fetches, maps, and leaves the result for
  another plugin to use. The right shape when the answer is *data the backend
  needs*.
- **`forward-auth`** — calls an external service and acts on its verdict, allowing
  or rejecting the request. The right shape when the answer decides whether the
  request proceeds. If you find yourself wanting to reject based on what the
  callout returned, you want this instead.
- **`opa`** — policy evaluation against a decision service, for the same class of
  problem as `forward-auth` with a richer policy language.

The distinction is not the HTTP call — all three make one. It is what happens to
the response: `service-callout` stores it, the other two act on it.

No custom code is required, and none is included.

## Why headers

The mapped values leave the gateway as request headers, which constrains them to
strings and makes them visible to anything on the path to the backend.

| | Headers | A rewritten request body |
|---|---|---|
| Backend change needed | Read a header | Parse a changed body |
| Works for GET | Yes | No |
| Structured data | Must be flattened | Natural |
| Visible to intermediaries | Yes | Yes, but less obviously |
| Interacts with body transforms | No | Yes, and the ordering is subtle |

Headers are the right default because they work on every method and cost the
backend almost nothing to adopt. Map what the backend needs rather than the whole
profile — anything injected is visible downstream.

## `set` versus `add`

`headers.set` replaces a header the client supplied. `headers.add` appends,
leaving the client's value in place.

For an enrichment header this is a security property, not a style choice: with
`add`, any caller can send `X-Tenant-Plan: Enterprise-Unlimited` and have the
backend see it. Verified in both directions — with `set`, a spoofed header is
overwritten with the callout's value.

## Failure policy

| Policy | Behaviour | Fits |
|---|---|---|
| `fail-open` | The request proceeds; the enrichment headers are **absent**; the error is recorded in the context | A read path where a missing answer is survivable |
| `fail-close` | 503 with the configured message; the backend is never called | A write path where acting without the answer is worse than failing |
| `log-only` | Log and continue, without recording the error in the context | Diagnostics, and rarely what you want in production |

Both of the first two were reproduced against an unreachable callout. The detail
that reaches your backend teams: under `fail-open` the headers are **absent**, not
empty, so every consumer needs an explicit decision about what a missing header
means.

## When not to use this shape

- **The answer decides whether the request is allowed** — `forward-auth` or `opa`.
- **The value is static configuration** — a per-request call to fetch something
  that changes monthly is a cost with no benefit.
- **The backend needs the whole document** — headers are the wrong shape.
- **The profile service cannot take one call per request** — this consolidates, it
  does not eliminate.
- **Latency is already at budget** — a synchronous callout adds a round trip.

## Failure modes and what they look like

| Symptom | Cause |
|---|---|
| 200, and no enrichment headers at all | `phase: access` instead of `rewrite`; or the callout failed under `fail-open` |
| One header missing, the others present | That mapped path did not resolve. A path matching nothing yields no value and no error |
| The header is there but wrong | The variable name does not match `ctx.helix.<ctx_namespace>.<field>` — usually after `ctx_namespace` was changed |
| A caller's own value reaches the backend | `headers.add` where `headers.set` belongs |
| 503 with the callout's message | `fail-close` doing its job; the profile service is unreachable from the gateway |
| The route got slower by exactly the timeout | The callout is timing out on every request; the request path waits for it |
| A new route is not enriched | `service-callout` is configured per route |
