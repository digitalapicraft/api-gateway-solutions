# Verification record

On **2026-08-18** all four solutions were deployed to and exercised against a live
Helix gateway (a fresh free-trial environment). This file records exactly what ran,
what passed, and — importantly — the three things the live build proved *wrong* in
the packages, which have since been corrected.

Gateway details (host, org and resource identifiers) are withheld here, as
everywhere in this repo. What matters is reproducible against any environment.

---

## Result at a glance

| # | Solution | `verify.sh` | Notes |
|---|----------|-------------|-------|
| 01 | OAuth 2.0 with JWT | ✅ exit 0, 6/6 cases | Passed **as shipped**, unmodified. |
| 02 | SOAP to REST | ✅ exit 0, 5/5 cases | Passed **only after fixing three real bugs** — see below. |
| 03 | API Products | ✅ exit 0, 5/5 cases | Passed **as shipped**. Isolation confirmed; quota exact. |
| 04 | Analytics | ✅ verified via the analytics API | Per-app attribution and path-templating both confirmed. |

Every solution reached the strongest status this repo defines — *Functional test
passed* — against a real gateway. Three of the four required no code change. The
fourth (SOAP→REST) was genuinely broken as shipped and is now fixed and re-proven.

The full request-path proofs are the same `gateway/verify.sh` scripts in each
package, run with the deployed routes.

---

## What the live build confirmed (repo was right)

- **The importable artifact really is an OpenAPI document with
  `x-helix-gateway.plugins`.** Root-level plugins mapped to the service, per-method
  plugins to the route, and `service_id` was assigned automatically on import.
- **Dry-run is genuinely non-destructive** and it caught a missing upstream binding
  before any deploy — exactly the workflow the repo prescribes.
- **ACTIVE revisions reject edits** with HTTP 409; clone-or-undeploy first, as
  documented.
- **`helix-auth` generate/validate** issues a three-segment HS256 JWT with the
  configured `token_ttl`; a wrong client secret is rejected (the secret *is*
  checked); a forged token is rejected.
- **`api-product-enforcer` accepts only `error_policy` and `ctx_namespace`** — the
  schema confirms it, and Redis settings on the route are not part of it.
- **A product with no `quota` object is rejected at creation** — `quota` is a
  required field, matching the repo's "no quota is a 403, not unlimited" warning.
- **Quota is counted per app, and isolation holds**: a Free app (limit 5/min)
  returned exactly five 200s then 429, while a second app on a different product
  kept getting 200s in the same window.
- **The 429 carries `{"error":"quota exceeded"}` with no `Retry-After` and no
  `X-RateLimit-*` headers** — asserted present/absent explicitly.
- **An app whose product doesn't cover the API gets 403**
  (`"This credential is not authorized to access this API."`).
- **Analytics is global** — no analytics plugin appears in any spec, yet every call
  was captured, attributed to app, developer and product.
- **Path templating works at the `route_id` dimension**: five requests to five
  distinct `/orders/{orderId}` values aggregate to **one** row by `route_id`, versus
  five rows by `api_path`.

---

## What the live build proved WRONG (repo has been corrected)

### 1. `xml-to-json` is not "bidirectional by default" (solution 02)

The shipped spec used an empty `xml-to-json: {}` block and the docs called the
plugin "bidirectional — one plugin, both directions". The live schema and behaviour
say otherwise:

- **`transform_request` defaults to `false`.** An empty block converts the
  **response only**. The client's JSON request body reached the SOAP handler as JSON
  (the backend replied "Invalid request input"), so the request direction silently
  never happened.
- **The response transform is content-negotiated.** It fires only when the client
  sends `Accept: application/json`. Without that header the upstream XML passed
  straight through as `text/xml` — which is exactly how the original `verify.sh`
  failed (case 4).
