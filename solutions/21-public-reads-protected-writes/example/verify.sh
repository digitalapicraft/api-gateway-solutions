#!/usr/bin/env bash
# Solution 21 — proof that the catalogue is open to read and closed to write.
#
# Exits 0 only if ALL of the following hold:
#    1. GET  /catalog/items, no key                 → 200
#    2. GET  /catalog/items/1, no key               → 200
#    3. POST /catalog/items, no key                 → 401 "Missing API key in request"
#    4. PUT  /catalog/items/1, no key               → 401
#    5. DELETE /catalog/items/1, no key             → 401
#    6. POST with an unknown key                    → 401 "Invalid API key in request"
#    7. PUT  with an unknown key                    → 401
#    8. DELETE with an unknown key                  → 401
#    9. POST with the partner app's key             → 201
#   10. PUT  with the partner app's key             → 200
#   11. DELETE with the partner app's key           → 200
#   12. GET  /catalog/items/1 WITH the key          → 200 (a key never hurts a read)
#   13. GET  /catalog/items/1 with an unknown key   → 200 (reads never look at the key)
#   14. PATCH /catalog/items/1, no key              → 404 (no route for that method)
#
# Cases 1-2 and 3-5 are the point. If 1 or 2 returns 401, the key check is on
# the whole API instead of the write routes, and the public can't read. If any
# of 3-5 returns a 2xx, that write is open to anyone.
#
# Case 14 shows that "open reads" is not "open everything": a method the API
# does not list has no route at all.
#
# The sample backend (jsonplaceholder) accepts writes and answers as if it
# stored them, but stores nothing, so running this changes no data.
#
# Usage:
#   GATEWAY=https://<YOUR_GATEWAY_HOST> \
#   API_KEY=<PARTNER_API_KEY> \
#   ./verify.sh
#
# Optional overrides:
#   ITEM_ID      default 1
#   BASE_PATH    default /catalog/items
#   KEY_HEADER   default X-Api-Key

set -uo pipefail

GATEWAY="${GATEWAY:?set GATEWAY to the gateway base URL, e.g. https://<YOUR_GATEWAY_HOST>}"
API_KEY="${API_KEY:?set API_KEY to the credential key of a partner app}"
ITEM_ID="${ITEM_ID:-1}"
BASE_PATH="${BASE_PATH:-/catalog/items}"
KEY_HEADER="${KEY_HEADER:-X-Api-Key}"
UNKNOWN_KEY="00000000-not-a-real-key"

LIST_URL="${GATEWAY%/}${BASE_PATH}"
ITEM_URL="${GATEWAY%/}${BASE_PATH}/${ITEM_ID}"
BODY_FILE="$(mktemp)"
trap 'rm -f "$BODY_FILE"' EXIT

fail() { printf '\033[31mFAIL\033[0m  %s\n' "$1"; exit 1; }
pass() { printf '\033[32mPASS\033[0m  %s\n' "$1"; }

# --- expected statuses come from the fixtures, not from literals here ---------
# tests/expected/*.json is the single source of truth for what each case
# expects, so this script and the fixtures cannot drift apart. Parsed with sed,
# so verify.sh needs nothing beyond bash and curl.
FIXTURES="$(cd "$(dirname "${BASH_SOURCE[0]}")/../tests/expected" 2>/dev/null && pwd || true)"
expect() {
  local f="${FIXTURES:-}/$1" v=""
  [ -n "${FIXTURES:-}" ] && [ -f "$f" ] && \
    v="$(sed -n 's/.*"status"[[:space:]]*:[[:space:]]*\([0-9][0-9]*\).*/\1/p' "$f" | head -1)"
  printf '%s' "${v:-$2}"
}
EXP_LIST="$(expect read-list-200.json 200)"
EXP_ITEM="$(expect read-item-200.json 200)"
EXP_NOKEY="$(expect no-key-401.json 401)"
EXP_UNKNOWN="$(expect unknown-key-401.json 401)"
EXP_CREATE="$(expect create-201.json 201)"
EXP_UPDATE="$(expect update-200.json 200)"
EXP_DELETE="$(expect delete-200.json 200)"
EXP_NOROUTE="$(expect unlisted-method-404.json 404)"

body() { tr -d '\n' < "$BODY_FILE" | cut -c1-160; }

# call METHOD URL [KEY]  → prints the status; the body lands in $BODY_FILE
call() {
  local method="$1" url="$2" key="${3:-}"
  local args=(-s -o "$BODY_FILE" -w '%{http_code}' -X "$method" "$url")
  [ -n "$key" ] && args+=(-H "${KEY_HEADER}: ${key}")
  case "$method" in
    POST)  args+=(-H 'content-type: application/json' -d '{"title":"Trail running shoe","price":89.5}') ;;
    PUT)   args+=(-H 'content-type: application/json' -d "{\"id\":${ITEM_ID},\"title\":\"Trail running shoe\",\"price\":79.5}") ;;
    PATCH) args+=(-H 'content-type: application/json' -d '{"price":69.5}') ;;
  esac
  curl "${args[@]}"
}

echo "→ Catalogue:  $LIST_URL"
echo "→ Key header: $KEY_HEADER"
echo

