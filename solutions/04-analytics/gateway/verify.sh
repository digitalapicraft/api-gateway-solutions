#!/usr/bin/env bash
# Solution 04 — seed identifiable traffic, then verify the request path is shaped so
# analytics can answer something useful.
#
# WHAT THIS SCRIPT CAN AND CANNOT DO — read this before trusting its exit code.
#
#   Analytics is captured asynchronously by the platform and read from the portal or
#   via the agent. A shell script cannot assert that a chart is correct, and this one
#   does not pretend to. What it CAN do, and does:
#
#     1. Confirm identity is being resolved (unauthenticated -> 401, authenticated
#        -> 200). Without this, every analytics row attributes to an IP address and
#        the whole solution is pointless.
#     2. Confirm X-Request-Id is present on responses, so an aggregate can be traced
#        back to a single request.
#     3. Generate a KNOWN, LABELLED traffic pattern across several routes and status
#        codes — deliberately including failures — so you have something specific to
#        look for when you query analytics.
#     4. Print the exact queries to run next, and the numbers to expect.
#
#   Exit 0 means: the request path is correctly shaped AND a known pattern has been
#   seeded. It does NOT mean analytics is verified. That step is manual and is
#   recorded as such in ../tests/test-plan.yaml and ../validation/.
#
# Usage:
#   GATEWAY=https://<YOUR_GATEWAY_HOST> \
#   CLIENT_ID=<CLIENT_ID> \
#   CLIENT_SECRET=<CLIENT_SECRET> \
#   ./verify.sh
#
# Optional overrides:
#   TOKEN_PATH   default /oauth/token
#   API_PATH     default /orders
#   ITEM_PATH    default /orders/verify-probe-001   (exercises /orders/{orderId})
#   SEED_OK      default 12   successful calls to seed
#   SEED_401     default 3    deliberate auth failures to seed
#   SEED_404     default 2    deliberate not-founds to seed

set -uo pipefail

GATEWAY="${GATEWAY:?set GATEWAY to the gateway base URL, e.g. https://<YOUR_GATEWAY_HOST>}"
CLIENT_ID="${CLIENT_ID:?set CLIENT_ID to the app client id, i.e. the credential key}"
CLIENT_SECRET="${CLIENT_SECRET:?set CLIENT_SECRET to the app client secret}"
TOKEN_PATH="${TOKEN_PATH:-/oauth/token}"
API_PATH="${API_PATH:-/orders}"
ITEM_PATH="${ITEM_PATH:-/orders/verify-probe-001}"
SEED_OK="${SEED_OK:-12}"
SEED_401="${SEED_401:-3}"
SEED_404="${SEED_404:-2}"

TOKEN_URL="${GATEWAY%/}${TOKEN_PATH}"
API_URL="${GATEWAY%/}${API_PATH}"
ITEM_URL="${GATEWAY%/}${ITEM_PATH}"
BODY_FILE="$(mktemp)"; HDR_FILE="$(mktemp)"
trap 'rm -f "$BODY_FILE" "$HDR_FILE"' EXIT

fail() { printf '\033[31mFAIL\033[0m  %s\n' "$1"; exit 1; }
pass() { printf '\033[32mPASS\033[0m  %s\n' "$1"; }
info() { printf '\033[34mNOTE\033[0m  %s\n' "$1"; }
step() { printf '\n\033[1m%s\033[0m\n' "$1"; }

START_UTC="$(date -u '+%Y-%m-%dT%H:%M:%SZ')"

echo "→ Token endpoint: $TOKEN_URL"
echo "→ Collection:     $API_URL"
echo "→ Item route:     $ITEM_URL   (exercises the templated /orders/{orderId})"
echo "→ Window starts:  $START_UTC"
echo

# --- 1: identity is enforced -------------------------------------------------
step "1. Identity is resolved (without this, analytics attributes to IP addresses)"
status="$(curl -s -o "$BODY_FILE" -w '%{http_code}' "$API_URL")"
[[ "$status" == "000" ]] && fail "could not reach ${API_URL} at all — curl got no HTTP
     response. Check GATEWAY, DNS and network reachability before anything else."
[[ "$status" == "401" ]] \
  && pass "unauthenticated → 401 (identity is actually required)" \
  || fail "unauthenticated → ${status} (expected 401). If this is 200, the route is
     unauthenticated and EVERY analytics row for it will attribute to a source IP
     rather than to an app. Per-app charts cannot be built from that. Add helix-auth
     validate before going further — see solution 01."

# --- 2: get a token ----------------------------------------------------------
step "2. Obtain a token"
status="$(curl -s -o "$BODY_FILE" -w '%{http_code}' -X POST "$TOKEN_URL" \
  -u "${CLIENT_ID}:${CLIENT_SECRET}" -H 'content-type: application/json')"
[[ "$status" == "200" ]] \
  || fail "token request → ${status} (expected 200). Body: $(tr -d '\n' < "$BODY_FILE")"
ACCESS_TOKEN="$(tr -d '\n' < "$BODY_FILE" | sed -n 's/.*"access_token"[[:space:]]*:[[:space:]]*"\([^"]*\)".*/\1/p')"
[[ -n "$ACCESS_TOKEN" ]] && pass "token issued" || fail "no access_token in the response body"

# --- 3: authenticated call, and the correlation id ---------------------------
step "3. Correlation id is present (the bridge from a chart row to one request)"
status="$(curl -s -o "$BODY_FILE" -D "$HDR_FILE" -w '%{http_code}' "$API_URL" \
  -H "authorization: Bearer ${ACCESS_TOKEN}")"
case "$status" in
  200|201) pass "authenticated → ${status}" ;;
  401) fail "authenticated → 401. The signing secret on ${TOKEN_PATH} and ${API_PATH} almost certainly differ." ;;
  403) fail "authenticated → 403. Authentication passed, authorization did not — is api-product-enforcer on this route with no subscription behind it? See solution 03." ;;
  *)   fail "authenticated → ${status} (expected 200). Body: $(tr -d '\n' < "$BODY_FILE")" ;;
