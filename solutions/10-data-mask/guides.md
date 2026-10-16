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

The fastest path, and it works on a **fresh, empty org**. One prompt does the
whole build: [`helix-agent-prompt.md`](helix-agent-prompt.md) has it as two
numbered steps — Step 1 creates the API and its two routes, Step 2 adds the
masking the caller sees and the masking a logger would keep. Paste the whole thing
as one message, read the revision back before you deploy, then run the checks
under [See it work](#see-it-work).

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

**1. Create the API**

Pick one of the two ways below. Both give you the same thing: an API called
`Support Console API` with two routes and no plugins yet.

*Option A — from scratch*
1. Go to **API Gateway → APIs**, click **Add API** (or **Create your first API**).
2. Choose **Create from scratch**. Set **Display name** to `Support Console API`,
   then **Save**.
3. On the API's page, open **Configuration → Routes** and add two routes, both
   with method `GET`:
   - `/support/customers`, the list of customers
   - `/support/customers/:customerId`, one customer. The gateway writes a path
     parameter as `:customerId`, not `{customerId}`.

*Option B — from an OpenAPI spec*
1. Go to **API Gateway → APIs**, click **Add API** (or **Create your first API**).
2. Set **Method** to **Import an OpenAPI spec**.
3. Drag in your own OpenAPI 3.0 file, or use our example,
   [`example/api-spec-basic.yaml`](example/api-spec-basic.yaml): the same two
   routes, no plugins. Then click **Import**.

> **A spec can carry the plugins too.** Add an `x-helix-gateway` block that
> lists them. At the top level of the file it covers every route; under one
> path and method it covers that route only:
>
> ```yaml
> paths:
>   /support/customers:
>     get:
>       x-helix-gateway:
>         plugins:
>           response-rewrite:
>             filters:
>               - regex: '("phone"\s*:\s*")[^"]*"'
>                 replace: '$1[redacted]"'
>                 scope: global
>           proxy-rewrite:
>             uri: /users
> ```
>
> [`example/api-spec.yaml`](example/api-spec.yaml) is this API with all its
> plugins already in place. Import that instead and you can skip step 2.

Either way, the API is not live yet: it has no upstream and isn't deployed.
That comes in step 3.

**2. Add the plugins**

Three plugins on each route do the work: one masks what the caller sees, one
masks what a logger would write, and one sends the call to the right backend
path. Add them **before** you deploy: a live revision can't be changed.

These go on each route rather than on the whole API: open the route under
**Configuration → Routes** and add the plugin there. (Adding a plugin under
**Configuration → Plugins → Add plugin** would apply it to every route.) The
masking settings are lists of rules, so switch to the **JSON view** and paste
them; the simpler path settings also fit the **Properties** form.

On **both** routes, `/support/customers` and `/support/customers/:customerId`:

1. **`response-rewrite` — masks what the caller sees.** Four find-and-replace
   rules over the reply: the part of each email address before the `@`, the
   whole phone number, and both map coordinates. Each rule names its field, so
   it can't match text elsewhere. **Keep `scope: global` on every rule**:
   without it a rule stops after its first match, so in a list only the first
   customer is masked.

   ```json
   {
     "filters": [
       {"regex": "(\"email\"\\s*:\\s*\")[^\"@]+@", "replace": "$1***@", "scope": "global"},
       {"regex": "(\"phone\"\\s*:\\s*\")[^\"]*\"", "replace": "$1[redacted]\"", "scope": "global"},
       {"regex": "(\"lat\"\\s*:\\s*\")[^\"]*\"", "replace": "$1[redacted]\"", "scope": "global"},
       {"regex": "(\"lng\"\\s*:\\s*\")[^\"]*\"", "replace": "$1[redacted]\"", "scope": "global"}
     ]
   }
   ```

2. **`log-data-mask` — masks what a logger writes.** It replaces `email` and
   `phone` in the logged reply and drops the caller's credentials from the
   logged request. It never changes the reply itself, and it does nothing
   unless the route also has a logger plugin.

   ```json
   {
     "response": [
       {"type": "body", "name": "email", "action": "replace", "value": "[redacted]", "body_format": "json"},
       {"type": "body", "name": "phone", "action": "replace", "value": "[redacted]", "body_format": "json"}
     ],
     "request": [
       {"type": "header", "name": "authorization", "action": "remove"},
       {"type": "header", "name": "x-api-key", "action": "remove"}
     ]
   }
   ```

Then one `proxy-rewrite` per route — it sends the call to the backend's path:

3. **On `/support/customers`:** to `/users` on the test backend.

   | Field | Value |
   |---|---|
   | **uri** | `/users` |

   ```json
   {"uri":"/users"}
   ```

4. **On `/support/customers/:customerId`:** to `/users/` followed by the same
   customer id, so each customer reaches their own record.

   ```json
   {"regex_uri":["^/support/customers/(.*)$","/users/$1"]}
   ```

Each plugin then appears on its route. The optional extra (`request-id`) the
full spec adds API-wide: [Configuration reference](#configuration-reference).

**3. Give it an upstream, then deploy it**
1. Go to **API Gateway → Upstreams → Add Upstream**. Name it, pick environment
   `test`, point it at `jsonplaceholder.typicode.com` (or your own backend), then
   **Create Upstream**.
2. Back on the API's page, click **Deploy** on the revision. The dialog asks you
   to map an upstream for `test`. Pick the one you just created, then **Deploy**.

No products, developers or apps are needed: the package ships unauthenticated.

**Two things to adjust for your own data:**

- **Your own field names.** In step 2, change the field names in *both* masking
  plugins, and the `proxy-rewrite` paths, on both routes.
- **A logger.** This walkthrough adds the log mask, not a logger, and
  `log-data-mask` does nothing without one. Add a logger plugin to each route in
  step 2, or use the "prove the log half too" prompt under
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

Follow-ups you can paste to the agent in the same chat, once the build is
standing. Say what you want to be true.

**Prove the log half too**
```text
Add a logger to both routes that sends each request and response body to
{{log_sink_url}} as soon as it happens. Then tell me how to compare one logged
entry with and without the log masking, because that comparison is the only proof
the log mask works.
```

**My payload names the fields differently**
```text
My records use contactEmail, mobileNumber and homeLat/homeLng. Mask those instead,
in the response and in the logs, and remind me what happens to a copy of the same
value stored under another key.
```

**Mask by role rather than for everyone**
```text
Only agents in the support tier should get the masked view; the fraud team needs
the full record. Tell me honestly whether one route can do that, and if not, what
the two-route shape looks like and how the caller is identified.
```

**Put identity in front of it** — that's [solution 08](../08-api-key/). Masking
is not access control.
```text
Require an app's API key in the X-Api-Key header on both routes, and keep the
masking exactly as it is. Then create a developer, a product and an app, and give
me the key.
```

## Configuration reference

Source of truth: [`example/api-spec.yaml`](example/api-spec.yaml). Both routes
carry the same two masking blocks.
[`example/api-spec-basic.yaml`](example/api-spec-basic.yaml) is the same routes
with no plugins, for adding them yourself.

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
- **Nothing is masked, and every call returns 200.** The patterns assume compact
  JSON (`"email":"`) while the backend sends `"email": "…"`. Ask for patterns that
  match a field however it is spaced.
- **An email address in some other field is masked too.** The email pattern
  matches anything shaped like an address, not just the `email` field. Tie it to
  `"email"` if other fields must stay unchanged.
- **The response is no longer valid JSON.** A pattern made the quotes optional, and
  the backend sends that field as a number, so the match runs into the next field.
  Require the quotes, or match numbers separately.
- **A literal `[^"]*` appears in responses.** Regex syntax ended up in the
  *replacement*. Replacements take `$1` and plain text only.
- **The single-record route returns 404.** If you built it with the agent, check
  the stored path: a live route needs `/support/customers/:customerId`, and the
  agent may store `{customerId}` instead. Fix the path by hand.
- **Every single-record call returns the same customer.** The path rewrite is a
  fixed `uri`. It needs a `regex_uri` that carries the id.
- **A `file-logger` appears on the API.** The agent added a logger nobody asked
  for. It writes masked bodies to a file on the gateway; remove it if you don't
  want it.
- **The agent says the logs are masked, and there is no logger on the route.**
  `log-data-mask` has no effect without one, and never changes the response.
- **The agent says the routes are built, and the API has no routes.** The route
  write reported success and stored nothing. Read the revision back before any
  deploy; if it's empty, ask for the routes again or import
  [`example/api-spec.yaml`](example/api-spec.yaml).
- **The routes exist but have no plugins.** The agent nested them under
  `x-helix-gateway`, which a live route silently ignores. Read the revision back.
- **`stream closed with reason: error` after a route write.** Nothing was written.
  Try once more; if it repeats, import [`example/api-spec.yaml`](example/api-spec.yaml).
- **Deploy fails with `Only INACTIVE revisions can be updated`.** Clone the
  revision or undeploy it, then apply the change.
