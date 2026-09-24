# Agent-mode prompt — mask sensitive values in the response and in the logs

Four small steps, from a **fresh, empty org** to two routes whose responses are
masked for the caller and whose log entries are masked for the aggregator.

**The four steps are measured, not stylistic.** `update_route_spec` is a *full
replace*, so every increment resends the whole route spec; past roughly a kilobyte
the agent emits malformed tool arguments and the run dies with `stream closed with
reason: error`. The one-prompt version failed four times out of four. Step 4 is
the one that still tips it over, so it ships with a fallback.

[AGENT-GUIDE.md](../../AGENT-GUIDE.md) carries the standing rules these prompts
assume.

---

## Step 1 — the API and the collection route

```text
Create a REST API "Support Console API" with ONE route for now. Upstream
https://jsonplaceholder.typicode.com — reuse it if it already exists as an upstream
in this org rather than creating another; the org's upstream limit is low.
Environment test.

Route: GET /support/customers -> proxy-rewrite uri /users
Put request-id in the SERVICE spec so it applies API-wide. Set only the fields you
need — an empty headers {} or a regex_uri of nulls is rejected at dry-run.

Plugins go in a top-level "plugins" map on the route object, each under its own
plugin name. No "x-helix-gateway" wrapper — a live route discards it silently and
still reports success.

Bind the upstream, run dry_run_deploy, then read the revision back so I can see
which plugins actually landed. Wait before deploying.
```

## Step 2 — the single-record route

```text
Add a second route to the same revision, keeping the first exactly as it is:

  GET /support/customers/{customerId}

It needs proxy-rewrite with regex_uri, not uri, so the id reaches the backend:
regex_uri: ["^/support/customers/(.*)$", "/users/$1"]

Send routeSpec as a JSON array of both route objects — update_route_spec replaces
the whole list. Then read the revision back.
```

## Step 3 — the masking the caller sees

```text
Give BOTH routes this response-rewrite block, verbatim — these are the exact
patterns, do not rewrite them:

filters:
  - regex: ("email"\s*:\s*")[^"@]+@
    replace: $1***@
    scope: global
  - regex: ("phone"\s*:\s*")[^"]*"
    replace: $1[redacted]"
    scope: global
  - regex: ("lat"\s*:\s*")[^"]*"
    replace: $1[redacted]"
    scope: global
  - regex: ("lng"\s*:\s*")[^"]*"
    replace: $1[redacted]"
    scope: global

Every filter keeps scope: global. The default is "once" — one match, then stop —
which on a list masks the first record and leaves the rest in the clear.

Send routeSpec as a JSON array of both routes, then read the revision back.
```

## Step 4 — the masking the logs keep

```text
Add log-data-mask to both routes, keeping everything else exactly as it is:
  response:
    - { type: body, name: email, action: replace, value: "[redacted]", body_format: json }
    - { type: body, name: phone, action: replace, value: "[redacted]", body_format: json }
  request:
    - { type: header, name: authorization, action: remove }
    - { type: header, name: x-api-key, action: remove }

Then read the revision back, and tell me in one sentence what log-data-mask does
NOT do.
```

> **If step 4 ends in `stream closed with reason: error`, that's the defect above,
> not your prompt.** The route spec is now large enough to trigger it reliably.
> Import [`gateway/api-spec.yaml`](gateway/api-spec.yaml) instead — same
> configuration, complete, and the agent has already done the parts that teach you
> anything.

---

## Why it's shaped this way

- **`scope: global` on every filter.** The most dangerous default here. `once`
  masks the first match and leaves the rest of the list — and the first record is
  the one in every screenshot.
- **The patterns verbatim.** Asked to invent them, the agent produced a replacement
  containing a literal `[^"]*`, which would have written that text into every
  response. Given them, it reproduced them exactly.
- **`regex_uri`, not `uri`, on the single-record route.** A fixed `uri` sends every
  request to the same record, and an agent that has just written one fixed rewrite
  writes a second one.
- **"What does `log-data-mask` NOT do."** Forces the distinction into the agent's
  own words. It changes only what a *logger* writes, does nothing without a logger
  on the route, and never changes the response — and that is the thing readers get
  wrong.
- **Read the revision back, every step.** Nested plugins on a live route are
  silently discarded: the write reports success, the dry-run passes, and the routes
  deploy with no masking. The read-back is the only thing that catches it.

## Tweak knobs

**Also mask the logs for real**
```text
Add http-logger to both routes pointing at <<https://my-log-sink.example/ingest>>,
include_resp_body true, batch_max_size 1 so it flushes immediately. Then tell me
how to compare the logged entry with and without log-data-mask — that comparison is
the only way to know the log mask works.
```

**My payload names the fields differently**
```text
My records use contactEmail, mobileNumber and homeLat/homeLng. Rewrite every filter
and every log-data-mask entry for those names, and remind me what happens to a copy
of the same value stored under another key.
```

**Mask by role rather than for everyone**
```text
Only agents in the "support" tier should get the masked view; the fraud team needs
the full record. Tell me honestly whether response-rewrite can do that on one
route, and if not, what the two-route shape looks like and how the caller is
identified.
```

**Put identity in front of it**
```text
Add API-key authentication to both routes with helix-auth validate,
validate_auth_type key-auth, reading the key from X-Api-Key. Keep the masking
exactly as it is — masking is not access control.
```
(That's [solution 08](../08-api-key/).)

## When it goes wrong

| Symptom | Cause |
|---|---|
| `stream closed with reason: error` after `update_route_spec` | The serialisation defect above. Nothing was written. Retry once; if it repeats, import [`gateway/api-spec.yaml`](gateway/api-spec.yaml) for the rest. |
| The write succeeds and the routes have no plugins | They were nested under `x-helix-gateway`. Ask for a flat `plugins` map and read the revision back. |
| Only the first record is masked | A filter is missing `scope: global`. |
| Nothing is masked | The pattern doesn't match the serialised body — check key spelling and whitespace, and whether something on the route converts the format first. |
| A field nobody asked about is mangled | An over-broad pattern. Anchor it to its key. |
| The agent says the logs are masked after adding only `log-data-mask` | There's no logger on the route, so it has no effect — and it never changes the response. |
| The single-record route 404s | `regex_uri` is wrong or missing. Routing, not masking. |
| Deploy fails: `Only INACTIVE revisions can be updated` | Clone the revision or undeploy, then apply. |

## Related

- **[Solution 08 — API keys](../08-api-key/helix-agent-prompt.md)** — masking is
  not access control; this package ships open on purpose.
- **[Solution 09 — XML to JSON](../09-xml-to-json/helix-agent-prompt.md)** — if you
  convert on the same route, the converter runs first.
- **[Solution 04 — Analytics](../04-analytics/)** — unaffected by `log-data-mask`,
  which is worth knowing before you assume it is covered.