# --- 1-2: the public can read, with no key -------------------------------------
status="$(call GET "$LIST_URL")"
[[ "$status" == "000" ]] && fail "could not reach $LIST_URL at all — curl got no HTTP response.
     Check GATEWAY, DNS and network reachability before anything else."
[[ "$status" == "$EXP_LIST" ]] \
  && pass "1  GET ${BASE_PATH}, no key → ${status}" \
  || fail "1  GET ${BASE_PATH}, no key → ${status} (expected ${EXP_LIST}). A 401 here means the key
     check is on the WHOLE API, not just the write routes. Body: $(body)"

status="$(call GET "$ITEM_URL")"
[[ "$status" == "$EXP_ITEM" ]] \
  && pass "2  GET ${BASE_PATH}/${ITEM_ID}, no key → ${status}" \
  || fail "2  GET ${BASE_PATH}/${ITEM_ID}, no key → ${status} (expected ${EXP_ITEM}). A 404 Route Not Found
     means the path parameter was stored as {itemId} instead of :itemId. Body: $(body)"

# --- 3-5: no write without a key ------------------------------------------------
n=3
for pair in "POST $LIST_URL" "PUT $ITEM_URL" "DELETE $ITEM_URL"; do
  method="${pair%% *}"; url="${pair#* }"
  status="$(call "$method" "$url")"
  [[ "$status" == "$EXP_NOKEY" ]] \
    && pass "$n  ${method} with no key → ${status} ($(body))" \
    || fail "$n  ${method} with no key → ${status} (expected ${EXP_NOKEY}). This write is open to
     anyone: the key check is missing from the ${method} route. Body: $(body)"
  n=$((n + 1))
done

# --- 6-8: no write with a key that belongs to no app ----------------------------
for pair in "POST $LIST_URL" "PUT $ITEM_URL" "DELETE $ITEM_URL"; do
  method="${pair%% *}"; url="${pair#* }"
  status="$(call "$method" "$url" "$UNKNOWN_KEY")"
  [[ "$status" == "$EXP_UNKNOWN" ]] \
    && pass "$n  ${method} with an unknown key → ${status} ($(body))" \
    || fail "$n  ${method} with an unknown key → ${status} (expected ${EXP_UNKNOWN}). If this is a 2xx
     the route is not checking keys at all. Body: $(body)"
  n=$((n + 1))
done

# --- 9-11: a partner's key opens every write ------------------------------------
status="$(call POST "$LIST_URL" "$API_KEY")"
case "$status" in
  "$EXP_CREATE") pass "9  POST with the partner's key → ${status}" ;;
  401) fail "9  POST with the partner's key → 401. The key did not match an app. Send the app's
     credential KEY (not its secret, not the app id), in the ${KEY_HEADER} header. Body: $(body)" ;;
  403) fail "9  POST with the partner's key → 403. Something besides the key check is on the route
     (for example a product check). Read the deployed revision back. Body: $(body)" ;;
  *)   fail "9  POST with the partner's key → ${status} (expected ${EXP_CREATE}). Body: $(body)" ;;
esac

status="$(call PUT "$ITEM_URL" "$API_KEY")"
[[ "$status" == "$EXP_UPDATE" ]] \
  && pass "10 PUT with the partner's key → ${status}" \
  || fail "10 PUT with the partner's key → ${status} (expected ${EXP_UPDATE}). Body: $(body)"

status="$(call DELETE "$ITEM_URL" "$API_KEY")"
[[ "$status" == "$EXP_DELETE" ]] \
  && pass "11 DELETE with the partner's key → ${status}" \
  || fail "11 DELETE with the partner's key → ${status} (expected ${EXP_DELETE}). Body: $(body)"

# --- 12-13: a key, good or bad, changes nothing on a read -----------------------
status="$(call GET "$ITEM_URL" "$API_KEY")"
[[ "$status" == "$EXP_ITEM" ]] \
  && pass "12 GET with the partner's key → ${status} (partners read like everyone else)" \
  || fail "12 GET with the partner's key → ${status} (expected ${EXP_ITEM}). Body: $(body)"

status="$(call GET "$ITEM_URL" "$UNKNOWN_KEY")"
[[ "$status" == "$EXP_ITEM" ]] \
  && pass "13 GET with an unknown key → ${status} (the read route never looks at the key)" \
  || fail "13 GET with an unknown key → ${status} (expected ${EXP_ITEM}). A 401 means a key check sits
     on the read route, so a caller with a stale key can't read what everyone else can. Body: $(body)"

# --- 14: a method the API does not list ------------------------------------------
status="$(call PATCH "$ITEM_URL")"
[[ "$status" == "$EXP_NOROUTE" ]] \
  && pass "14 PATCH (not in the API) → ${status} ($(body))" \
  || fail "14 PATCH, which the API does not list → ${status} (expected ${EXP_NOROUTE}). Something
     answers a method nobody declared. Read the deployed revision back. Body: $(body)"

echo
printf '\033[32mAll 14 checks passed.\033[0m Anyone can read the catalogue; only a partner key can
add, change or remove an item.\n'