esac

FIRST_ID="$(grep -i '^x-request-id:' "$HDR_FILE" | head -1 | tr -d '\r' | sed 's/^[^:]*:[[:space:]]*//')"
if [[ -n "$FIRST_ID" ]]; then
  pass "X-Request-Id present: ${FIRST_ID}"
else
  fail "no X-Request-Id on the response. Without a correlation id you can see that 3%
     of calls failed but you cannot get from that row to the failing request, or to
     the matching entry in your backend's logs. Add the request-id plugin API-wide."
fi

# --- 4: seed a known, labelled traffic pattern -------------------------------
step "4. Seed a known traffic pattern (so you have something specific to look for)"
info "seeding ${SEED_OK} successes, ${SEED_401} auth failures, ${SEED_404} not-founds…"

ok=0
for (( i=1; i<=SEED_OK; i++ )); do
  s="$(curl -s -o /dev/null -w '%{http_code}' "$API_URL" -H "authorization: Bearer ${ACCESS_TOKEN}")"
  [[ "$s" == "200" || "$s" == "201" ]] && ok=$(( ok + 1 ))
done
[[ $ok -eq $SEED_OK ]] \
  && pass "${ok}/${SEED_OK} successful calls to ${API_PATH}" \
  || info "${ok}/${SEED_OK} succeeded — the rest returned something else; adjust your expected counts below accordingly"

# The templated item route: one row in a per-route breakdown, not one row per id.
item_ok=0; item_404=0
for (( i=1; i<=SEED_404; i++ )); do
  s="$(curl -s -o /dev/null -w '%{http_code}' "$ITEM_URL" -H "authorization: Bearer ${ACCESS_TOKEN}")"
  case "$s" in
    200|201) item_ok=$(( item_ok + 1 )) ;;
    404)     item_404=$(( item_404 + 1 )) ;;
  esac
done
info "item route ${ITEM_PATH}: ${item_ok} success, ${item_404} not-found"
info "these must aggregate under /orders/{orderId} — if your per-route breakdown shows"
info "a separate row per order id, the path is not templated and route-level charts"
info "are worthless. That is the check in ../tests/test-plan.yaml case path-templating."

f401=0
for (( i=1; i<=SEED_401; i++ )); do
  s="$(curl -s -o /dev/null -w '%{http_code}' "$API_URL" \
        -H 'authorization: Bearer eyJhbGciOiJIUzI1NiJ9.eyJzdWIiOiJwcm9iZSJ9.deliberate-verify-probe-failure')"
  [[ "$s" == "401" ]] && f401=$(( f401 + 1 ))
done
[[ $f401 -eq $SEED_401 ]] \
  && pass "${f401}/${SEED_401} deliberate auth failures seeded" \
  || info "${f401}/${SEED_401} returned 401"

END_UTC="$(date -u '+%Y-%m-%dT%H:%M:%SZ')"

# --- what to do next --------------------------------------------------------
TOTAL_AUTHED=$(( ok + item_ok + item_404 ))
cat <<REPORT

$(printf '\033[32mRequest path checks passed, and a known pattern is seeded.\033[0m')

$(printf '\033[1mWindow:\033[0m') ${START_UTC} → ${END_UTC}
$(printf '\033[1mSeeded from this app:\033[0m')
  ${ok}  x  200/201  on ${API_PATH}
  ${item_ok}  x  200/201  on ${ITEM_PATH}   (must group under /orders/{orderId})
  ${item_404}  x  404      on ${ITEM_PATH}
  ${f401}  x  401      on ${API_PATH}   (deliberate — forged token)
  1  x  200      on ${TOKEN_PATH}   (the token exchange is captured too)
  1  x  401      on ${API_PATH}   (the first unauthenticated probe)

  Authenticated and attributable to this app: ${TOTAL_AUTHED}
  The ${f401} forged-token 401s and the initial unauthenticated 401 have NO app to
  attribute to — identity never resolved. Expect them in an "unidentified" bucket.

$(printf '\033[1mNOT YET VERIFIED — analytics itself.\033[0m') Capture is asynchronous and read
from the portal or the agent; no shell script can assert a chart. Do this now:

  1. Ask the agent:
       "Show me calls to <<your API>> since ${START_UTC}, broken down by app and
        route, with the status code counts."
     Expect the counts above, attributed to this app.

  2. Confirm path templating — the single most important check:
       "Show me the per-route breakdown for <<your API>> since ${START_UTC}."
     ${ITEM_PATH} must appear as /orders/{orderId}, NOT as a literal path. If you
     see a row per order id, your route-level charts are already worthless and no
     amount of querying will fix data already captured that way.

  3. Confirm correlation works end to end:
       "Find the request with X-Request-Id ${FIRST_ID}."
     Then check the SAME id appears in your backend's own logs for that call. If it
     does not, your teams are not logging the forwarded header, and you can correlate
     the gateway with itself and nothing else.

  4. Confirm the 401s land in an unidentified bucket rather than being silently
     dropped or misattributed.

  Then record what you actually observed in ../validation/gateway-validation.yaml.
  Analytics is verified by observation, never by assertion — see ../charts.md for the
  full catalogue of questions worth asking.
REPORT
