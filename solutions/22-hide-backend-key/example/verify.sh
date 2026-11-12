#!/usr/bin/env bash
# Solution 22 — proof that the supplier's key stays at the gateway.
#
# Exits 0 only if ALL of the following hold:
#   1. No key                      → 401 "Missing API key in request"
#   2. An unknown key              → 401 "Invalid API key in request"
#   3. A valid app key             → 200, the supplier answered
#   4. The supplier got its key    → X-Supplier-Key reached the backend with the
#                                    value you configured
#   5. The supplier did NOT get    → no X-Api-Key reached the backend
#      the client's own key
#   6. A client cannot choose the  → a client that sends its own X-Supplier-Key
#      supplier key                  gets 200 and the backend still sees only the
#                                    configured value
#   7. No response header carries  → the supplier's key is not in any header the
#      the supplier's key            client receives
#
# Cases 4-6 read what the backend received, so they need a backend that echoes
# the request back: postman-echo.com, as in the example. postman-echo also echoes
# the supplier's key in the response BODY, so a client of THIS test setup can
# read it there. A real supplier does not echo its key back; with one, run cases
# 4-6 once against the echo upstream, then switch the upstream.
#
# Usage:
#   GATEWAY=https://<YOUR_GATEWAY_HOST> \
#   API_KEY=<APP_API_KEY> \
#   SUPPLIER_KEY=<SUPPLIER_API_KEY> \
#   ./verify.sh
#
#   API_KEY       the app's key (the credential KEY, not its secret or its id)
#   SUPPLIER_KEY  the value you put in place of <SUPPLIER_API_KEY> in the spec
#
# Optional overrides:
#   FORECAST_PATH    default /forecast
#   KEY_HEADER       default X-Api-Key
#   SUPPLIER_HEADER  default X-Supplier-Key
#
# Needs only bash and curl (bash 3.2 is fine).

set -uo pipefail

GATEWAY="${GATEWAY:?set GATEWAY to the gateway base URL, e.g. https://<YOUR_GATEWAY_HOST>}"
API_KEY="${API_KEY:?set API_KEY to the key of your app (the credential key)}"
SUPPLIER_KEY="${SUPPLIER_KEY:?set SUPPLIER_KEY to the supplier key value configured on the route}"
FORECAST_PATH="${FORECAST_PATH:-/forecast}"
KEY_HEADER="${KEY_HEADER:-X-Api-Key}"
SUPPLIER_HEADER="${SUPPLIER_HEADER:-X-Supplier-Key}"

URL="${GATEWAY%/}${FORECAST_PATH}"
BODY_FILE="$(mktemp)"
HEAD_FILE="$(mktemp)"
trap 'rm -f "$BODY_FILE" "$HEAD_FILE"' EXIT

fail() { printf '\033[31mFAIL\033[0m  %s\n' "$1"; exit 1; }
pass() { printf '\033[32mPASS\033[0m  %s\n' "$1"; }

# --- expected statuses come from the fixtures, not from literals here ---------
# tests/expected/*.json is the single source of truth for what each case expects,
# so this script and the fixtures cannot drift apart.
FIXTURES="$(cd "$(dirname "${BASH_SOURCE[0]}")/../tests/expected" 2>/dev/null && pwd || true)"
expect() {
  local f="${FIXTURES:-}/$1" v=""
  [ -n "${FIXTURES:-}" ] && [ -f "$f" ] && \
    v="$(sed -n 's/.*"status"[[:space:]]*:[[:space:]]*\([0-9][0-9]*\).*/\1/p' "$f" | head -1)"
  printf '%s' "${v:-$2}"
}
EXP_NOKEY="$(expect no-key-401.json 401)"
EXP_UNKNOWN="$(expect unknown-key-401.json 401)"
EXP_VALID="$(expect valid-200.json 200)"

body() { tr -d '\n' < "$BODY_FILE"; }
lower() { printf '%s' "$1" | tr 'A-Z' 'a-z'; }

# The value of one header as the backend saw it, read from the echoed JSON body.
# Header names are matched without regard to case: echo services differ.
echoed() {
  local name; name="$(lower "$1")"
  tr -d '\n' < "$BODY_FILE" \
    | grep -io "\"${name}\"[[:space:]]*:[[:space:]]*\"[^\"]*\"" \
    | head -1 \
    | sed 's/^"[^"]*"[[:space:]]*:[[:space:]]*"\(.*\)"$/\1/'
}

echo "→ Route:            $URL"
echo "→ Client key in:    $KEY_HEADER"
echo "→ Supplier key in:  $SUPPLIER_HEADER"
echo

