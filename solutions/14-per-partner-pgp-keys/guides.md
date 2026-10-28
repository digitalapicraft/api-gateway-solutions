# Guides — per-partner key material, fetched at request time

> [Overview](README.md) · [Business need](business-need.md) · [Architecture](architecture.md) · **Guides** · [Agent prompt](helix-agent-prompt.md) · [Tests](tests.md) · [API reference](api-reference.md)

---

Three ways to build the same thing, then how to see it work. Whichever way you
pick, the result is one API with two routes: `POST /partners/keys`, which stores a
partner's public key, and `GET /partners/documents`, which encrypts the backend's
response to whichever partner is asking.

**Every path includes one step you must not skip: protect the registration route
before you deploy.** The spec and the agent prompt leave `POST /partners/keys`
open. Anyone who can reach an open one can register their own key under any
partner's id, and that partner's documents are then encrypted to them. The step
puts two plugins on that one route, `helix-auth` and `api-product-enforcer`, and an
operators-only product behind them, so only your operators' apps get through.

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
has the whole build as one prompt with two steps: the routes, then the store and
the encryption. Paste it as one message and replace the `{{...}}` values.

When it finishes, read the revision back. Before you trust it, check:

- both routes write the partner id as `$request.headers.x-partner-id`, `headers`
  plural, and never as a fixed value;
- the registration route stores `$request.body.public_key` under that id, and the
  document route fetches the same id;
- `pgp-crypto`'s settings sit under `encrypt`, with `fail_policy: fail-close`, and
  its `public_key` is that same reference, or `$ctx.helix.key_value_map.<alias>`
  when the fetch names an alias;
- a partner with no stored key gets HTTP 500 (server error), not the document. The
  message may be the plugin's default, `failed to encrypt response`; that's fine.

