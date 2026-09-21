# Agent-mode prompt — mask sensitive values in the response and in the logs

Paste these into **Helix Agent Mode**. They work from a **fresh, empty org**: the
agent *creates* the API on a public upstream whose records carry email, phone and
coordinates, then builds the configuration in four bounded steps.

Replace the `<<...>>` values. Everything else is deliberate — the table below
says why each block earns its place. Read [AGENT-GUIDE.md](../../AGENT-GUIDE.md)
first if you haven't.

---

## The prompt

Full prompt with all the constraints: [`helix-agent-prompt.md`](helix-agent-prompt.md).

> **This one needs four small steps, not one big prompt — and the reason is
> measured, not stylistic.** `update_route_spec` is a *full replace*, so every
> incremental change resends the whole route spec. Past roughly a kilobyte the
> agent starts emitting malformed tool arguments (a stray bracket appended to the
> JSON), which surfaces as `stream closed with reason: error`. Four attempts at
> the one-prompt version failed the same way; the four-step version below is the
> shape that completed. The last step is the one that still tips it over, so it
> ships with a fallback.

**Step 1 — the API and the collection route**

```text
Create a new REST API called "Support Console API" with ONE route for now.

Upstream: https://jsonplaceholder.typicode.com (reuse it if it already exists in this
org as an upstream rather than creating another). Deploy to the "test" environment.

Route: GET /support/customers -> proxy-rewrite uri /users

Put request-id in the SERVICE spec so it applies API-wide.

We are editing a LIVE route object, not authoring an OpenAPI document — so do not
follow the spec-generator examples for plugin placement. Each route object in
routeSpec takes "plugins" as a TOP-LEVEL key, and inside it each plugin is
keyed by its own NAME:
  { "name": ..., "uri": ..., "methods": [...], "service_id": ...,
    "plugins": { "<plugin-name>": { <that plugin's own fields> } } }
Do not promote a plugin's fields into the plugins map: "plugins":
{"response_status": 202, "content_type": ...} is four broken plugins, not one
working one — the plugin name level is mandatory.
There must be no "x-helix-gateway" key anywhere in a route object: a live route
silently discards that wrapper, the write still reports success, and the route
deploys with no plugins at all. Set only the fields you need.

Skip validate_route — use dry_run_deploy. Bind the upstream, run dry_run_deploy, then
call get_revision and show me the stored routeSpec so I can see the plugins landed.
Wait before deploying.
```

**Step 2 — the single-record route**

```text
Now add a second route to the same revision, keeping the first exactly as it is:

  GET /support/customers/{customerId}

It needs proxy-rewrite with regex_uri, not uri, so the id reaches the backend:
regex_uri: ["^/support/customers/(.*)$", "/users/$1"]

Send the routeSpec as a JSON array of both route objects — update_route_spec replaces
the whole list. Then call get_revision and show me the stored routeSpec.
```

**Step 3 — the masking the caller sees**

```text
Give BOTH routes this response-rewrite block, verbatim — these are the exact patterns,
do not rewrite them:

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

Every filter keeps scope: global — the default is "once" and masks only the first match,
which on a list leaves every record but the first in the clear.

Send the routeSpec as a JSON array of both routes, then call get_revision and show me the
stored routeSpec.
```

**Step 4 — the masking the logs keep**

```text
Add log-data-mask to both routes, keeping everything else exactly as it is:
  response:
    - { type: body, name: email, action: replace, value: "[redacted]", body_format: json }
    - { type: body, name: phone, action: replace, value: "[redacted]", body_format: json }
  request:
    - { type: header, name: authorization, action: remove }
    - { type: header, name: x-api-key, action: remove }

Then call get_revision, show me the stored routeSpec, and tell me in one sentence what
log-data-mask does NOT do.
```

> **If step 4 ends in `stream closed with reason: error`, that is the defect above
> and not your prompt.** The route spec is now large enough to trigger it
> reliably. Import [`gateway/api-spec.yaml`](gateway/api-spec.yaml) instead — it
> is the same configuration, complete, and the agent has already done the parts
> that teach you anything.


---

## Why the prompt is shaped this way