# --- 1: no key ---------------------------------------------------------------
status="$(curl -s -o "$BODY_FILE" -w '%{http_code}' "$URL")"
[[ "$status" == "000" ]] && fail "could not reach $URL at all. Check GATEWAY, DNS and network first."
[[ "$status" == "$EXP_NOKEY" ]] \
  && pass "no key → ${status} ($(body))" \
  || fail "no key → ${status} (expected ${EXP_NOKEY}). Is the key check (helix-auth) on this API?"

# --- 2: unknown key ----------------------------------------------------------
status="$(curl -s -o "$BODY_FILE" -w '%{http_code}' "$URL" -H "${KEY_HEADER}: 00000000-not-a-real-key")"
[[ "$status" == "$EXP_UNKNOWN" ]] \
  && pass "unknown key → ${status} ($(body))" \
  || fail "unknown key → ${status} (expected ${EXP_UNKNOWN}). A 200 here means the route checks no key at all."

# --- 3: valid key ------------------------------------------------------------
status="$(curl -s -D "$HEAD_FILE" -o "$BODY_FILE" -w '%{http_code}' "${URL}?city=London" \
  -H "${KEY_HEADER}: ${API_KEY}")"
case "$status" in
  "$EXP_VALID") pass "valid key → ${status} (the supplier answered)" ;;
  401) fail "valid key → 401. The key did not match an app. Send the app's credential KEY,
     not its secret or its id, in ${KEY_HEADER}." ;;
  502|503|504) fail "valid key → ${status}. The key check passed but the supplier could not be reached.
     Check the upstream linked to the API." ;;
  *) fail "valid key → ${status} (expected ${EXP_VALID}). Body: $(body)" ;;
esac

if ! grep -qi '"headers"[[:space:]]*:' "$BODY_FILE"; then
  fail "the backend did not echo the request headers, so cases 4-6 cannot see what it received.
     Run this against an echo upstream (postman-echo.com) first."
fi

# --- 4: the supplier got its key --------------------------------------------
got="$(echoed "$SUPPLIER_HEADER")"
if [[ "$got" == "$SUPPLIER_KEY" ]]; then
  pass "the backend received ${SUPPLIER_HEADER} with the configured value"
elif [[ -z "$got" ]]; then
  fail "the backend received no ${SUPPLIER_HEADER}. proxy-rewrite headers.set is missing on this route,
     or its value is a \${...} reference, which the gateway reads as an empty variable."
elif [[ "$got" == *"<"* ]]; then
  fail "the backend received ${SUPPLIER_HEADER}: ${got}. That is a placeholder or a reference, stored as
     text. The gateway reads no environment variables: put the literal key in the route's config."
else
  fail "the backend received ${SUPPLIER_HEADER} with a different value than SUPPLIER_KEY.
     Check the value on the route, and check SUPPLIER_KEY. A \$ in the key starts a gateway
     variable, which shortens what the supplier receives."
fi

# --- 5: the supplier did NOT get the client's key ---------------------------
if grep -qi "\"$(lower "$KEY_HEADER")\"[[:space:]]*:" "$BODY_FILE"; then
  fail "the backend received the client's ${KEY_HEADER}. Add it to proxy-rewrite headers.remove."
fi
pass "the backend did not receive the client's ${KEY_HEADER}"

# --- 6: a client cannot choose the supplier key ------------------------------
status="$(curl -s -o "$BODY_FILE" -w '%{http_code}' "$URL" \
  -H "${KEY_HEADER}: ${API_KEY}" -H "${SUPPLIER_HEADER}: client-chosen-value")"
got="$(echoed "$SUPPLIER_HEADER")"
if [[ "$status" == "$EXP_VALID" && "$got" == "$SUPPLIER_KEY" ]] \
   && ! grep -q 'client-chosen-value' "$BODY_FILE"; then
  pass "a client's own ${SUPPLIER_HEADER} is replaced → ${status}, the backend saw only the configured value"
else
  fail "a client-sent ${SUPPLIER_HEADER} → ${status}, the backend saw: ${got:-nothing}. Use headers.set
     (which replaces), not headers.add (which keeps the client's value as well)."
fi

# --- 7: no response header carries the supplier key -------------------------
if grep -qF "$SUPPLIER_KEY" "$HEAD_FILE"; then
  fail "a response header the client received contains the supplier's key."
fi
pass "no response header carries the supplier's key"

echo
printf '\033[32mAll checks passed.\033[0m Clients are checked with their own keys, the supplier gets
only its own key, and no client key reaches it.\n'
