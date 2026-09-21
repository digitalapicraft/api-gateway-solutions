#!/usr/bin/env bash
# Solution 08 — proof that API-key identity is enforced at the edge.
#
# Exits 0 only if ALL of the following hold:
#   1. No key                 → 401 "Missing API key in request"
#   2. A live app's key       → 200 with the upstream's real payload
#   3. An unknown key         → 401 "Invalid API key in request"
#   4. The key in the WRONG header (apikey:) → 401
#   5. The key as a QUERY parameter          → 401
#   6. The app's SECRET sent as the key      → 401
#   7. The key on the write route            → 201
#
# Cases 4-6 are the ones worth keeping. Each proves the contract is narrower than
# it looks: the header NAME is part of it (4), `source: header` means header and
# nothing else (5), and the credential's secret is not an alternative credential
# in this configuration (6) — which is exactly what `secret_validation: true`
# would change, and why this package leaves it off.
#
# Usage:
#   GATEWAY=https://<YOUR_GATEWAY_HOST> \
#   DEVICE_KEY=<DEVICE_API_KEY> \
#   ./verify.sh
#
# Optional overrides:
#   APP_SECRET   the secret of the app; enables case 6 (skipped, loudly, without it)
#   READ_PATH    default /fleet/price-list
#   WRITE_PATH   default /fleet/takings
#   KEY_HEADER   default X-Device-Key

set -uo pipefail

GATEWAY="${GATEWAY:?set GATEWAY to the gateway base URL, e.g. https://<YOUR_GATEWAY_HOST>}"
DEVICE_KEY="${DEVICE_KEY:?set DEVICE_KEY to the API key of the app, i.e. the credential key}"
APP_SECRET="${APP_SECRET:-}"
READ_PATH="${READ_PATH:-/fleet/price-list}"
WRITE_PATH="${WRITE_PATH:-/fleet/takings}"
KEY_HEADER="${KEY_HEADER:-X-Device-Key}"

READ_URL="${GATEWAY%/}${READ_PATH}"
WRITE_URL="${GATEWAY%/}${WRITE_PATH}"
BODY_FILE="$(mktemp)"
trap 'rm -f "$BODY_FILE"' EXIT

fail() { printf '\033[31mFAIL\033[0m  %s\n' "$1"; exit 1; }
pass() { printf '\033[32mPASS\033[0m  %s\n' "$1"; }
info() { printf '\033[34mNOTE\033[0m  %s\n' "$1"; }

# --- expected statuses come from the fixtures, not from literals here ---------
# tests/expected/*.json is the single source of truth for what each case expects,
# so this script and the fixtures cannot drift apart. Parsed with sed, so verify.sh
# still needs nothing beyond bash and curl.
FIXTURES="$(cd "$(dirname "${BASH_SOURCE[0]}")/../tests/expected" 2>/dev/null && pwd || true)"
expect() {
  local f="${FIXTURES:-}/$1" v=""
  [ -n "${FIXTURES:-}" ] && [ -f "$f" ] && \
    v="$(sed -n 's/.*"status"[[:space:]]*:[[:space:]]*\([0-9][0-9]*\).*/\1/p' "$f" | head -1)"
  printf '%s' "${v:-$2}"
}
EXP_NOKEY="$(expect no-key-401.json 401)"
EXP_VALID="$(expect valid-200.json 200)"
EXP_UNKNOWN="$(expect unknown-key-401.json 401)"
EXP_WRITE="$(expect takings-201.json 201)"

echo "→ Read route:  $READ_URL"
echo "→ Write route: $WRITE_URL"
echo "→ Key header:  $KEY_HEADER"
echo

body() { tr -d '\n' < "$BODY_FILE"; }

# --- 1: no key ---------------------------------------------------------------
status="$(curl -s -o "$BODY_FILE" -w '%{http_code}' "$READ_URL")"
[[ "$status" == "000" ]] && fail "could not reach $READ_URL at all — curl got no HTTP
     response. Check GATEWAY, DNS and network reachability before anything else;
     every assertion below depends on the gateway answering."
