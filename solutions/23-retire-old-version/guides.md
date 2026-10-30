# Guides — Retire an old API version in stages

> [Overview](README.md) · [Business need](business-need.md) · [Architecture](architecture.md) · **Guides** · [Agent prompt](helix-agent-prompt.md) · [Tests](tests.md) · [API reference](api-reference.md)

---

## Pick your path

| | Choose this if you… | Go to |
|---|---|---|
| **1. Helix Agent** | want the quickest result and are happy to paste a prompt | [Build it with the Helix Agent](#build-it-with-the-helix-agent) |
| **2. Helix control plane** | prefer clicking through screens | [Build it in the UI](#build-it-in-the-ui) |
| **3. API script** | are scripting this, or wiring it into a pipeline | [Install it directly](#install-it-directly) |

Then, for everyone: [See it work](#see-it-work) · [Variations](#variations) ·
[Configuration reference](#configuration-reference) ·
[Troubleshooting](#troubleshooting)

## Build it with the Helix Agent

The fastest path, and it works on a **fresh, empty org**. One prompt builds and
deploys the API: [`helix-agent-prompt.md`](helix-agent-prompt.md) has it as two
numbered steps. Step 1 creates the four routes, step 2 adds the headers, the
410 and the request id. Paste the whole thing as one message, or one step at a
time if the run ends early. The agent asks before it deploys.

When it finishes, read the revision back: paths with `:productId`, and the 410
route answered by a mock response, not by code. Then run the checks under
[See it work](#see-it-work).

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
`Products API` with four routes and no plugins yet.

*Option A — from scratch*
1. Go to **API Gateway → APIs**, click **Add API** (or **Create your first API**).
2. Choose **Create from scratch**. Set **Display name** to `Products API`, then
   **Create**.
3. On the API's page, open **Configuration → Routes** and add four routes, all
   `GET`. The gateway writes a path parameter as `:productId`, not
   `{productId}`.
   - `/v1/products/:productId`, the deprecated v1 lookup
   - `/v1/products/:productId/reviews`, the retired v1 endpoint
   - `/v2/products/:productId`, the current lookup
   - `/v2/products/:productId/reviews`, the current reviews

   The route form opens already filled in with the name *New* and the path
   `/new-route`. Clear both fields first, then type your own.

*Option B — from an OpenAPI spec*
1. Go to **API Gateway → APIs**, click **Add API** (or **Create your first API**).
2. Set **Method** to **Import an OpenAPI spec**.
3. Drag in or browse to your own OpenAPI 3.0 file, or use our example,
   [`example/api-spec-basic.yaml`](example/api-spec-basic.yaml): the same four
   routes, no plugins. There is no option to paste the spec as text. Then click
   **Import**.

If an API with the same name already exists in your org, the import fails with
*API with name '<name>' already exists*. Type another name in the form's
**Display name** field, which overrides the name in the spec, and import again.

> **A spec can carry the plugins too.** Add an `x-helix-gateway` block that
> lists them. At the top level of the file it covers every route; under one
> path and method it covers that route only:
>
> ```yaml
> paths:
>   /v1/products/{productId}:
>     get:
>       x-helix-gateway:
>         plugins:
>           response-rewrite:
>             headers:
>               set:
>                 Deprecation: "@1777593600"
>                 Sunset: "Wed, 31 Mar 2027 23:59:59 GMT"
> ```
>
> [`example/api-spec.yaml`](example/api-spec.yaml) is this API with all its
> plugins already in place. Import that instead and you can skip step 2.

Either way, the API is not live yet: it has no upstream and isn't deployed.
That comes in step 3.

**2. Add the plugins**

Four plugins do the work. Add them **before** you deploy: a live revision can't
be changed.

On the API's page, open **Configuration → Plugins** and click **Configure
plugin**. A short wizard opens:

1. **Plugin** — pick the plugin from the catalog.
2. **Scope** — **Entire Revision** applies it to every route; **Specific
   endpoint** applies it to one route.
3. **Configure** — the JSON editor and the Properties list sit side by side.
   Paste the JSON below, or fill in the fields. Then **Next**.
4. **Review** — shows the configuration before and after. Click **Apply**.

Run the wizard once per plugin per route: six times in all.

1. **`proxy-rewrite` — sends each lookup to the backend's path.** The backend
   calls a product a post, so `/v1/products/1` and `/v2/products/1` both become
   `/posts/1`. Scope: **Specific endpoint**, once on each of these three routes,
   with its own JSON:

   | Route | JSON |
   |---|---|
   | `GET /v1/products/:productId` | `{"regex_uri":["^/v1/products/([^/]+)$","/posts/$1"]}` |
   | `GET /v2/products/:productId` | `{"regex_uri":["^/v2/products/([^/]+)$","/posts/$1"]}` |
   | `GET /v2/products/:productId/reviews` | `{"regex_uri":["^/v2/products/([^/]+)/reviews$","/posts/$1/comments"]}` |

   `$1` is the part of the path in brackets: the product id.

2. **`response-rewrite` — adds the three headers to every v1 answer.** Scope:
   **Specific endpoint**, `GET /v1/products/:productId`. The headers are added to
   whatever the backend returns, errors included.

   ```json
   {"headers":{"set":{"Deprecation":"@1777593600","Sunset":"Wed, 31 Mar 2027 23:59:59 GMT","Link":"</v2/products/$uri_param_productId>; rel=\"successor-version\""}}}
   ```

   Use your own dates; [Configuration reference](#configuration-reference)
   shows the format of each.

3. **`mocking` — answers the retired endpoint with 410.** Scope: **Specific
   endpoint**, `GET /v1/products/:productId/reviews`. The gateway sends this
   answer itself, so the backend is never called.

   ```json
   {"response_status":410,"content_type":"application/json","with_mock_header":false,"response_headers":{"Sunset":"Wed, 30 Sep 2026 23:59:59 GMT","Link":"</v2/products/$uri_param_productId/reviews>; rel=\"successor-version\""},"response_example":"{\"error\":\"gone\",\"message\":\"This endpoint was retired on 30 September 2026. Use the successor address.\",\"successor\":\"/v2/products/$uri_param_productId/reviews\"}"}
   ```

4. **`request-id` — puts an id on every response.** Scope: **Entire Revision**.
   Settings: [Configuration reference](#configuration-reference).

   ```json
   {"algorithm":"uuid","header_name":"X-Request-Id"}
   ```

Each plugin then appears under **Configuration → Plugins**.

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
   **Map & Deploy**. (The button reads **Map & Deploy** while no upstream is
   mapped yet, and **Deploy** once one is.)

**Changing it later.** Each stage of a retirement is a change to routes or
plugins, so each needs a new revision: a live revision can't be edited. Use
**Clone Revision**, make your change on the copy, then **Force Deploy** it. To
roll back, click **Deploy**, pick the older revision (for example `r1`) and
click **Force Deploy**; no clone is needed. A change to the upstream's host or
port applies to the live API straight away, with no new deploy.

## Install it directly

```bash
export ORG=<ORG_ID>
export TOKEN=<control-plane bearer token>      # short-lived
export CP=https://<YOUR_CONTROL_PLANE_API>
H=(-H "authorization: Bearer $TOKEN" -H 'content-type: application/json')

# 1. Import the spec. Keep both ids the response returns.
curl -s -H "authorization: Bearer $TOKEN" -F "file=@example/api-spec.yaml" \
  "$CP/api/orgs/$ORG/apis/from-spec"
# → {"api":{"id":"<API_ID>", ...}, "revision":{"id":"<REVISION_ID>", ...}}

# 2. Create an upstream, bind it to the revision, deploy the revision.
curl -s "${H[@]}" -X POST "$CP/api/orgs/$ORG/envs/<ENV_ID>/upstreams" \
  -d '{"name":"products-upstream","specification":{"scheme":"https","pass_host":"rewrite","upstream_host":"jsonplaceholder.typicode.com","nodes":[{"host":"jsonplaceholder.typicode.com","port":443,"weight":1}]}}'
# → {"id":"<UPSTREAM_ID>", ...}   Keep pass_host and upstream_host, or every call returns 502.
curl -s "${H[@]}" -X PATCH "$CP/api/orgs/$ORG/apis/<API_ID>/revisions/<REVISION_ID>/upstream-bindings/add" \
  -d '{"environmentUpstreams":[{"environmentId":"<ENV_ID>","upstreamId":"<UPSTREAM_ID>"}]}'
curl -s "${H[@]}" -X POST "$CP/api/orgs/$ORG/apis/<API_ID>/revisions/<REVISION_ID>/deploy/dry-run" \
  -d '{"environmentId":"<ENV_ID>"}'
# → {"message":"Dry-run validation successful","success":true}
curl -s "${H[@]}" -X POST "$CP/api/orgs/$ORG/apis/<API_ID>/revisions/<REVISION_ID>/deploy" \
  -d '{"environmentId":"<ENV_ID>","force":false}'
```

The routes answer a few seconds after the deploy. The same calls without
narration: [API reference](api-reference.md).

## See it work

Each stage gives a different answer. Look at the headers (`-i`):

```bash
G=https://<YOUR_GATEWAY_HOST>
curl -s -i $G/v1/products/1           # 200, the product, plus Deprecation, Sunset, Link
curl -s -i $G/v1/products/7/reviews   # 410, a JSON body, Sunset and Link; backend not called
curl -s -i $G/v2/products/1           # 200, the same product, no Deprecation or Sunset
```

The deprecated route, trimmed to what matters:

```text
HTTP/2 200
link: </v2/products/1>; rel="successor-version"
deprecation: @1777593600
sunset: Wed, 31 Mar 2027 23:59:59 GMT
```

The retired route:

```text
HTTP/2 410
content-type: application/json
sunset: Wed, 30 Sep 2026 23:59:59 GMT
link: </v2/products/7/reviews>; rel="successor-version"

{"error":"gone","message":"This endpoint was retired on 30 September 2026. Use the successor address.","successor":"/v2/products/7/reviews"}
```

The `Link` follows the id: ask for product 42 and it names `/v2/products/42`.
The headers are also on the backend's own errors: `GET /v1/products/999999`
returns the backend's 404 with all three.

### Run it as a script

`example/verify.sh` checks every stage, then follows the `Link` and the
`successor` to v2, the way a caller's code would:

```bash
GATEWAY=https://<YOUR_GATEWAY_HOST> ./example/verify.sh
```

Exit code 0 means every check held. It needs only `bash` and `curl`. If you
changed the dates, pass them as `DEPRECATION`, `SUNSET` and `RETIRED_SUNSET`.
What each check proves: [Tests](tests.md).

## Variations

**Retire the next endpoint.** Clone the revision. On that route, remove
`proxy-rewrite` and `response-rewrite`, add `mocking` as in step 2 with its own
retirement date and successor address, and **Force Deploy**. Nothing else
changes.

**Remove a retired endpoint.** Clone the revision, delete the route, and
**Force Deploy**. Callers then get `404 Route Not Found`. Do this only once
analytics shows no calls to it for a while; a 410 costs nothing to keep.

**Let browser apps read the headers.** A script in a web page on another site
can't read `Deprecation`, `Sunset` or `Link` unless the response names them in
`Access-Control-Expose-Headers`. Add one more entry to the same `set`:

```json
{"Access-Control-Expose-Headers":"Deprecation, Sunset, Link"}
```

**Point at a migration guide as well.** One `Link` header can carry several
links, separated by commas. RFC 9745 adds `rel="deprecation"` for a page
about the deprecation:

```text
</v2/products/$uri_param_productId>; rel="successor-version", <https://example.com/docs/v1-retirement>; rel="deprecation"; type="text/html"
```

**See who still calls v1.** In analytics ([solution 04](../04-analytics/)),
group calls by route (`route_name`); with app keys
([solution 08](../08-api-key/)) you also see which app made each call.

## Configuration reference

**`response-rewrite`** (`GET /v1/products/:productId`):

| Field | Value | What it means |
|---|---|---|
| `headers.set.Deprecation` | `@1777593600` | When v1 was deprecated. `@` then whole seconds since 1 January 1970, UTC ([RFC 9745](https://www.rfc-editor.org/rfc/rfc9745)). Seconds, not milliseconds: 10 digits for any date this century. |
| `headers.set.Sunset` | `Wed, 31 Mar 2027 23:59:59 GMT` | When v1 stops working. An HTTP date, always GMT ([RFC 8594](https://www.rfc-editor.org/rfc/rfc8594)). |
| `headers.set.Link` | `</v2/products/$uri_param_productId>; rel="successor-version"` | Where to go instead. `$uri_param_productId` becomes the caller's `:productId`. |

`set` replaces a header of the same name if the backend sent one. To make
your own dates on Linux, `date -u -d '2026-05-01' +%s` gives the seconds, and
`LC_ALL=C date -u -d '2027-03-31 23:59:59' '+%a, %d %b %Y %H:%M:%S GMT'`
gives the HTTP date.

**`mocking`** (`GET /v1/products/:productId/reviews`):

| Field | Value | What it means |
|---|---|---|
| `response_status` | `410` | HTTP 410 (gone): retired on purpose, not coming back. |
| `content_type` | `application/json` | Only JSON, plain text and XML types are accepted. `application/problem+json` is refused when you deploy. |
| `with_mock_header` | `false` | Leaves out the header that marks a reply as a mock. This one is a real answer. |
| `response_headers` | `Sunset`, `Link` | The retirement date and the successor. `$uri_param_productId` works here too. |
| `response_example` | the JSON body | Sent as written, with `$uri_param_productId` filled in. |

**`proxy-rewrite`** (three routes): `regex_uri` is a pattern and a
replacement. `$1` is the first bracketed part of the pattern.

**`request-id`** (API-wide): `algorithm: uuid`, `header_name: X-Request-Id`.
If a request already carries an `X-Request-Id`, the plugin keeps that id.

Source of truth: [`example/api-spec.yaml`](example/api-spec.yaml).
`example/api-spec-basic.yaml` is the same routes with no plugins, for adding
them yourself.

Placeholders in this package: `<ORG_ID>`, `<API_ID>`, `<ENV_ID>`,
`<REVISION_ID>`, `<UPSTREAM_ID>`, `<YOUR_GATEWAY_HOST>`,
`<YOUR_CONTROL_PLANE_API>`. Replace all of them before you run anything.

Every field of every plugin: [docs.digitalapi.ai/api-gateway](https://docs.digitalapi.ai/api-gateway).

## Troubleshooting

- **`GET /v1/products/1` returns `404 Route Not Found`.** The route is missing,
  or was stored as `/v1/products/{productId}`. Change it to
  `/v1/products/:productId` on a cloned revision and redeploy. The agent can
  store braces even when the prompt says `:productId`, so check the revision.
- **The `Link` reads `</v2/products/>` or `</v2/products//reviews>`.** The id
  didn't come through. Check the variable matches the route's parameter
  exactly: `:productId` is `$uri_param_productId`.
- **The 410 comes back as `text/plain`, or its body has no `successor`.** The
  route is answered by something other than `mocking`, such as code the agent
  wrote. Replace it with the `mocking` JSON from
  [step 2](#build-it-in-the-ui) on a cloned revision.
- **The retired route returns 200, or the backend's data.** `mocking` isn't on
  that route. Add it as in step 2.
- **The dry-run or deploy fails with `unsupported content type!`.** `mocking`'s
  `content_type` is something other than JSON, plain text or XML, for example
  `application/problem+json`. Use `application/json`.
- **A client can't read the `Deprecation` date.** It must be `@` and whole
  seconds (10 digits): not milliseconds (13 digits), not an HTTP date, and not
  `true`.
- **A browser app sees `null` for `Sunset`.** Expose the headers, as in
  [Variations](#variations). `curl` and server-side code see them already.
- **v2 responses carry `Deprecation`.** `response-rewrite` was added with
  Scope **Entire Revision**. Move it to the v1 route only.
- **Use the trace inspector to see each step.** On the API's page, open the
  **Observability** tab and click **Start trace session**. The 410 shows
  **Upstream not called**, answered by `mocking`; the v1 lookup shows
  `response-rewrite` on the way back. A session stops after 10 requests, and
  the list doesn't refresh by itself: click **Refresh**. The **Inspector**
  shows API keys and cookies in plain text, so remove them before you share
  a trace.
- **See what changed, and when, in Audit Logs.** **Observability → Audit Logs**
  lists every clone, plugin change and deploy. Its times are in your local time,
  while analytics uses UTC. Anything done with your token, including scripts and
  the Helix Agent, appears under your name.
