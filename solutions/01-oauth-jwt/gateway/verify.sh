#!/usr/bin/env bash
# Solution 01 — proof of the OAuth 2.0 client-credentials flow.
#
# Exits 0 only if ALL of the following hold:
#   1. No token          → the protected route returns 401
#   2. Client creds      → POST /oauth/token returns 200 with an access_token
#   3. Valid token       → the protected route returns 200
#   4. Forged token      → the protected route returns 401
#   5. Wrong secret      → POST /oauth/token returns 401 (the secret IS checked)
#   6. Bearer omitted    → a raw token with no "Bearer " prefix returns 401
#
# Case 5 is the one people skip, and it is the one that proves you built a
# credentials flow rather than a static-key flow wearing a token's clothes.
#
# Usage:
#   GATEWAY=https://<YOUR_GATEWAY_HOST> \
#   CLIENT_ID=<CLIENT_ID> \
#   CLIENT_SECRET=<CLIENT_SECRET> \
#   ./verify.sh
#
# Optional overrides:
#   TOKEN_PATH   default /oauth/token
#   API_PATH     default /posts
#   EXPECT_TTL   if set, assert expires_in equals this value (e.g. 900)

set -uo pipefail

GATEWAY="${GATEWAY:?set GATEWAY to the gateway base URL, e.g. https://<YOUR_GATEWAY_HOST>}"
CLIENT_ID="${CLIENT_ID:?set CLIENT_ID to the app client id, i.e. the credential key}"
CLIENT_SECRET="${CLIENT_SECRET:?set CLIENT_SECRET to the app client secret}"
TOKEN_PATH="${TOKEN_PATH:-/oauth/token}"
API_PATH="${API_PATH:-/posts}"
EXPECT_TTL="${EXPECT_TTL:-}"

TOKEN_URL="${GATEWAY%/}${TOKEN_PATH}"
API_URL="${GATEWAY%/}${API_PATH}"
BODY_FILE="$(mktemp)"
trap 'rm -f "$BODY_FILE"' EXIT

fail() { printf '\033[31mFAIL\033[0m  %s\n' "$1"; exit 1; }
pass() { printf '\033[32mPASS\033[0m  %s\n' "$1"; }
info() { printf '\033[34mNOTE\033[0m  %s\n' "$1"; }

echo "→ Token endpoint: $TOKEN_URL"
echo "→ Protected API:  $API_URL"
echo

# --- 1: no token -------------------------------------------------------------
status="$(curl -s -o "$BODY_FILE" -w '%{http_code}' "$API_URL")"
[[ "$status" == "000" ]] && fail "could not reach $API_URL at all — curl got no HTTP
     response. Check GATEWAY, DNS and network reachability before anything else;
     every assertion below depends on the gateway answering."
[[ "$status" == "401" ]] \
  && pass "no token → 401 (rejected in the access phase, never reached upstream)" \
  || fail "no token → ${status} (expected 401 — is helix-auth validate on ${API_PATH}?)"

# --- 2: client-credentials exchange ------------------------------------------
echo
status="$(curl -s -o "$BODY_FILE" -w '%{http_code}' -X POST "$TOKEN_URL" \
  -u "${CLIENT_ID}:${CLIENT_SECRET}" -H 'content-type: application/json')"
[[ "$status" == "200" ]] \
  || fail "token request → ${status} (expected 200). Body: $(tr -d '\n' < "$BODY_FILE")
     Check the app's client_id/secret, and that helix-auth generate is on ${TOKEN_PATH}."

ACCESS_TOKEN="$(tr -d '\n' < "$BODY_FILE" | sed -n 's/.*"access_token"[[:space:]]*:[[:space:]]*"\([^"]*\)".*/\1/p')"
[[ -n "$ACCESS_TOKEN" ]] \
  && pass "client credentials → 200 with an access_token" \
  || fail "200 but no access_token in the body: $(tr -d '\n' < "$BODY_FILE")"

# The token must be a JWT: three base64url segments separated by dots. An opaque
# string here means something other than helix-auth generate answered.
if [[ "$ACCESS_TOKEN" =~ ^[A-Za-z0-9_-]+\.[A-Za-z0-9_-]+\.[A-Za-z0-9_-]+$ ]]; then
  pass "access_token is a well-formed JWT (three segments)"
else
  fail "access_token is not a three-segment JWT — got '${ACCESS_TOKEN:0:32}...'"
fi

TTL="$(tr -d '\n' < "$BODY_FILE" | sed -n 's/.*"expires_in"[[:space:]]*:[[:space:]]*\([0-9]*\).*/\1/p')"
if [[ -n "$EXPECT_TTL" ]]; then
  [[ "$TTL" == "$EXPECT_TTL" ]] \
    && pass "expires_in is ${TTL} as configured" \
    || fail "expires_in is ${TTL:-absent}, expected ${EXPECT_TTL} — check token_ttl on ${TOKEN_PATH}"
else
  info "expires_in = ${TTL:-absent}. Set EXPECT_TTL to assert your configured token_ttl."
fi

# --- 3: valid token ----------------------------------------------------------
echo
status="$(curl -s -o "$BODY_FILE" -w '%{http_code}' "$API_URL" \
  -H "authorization: Bearer ${ACCESS_TOKEN}")"
case "$status" in
  200|201) pass "valid token → ${status}" ;;
  401) fail "valid token → 401. The signing secret on ${TOKEN_PATH} and ${API_PATH} almost certainly differ. Both must reference the same JWT_SIGNING_SECRET." ;;
  403) fail "valid token → 403. Authentication succeeded but authorization did not — is api-product-enforcer on this route with no subscription behind it? See solution 03." ;;
  502|503|504) fail "valid token → ${status}. Auth passed but the upstream errored — check the upstream binding." ;;
  *)   fail "valid token → ${status} (expected 200). Body: $(tr -d '\n' < "$BODY_FILE")" ;;
esac

# --- 4: forged token ---------------------------------------------------------
echo
status="$(curl -s -o "$BODY_FILE" -w '%{http_code}' "$API_URL" \
  -H 'authorization: Bearer eyJhbGciOiJIUzI1NiJ9.eyJzdWIiOiJmb3JnZWQifQ.not-a-valid-signature')"
[[ "$status" == "401" ]] \
  && pass "forged token → 401 (signature is actually verified)" \
  || fail "forged token → ${status} (expected 401). A token this gateway did not sign MUST be rejected. If this returns 200 the route is not validating at all."

# --- 5: wrong secret ---------------------------------------------------------
echo
status="$(curl -s -o "$BODY_FILE" -w '%{http_code}' -X POST "$TOKEN_URL" \
  -u "${CLIENT_ID}:definitely-not-the-secret" -H 'content-type: application/json')"
[[ "$status" == "401" ]] \
  && pass "wrong client_secret → 401 (the secret is verified, not just the id)" \
  || fail "wrong client_secret → ${status} (expected 401). If a bad secret still issues a token, this is a static-key flow, not a credentials flow."

# --- 6: malformed authorization header ---------------------------------------
echo
status="$(curl -s -o "$BODY_FILE" -w '%{http_code}' "$API_URL" \
  -H "authorization: ${ACCESS_TOKEN}")"
[[ "$status" == "401" ]] \
  && pass "token without the Bearer prefix → 401" \
  || fail "token without the Bearer prefix → ${status} (expected 401)."

echo
printf '\033[32mAll checks passed.\033[0m The OAuth 2.0 client-credentials flow is enforced at the gateway.\n'