- **`proxy-rewrite` setting `Content-Type: text/xml` broke the request transform.**
  `proxy-rewrite` (priority 1008) runs before `xml-to-json` (997); it rewrote the
  content type before the transform inspected it, so the JSON body no longer matched
  `request_content_types` and was not converted.

**Fix:** enable `transform_request: true` explicitly, drop the `Content-Type`
override from `proxy-rewrite`, and send `Accept: application/json` from clients.
With those three changes `verify.sh` passes 5/5, including the case-4 no-XML-markup
assertion (request → XML → backend → XML → JSON round-trip proven end to end).

`json-to-xml` is a real plugin, but it is **not** the request-side counterpart the
repo implied — it converts a JSON *upstream response* to XML for clients that ask
for XML. It solves the opposite problem.

### 2. `<ENV:...>` is not resolved — the literal string becomes the key (all solutions)

The repo's core safety guidance was that `signing_secret: "<ENV:JWT_SIGNING_SECRET>"`
references an environment variable the control plane resolves. **It does not.** On
this build the gateway uses whatever string is in `signing_secret` as the literal
HMAC key. Verified conclusively: a token issued by a route configured with the
literal `<ENV:JWT_SIGNING_SECRET>` validates under HMAC-SHA256 using that exact
string as the key. No `${...}` or bare-name syntax resolved either, and there is no
secret-management endpoint in the control-plane API.

The consequence is a security trap: **shipping the placeholder verbatim makes your
signing key a publicly known constant.** The placeholder must be replaced with a
real secret value before deploy — it is a fill-in-the-blank, not an indirection.

**Fix:** every spec now labels the secret placeholder as a value to replace, with a
prominent warning that it is used literally and must never be shipped as-is. The
"secrets never appear in a spec" claim has been corrected throughout.

### 3. `jwt-auth` and `key-auth` are not standalone plugins (all solutions)

The build ships **86 plugins**; `jwt-auth` and `key-auth` are **not** among them.
They exist only as values of `helix-auth`'s `validate_auth_type`
(`enum: [jwt-auth, key-auth]`). The repo's external-issuer advice ("use the
`jwt-auth` plugin") is not literally actionable on this build — external-issuer JWT
validation is a `helix-auth` configuration, not a separate plugin. Wording corrected
where it implied a standalone plugin.

---

## Smaller observations (noted in the packages)

- **The 429 body is JSON but `content-type: text/plain`.** The body is
  `{"error":"quota exceeded"}` but not labelled as JSON. Parse defensively.
- **The quota window is fixed wall-clock, not sliding.** A burst straddling the
  minute boundary can briefly serve up to 2× the limit (five before, five after).
  Consistent with the repo's "per-minute absorbs bursts" note, now stated
  explicitly.
- **`X-Request-Id` is not an analytics dimension.** Correlation to a *single*
  request is done in your logs via the forwarded header, not by querying analytics
  for the id. The available dimensions are: `env_name`, `app_id`, `app_name`,
  `product_name`, `api_name`, `route_id`, `route_name`, `api_path`,
  `request_method`, `response_status_code`, `upstream_path`, `developer`.
- **Free-trial resource caps are low** (developers, products, apps). Verification
  reused existing demo resources additively rather than creating fresh ones.

---

## How analytics was actually queried (feeds `solutions/04-analytics/charts.md`)

The control plane exposes `POST /api/orgs/{orgId}/analytics/metrics/*` (requests
count, response time, sizes, RPS, upstream time) taking `{startTime, endTime,
filters[], dimensions[], aggregation, timeUnit}`. Grouping by `route_id` gives
templated per-route rows; grouping by `api_path` gives one row per concrete path.
`app_name`, `developer` and `product_name` are all populated once identity is
resolved. This is the concrete backing for the (previously agent-phrased) queries in
`charts.md`.

---

## Reproducing this

Each package's `gateway/verify.sh` is the request-path proof. Deploy the spec, bind
an upstream, create an app (and products for solution 03), then run `verify.sh` with
your gateway host and credentials. See each solution's README § *Testing*.
