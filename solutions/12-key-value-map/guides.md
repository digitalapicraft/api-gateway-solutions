# Guides — per-partner key material, fetched at request time

> [Overview](README.md) · [Business need](business-need.md) · [Architecture](architecture.md) · **Guides** · [Agent prompt](helix-agent-prompt.md) · [Tests](tests.md) · [API reference](api-reference.md)

---

Three ways to build the same thing, then how to see it work. Whichever way you
pick, the result is one API with two routes: `POST /partners/keys`, which stores a
partner's public key, and `GET /partners/documents`, which encrypts the backend's
response to whichever partner is asking.

## Pick your path

| | Choose this if you… | Go to |
|---|---|---|
| **1. Helix Agent** | want the quickest result and are happy to paste a prompt | [Build it with the Helix Agent](#build-it-with-the-helix-agent) |
| **2. Helix control plane** | prefer clicking through screens and want to see every setting | [Build it in the UI](#build-it-in-the-ui) |
| **3. API script** | are scripting this, or wiring it into a pipeline | [Install it directly](#install-it-directly) |

Then, for everyone: [See it work](#see-it-work) · [Variations](#variations) ·
[Configuration reference](#configuration-reference) · [Troubleshooting](#troubleshooting)

## Build it with the Helix Agent

Works on a **fresh, empty org**. [`helix-agent-prompt.md`](helix-agent-prompt.md)
has two steps: the registration route first, then the document route. **Paste each
as its own message.**

See [AGENT-GUIDE.md](../../AGENT-GUIDE.md) for the ground rules these prompts
assume.

## Build it in the UI

Screen and button names below are the real ones. The API lives under
**API Gateway** in the left sidebar.

**Before you start:**

- **You have an account.** If you don't, register for a free trial at
  [trial.digitalapi.ai](https://trial.digitalapi.ai/). A new trial org comes with a
  `test` environment, which is all this walkthrough needs.
- **You can create APIs.** If you don't see an **Add API** button, ask your org
  admin.
- **You have an OpenPGP public key with an encryption subkey** to register. How to
  check one: [See it work](#see-it-work).

**1. Create the API**

Pick one of the two ways below. Both give you the same thing: an API called
`Partner Documents API` with two routes and no plugins yet.

*Option A — from scratch*
1. Go to **API Gateway → APIs**, click **Add API** (or **Create your first API**).
2. Choose **Create from scratch**. Set **Display name** to `Partner Documents API`,
   then **Create**.
3. On the API's page, open **Configuration → Routes** and add two routes:
   - `POST` `/partners/keys`, where an operator registers a partner's public key
   - `GET` `/partners/documents`, where a partner fetches a document

   The route form opens already filled in with the name *New* and the path
   `/new-route`. Clear both fields first, then type your own.

*Option B — from an OpenAPI spec*
1. Go to **API Gateway → APIs**, click **Add API** (or **Create your first API**).
2. Set **Method** to **Import an OpenAPI spec**.
3. Drag in your own OpenAPI 3.0 file, or use our example,
   [`example/api-spec-basic.yaml`](example/api-spec-basic.yaml): the same two
   routes, no plugins. Then click **Import**.

> **A spec can carry the plugins too.** Add an `x-helix-gateway` block that
> lists them. At the top level of the file it covers every route; under one
> path and method it covers that route only. This is the document route's:
>
> ```yaml
> /partners/documents:
>   get:
>     x-helix-gateway:
>       plugins:
>         key-value-map:
>           fail_action: close
>           fetch:
>             keys:
>               - key: "$request.headers.x-partner-id"
>         pgp-crypto:
>           keys_ctx_namespace: key_value_map
>           encrypt:
>             target: response
>             source: body
>             public_key: "$request.headers.x-partner-id"
>             fail_policy: fail-close
>             fail_close_status: 500
>             fail_close_message: "no usable key is registered for this partner"
>           max_body_size: 1048576
> ```
>
> [`example/api-spec.yaml`](example/api-spec.yaml) is this API with all its
> plugins already in place, and nothing in it needs filling in. Import that
> instead and you can skip step 2.

Either way, the API is not live yet: it has no upstream and isn't deployed.
That comes in step 3.

**2. Add the plugins**

These plugins store each partner's key and encrypt each document to the right
one. Add them **before** you deploy: a live revision can't be changed.

Each one goes on one route, not on the whole API.

On the API's page, open **Configuration → Plugins** and click **Configure
plugin**. A short wizard opens:

1. **Plugin** — pick the plugin from the catalog.
2. **Scope** — choose **Specific endpoint** and pick the route. (**Entire
   Revision** would apply it to every route.)
3. **Configure** — the JSON editor and the Properties list sit side by side.
   Paste the JSON below, or fill in the fields. Then **Next**.
4. **Review** — shows the configuration before and after. Click **Apply**.

Run the wizard once for each plugin on each route: five times in all.

Keep every value that starts with `$` exactly as written, such as
`$request.headers.x-partner-id`. It is not a placeholder for you to fill in: the
gateway reads it from each request as it arrives, so the partner id in the
`X-Partner-Id` header picks the entry.

On the **`POST /partners/keys`** route (Scope: **Specific endpoint**, that
route):

1. **`key-value-map` — stores the partner's key.** It saves the `public_key`
   from the request body under the partner id. Sending the same id again
   replaces the key, so rotating a key needs no deploy. If the store can't be
   written, the request fails rather than pretending it worked.

   ```json
   {"fail_action":"close","inserts":[{"key":"$request.headers.x-partner-id","value":"$request.body.public_key"}]}
   ```

2. **`proxy-rewrite` — sends the request to the right backend path.**

   | Field | Value |
   |---|---|
   | **uri** | `/post` |

   ```json
   {"uri":"/post"}
   ```

On the **`GET /partners/documents`** route (Scope: **Specific endpoint**, that
route):

1. **`key-value-map` — looks up the calling partner's key.** It fetches the
   entry stored under the partner id, ready for the next plugin to use.

   ```json
   {"fail_action":"close","fetch":{"keys":[{"key":"$request.headers.x-partner-id"}]}}
   ```

2. **`pgp-crypto` — encrypts the document to that key.** It uses the same `$`
   reference as the lookup, so it reads the same partner's key. If no usable key
   is registered for the partner, the caller gets HTTP 500 (a server-side error)
   with a short message, never the document in readable form.

   ```json
   {"keys_ctx_namespace":"key_value_map","encrypt":{"target":"response","source":"body","public_key":"$request.headers.x-partner-id","fail_policy":"fail-close","fail_close_status":500,"fail_close_message":"no usable key is registered for this partner"},"max_body_size":1048576}
   ```

3. **`proxy-rewrite` — sends the request to the right backend path.**

   | Field | Value |
   |---|---|
   | **uri** | `/json` |

   ```json
   {"uri":"/json"}
   ```

Repeat for each plugin and route. What every field means, and the optional extra (`request-id`) the full spec adds:
[Configuration reference](#configuration-reference).

**3. Give it an upstream, then deploy it**
1. Go to **API Gateway → Upstreams → Add Upstream**. Name it, pick environment
   `test`, and add a node at `httpbin.org`, port `443`, scheme HTTPS. If you
   switch the scheme to HTTP, the port stays at `443`: change it to `80` by
   hand. If an `httpbin` upstream already exists in your org, reuse it.
2. **Pass Host** is set to **Rewrite**, which makes **Upstream Host** required.
   It fills in from the node's host; check it reads `httpbin.org`.
3. Click **Next** through the remaining tabs, then **Add Upstream**.
4. Back on the API's page, click **Deploy** on the revision. The dialog asks you
   to map an upstream for `test`. Pick the one you just created, then click
   **Map & Deploy**. (The button reads **Map & Deploy** while no upstream is
   mapped yet, and **Deploy** once one is.)

**Changing it later.** A change to the upstream (host, port, scheme) applies to
the live API straight away, with no new deploy. A change to routes or plugins
does need one, because a live revision can't be edited: use **Clone Revision**,
make your change on the copy, then **Force Deploy** it. The same steps roll you
back: clone the older revision and force-deploy that.

**4. Register a partner's key**

There is no screen for this, and no control-plane API either: on this build, the
registration route is the only way to write an entry. Send the request from
[See it work](#see-it-work).

**5. Protect the registration route before real use**

As shipped it is open to anyone who can reach it. Add authentication to
`/partners/keys` only, as in [solution 08](../08-api-key/), and restrict it to
operators.

## Install it directly

If you'd rather script it against the control plane:

```bash
export ORG=<ORG_ID>
export TOKEN=<control-plane bearer token>      # short-lived
export BASE=https://<YOUR_GATEWAY_HOST>/api
H=(-H "authorization: Bearer $TOKEN" -H 'content-type: application/json')

# 1. Import the spec. Nothing in it needs filling in — no key material is in it.
#    Keep both ids the response returns.
curl -s -H "authorization: Bearer $TOKEN" -F "file=@example/api-spec.yaml" \
  "$BASE/orgs/$ORG/apis/from-spec"
# → {"api":{"id":"<API_ID>", ...}, "revision":{"id":"<REVISION_ID>", ...}}

# 2. Import does NOT make the routes live. Create an upstream, bind it to the
#    revision, then deploy the revision.
# pass_host + upstream_host: without them the backend gets the gateway's host
# and every call returns 502.
curl -s "${H[@]}" -X POST "$BASE/orgs/$ORG/envs/<TEST_ENV_ID>/upstreams" \
  -d '{"name":"httpbin","specification":{"scheme":"https","pass_host":"rewrite","upstream_host":"httpbin.org","nodes":[{"host":"httpbin.org","port":443,"weight":1}]}}'
# → {"id":"<UPSTREAM_ID>", ...}

curl -s "${H[@]}" -X PATCH "$BASE/orgs/$ORG/apis/<API_ID>/revisions/<REVISION_ID>/upstream-bindings/add" \
  -d '{"environmentUpstreams":[{"environmentId":"<TEST_ENV_ID>","upstreamId":"<UPSTREAM_ID>"}]}'
curl -s "${H[@]}" -X POST "$BASE/orgs/$ORG/apis/<API_ID>/revisions/<REVISION_ID>/deploy" \
  -d '{"environmentId":"<TEST_ENV_ID>","force":false}'

# 3. Put authentication in front of /partners/keys before anyone else can reach it
#    (solution 08). Then register keys and prove it — see "See it work".
```

> Revisions must be **INACTIVE** to accept a spec change. If it's live, undeploy
> first, or clone the revision so you keep a rollback target.

The same calls without narration: [API reference](api-reference.md).

## See it work

Register a partner's key, then fetch a document as that partner:

```bash
GW=https://<YOUR_GATEWAY_HOST>

# an unregistered partner gets an error, never the document
curl -s -w "\n%{http_code}\n" "$GW/partners/documents" -H 'X-Partner-Id: acme-bank'
# {"message":"no usable key is registered for this partner"}
# 500

# register acme-bank's public key (the body is {"public_key": "<armored key>"})
jq -Rs '{public_key: .}' partner-a-public.asc \
  | curl -s -X POST "$GW/partners/keys" -H 'X-Partner-Id: acme-bank' \
      -H 'content-type: application/json' --data-binary @-

# now the document comes back encrypted to that key
curl -s "$GW/partners/documents" -H 'X-Partner-Id: acme-bank' | base64 -d | head -1
# -----BEGIN PGP MESSAGE-----
```

The response body is base64 **of** an ASCII-armored PGP message, with
`content-type: text/plain`. Decode it, then decrypt with the partner's private key.

To rotate, send the registration request again with the new key. The next
document is encrypted to the new key, and the old key can no longer read it.

**Check the key before you register it.** A key with no encryption subkey is
stored without complaint and then fails as a **200 carrying the error body**, which
looks like success to anything that only checks the status:

| Partner id | Status | Body |
|---|---|---|
| never registered | **500** | `{"message":"no usable key is registered for this partner"}` |
| registered with a **sign-only** key | **200** | *identical body* |
| registered with a usable key | **200** | base64 PGP |

`gpg --quick-generate-key`, the command almost everyone reaches for, makes exactly
that kind of key, and adding `default never` does not change that. Check with:

```bash
gpg --list-keys --with-colons "$UID" | awk -F: '/^(pub|sub)/{print $1, $12}'
# want:  pub scESC        e = encrypt, s = sign, c = certify
#        sub e            no `sub e` row means the route cannot encrypt to it
```

Repair an existing key rather than regenerating it:

```bash
FPR=$(gpg --list-keys --with-colons "$UID" | awk -F: '/^fpr/{print $10; exit}')
gpg --quick-add-key "$FPR" rsa3072 encr never
```

Then **register it again** — the stored copy stays broken until you overwrite it.
Put this check in the note you send each partner.

To run every check as a script, including rotation:

```bash
GATEWAY=https://<YOUR_GATEWAY_HOST> \
PUBLIC_KEY_FILE=./partner-a-public.asc GNUPGHOME=~/.gnupg-partner-a \
SECOND_PUBLIC_KEY_FILE=./partner-a-rotated.asc SECOND_GNUPGHOME=~/.gnupg-partner-a2 \
./example/verify.sh
```

Exit code 0 means an unregistered partner is refused, a registered one gets
ciphertext, entries are kept per partner, and re-registering changes the key with
no deploy. What each check proves: [Tests](tests.md).

## Variations

**Protect the registration route.** It writes key material, so treat it like any
admin endpoint: authenticated, restricted to operators, audited.
[Solution 08](../08-api-key/) shows the authentication.

**Key entries on the authenticated caller.** Put `helix-auth` in front of the
document route and use `$consumer.<suffix>` instead of
`$request.headers.x-partner-id` in **both** places on that route. The entry is
then picked by who the caller is, not by a header they choose.

**Use a different injecting consumer.** On an organisation that is not on a free
trial, `lua-callout` can read a stored value and inject it into a proxied call
without any encryption. Its default priority is **0**: on a route with a plugin
that answers the request itself, such as `mocking` (1999), it never runs and you
get an empty value with no error. Raise it with `_meta.priority`. The store half of
this package does not change.

**Store something other than a key.** The store is generic. Add more `inserts` and
`fetch.keys` entries for other per-partner values.

**Go back to one key in the route.** If you only ever have one partner,
[solution 13](../13-pgp-encryption/) is simpler and has nothing extra to protect.

## Configuration reference

Source of truth: [`example/api-spec.yaml`](example/api-spec.yaml).
[`example/api-spec-basic.yaml`](example/api-spec-basic.yaml) is the same routes
with no plugins, for adding them yourself.

Registration — the value comes from the **request body**, never from this file:

```yaml
key-value-map:
  fail_action: close
  inserts:
    - key: "$request.headers.x-partner-id"
      value: "$request.body.public_key"
```

Use — fetch, then let the encryption plugin resolve the same reference:

```yaml
key-value-map:
  fail_action: close
  fetch:
    keys:
      - key: "$request.headers.x-partner-id"

pgp-crypto:
  keys_ctx_namespace: key_value_map
  encrypt:
    target: response
    source: body
    public_key: "$request.headers.x-partner-id"
    fail_policy: fail-close
    fail_close_status: 500
    fail_close_message: "no usable key is registered for this partner"
  max_body_size: 1048576
```

| Plugin | Field | Value here | What it means |
|---|---|---|---|
| `key-value-map` | `fail_action` | `close` | If the store cannot be reached or written, fail the request. It does not cover a missing key. |
| `key-value-map` | `inserts[].key` / `.value` | `$request.headers.x-partner-id` / `$request.body.public_key` | Store the body's `public_key` under the partner id. Writing the same id again replaces the value. |
| `key-value-map` | `fetch.keys[].key` | `$request.headers.x-partner-id` | Fetch the calling partner's entry into the namespace. |
| `pgp-crypto` | `keys_ctx_namespace` | `key_value_map` | Where to look up a key reference. Must match `key-value-map`'s `ctx_namespace`; both are left at the default so they agree. |
| `pgp-crypto` | `encrypt.target` / `encrypt.source` | `response` / `body` | Encrypt the whole response body. |
| `pgp-crypto` | `encrypt.public_key` | `$request.headers.x-partner-id` | A reference, not a literal key — the same string the fetch used. |
| `pgp-crypto` | `encrypt.fail_policy` | `fail-close` | No usable key, no document. `fail-open` would return it unencrypted. |
| `pgp-crypto` | `encrypt.fail_close_status` / `fail_close_message` | `500` / `no usable key is registered for this partner` | What an unregistered partner receives. |
| `pgp-crypto` | `max_body_size` | `1048576` | The encryption buffers the whole body; larger bodies are rejected. |
| `proxy-rewrite` | `uri` | `/post` (registration), `/json` (document) | The backend's paths. |
| `request-id` | `algorithm` / `header_name` | `uuid` / `X-Request-Id` | API-wide. Encryption errors are deliberately vague; this is what a partner quotes. |

**Do not put a literal key in `inserts`.** That puts key material straight back
into the configuration document, which is what this package exists to avoid.

Placeholders in this package: `<ORG_ID>`, `<TEST_ENV_ID>`, `<API_ID>`,
`<REVISION_ID>`, `<UPSTREAM_ID>`, `<YOUR_GATEWAY_HOST>`. Replace all of them before
you run anything.

Every field of every plugin: [docs.digitalapi.ai/api-gateway](https://docs.digitalapi.ai/api-gateway).

## Troubleshooting

| Symptom | Cause |
|---|---|
| Every partner gets the error | The reference resolves to nothing. Check `headers` is plural, and that the client sends the `X-Partner-Id` header. |
| One partner works and the rest fail | A fixed string was written where a reference belongs. |
| A registered partner gets 200 with the error message in the body | The stored key has no encryption subkey. Repair it and register again — see [See it work](#see-it-work). |
| The document comes back readable | `fail_policy` is `fail-open` on `pgp-crypto`, which returns the backend's document unencrypted. |
| The partner cannot decrypt a well-formed document | The wrong key was stored. Nothing at the gateway shows this; only a round-trip decrypt finds it. |
| Registration returns 503 | The store could not be written. `fail_action: close` means nothing was saved. |
| Registration returns 502, yet the key works | The status belongs to the echo upstream. The key is written before the request is passed on. Fetch a document to confirm. |
| Rotation appears not to take effect | The write used a different id, so it created a second entry instead of replacing one. |
| It worked, then stopped after an edit | `ctx_namespace` and `keys_ctx_namespace` no longer match. |
| Deploy fails: `Only INACTIVE revisions can be updated` | Clone the revision or undeploy, then apply. |

If you built it with the agent:

| Symptom | Cause |
|---|---|
| `stream closed with reason: error` after a route write | The agent's tool arguments arrived malformed; nothing was written. Retry once, then import the spec for the rest. |
| The agent substitutes a value for `$request.headers.x-partner-id` | Reply: leave the `$` references as written — the plugin resolves them at request time, not you. |
| The agent writes `pgp-crypto` flat | Reply: the crypto config is nested under `encrypt` — show me the route object as JSON before sending. |
| The write succeeds and the routes have no plugins | Nested under `x-helix-gateway`. Read the revision back and rewrite with a top-level `plugins` key. |

Everything in [solution 13's troubleshooting](../13-pgp-encryption/guides.md#troubleshooting)
still applies to the encryption itself — the wire format especially.
- **Use the trace inspector to see each step.** On the API's page, open the
  **Observability** tab and click **Start trace session**. It shows the headers
  each plugin changes and the request body at every stage, which is the fastest
  way to see what each plugin did to a call. A session stops after 10 requests,
  so use **Advanced: filter which requests to capture** to record only the ones
  you care about (skipped requests don't count). The list doesn't refresh by
  itself: click **Refresh**. The **Inspector** shows API keys and cookies in
  plain text, so don't share your screen or paste a trace into a ticket without
  removing them. A compressed response, which browsers always ask for, is
  unreadable in the **Response** tab, so call the API with curl to read it. The
  **Upstream** tab's **Total** adds connect time to response time, so it can be
  larger than the request's own total.
- **See what changed, and when, in Audit Logs.** **Observability → Audit Logs**
  lists every clone, plugin change and deploy. Its times are in your local time,
  while analytics uses UTC. Anything done with your token, including scripts and
  the Helix Agent, appears under your name.