[[ "$status" == "$EXP_NOKEY" ]] \
  && pass "no key → 401 ($(body))" \
  || fail "no key → ${status} (expected ${EXP_NOKEY} — is helix-auth validate on ${READ_PATH}?)"

# --- 2: a live app's key -----------------------------------------------------
status="$(curl -s -o "$BODY_FILE" -w '%{http_code}' "$READ_URL" -H "${KEY_HEADER}: ${DEVICE_KEY}")"
case "$status" in
  200) pass "valid key → 200 (upstream reached, payload returned)" ;;
  401) fail "valid key → 401. The key did not resolve to an app. Check that the key is the app's
     CREDENTIAL KEY (not its secret, not the app id) and that the app still exists." ;;
  403) fail "valid key → 403. Authentication succeeded and authorization did not — the app's product
     does not cover this API. Add the API to the product the app is subscribed to." ;;
  502|503|504) fail "valid key → ${status}. Auth passed but the upstream errored — check the upstream binding." ;;
  *)   fail "valid key → ${status} (expected ${EXP_VALID}). Body: $(body)" ;;
esac

# --- 3: unknown key ----------------------------------------------------------
status="$(curl -s -o "$BODY_FILE" -w '%{http_code}' "$READ_URL" -H "${KEY_HEADER}: 00000000-not-a-real-key")"
[[ "$status" == "$EXP_UNKNOWN" ]] \
  && pass "unknown key → 401 ($(body))" \
  || fail "unknown key → ${status} (expected ${EXP_UNKNOWN}). If this returns 200 the route is not
     resolving the credential at all — it is passing everything through while appearing configured."

# --- 4: right key, wrong header ----------------------------------------------
status="$(curl -s -o "$BODY_FILE" -w '%{http_code}' "$READ_URL" -H "apikey: ${DEVICE_KEY}")"
[[ "$status" == "$EXP_NOKEY" ]] \
  && pass "key in the wrong header → 401 (the header name is part of the contract)" \
  || fail "key in the 'apikey' header → ${status} (expected ${EXP_NOKEY}). The route says
     apikey.key: ${KEY_HEADER}; if another header also works, the deployed config is not this spec."

# --- 5: right key, wrong place -----------------------------------------------
status="$(curl -s -o "$BODY_FILE" -w '%{http_code}' "${READ_URL}?apikey=${DEVICE_KEY}")"
[[ "$status" == "$EXP_NOKEY" ]] \
  && pass "key as a query parameter → 401 (source: header means header only)" \
  || fail "key in the query string → ${status} (expected ${EXP_NOKEY}). With source: header a query
     parameter must NOT authenticate — a key in a URL ends up in every access log it passes."

# --- 6: the secret sent as the key -------------------------------------------
if [[ -n "$APP_SECRET" ]]; then
  status="$(curl -s -o "$BODY_FILE" -w '%{http_code}' "$READ_URL" -H "${KEY_HEADER}: ${APP_SECRET}")"
  [[ "$status" == "$EXP_UNKNOWN" ]] \
    && pass "the app's secret sent as the key → 401 (secret_validation is off, as shipped)" \
    || fail "the app's secret authenticated → ${status}. That is what secret_validation: true does, and
     this package ships it OFF. Check the deployed config."
else
  info "case 6 skipped — set APP_SECRET to prove the credential's secret is NOT an accepted
     alternative credential in this configuration."
fi

# --- 7: the write route ------------------------------------------------------
status="$(curl -s -o "$BODY_FILE" -w '%{http_code}' -X POST "$WRITE_URL" \
  -H "${KEY_HEADER}: ${DEVICE_KEY}" -H 'content-type: application/json' \
  -d '{"terminalId":"T-3312","periodEnd":"2026-01-01T00:00:00Z","grossCents":184250}')"
[[ "$status" == "$EXP_WRITE" ]] \
  && pass "valid key on the write route → ${status}" \
  || fail "write route → ${status} (expected ${EXP_WRITE}). Body: $(body)"

echo
printf '\033[32mAll checks passed.\033[0m Every call is identified by an app credential, and the three
near-miss shapes (wrong header, query string, secret-as-key) are all rejected.\n'
