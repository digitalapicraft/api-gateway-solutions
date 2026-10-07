# Guides — two masks, two audiences

> [Overview](README.md) · [Business need](business-need.md) · [Architecture](architecture.md) · **Guides** · [Agent prompt](helix-agent-prompt.md) · [Tests](tests.md) · [API reference](api-reference.md)

---

Three ways to build the same thing, then how to see it work. Whichever way you
pick, the result is one API with two routes — `GET /support/customers` and
`GET /support/customers/{customerId}` — whose responses are masked for the caller
and whose log entries are masked for any logger on the route.

## Pick your path

| | Choose this if you… | Go to |
|---|---|---|
| **1. Helix Agent** | want the quickest result and are happy to paste a prompt | [Build it with the Helix Agent](#build-it-with-the-helix-agent) |
| **2. Helix control plane** | prefer clicking through screens | [Build it in the UI](#build-it-in-the-ui) |
| **3. API script** | are scripting this, or wiring it into a pipeline | [Install it directly](#install-it-directly) |

Then, for everyone: [See it work](#see-it-work) · [Variations](#variations) ·
[Configuration reference](#configuration-reference) · [Troubleshooting](#troubleshooting)

## Build it with the Helix Agent

Works on a **fresh, empty org**. [`helix-agent-prompt.md`](helix-agent-prompt.md)
has four small steps: the API and list route, the single-record route, the mask
the caller sees, then the mask the logs keep. Paste them one at a time and let the
agent read the revision back after each.

**The four steps are needed, not a matter of style.** `update_route_spec` replaces
the whole route list each time, so every step resends the complete route spec. As
that spec grows, the agent's tool call comes out malformed and the run ends with
`stream closed with reason: error`. The one-prompt version failed four times out
of four. Step 4 is the one that can still tip it over: **if step 4 ends in that
error, import [`example/api-spec.yaml`](example/api-spec.yaml) instead** — same
configuration, complete, and the agent has already done the steps that teach you
anything.

**Why the prompt is shaped the way it is:**

- **`scope: global` on every filter.** The most dangerous default here. `once`
  masks the first match and leaves the rest of the list — and the first record is
  the one in every screenshot.
- **The patterns given word for word.** Asked to invent them, the agent produced a
  replacement containing a literal `[^"]*`, which would have written that text into
  every response. Given them, it reproduced them exactly.
- **`regex_uri`, not `uri`, on the single-record route.** A fixed `uri` sends every
  request to the same record, and an agent that has just written one fixed rewrite
  tends to write a second.
- **"What does `log-data-mask` NOT do."** Makes the agent put the distinction into
  its own words. It changes only what a *logger* writes, does nothing without a
  logger on the route, and never changes the response — the thing readers get
  wrong.
- **Read the revision back, every step.** Plugins nested under `x-helix-gateway`
  on a live route are silently discarded: the write reports success, the dry-run
  passes, and the routes deploy with no masking. The read-back is the only thing
  that catches it.

**If the agent run goes wrong:**

| Symptom | Cause |
|---|---|
| `stream closed with reason: error` after `update_route_spec` | The malformed tool-call defect above. Nothing was written. Try once more; if it repeats, import [`example/api-spec.yaml`](example/api-spec.yaml) for the rest. |
| The write succeeds and the routes have no plugins | They were nested under `x-helix-gateway`. Ask for a flat `plugins` map and read the revision back. |
| Only the first record is masked | A filter is missing `scope: global`. |
| Nothing is masked | The pattern doesn't match the body as sent — check key spelling and whitespace, and whether something on the route converts the format first. |
| A field nobody asked about is damaged | An over-broad pattern. Tie it to its key. |
| The agent says the logs are masked after adding only `log-data-mask` | There's no logger on the route, so it has no effect — and it never changes the response. |
| The single-record route returns 404 | `regex_uri` is wrong or missing. Routing, not masking. |
| Deploy fails: `Only INACTIVE revisions can be updated` | Clone the revision or undeploy, then apply. |

See [AGENT-GUIDE.md](../../AGENT-GUIDE.md) for the ground rules these prompts
assume.

## Build it in the UI

Screen and button names below are the real ones. The API lives under
**API Gateway** in the left sidebar.

**Before you start:**

- **You have an account.** If you don't, register for a free trial at
  [trial.digitalapi.ai](https://trial.digitalapi.ai/). A new trial org comes with
  a `test` environment, which is all this walkthrough needs.
- **You can create APIs.** If you don't see an **Add API** button, ask your org
  admin.

**1. Import the API**
1. Go to **API Gateway → APIs**, click **Add API** (or **Create your first API**).
2. Set **Method** to **Import an OpenAPI spec**.
3. Drag in [`example/api-spec.yaml`](example/api-spec.yaml), or paste its
   contents, then click **Import**. Nothing in it needs filling in.

This creates the API and its first revision. The imported spec already carries
`response-rewrite` (the four filters, each with `scope: global`), `log-data-mask`,
`proxy-rewrite` on both routes, and `request-id` API-wide, with the settings in
the [Configuration reference](#configuration-reference). There is no separate
screen to set them up in this walkthrough.

**2. Give it an upstream, then deploy it**
1. Go to **API Gateway → Upstreams → Add Upstream**. Name it, pick environment
   `test`, point it at `jsonplaceholder.typicode.com` (or your own backend), then
   **Create Upstream**.
2. Back on the API's page, click **Deploy** on the revision. The dialog asks you
   to map an upstream for `test`. Pick the one you just created, then **Deploy**.

No products, developers or apps are needed: the package ships unauthenticated.

**Two things this walkthrough doesn't cover:**

- **Your own field names.** Change the field names in *both* plugin blocks, and
  the `proxy-rewrite` paths, in the spec before you import it.
- **A logger.** The spec carries the log mask, not a logger, and `log-data-mask`
  does nothing without one. Add a logger plugin block to the routes in the spec
  before importing, or use the "also mask the logs for real" prompt under
  [Variations](#variations).

## Install it directly

If you'd rather script it against the control plane:

```bash
export ORG=<ORG_ID>
export TOKEN=<control-plane bearer token>      # short-lived
export BASE=https://<YOUR_GATEWAY_HOST>/api
H=(-H "authorization: Bearer $TOKEN" -H 'content-type: application/json')

# 1. Import the spec. Nothing in it needs filling in. Keep both ids it returns.
#    For your own data, first adjust the field names in BOTH plugin blocks, and
#    the proxy-rewrite paths to your backend.
curl -s -H "authorization: Bearer $TOKEN" \
  -F "file=@example/api-spec.yaml" "$BASE/orgs/$ORG/apis/from-spec"
# → {"api":{"id":"<API_ID>", ...}, "revision":{"id":"<REVISION_ID>", ...}}

# 2. Import does NOT make the routes live. Create an upstream, bind it
#    to the revision, then deploy the revision.
curl -s "${H[@]}" -X POST "$BASE/orgs/$ORG/envs/<TEST_ENV_ID>/upstreams" \
  -d '{"name":"customers-upstream","specification":{"scheme":"https","nodes":[{"host":"jsonplaceholder.typicode.com","port":443,"weight":1}]}}'
# → {"id":"<UPSTREAM_ID>", ...}

curl -s "${H[@]}" -X PATCH "$BASE/orgs/$ORG/apis/<API_ID>/revisions/<REVISION_ID>/upstream-bindings/add" \
  -d '{"environmentUpstreams":[{"environmentId":"<TEST_ENV_ID>","upstreamId":"<UPSTREAM_ID>"}]}'
curl -s "${H[@]}" -X POST "$BASE/orgs/$ORG/apis/<API_ID>/revisions/<REVISION_ID>/deploy" \
  -d '{"environmentId":"<TEST_ENV_ID>","force":false}'
```

> Revisions must be **INACTIVE** to accept a spec change. If it's live, undeploy
> first, or clone the revision so you keep a rollback target.

The same calls without narration: [API reference](api-reference.md).

## See it work

```bash
curl -s "https://<YOUR_GATEWAY_HOST>/support/customers" | head -c 600
# every record, not just the first: email "***@<domain>", phone "[redacted]",
# lat and lng "[redacted]"

curl -s "https://<YOUR_GATEWAY_HOST>/support/customers/3"
# the single-record route, masked the same way
```

To run all six response-side checks as a script:

```bash
GATEWAY=https://<YOUR_GATEWAY_HOST> ./example/verify.sh
```

`LIST_PATH`, `ONE_PATH` and `MASK` override the defaults if your routes or
replacement text differ. Exit code 0 means every record is masked, the email
domain survives, and fields outside the filters are untouched.

**`verify.sh` can't check the log side** — no client-side check can see what a
logger wrote. To check it: add a logger (for example `http-logger`, pointing at a
destination whose received body you can read, with `include_resp_body: true` and
`batch_max_size: 1` so it sends immediately), call the route with an
`Authorization` header, and read what arrived. Then remove `log-data-mask` and
compare the two entries. Full procedure and the other manual tests:
[Tests](tests.md).

## Variations

Each of these is a follow-up you can paste to the agent after step 4.

**Also mask the logs for real**
```text
Add http-logger to both routes pointing at {{log_sink_url}},
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

**Put identity in front of it** — that's [solution 08](../08-api-key/).
```text
Add API-key authentication to both routes with helix-auth validate,
validate_auth_type key-auth, reading the key from X-Api-Key. Keep the masking
exactly as it is — masking is not access control.
```

## Configuration reference

Source of truth: [`example/api-spec.yaml`](example/api-spec.yaml). Both routes
carry the same two masking blocks.

What the caller sees:

```yaml
response-rewrite:
  filters:
    - regex: '("email"\s*:\s*")[^"@]+@'
      replace: '$1***@'
      scope: global
    - regex: '("phone"\s*:\s*")[^"]*"'
      replace: '$1[redacted]"'
      scope: global
    - regex: '("lat"\s*:\s*")[^"]*"'
      replace: '$1[redacted]"'
      scope: global
    - regex: '("lng"\s*:\s*")[^"]*"'
      replace: '$1[redacted]"'
      scope: global
```

What a logger writes:

```yaml
log-data-mask:
  response:
    - { type: body, name: email, action: replace, value: "[redacted]", body_format: json }
    - { type: body, name: phone, action: replace, value: "[redacted]", body_format: json }
  request:
    - { type: header, name: authorization, action: remove }
    - { type: header, name: x-api-key, action: remove }
```

| Plugin | Field | Value here | What it means |
|---|---|---|---|
| `response-rewrite` | `filters[].regex` | anchored on `"email"`, `"phone"`, `"lat"`, `"lng"` | Each pattern is tied to its own field name so it can't match text elsewhere. |
| `response-rewrite` | `filters[].replace` | `$1***@` for email, `$1[redacted]"` for the others | The email keeps its domain; phone and coordinates are replaced whole. There's no partial phone number that is both useful and safe. |
| `response-rewrite` | `filters[].scope` | `global` | **Defaults to `once`**, which masks only the first match in the body. |
| `log-data-mask` | `response[]` | `email`, `phone` → `[redacted]`, `body_format: json` | Named body fields masked in what a logger writes. |
| `log-data-mask` | `request[]` | remove `authorization`, `x-api-key` | The credential must never reach a log line. |
| `proxy-rewrite` | `uri` (list route) | `/users` | A fixed path. |
| `proxy-rewrite` | `regex_uri` (single-record route) | `["^/support/customers/(.*)$", "/users/$1"]` | Carries the customer id through. A fixed `uri` would send every request to the same record. |
| `request-id` | `algorithm` / `header_name` | `uuid` / `X-Request-Id` | API-wide. What a support agent quotes instead of the masked value. |

Placeholders in this package: `<ORG_ID>`, `<API_ID>`, `<REVISION_ID>`,
`<UPSTREAM_ID>`, `<TEST_ENV_ID>`, `<YOUR_GATEWAY_HOST>`. Replace all of them
before you deploy.

Every field of every plugin, and the wider product docs:
[docs.digitalapi.ai/api-gateway](https://docs.digitalapi.ai/api-gateway).

## Troubleshooting

- **`scope` defaults to `once`.** One record masked, the rest in the clear, and the
  masked one is the one you look at. Always set `scope: global`.
- **`log-data-mask` does nothing without a logger on the route.** It is read by the
  shared log helper the logger plugins use. It is not a response filter.
- **`log-data-mask` doesn't change the response.** A route with only that plugin
  sends the caller everything.
- **It doesn't affect analytics either.** Analytics doesn't go through the log
  helper.
- **Masking is not access control.** A caller who shouldn't see the record at all
  must be stopped by identity — [solution 08](../08-api-key/) or
  [solution 02](../02-oauth-jwt/). This package ships unauthenticated so masking is
  the only thing being shown; don't deploy it that way.
- **The regex sees text, not meaning.** Renamed keys, encoded strings and
  free-text copies aren't masked. Error messages and audit-trail fields are where
  copies usually hide.
- **A broad pattern damages data.** Tie every filter to its own field name.
- **If you also convert formats on this route** ([solution 09](../09-xml-to-json/)),
  the converter runs first — write the patterns against the *converted* body.
- **Filters are per route.** It's easy to update one route and forget the other;
  `verify.sh` checks both.
- **Rewriting the body holds the response in memory**, which costs memory on large
  payloads.
- **Confirm `response-rewrite` and `log-data-mask` exist in your org** before you
  design around them.