**Then, before you deploy, protect the registration route.** The prompt doesn't.
Add the two plugins from [step 3 of Build it in the UI](#build-it-in-the-ui) to the
revision the agent built, deploy it, and carry on from step 5. If the agent has
already deployed, the route is open now: clone the revision, add the plugins to the
copy, and **Force Deploy** it straight away.

See [AGENT-GUIDE.md](../../AGENT-GUIDE.md) for the ground rules these prompts
assume.

## Build it in the UI

Screen and button names below are the real ones. The API lives under
**API Gateway** in the left sidebar; products, developers and apps live under
**API Distribution**.

**Before you start:**

- **You have an account.** If you don't, register for a free trial at
  [trial.digitalapi.ai](https://trial.digitalapi.ai/). A new trial org comes with a
  `test` environment, which is all this walkthrough needs.
- **You can create APIs, products and apps.** If you don't see an **Add API**
  button, ask your org admin.
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

If an API with the same name already exists in your org, the import fails with
*API with name '<name>' already exists*. Type another name in the form's
**Display name** field, which overrides the name in the spec, and import again.

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
> instead and you can skip step 2. **Step 3 still applies:** that spec leaves the
> registration route open.

Either way, the API is not live yet: it has no upstream and isn't deployed.
That comes in step 4.

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
   reference as the lookup, so it reads the same partner's key. A partner with no
   key registered gets HTTP 500 (a server-side error) with a short message, never
   the document in readable form.

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

**3. Protect the registration route (required, before you deploy)**

As built so far, anyone who can reach `POST /partners/keys` can register a key
under any partner's id. Add two more plugins to that route only, with the same
wizard (Scope: **Specific endpoint**, `POST /partners/keys`). Do this whichever way
you created the API: neither example spec, and not the agent prompt, carries it.
The document route stays as it is.

1. **`helix-auth` — checks the caller's app key.** It reads the key from the
   `X-Admin-Key` header and looks up which app it belongs to. No key, or a key that
   belongs to no app, gets HTTP 401 (not signed in), and nothing is stored.

   | Field | Value |
   |---|---|
   | **mode** | `validate` |
   | **validate_auth_type** | `key-auth` |
   | **apikey → source** | `header` |
   | **apikey → key** | `X-Admin-Key` |

   ```json
   {"mode":"validate","validate_auth_type":"key-auth","apikey":{"source":"header","key":"X-Admin-Key"}}
   ```

   **apikey → source** is required. Until it is filled in, the wizard shows
   `apikey.source: Missing required field` and won't let you continue. There is
   no key to type in here: the keys live on the apps you create in step 6.

2. **`api-product-enforcer` — lets only operator apps through.** `helix-auth` on
   its own accepts the key of any app in the environment, whatever product that
   app is on. This plugin lets through only apps on a product that includes this
   API, and answers every other app with HTTP 403 (not allowed). In step 5 you
   create that product for your operators alone.

   ```json
   {"error_policy":"fail_close","_meta":{"priority":3100}}
   ```

   Keep both settings. With `fail_open` instead of `fail_close`, the plugin would
   let a refused app through. The priority makes the check run before
   `key-value-map` writes the key; at its own priority it runs after, so a refused
   app's key would already be stored by the time it got its 403. Details:
   [Architecture → Execution order](architecture.md#execution-order).

Until step 6 gives an operator a key, every registration is turned away. That is
the safe state to deploy in.

**4. Give it an upstream, then deploy it**
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

**Changing it later.** A change to the upstream's host or port applies to the
live API straight away, with no new deploy. A change to its scheme does not:
undeploy the revision and deploy it again. A change to routes or plugins does
need one, because a live revision can't be edited: use **Clone Revision**, make
your change on the copy, then **Force Deploy** it. Rolling back needs no copy:
click **Deploy**, pick the older revision (for example `r1`), and click **Force
Deploy**.

**5. Create the operators product, and deploy it**
1. Go to **API Distribution → API Products**, click **Add API Product**.
2. Under **Basic Information**, set a **Display Name**, for example
   `Partner key operators`.
3. Under **APIs**, click **Add API**. In the **Add APIs** dialog, tick
   `Partner Documents API`, then click **Add (1)**.
4. Under **Authentication Methods**, leave it blank. It defaults to `helix-auth`,
   which is what the registration route checks.
5. Under **Quota**, make sure **Enable request quota** is on. It is by default,
   set to 1000 per 1 hour, so don't click the switch: that turns the quota off,
   and every product needs one. Each registration uses one request of it, so the
   default is plenty.
6. Leave **Quota scope** on **App level**.
7. Click **Create API Product**.
8. On the product's page, click **Deploy**, pick `test`, then **Deploy** again.
   This is a different deploy from step 4. Do it before step 6: an app can only
   pick products already deployed to its environment.

**Add this API to no other product.** An app on any product that includes it
gets through the registration route's check.

**6. Give each operator an app, and copy its key**
1. Go to **API Distribution → Developers**, click **Add Developer**, fill in the
   name and email, then **Add**.
2. Go to **API Distribution → Apps**, click **Add App**. Fill in **Display Name**,
   for example `key-operator`. Pick the **Environment** and the **Developer**, add
   the operators product, pick an authentication method and let credentials
   auto-generate, then **Create App**. If the product list says **No products
   found.**, the product isn't deployed to that environment yet: go back to
   step 5.
3. On the app's **Overview** tab, find the **Authentication** card. It shows
   `helix-auth` with a key and a secret, both hidden, each with a show and a copy
   button. Copy the **key**: that's what the operator sends in the `X-Admin-Key`
   header. It is the credential key, not the app's id and not its secret.

Give each operator their own app, so you can switch one off without the others.
**Generate New Credentials**, in the same card, stops the old key within seconds
and keeps the app's history.

**7. Register a partner's key**

There is no screen for this, and no control-plane API either: on this build, the
registration route is the only way to write an entry. Send the request from
[See it work](#see-it-work), with the operator's key.

## Install it directly

To script it, call the control plane instead. `BASE` is the API address the
portal calls (it usually starts with `api-`), not the portal page and not the
gateway's address.

**First, protect the registration route in your own copy of the spec.**
[`example/api-spec.yaml`](example/api-spec.yaml) leaves `POST /partners/keys`
open, so don't import it as it is. Copy it to
`partner-documents-protected.yaml`, and in the copy add `helix-auth` and
`api-product-enforcer` to that route's plugins, next to the two already there.
The route's block then reads:

```yaml
  /partners/keys:
    post:
      # summary, parameters, requestBody and responses as in example/api-spec.yaml
      x-helix-gateway:
        plugins:
          helix-auth:
            mode: validate
            validate_auth_type: key-auth
            apikey:
              source: header
              key: X-Admin-Key
          api-product-enforcer:
            error_policy: fail_close
            _meta:
              priority: 3100   # checks the app before key-value-map (3001) stores anything
          key-value-map:
            fail_action: close
            inserts:
              - key: "$request.headers.x-partner-id"
                value: "$request.body.public_key"
          proxy-rewrite:
            uri: /post
```

Then:

```bash
export ORG=<ORG_ID>
export TOKEN=<control-plane bearer token>      # short-lived
export BASE=https://<YOUR_CONTROL_PLANE_API>/api
H=(-H "authorization: Bearer $TOKEN" -H 'content-type: application/json')

# 1. Import YOUR COPY of the spec, the one with the registration route protected.
#    Nothing else in it needs filling in: no key material is in it.
#    Keep both ids the response returns.
curl -s -H "authorization: Bearer $TOKEN" -F "file=@partner-documents-protected.yaml" \
  "$BASE/orgs/$ORG/apis/from-spec"     # multipart upload, so no JSON content-type
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

# 3. Create the operators product with this API in it, then deploy it. Every
#    product needs a quota object. Add this API to no other product.
curl -s "${H[@]}" -X POST "$BASE/orgs/$ORG/products" \
  -d '{"name":"partner-key-operators","displayName":"Partner key operators","apiIds":["<API_ID>"],"quota":{"limit":60,"interval":1,"interval_unit":"minute"}}' \
  | jq -r '.id'                                              # → <PRODUCT_ID>
curl -s "${H[@]}" -X POST "$BASE/orgs/$ORG/envs/<TEST_ENV_ID>/products/<PRODUCT_ID>/deploy"

# 4. Create a developer, then ONE APP PER OPERATOR, subscribed to that product.
#    The control plane issues each app's key; the response carries it.
curl -s "${H[@]}" -X POST "$BASE/orgs/$ORG/developers" \
  -d '{"firstName":"<FIRST_NAME>","lastName":"<LAST_NAME>","email":"<EMAIL>"}' \
  | jq -r '.id'                                              # → <DEVELOPER_ID>

curl -s "${H[@]}" -X POST "$BASE/orgs/$ORG/developers/<DEVELOPER_ID>/envs/<TEST_ENV_ID>/apps" \
  -d '{"name":"<OPERATOR_APP_NAME>","products":{"<PRODUCT_ID>":1},"plugins":{"helix-auth":{}}}'

# 5. Register keys with the operator app's key in X-Admin-Key, and prove it:
#    see "See it work".
```

On an app, `plugins` names the way the app proves who it is. An empty
`{"helix-auth":{}}` asks the control plane to create the key and secret, like the
UI's auto-generate option. Check the shape your org's version of the gateway
expects before you script this for real.

> Revisions must be **INACTIVE** to accept a spec change. If it's live, undeploy
> first, or clone the revision so you keep a rollback target.

The same calls without narration: [API reference](api-reference.md).

## See it work

Register a partner's key with an operator's key, then fetch a document as that
partner:

```bash
GW=https://<YOUR_GATEWAY_HOST>
ADMIN_KEY=<OPERATOR_KEY>      # the operator app's key, from step 6

# an unregistered partner gets an error, never the document
curl -s -w "\n%{http_code}\n" "$GW/partners/documents" -H 'X-Partner-Id: acme-bank'
# {"message":"no usable key is registered for this partner"}
# 500

# without an operator's key, registration is turned away
jq -Rs '{public_key: .}' partner-a-public.asc \
  | curl -s -o /dev/null -w "%{http_code}\n" -X POST "$GW/partners/keys" \
      -H 'X-Partner-Id: acme-bank' -H 'content-type: application/json' --data-binary @-
# 401

# ...and nothing was stored: still the error
curl -s -o /dev/null -w "%{http_code}\n" "$GW/partners/documents" -H 'X-Partner-Id: acme-bank'
# 500

# register acme-bank's public key (the body is {"public_key": "<armored key>"})
jq -Rs '{public_key: .}' partner-a-public.asc \
  | curl -s -X POST "$GW/partners/keys" -H "X-Admin-Key: $ADMIN_KEY" \
      -H 'X-Partner-Id: acme-bank' -H 'content-type: application/json' --data-binary @-

# now the document comes back encrypted to that key
curl -s "$GW/partners/documents" -H 'X-Partner-Id: acme-bank' | base64 -d | head -1
# -----BEGIN PGP MESSAGE-----
```

An app key that isn't on the operators product gets HTTP 403 on the registration
route instead of 401, and nothing is stored either.

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

`gpg --quick-generate-key <uid> rsa3072`, or the same command with any other named
algorithm, makes exactly that kind of key: only a primary key, which signs and
certifies. The bare command, or `default default` in place of the algorithm, adds
an encryption subkey. Check with the key's user id (its name or email) in place of
`<uid>`:

```bash
gpg --list-keys --with-colons "<uid>" | awk -F: '/^(pub|sub)/{print $1, $12}'
# want:  pub scESC        e = encrypt, s = sign, c = certify
#        sub e            no `sub e` row means the route cannot encrypt to it
```

Repair an existing key rather than regenerating it:

```bash
FPR=$(gpg --list-keys --with-colons "<uid>" | awk -F: '/^fpr/{print $10; exit}')
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
no deploy. **The script sends no operator key**, so on a protected registration
route, which every build here has, its registration check gets HTTP 401 and the
run stops there. Make the calls above by hand instead. What each check proves:
[Tests](tests.md).

## Variations

**Keep the operator key away from your backend.** The gateway passes `X-Admin-Key`
on to the backend exactly as the operator sent it, and `httpbin.org` echoes it
back. To remove it, give the registration route's existing `proxy-rewrite` a
`headers.remove` list; don't add a second `proxy-rewrite`. The key is checked
before `proxy-rewrite` runs, so the check still works:

```json
{"uri":"/post","headers":{"remove":["X-Admin-Key"]}}
```

**Key entries on the authenticated caller.** Put `helix-auth` in front of the
document route and use `$consumer.<suffix>` instead of
`$request.headers.x-partner-id` in **both** places on that route. The entry is
then picked by who the caller is, not by a header they choose. Partners then need
apps of their own, so move the registration route into an API of its own first:
an app on any product that includes the API gets through the registration
route's check.

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

Registration — the protection you add before the first deploy. Neither example
spec carries it:

```yaml
helix-auth:
  mode: validate
  validate_auth_type: key-auth
  apikey:
    source: header
    key: X-Admin-Key

api-product-enforcer:
  error_policy: fail_close
  _meta:
    priority: 3100
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
| `helix-auth` | `mode` / `validate_auth_type` | `validate` / `key-auth` | Registration only, added by you. Check the caller's app key. |
| `helix-auth` | `apikey.source` / `apikey.key` | `header` / `X-Admin-Key` | Where the operator sends their app's key. `source` is required. |
| `api-product-enforcer` | `error_policy` | `fail_close` | Registration only, added by you. Turn away apps not on a product that includes this API. `fail_open` would let them through. |
| `api-product-enforcer` | `_meta.priority` | `3100` | Run the check before `key-value-map` (3001) stores anything. At its own priority, 2399, it runs after. |

**Do not put a literal key in `inserts`.** That puts key material straight back
into the configuration document, which is what this package exists to avoid.

Placeholders in this package: `<ORG_ID>`, `<TEST_ENV_ID>`, `<API_ID>`,
`<REVISION_ID>`, `<UPSTREAM_ID>`, `<PRODUCT_ID>`, `<DEVELOPER_ID>`, `<FIRST_NAME>`,
`<LAST_NAME>`, `<EMAIL>`, `<OPERATOR_APP_NAME>`, `<OPERATOR_KEY>`,
`<YOUR_CONTROL_PLANE_API>`, `<YOUR_GATEWAY_HOST>`. Replace all of them before you
run anything.

Every field of every plugin: [docs.digitalapi.ai/api-gateway](https://docs.digitalapi.ai/api-gateway).

## Troubleshooting

- **Every partner gets the error.** The reference resolves to nothing. Check
  `headers` is plural, that the client sends the `X-Partner-Id` header, and that
  `pgp-crypto` points at what the fetch stored: the same reference, or the
  fetch's alias.
- **One partner works and the rest fail.** A fixed string was written where a
  reference belongs.
- **A registered partner gets 200 with the error message in the body.** The
  stored key has no encryption subkey, which is what `gpg --quick-generate-key
  <uid> rsa3072`, or any other named algorithm, makes. Repair it and register it
  again: see [See it work](#see-it-work).
- **The document comes back readable.** `fail_policy` is `fail-open` on
  `pgp-crypto`, which returns the backend's document unencrypted.
- **The partner cannot decrypt a well-formed document.** The wrong key was stored.
  Nothing at the gateway shows this; only a round-trip decrypt finds it.
- **Registration returns 401.** No key was sent, the key belongs to no app, or it
  went in a header other than `X-Admin-Key`. Send the operator app's key, not its
  secret.
- **Registration returns 403 with an operator's key.** The app isn't on the
  operators product, the product doesn't include this API, or the product isn't
  deployed to the environment.
- **An app that isn't an operator's gets 403, yet its key was stored.**
  `api-product-enforcer` is at its own priority, so it runs after `key-value-map`
  has written. Set its `_meta.priority` to `3100`.
- **Anyone can register a key.** The protection isn't on the deployed revision.
  Clone the revision, add the two plugins from
  [step 3 of Build it in the UI](#build-it-in-the-ui), and **Force Deploy** it.
- **Registration returns 503.** The store could not be written, and
  `fail_action: close` means nothing was saved. With the protection in place, the
  product's quota store being out of reach also gives 503.
- **Registration returns 502, yet the key works.** The status belongs to the echo
  upstream. The key is written before the request is passed on. Fetch a document
  to confirm.
- **Rotation appears not to take effect.** The write used a different id, so it
  created a second entry instead of replacing one.
- **It worked, then stopped after an edit.** `ctx_namespace` and
  `keys_ctx_namespace` no longer match.
- **`verify.sh` stops at the registration check with 401.** The script sends no
  operator key. See [See it work](#see-it-work).
- **Deploy fails: `Only INACTIVE revisions can be updated`.** Clone the revision
  or undeploy, then apply.
- **`stream closed with reason: error` after an agent route write.** The agent's
  tool arguments arrived malformed, and nothing was written. Retry once, then
  import [`example/api-spec.yaml`](example/api-spec.yaml) instead.
- **The agent puts a value in place of `$request.headers.x-partner-id`.** Reply:
  leave the reference as written; the gateway resolves it on each request.
- **The schema rejects the agent's `pgp-crypto`.** It was written flat. The
  encryption settings are nested under `encrypt`.
- **The agent's routes exist with no plugins.** It wrapped them in
  `x-helix-gateway` inside the live route object, which a live route silently
  discards. Read the revision back and rewrite them with a top-level `plugins` key.
- **Everything in [solution 13's troubleshooting](../13-pgp-encryption/guides.md#troubleshooting)
  still applies** to the encryption itself, the wire format especially.
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
