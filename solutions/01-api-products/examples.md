# Examples — API Products with enforced quota

[Overview](README.md) · [Business need](business-need.md) · [Architecture](architecture.md) ·
[Guides](guides.md) · **Examples** · [Agent prompt](helix-agent-prompt.md) ·
[Tests](tests.md) · [Configuration reference](configuration-reference.md) ·
[API reference](api-reference.md)

---

Two worked examples, each shown three ways — Agent, UI, and API. The values
below are concrete, not placeholders: `posts-api`, `posts-free`, `posts-pro`,
`gateway.example.com`. Copy them as they are to follow along, then swap in
your own org's real names and hosts once you're building this for real.

## Example 1 — Create two pricing tiers

Free (5 requests a minute) and Pro (1,000 a minute), on the same API.

Three things have to exist for this to actually work, not just the products:
the **plugins** that check the key and enforce the quota (`helix-auth`,
`api-product-enforcer`, which come from the spec import, not a separate
step); the API's own **upstream and deploy** (importing a spec does *not*
make the routes live — that needs an upstream bound and the revision
deployed, and nothing warns you if you skip it); and the **products** that
carry the quota numbers.

**Way 1 — Agent**
```text
Create a REST API called "Posts API" on upstream https://jsonplaceholder.typicode.com,
environment test, with helix-auth (validate, key-auth, reading the key from an
"apikey" header) and api-product-enforcer (error_policy fail_close) on its routes.
Then create two products on it: "posts-free" with a quota of 5 requests per
minute, and "posts-pro" with a quota of 1000 requests per minute. Deploy both
to test.
```

**Way 2 — UI**
1. Go to **API Gateway → APIs → Add API**. Set **Method** to **Import an
   OpenAPI spec**, upload [`example/api-spec.yaml`](example/api-spec.yaml),
   click **Import**. This is the step that brings in `helix-auth` and
   `api-product-enforcer` — they're already in that file, so nothing further
   to configure here.
2. Go to **API Gateway → Upstreams → Add Upstream**. Point it at
   `jsonplaceholder.typicode.com` (or your own host), environment `test`.
3. Back on the API's page, click **Deploy** on the revision. Since no
   upstream is bound to `test` yet, the dialog asks you to map one inline —
   pick the upstream you just created, then **Deploy**. (Import alone doesn't
   make the routes live — this step does.)
4. Go to **API Distribution → API Products → Add API Product**. Display
   Name `Free` → APIs: add **posts-api** → Quota: enable it, Request limit
   `5`, Interval `1`, Unit `Minute` → **Create API Product**.
5. On the product page, click **Deploy** → environment `test` → **Deploy**.
   This is a *different* deploy from step 3 — the product needs its own.
6. Repeat steps 4–5 for a second product: Display Name `Pro`, Request limit
   `1000`.

**Way 3 — API**
```bash
BASE="https://gateway.example.com/api"
TOKEN="demo-token-123"
AUTH=(-H "authorization: Bearer $TOKEN")
H=("${AUTH[@]}" -H "content-type: application/json")

# 1. Import the spec — this is what attaches helix-auth and api-product-enforcer
#    to the routes. Note: no content-type header here — curl sets the
#    multipart one itself.
curl "${AUTH[@]}" -F "file=@example/api-spec.yaml" "$BASE/orgs/acme/apis/from-spec"
# → {"api":{"id":"posts-api"}, "revision":{"id":"rev-1"}}

# 2. Import alone doesn't make the routes live — nothing fails loudly if you
#    skip this. Create an upstream (no /api prefix on this one call — a real
#    inconsistency in the platform), bind it to the revision, then deploy.
curl "${H[@]}" -X POST "$BASE/orgs/acme/envs/test/upstreams" -d \
  '{"name":"posts-upstream","specification":{"scheme":"https","nodes":[{"host":"jsonplaceholder.typicode.com","port":443,"weight":1}]}}'
# → {"id":"up-1"}

curl "${H[@]}" -X PATCH "$BASE/orgs/acme/apis/posts-api/revisions/rev-1/upstream-bindings/add" -d \
  '{"environmentUpstreams":[{"environmentId":"test","upstreamId":"up-1"}]}'

curl "${H[@]}" -X POST "$BASE/orgs/acme/apis/posts-api/revisions/rev-1/deploy" -d \
  '{"environmentId":"test","force":false}'

# 3. Create the two products and deploy them — a SEPARATE deploy from the
#    revision's above; the quota isn't enforced until the product is too.
curl "${H[@]}" -X POST "$BASE/orgs/acme/products" -d \
  '{"name":"posts-free","apiIds":["posts-api"],"quota":{"limit":5,"interval":1,"interval_unit":"minute"}}'

curl "${H[@]}" -X POST "$BASE/orgs/acme/products" -d \
  '{"name":"posts-pro","apiIds":["posts-api"],"quota":{"limit":1000,"interval":1,"interval_unit":"minute"}}'

curl "${H[@]}" -X POST "$BASE/orgs/acme/envs/test/products/posts-free/deploy"
curl "${H[@]}" -X POST "$BASE/orgs/acme/envs/test/products/posts-pro/deploy"
```

