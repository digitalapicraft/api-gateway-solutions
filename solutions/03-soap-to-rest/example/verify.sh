#!/usr/bin/env bash
# Solution 03 — proof that a SOAP/XML backend is being served as REST/JSON.
#
# Exits 0 only if ALL of the following hold:
#   1. POST /locations returns 200 AND a JSON content-type
#   2. the body parses as JSON AND contains no XML markup, i.e. the upstream XML
#      was actually converted rather than passed through with a rewritten header
#
# Case 2 is the one that matters and the one people skip. A content-type header
# says what the gateway CLAIMS; a body with no angle brackets is what proves the
# transform ran. Setting content-type: application/json on unconverted XML is a
# real and easy misconfiguration, and it passes a naive check.
#
# THIS API HAS NO AUTHENTICATION. That is the package's scope, not an oversight —
# the mediation is what solution 03 is. If you have composed it with solution 02,
# this script does not exercise that layer; add the token yourself via CURL_OPTS.
#
# EVERY request below sends `accept: application/json`. This is NOT optional
# decoration: xml-to-json's response transformation is CONTENT-NEGOTIATED and does
# nothing at all unless the client advertises that it wants JSON. Verified against
# a live gateway — without the header the upstream XML passes through untouched
# with content-type text/xml. If your clients do not send Accept, they will not get
# JSON, and no amount of gateway configuration changes that.
#
# Usage:
#   GATEWAY=https://<YOUR_GATEWAY_HOST> ./verify.sh
#
# Optional overrides:
#   API_PATH     default /locations
#   REQ_BODY     default {} — set to a real query body if your handler needs one
#   CURL_OPTS    extra curl args, e.g. -H "authorization: Bearer $TOKEN" if you
#                have put solution 02 in front of this route

set -uo pipefail

GATEWAY="${GATEWAY:?set GATEWAY to the gateway base URL, e.g. https://<YOUR_GATEWAY_HOST>}"
API_PATH="${API_PATH:-/locations}"
REQ_BODY="${REQ_BODY:-\{\}}"
read -r -a CURL_EXTRA <<< "${CURL_OPTS:-}"

API_URL="${GATEWAY%/}${API_PATH}"
BODY_FILE="$(mktemp)"; HDR_FILE="$(mktemp)"
trap 'rm -f "$BODY_FILE" "$HDR_FILE"' EXIT

fail() { printf '\033[31mFAIL\033[0m  %s\n' "$1"; exit 1; }
pass() { printf '\033[32mPASS\033[0m  %s\n' "$1"; }
info() { printf '\033[34mNOTE\033[0m  %s\n' "$1"; }

# --- expected statuses come from the fixtures, not from literals here ---------
# tests/expected/*.json is the single source of truth for what each case expects,
# so this script and the fixtures cannot drift apart. Parsed with sed, so verify.sh
# still needs nothing beyond bash and curl. If a fixture is missing (someone copied
# this script on its own) the second argument is used instead.
FIXTURES="$(cd "$(dirname "${BASH_SOURCE[0]}")/../tests/expected" 2>/dev/null && pwd || true)"
expect() {
  local f="${FIXTURES:-}/$1" v=""
  [ -n "${FIXTURES:-}" ] && [ -f "$f" ] && \
    v="$(sed -n 's/.*"status"[[:space:]]*:[[:space:]]*\([0-9][0-9]*\).*/\1/p' "$f" | head -1)"
  printf '%s' "${v:-$2}"
}
EXP_VALID="$(expect locations-200.json 200)"

echo "→ Mediated API: $API_URL"
echo "→ Request body: $REQ_BODY"
echo

# --- 1: the call succeeds and comes back as JSON -----------------------------
status="$(curl -s -o "$BODY_FILE" -D "$HDR_FILE" -w '%{http_code}' -X POST "$API_URL" \
  "${CURL_EXTRA[@]}" \
  -H 'content-type: application/json' -H 'accept: application/json' -d "$REQ_BODY")"
case "$status" in
  000) fail "could not reach $API_URL at all — curl got no HTTP response. Check
     GATEWAY, DNS and network reachability before anything else; every assertion
     below depends on the gateway answering." ;;
  "$EXP_VALID") pass "POST ${API_PATH} → ${EXP_VALID}" ;;
  401|403) fail "POST ${API_PATH} → ${status}. This package ships no authentication,
     so something in front of the route is rejecting the call — if you composed it
     with solution 02, pass a token through CURL_OPTS." ;;
  415) fail "POST ${API_PATH} → 415. The SOAP handler rejected the content type.
     Do NOT 'fix' this by setting Content-Type in proxy-rewrite: it runs at
     priority 1008, xml-to-json at 997, so it would hide the JSON body from the
     request transform and the conversion would silently never fire. Check instead
     whether your handler needs a SOAPAction header, which is safe to set there." ;;
  500) fail "POST ${API_PATH} → 500. The handler was reached but errored. Very often
     a missing SOAPAction header, or a request body whose element names don't match
     what the handler reads. Try REQ_BODY with the real query fields." ;;
  502|503) fail "POST ${API_PATH} → ${status}. The SOAP upstream was unreachable —
     check the upstream binding and that the handler path exists." ;;
  504) fail "POST ${API_PATH} → 504. The SOAP backend didn't answer in time. Legacy
     handlers are often slow; consider whether the gateway timeout needs raising." ;;
  *)   fail "POST ${API_PATH} → ${status} (expected ${EXP_VALID}). Body: $(tr -d '\n' < "$BODY_FILE")" ;;
esac

if grep -qi '^content-type:.*application/json' "$HDR_FILE"; then
  pass "response content-type is application/json"
else
  ct="$(grep -i '^content-type:' "$HDR_FILE" | tr -d '\r\n')"
  fail "response is not JSON (${ct:-no content-type}). Check, in order:
     1. Is this request sending 'accept: application/json'? The transform is
        content-negotiated and is a no-op without it. This is the usual cause.
     2. Is xml-to-json applied on ${API_PATH}?
     3. Did the upstream actually return XML (one of its content_types)?"
fi

# --- 2: the body is REALLY converted, not just relabelled --------------------
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

echo
printf '\033[32mAll checks passed.\033[0m The SOAP backend is being served as REST/JSON.\n'
printf 'This API is unauthenticated — see solution 02 before partners call it.\n'
