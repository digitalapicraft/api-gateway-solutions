#!/usr/bin/env bash
# Solution 02 — proof that a SOAP/XML backend is being served as REST/JSON.
#
# Exits 0 only if ALL of the following hold:
#   1. No token           → POST /locations returns 401 (rejected before transform)
#   2. Client credentials → POST /oauth/token returns 200 with an access_token
#   3. Valid token        → POST /locations returns 200 AND a JSON content-type
#                           AND a body that parses as JSON
#   4. Valid token        → the response body contains no XML markers, i.e. the
#                           upstream XML was actually converted rather than
#                           passed through with a rewritten header
#   5. Bad token          → POST /locations returns 401
#
# Case 4 is the one that matters and the one people skip. A content-type header
# says what the gateway CLAIMS; a body with no angle brackets is what proves the
# transform ran. Setting content-type: application/json on unconverted XML is a
# real and easy misconfiguration, and it passes a naive check.
#
# Usage:
#   GATEWAY=https://<YOUR_GATEWAY_HOST> \
#   CLIENT_ID=<CLIENT_ID> \
#   CLIENT_SECRET=<CLIENT_SECRET> \
#   ./verify.sh
#
# Optional overrides:
#   TOKEN_PATH   default /oauth/token
#   API_PATH     default /locations
#   REQ_BODY     default {} — set to a real query body if your handler needs one

set -uo pipefail

GATEWAY="${GATEWAY:?set GATEWAY to the gateway base URL, e.g. https://<YOUR_GATEWAY_HOST>}"
CLIENT_ID="${CLIENT_ID:?set CLIENT_ID to the app client id, i.e. the credential key}"
CLIENT_SECRET="${CLIENT_SECRET:?set CLIENT_SECRET to the app client secret}"
TOKEN_PATH="${TOKEN_PATH:-/oauth/token}"
API_PATH="${API_PATH:-/locations}"
REQ_BODY="${REQ_BODY:-{\}}"

TOKEN_URL="${GATEWAY%/}${TOKEN_PATH}"
API_URL="${GATEWAY%/}${API_PATH}"
BODY_FILE="$(mktemp)"; HDR_FILE="$(mktemp)"
trap 'rm -f "$BODY_FILE" "$HDR_FILE"' EXIT

fail() { printf '\033[31mFAIL\033[0m  %s\n' "$1"; exit 1; }
pass() { printf '\033[32mPASS\033[0m  %s\n' "$1"; }
info() { printf '\033[34mNOTE\033[0m  %s\n' "$1"; }

echo "→ Token endpoint: $TOKEN_URL"
echo "→ Mediated API:   $API_URL"
echo "→ Request body:   $REQ_BODY"
echo

# --- 1: no token -------------------------------------------------------------
status="$(curl -s -o "$BODY_FILE" -w '%{http_code}' -X POST "$API_URL" \
  -H 'content-type: application/json' -d "$REQ_BODY")"
[[ "$status" == "000" ]] && fail "could not reach $API_URL at all — curl got no HTTP
     response. Check GATEWAY, DNS and network reachability before anything else;
     every assertion below depends on the gateway answering."
[[ "$status" == "401" ]] \
  && pass "no token → 401 (rejected in the access phase, before any transform work)" \
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

# --- 3: valid token, transformed response ------------------------------------
echo
status="$(curl -s -o "$BODY_FILE" -D "$HDR_FILE" -w '%{http_code}' -X POST "$API_URL" \
  -H "authorization: Bearer ${ACCESS_TOKEN}" \
  -H 'content-type: application/json' -d "$REQ_BODY")"
case "$status" in
  200) pass "valid token → 200" ;;
  401) fail "valid token → 401. The signing secret on ${TOKEN_PATH} and ${API_PATH} almost certainly differ." ;;
  415) fail "valid token → 415. The SOAP handler rejected the content type — check proxy-rewrite sets Content-Type: text/xml, and whether your handler also needs a SOAPAction header." ;;
  500) fail "valid token → 500. The handler was reached but errored. Very often a missing SOAPAction header, or a request body whose element names don't match what the handler reads. Try REQ_BODY with the real query fields." ;;
  502|503) fail "valid token → ${status}. The SOAP upstream was unreachable — check the upstream binding and that the handler path exists." ;;
  504) fail "valid token → 504. The SOAP backend didn't answer in time. Legacy handlers are often slow; consider whether the gateway timeout needs raising." ;;
  *)   fail "valid token → ${status} (expected 200). Body: $(tr -d '\n' < "$BODY_FILE")" ;;
esac

if grep -qi '^content-type:.*application/json' "$HDR_FILE"; then
  pass "response content-type is application/json"
else
  ct="$(grep -i '^content-type:' "$HDR_FILE" | tr -d '\r\n')"
  fail "response is not JSON (${ct:-no content-type}). Is xml-to-json applied on ${API_PATH}, and did the upstream actually return XML?"
fi

# --- 4: the body is REALLY converted, not just relabelled --------------------
# A content-type header is a claim. This is the evidence.
echo
if grep -qE '<[A-Za-z_?/]' "$BODY_FILE"; then
  fail "the response body still contains XML markup despite an application/json content-type.
     The transform did NOT run — something is relabelling unconverted XML.
     First 200 bytes: $(head -c 200 "$BODY_FILE")"
else
  pass "response body contains no XML markup — the upstream XML was genuinely converted"
fi

if command -v jq >/dev/null 2>&1; then
  jq -e . < "$BODY_FILE" >/dev/null 2>&1 \
    && pass "response body parses as JSON" \
    || fail "content-type says JSON but the body did not parse: $(head -c 200 "$BODY_FILE")"
  # A converted-but-empty object usually means the element names in the request
  # body didn't match what the handler reads, so it returned an empty envelope.
  if [[ "$(jq -r 'if type=="object" then (keys|length) elif type=="array" then length else 1 end' < "$BODY_FILE" 2>/dev/null)" == "0" ]]; then
    info "the JSON parsed but is empty. Usually the handler returned an empty envelope — check that REQ_BODY's field names match the elements it reads."
  fi
else
  info "jq not installed — skipped strict JSON parse (content-type and no-XML-markup checks still enforced)."
fi

# --- 5: bad token ------------------------------------------------------------
echo
status="$(curl -s -o "$BODY_FILE" -w '%{http_code}' -X POST "$API_URL" \
  -H 'authorization: Bearer eyJhbGciOiJIUzI1NiJ9.eyJzdWIiOiJmb3JnZWQifQ.not-a-valid-signature' \
  -H 'content-type: application/json' -d "$REQ_BODY")"
[[ "$status" == "401" ]] \
  && pass "forged token → 401" \
  || fail "forged token → ${status} (expected 401). A token this gateway did not sign MUST be rejected before the SOAP hop."

echo
printf '\033[32mAll checks passed.\033[0m The SOAP backend is being served as authenticated REST/JSON.\n'