## Example 2 — Prove one tier never blocks the other

A developer with two apps, one per tier — then show the Free app get
throttled while the Pro app keeps working.

**Way 1 — Agent**
```text
Create a developer called "Ada Partner" with two separate apps: "free-app"
subscribed to posts-free, and "pro-app" subscribed to posts-pro. Give me both
apps' keys, then show me a curl loop proving free-app gets a 429 after 5
requests to /posts while pro-app keeps getting 200s in the same window.
```

**Way 2 — UI**
1. Go to **API Distribution → Developers → Add Developer**. First Name
   `Ada`, Last Name `Partner`, Email `ada@example.com` → **Add**.
2. Go to **API Distribution → Apps → Add App**. Environment `test`,
   Developer `Ada Partner` → Products: add **Free** → **Create App**.
3. Repeat for a second app subscribed to **Pro** instead.
4. On each app's page, open **Credentials** and copy the key. You now have
   two keys — one per tier.

**Way 3 — API**

`developerId` and the environment are **path segments** on the app-create
call, not body fields — the developer's `id` comes back in the first
response (`dev-ada` below is illustrative):

```bash
curl "${H[@]}" -X POST "$BASE/orgs/acme/developers" -d \
  '{"firstName":"Ada","lastName":"Partner","email":"ada@example.com"}'
# → {"id":"dev-ada", ...}

curl "${H[@]}" -X POST "$BASE/orgs/acme/developers/dev-ada/envs/test/apps" -d \
  '{"name":"free-app","products":{"posts-free":1},"plugins":{"helix-auth":{}}}'

curl "${H[@]}" -X POST "$BASE/orgs/acme/developers/dev-ada/envs/test/apps" -d \
  '{"name":"pro-app","products":{"posts-pro":1},"plugins":{"helix-auth":{}}}'
```

`plugins` names the auth method this app authenticates with — matching
whichever method the product allows — and an empty object like
`{"helix-auth":{}}` asks the control plane to auto-generate the key/secret,
the same as the UI's "Credentials auto-generated" option. Confirm the exact
shape your org's build expects before scripting this for real.

**See it in action, any of the three ways:**
```bash
FREE_KEY="free-app-key-001"
PRO_KEY="pro-app-key-002"

for i in $(seq 1 6); do curl -s -o /dev/null -w "%{http_code}\n" \
  "https://gateway.example.com/posts" -H "apikey: $FREE_KEY"; done
# 200 200 200 200 200 429  <- blocked on the 6th call

curl -s -o /dev/null -w "%{http_code}\n" \
  "https://gateway.example.com/posts" -H "apikey: $PRO_KEY"
# 200  <- unaffected, different tier, different bucket
```

The 429 body: `{"error":"quota exceeded"}`, with no `Retry-After` or
`X-RateLimit-*` headers. See [What the caller sees](#what-the-caller-sees).

## What the caller sees

```http
HTTP/1.1 429 Too Many Requests
content-type: application/json

{"error":"quota exceeded"}
```

Publish the retry contract (window length, backoff *with jitter*) in your own
docs — the response can't carry it. Show remaining quota in your developer
portal or analytics instead of headers; see [solution 04](../04-analytics/).

## More variations

**Pool a developer's apps into one bucket** — add `quota_key_scope` to a
product:
```json
{"name":"posts-pro","apiIds":["posts-api"],
 "quota":{"limit":1000,"interval":1,"interval_unit":"minute","quota_key_scope":"developer"}}
```
Now every app that developer owns draws from the same bucket — a trade-off,
not just a tidier default: one misbehaving app can starve the developer's
others.

**Add more tiers** — Enterprise and an unmetered Internal product are just
two more of the same call:
```json
{"name":"posts-enterprise","apiIds":["posts-api"],"quota":{"limit":10000,"interval":1,"interval_unit":"minute"}}
{"name":"posts-internal","apiIds":["posts-api"],"quota":{"limit":-1}}
```
`limit: -1` means unlimited — still identified and counted in analytics, just
never throttled.

**Require a token instead of a static key** — compose with
[solution 02](../02-oauth-jwt/): add `POST /oauth/token` using `helix-auth
generate`, switch the protected routes to `validate_auth_type: jwt-auth`, and
leave `api-product-enforcer` exactly as it is.