| Block | Why it's there |
|---|---|
| **Four steps rather than one** | Measured, not stylistic. `update_route_spec` is a full replace, so each step resends the whole route spec; past roughly a kilobyte the agent emits malformed tool arguments and the run dies. The one-prompt version failed four times out of four. |
| **"This is a fresh org — create one"** | On a new free-trial org there is no API to "find". The agent must create it, or it stalls looking for something that isn't there. |
| **"reuse it if it already exists"** | The org's upstream limit is low, and an agent that cannot create one stops rather than looking for the one already there. |
| **"regex_uri, not uri, so the id reaches the backend"** | A fixed `uri` sends every request to the same record. An agent that has just written one fixed rewrite writes a second one. |
| **"Do NOT nest them under x-helix-gateway"** | Verified, and the worst failure in this package: nested plugins on a live route are **silently discarded**. `update_route_spec` reports success, the dry-run passes, and the routes deploy with no masking. |
| **"call get_revision and show me the stored routeSpec"** | The only check that catches the silent drop. A prompt that does not ask for the read-back cannot tell a working deploy from an empty one. |
| **"verbatim — these are the exact patterns"** | Asked to invent them, the agent produced a replacement containing a literal `[^"]*`, which would have written that text into every response. Given the patterns, it reproduced them exactly. |
| **"Every filter keeps scope: global"** | The most dangerous default here. `once` masks the first match and leaves the rest of a list — and the first record is the one in every screenshot. |
| **"tell me in one sentence what log-data-mask does NOT do"** | Forces the distinction into the agent's own words. It is the thing readers get wrong, and it is cheaper to catch in an explanation than in production. |
| **"Skip validate_route — use dry_run_deploy"** | Verified: `validate_route` fails on this build whatever you put in it — the tool posts `{"route": …}` and the control plane requires `{"routeSpec": [ … ]}`. |
| **"Set only the fields you need"** | Verified on another package: an agent volunteering `regex_uri: [null, null]` and `headers: {}` had two dry-runs rejected before removing them. |

## Tweak knobs

**Also mask the logs for real**
```text
Add http-logger to both routes pointing at <<https://my-log-sink.example/ingest>>,
with include_resp_body true and batch_max_size 1 so it flushes immediately. Then
tell me how to compare the logged entry with and without log-data-mask, because
that comparison is the only way to know the log mask is working.
```

**My payload names the fields differently**
```text
My records use contactEmail, mobileNumber and homeLat/homeLng. Rewrite every
filter and every log-data-mask entry for those names, and remind me what happens
to a copy of the same value stored under another key.
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

## Known failure modes when running this prompt

- **`stream closed with reason: error` after `update_route_spec`.** The agent
  appended a stray bracket to its tool arguments — a serialisation defect that
  becomes reliable once the route spec passes about a kilobyte. Nothing was
  written. Retry once; if it repeats, import
  [`gateway/api-spec.yaml`](gateway/api-spec.yaml) for the remaining step.
- **The write succeeds and the routes have no plugins.** The agent nested them
  under `x-helix-gateway`. Reply: `put the plugins in a flat plugins map on each
  route object, then read the revision back and show me.`
- **Only the first record is masked.** A filter is missing `scope: global`.
- **Nothing is masked.** The pattern does not match the serialised body — check key
  spelling and whitespace, and whether something on the route converts the format
  first.
- **A field nobody asked about is mangled.** An over-broad pattern; anchor it to
  its key.
- **The agent claims the logs are masked after adding only `log-data-mask`.**
  Reply: `there is no logger on this route, so that plugin has no effect — and it
  never changes the response.`
- **The single-record route 404s.** `regex_uri` is wrong or missing. Routing, not
  masking.
- **`validate_route` errors and the agent stalls.** Not your config — the tool is
  broken against this control plane. Reply: `skip validate_route, run
  dry_run_deploy instead.`
- **Deploy fails with `Only INACTIVE revisions can be updated`.** Clone the
  revision or undeploy, then apply.

## Related

- **[Solution 08 — API keys](../08-api-key/helix-agent-prompt.md)** — masking is
  not access control; this package ships open on purpose.
- **[Solution 09 — XML to JSON](../09-xml-to-json/helix-agent-prompt.md)** — if you
  convert on the same route, the converter runs first.
- **[Solution 04 — Analytics](../04-analytics/)** — unaffected by `log-data-mask`,
  which is worth knowing before you assume it is covered.
