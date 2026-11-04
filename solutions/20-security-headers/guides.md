# Guides — Security headers

> [Overview](README.md) · [Business need](business-need.md) · [Architecture](architecture.md) · **Guides** · [Agent prompt](helix-agent-prompt.md) · [Tests](tests.md) · [API reference](api-reference.md)

---

## Pick your path

| | Choose this if you… | Go to |
|---|---|---|
| **1. Helix Agent** | want the quickest result and are happy to paste a prompt | [Build it with the Helix Agent](#build-it-with-the-helix-agent) |
| **2. Helix control plane** | prefer clicking through screens | [Build it in the UI](#build-it-in-the-ui) |
| **3. API script** | are scripting this, or wiring it into a pipeline | [Install it directly](#install-it-directly) |

Already have a deployed API that needs the headers? Skip the API: in
[Build it in the UI](#build-it-in-the-ui), go straight to step 2 and add the
plugin to yours, on a cloned revision.

Then, for everyone: [See it work](#see-it-work) · [Variations](#variations) ·
[Configuration reference](#configuration-reference) ·
[Troubleshooting](#troubleshooting)

## Build it with the Helix Agent

The fastest path, and it works on a **fresh, empty org**. One prompt builds and
deploys the sample API: the two routes, both plugins and the upstream.
[`helix-agent-prompt.md`](helix-agent-prompt.md) has it as two steps: paste the
whole thing as one message, or one step at a time if the run ends early.

The prompt names no plugin. It says what must be true, and three phrases do the
work:

| The prompt says | So the agent |
|---|---|
| "once for the whole API rather than route by route" | puts the rule on the API, where it covers every route, including routes added later |
| "replace its value rather than adding a second one" | uses `set`, not `add` |
| "The response body stays exactly as the backend sent it" | configures headers only: no `body`, no `filters` |

The agent asks before it does two things. Answer them:

- **Which upstream to use**, if your environment already has some for the same
  host. Reuse one, or let it create its own.
- **Whether to deploy.** It shows what it is about to deploy and waits for a
  yes.

What the prompt leaves unstated, the agent picks:

| Choice | What the agent picks | To change it |
|---|---|---|
| The upstream | asked which to reuse, when the environment already had several for this host | answer its question, or say "create a new upstream" |
| The request-id format | `uuid`, the default | "use a ksuid request id" |
| A trial deploy first | may skip it and deploy directly, after asking | "dry-run the deploy before you deploy" |

**Check the result before you rely on it.** Read the revision back
([API reference](api-reference.md)): `response-rewrite` and `request-id`
belong under `serviceSpec.plugins`, which covers the whole API, and no route
should carry its own. `response-rewrite` should hold only `headers`. The routes
should read `/users/:userId`, with a colon. Then run
[`example/verify.sh`](example/verify.sh) against it.

The agent may offer to add a **catch-all route**, so that paths with no route
get the headers too. Decline it unless this API is the only one in the
environment. A catch-all route answers every path no other API serves, sends
those requests to your backend, and can clash with another API's routes.

See [AGENT-GUIDE.md](../../AGENT-GUIDE.md) for the ground rules these prompts
assume.

## Build it in the UI

Screen and button names below are the real ones. The API lives under
**API Gateway** in the left sidebar.

**Before you start:**

- **You have an account.** If you don't, register for a free trial at
  [trial.digitalapi.ai](https://trial.digitalapi.ai/). A new trial org comes
  with a `test` environment, which is all this walkthrough needs.
- **You're an org admin or a gateway admin.** Those roles can create and deploy
  APIs.

**1. Create the API**

1. Go to **API Gateway → APIs**, click **Add API** (or **Create your first API**).
2. Set **Method** to **Import an OpenAPI spec**.
3. Drag in or browse to [`example/api-spec-basic.yaml`](example/api-spec-basic.yaml):
   the two routes, no plugins. Then click **Import**.

If an API with the same name already exists in your org, the import fails with
*API with name '<name>' already exists*. Type another name in the form's
**Display name** field and import again.

To create the routes by hand instead, choose **Create from scratch**, then add
`GET /users` and `GET /users/:userId` under **Configuration → Routes**. The
gateway writes a path parameter as `:userId`, not `{userId}`.

> **Skip step 2:** import [`example/api-spec.yaml`](example/api-spec.yaml)
> instead. It is the same API with both plugins already in place.

**2. Add the plugins**

Add them **before** you deploy: a live revision can't be changed.

On the API's page, open **Configuration → Plugins** and click **Configure
plugin**. A short wizard opens:

1. **Plugin** — pick the plugin from the catalog.
2. **Scope** — pick **Entire Revision** for both plugins here. That is what
   makes the rule cover every route, including ones added later.
3. **Configure** — the JSON editor and the Properties list sit side by side.
   Paste the JSON below. Then **Next**.
4. **Review** — shows the configuration before and after. Click **Apply**.

1. **`response-rewrite` — sets five headers and removes five.**

   ```json
   {"headers":{"set":{"X-Content-Type-Options":"nosniff","Cache-Control":"no-store","X-Frame-Options":"DENY","Content-Security-Policy":"default-src 'none'; frame-ancestors 'none'","Referrer-Policy":"no-referrer"},"remove":["X-Powered-By","Server","Via","X-AspNet-Version","X-AspNetMvc-Version"]}}
   ```

   Only `headers`. Leave **body** and **filters** empty: they rewrite the
   response body, which this package never does.

2. **`request-id` — an id on every response.**

   ```json
   {"algorithm":"uuid","header_name":"X-Request-Id"}
   ```

Both then appear under **Configuration → Plugins**.

**3. Give it an upstream, then deploy it**

1. Go to **API Gateway → Upstreams → Add Upstream**. Name it, pick environment
   `test`, and add a node at `jsonplaceholder.typicode.com`, port `443`, scheme
   HTTPS (or your own host). If you switch the scheme to HTTP, the port stays at
   `443`: change it to `80` by hand.
2. **Pass Host** is set to **Rewrite**, which makes **Upstream Host** required.
   It fills in from the node's host; check it reads
   `jsonplaceholder.typicode.com`.
3. Click **Next** through the remaining tabs, then **Add Upstream**.
4. Back on the API's page, click **Deploy** on the revision. The dialog asks you
   to map an upstream for `test`. Pick the one you just created, then click
   **Map & Deploy**.

**Changing it later.** A live revision can't be edited: use **Clone Revision**,
change the plugin on the copy, then **Force Deploy** it. Rolling back: click
**Deploy**, pick the older revision, and click **Force Deploy**.

## Install it directly

```bash
export ORG=<ORG_ID>
export TOKEN=<control-plane bearer token>      # short-lived
export CP=https://<YOUR_CONTROL_PLANE_API>
H=(-H "authorization: Bearer $TOKEN" -H 'content-type: application/json')

# 1. Import the spec. Nothing in it needs filling in. Keep both ids.
curl -s -H "authorization: Bearer $TOKEN" -F "file=@example/api-spec.yaml" \
  "$CP/api/orgs/$ORG/apis/from-spec"
# → {"api":{"id":"<API_ID>", ...}, "revision":{"id":"<REVISION_ID>", ...}}

# 2. Create an upstream, bind it, dry-run, deploy.
curl -s "${H[@]}" -X POST "$CP/api/orgs/$ORG/envs/<ENV_ID>/upstreams" \
  -d '{"name":"customers-upstream","specification":{"scheme":"https","pass_host":"rewrite","upstream_host":"jsonplaceholder.typicode.com","nodes":[{"host":"jsonplaceholder.typicode.com","port":443,"weight":1}]}}'
# → {"id":"<UPSTREAM_ID>", ...}
curl -s "${H[@]}" -X PATCH "$CP/api/orgs/$ORG/apis/<API_ID>/revisions/<REVISION_ID>/upstream-bindings/add" \
  -d '{"environmentUpstreams":[{"environmentId":"<ENV_ID>","upstreamId":"<UPSTREAM_ID>"}]}'
curl -s "${H[@]}" -X POST "$CP/api/orgs/$ORG/apis/<API_ID>/revisions/<REVISION_ID>/deploy/dry-run" \
  -d '{"environmentId":"<ENV_ID>"}'
# → {"message":"Dry-run validation successful","success":true}
curl -s "${H[@]}" -X POST "$CP/api/orgs/$ORG/apis/<API_ID>/revisions/<REVISION_ID>/deploy" \
  -d '{"environmentId":"<ENV_ID>","force":false}'
```

The same calls without narration: [API reference](api-reference.md).

## See it work

Compare the backend with the gateway. `-D -` prints the headers, `-o /dev/null`
drops the body:

```bash
G=https://<YOUR_GATEWAY_HOST>

# Before: the backend on its own
curl -s -D - -o /dev/null https://jsonplaceholder.typicode.com/users/1 \
  | grep -iE 'cache-control|x-powered-by|x-content-type|x-frame|content-security|referrer'
# cache-control: max-age=43200
# x-content-type-options: nosniff
# x-powered-by: Express

# After: through the gateway
curl -s -D - -o /dev/null $G/users/1 \
  | grep -iE 'cache-control|x-powered-by|x-content-type|x-frame|content-security|referrer|x-request-id'
# cache-control: no-store
# x-content-type-options: nosniff
# x-request-id: <an id>
# x-frame-options: DENY
# content-security-policy: default-src 'none'; frame-ancestors 'none'
# referrer-policy: no-referrer

# An error carries them too
curl -s -D - -o /dev/null $G/users/999999 | grep -iE '^HTTP|cache-control|x-powered-by'
# HTTP/2 404
# cache-control: no-store

# The data is untouched: no output from cmp means identical
cmp <(curl -s $G/users) <(curl -s https://jsonplaceholder.typicode.com/users)
```

Headers you didn't touch still come through. The sample backend's CDN adds a
few of its own (`cf-ray`, `nel`, `report-to`); see
[Remove more headers](#remove-more-headers).

### Run it as a script

```bash
GATEWAY=https://<YOUR_GATEWAY_HOST> ./example/verify.sh
```

Exit code 0 means every check held. What each check proves: [Tests](tests.md).

## Variations

### Add HSTS

`Strict-Transport-Security` is left out on purpose: it covers the whole host, so
it belongs to whoever runs TLS for the domain
([why](architecture.md#hsts-and-why-it-is-not-in-the-block)). First check what
your callers get:

```bash
curl -s -D - -o /dev/null $G/users/1 | grep -i strict-transport-security
```

If a value comes back, something in front of the gateway already sets it, and a
value you set in the gateway may not be the one callers receive. Talk to whoever
owns that layer. If nothing comes back and HTTPS is the only way in, add it to
`set`:

```yaml
Strict-Transport-Security: max-age=31536000
```

Add `includeSubDomains` only when every subdomain of the host serves HTTPS.
Browsers remember the setting for `max-age` seconds, so start short if you are
unsure.

### Remove more headers

Each backend leaks something different. List what yours sends, then add every
name that says what runs behind the API to `remove`:

```bash
curl -s -D - -o /dev/null https://<YOUR_BACKEND>/<any-path>
```

For the sample backend, that would be its CDN's `CF-Ray`, `CF-Cache-Status`,
`NEL` and `Report-To`. Header names are not case-sensitive.

### A route that may be cached

Public reference data, such as a country list, can be cached. Give that route
its own `response-rewrite` with a different `Cache-Control`. Because a
route-level block **replaces** the API-wide one on that route, repeat every other
header in it:

```yaml
x-helix-gateway:            # under paths./countries.get
  plugins:
    response-rewrite:
      headers:
        set:
          Cache-Control: "public, max-age=300"
          X-Content-Type-Options: nosniff
          X-Frame-Options: DENY
          Content-Security-Policy: "default-src 'none'; frame-ancestors 'none'"
          Referrer-Policy: no-referrer
        remove: [X-Powered-By, Server, Via, X-AspNet-Version, X-AspNetMvc-Version]
```

The same applies when a route masks its body, as in
[solution 10](../10-data-mask/): put this `headers` block beside its `filters`.

## Configuration reference

The plugins, as they appear in [`example/api-spec.yaml`](example/api-spec.yaml),
under the top-level `x-helix-gateway.plugins`:

| Plugin | Field | Value here | What it means |
|---|---|---|---|
| `response-rewrite` | `headers.set` | five headers | Put each header on the response with this value, **replacing** one the backend sent. |
| | `headers.remove` | five names | Take each header off the response, if present. |
| | `headers.add` | *(not used)* | Append a header as `"Name: value"`, beside any the backend sent. |
| | `body`, `filters` | *(not used)* | Replace or regex-edit the response body. Leave both out to keep the body untouched. |
| | `status_code` | *(not used)* | Change the response status. Leave it out. |
| `request-id` | `header_name` | `X-Request-Id` | The header carrying the id. |
| | `algorithm` | `uuid` | How a new id is made. A request that already carries one keeps it. |
| | `include_in_response` | default `true` | Return the id to the caller. |

Placeholders in this package: `<ORG_ID>`, `<API_ID>`, `<ENV_ID>`,
`<REVISION_ID>`, `<UPSTREAM_ID>`, `<YOUR_GATEWAY_HOST>`,
`<YOUR_CONTROL_PLANE_API>`, `<YOUR_BACKEND>`. Replace all of them before you
run anything.

Every field of every plugin: [docs.digitalapi.ai/api-gateway](https://docs.digitalapi.ai/api-gateway).

## Troubleshooting

- **`Cache-Control` comes back twice** (`max-age=43200` and `no-store`). The
  rule uses `add` instead of `set`. Move the header to `set`.
- **One route has none of the headers.** That route carries its own
  `response-rewrite`, which replaces the API-wide one. Copy the `headers` block
  into it ([One rule per route](architecture.md#one-rule-per-route)).
- **`X-Powered-By` is still there.** The revision you are calling isn't the one
  with the plugin, or the plugin sits on another route. Check which revision is
  deployed and that `response-rewrite` is scoped to the **Entire Revision**.
- **A scanner reports missing headers on a `404`.** Check the body. If it says
  `404 Route Not Found`, the path matched no route and never reached the API.
  That's expected; a `404` from your backend carries the headers.
- **The HSTS value isn't the one you set.** Something in front of the gateway
  sets it. See [Add HSTS](#add-hsts).
- **The body changed.** Something else on the route rewrites it: a
  `response-rewrite` with `body` or `filters`, or another plugin. This rule
  alone never touches the body.
- **The deploy fails because another API already uses these routes.** APIs
  deployed to the same environment share its host, so two APIs can't both serve
  `GET /users`. Undeploy the other one, or change the paths. Don't let the
  agent delete an API you still need.
- **`GET /users/1` returns `404 Route Not Found` after an agent build.** The
  route was stored as `/users/{userId}`. Change it to `/users/:userId` on a
  cloned revision and deploy again. The agent can do this even when the prompt
  says `:userId`, so check the routes whatever the prompt says.
- **After an agent build, the headers are on each route instead of the API.**
  The responses are right today, but a route added later gets nothing. Move
  `response-rewrite` to **Entire Revision** scope and remove the per-route
  copies.
