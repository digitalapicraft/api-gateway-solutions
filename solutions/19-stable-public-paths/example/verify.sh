#!/usr/bin/env bash
# Solution 19 — proof that the public paths are a contract: each one returns the
# backend's data for the right resource, the query string passes through, and
# nothing outside the contract is reachable through the gateway.
#
# Exits 0 only if ALL of the following hold:
#   1. GET /v1/customers                    → 200, 10 customers, X-Request-Id set
#   2. GET /v1/customers?_limit=2           → 200, exactly 2 customers: the query
#                                             string is kept through "uri"
#   3. GET /v1/customers/3                  → 200, customer 3: the id is carried
#                                             through "regex_uri"
#   4. GET /v1/customers/1/orders           → 200, 20 orders, every one customer 1's
#   5. GET /v1/customers/1/orders?_limit=3  → 200, exactly 3, all customer 1's: the
#                                             query string is kept through "regex_uri"
#   6. GET /v1/customers/1/orders?userId=2  → 200, still only customer 1's orders:
#                                             an added parameter doesn't widen the list
#   7. GET /v1/customers/999                → 404 from the BACKEND, passed through
#   8. GET /v1/accounts                     → 404 Route Not Found from the GATEWAY:
#                                             not part of the contract
#   9. the backend's own paths              → 404 Route Not Found: /users, /users/1
#                                             and /users/1/todos have no route
#  10. /v1/customers/../../users/1/todos    → 404 Route Not Found: a "..", sent
#                                             as-is, can't climb out of the contract
#
# Case 6 holds because the id travels in the backend's PATH (/users/1/todos), and
# this backend takes the id from the path. If the backend moves the id into its
# query string (/todos?userId=1), the caller's ?userId=2 is added after it and
# case 6 fails. That is the point of running this again after every backend move.
#
# Usage:
#   GATEWAY=https://<YOUR_GATEWAY_HOST> ./verify.sh
#
# Optional:
#   BACKEND_PATHS  the backend paths case 9 proves unreachable, separated by
#                  spaces (default "/users /users/1 /users/1/todos"). Change it if
#                  another API in the same environment serves one of them.
#
# Needs bash, curl and jq.

set -uo pipefail

GATEWAY="${GATEWAY:?set GATEWAY to the gateway base URL, e.g. https://<YOUR_GATEWAY_HOST>}"
BACKEND_PATHS="${BACKEND_PATHS:-/users /users/1 /users/1/todos}"
command -v jq >/dev/null || { echo "verify.sh needs jq"; exit 1; }

GW="${GATEWAY%/}"
BODY="$(mktemp)"; HDRS="$(mktemp)"
trap 'rm -f "$BODY" "$HDRS"' EXIT

fail() { printf '\033[31mFAIL\033[0m  %s\n' "$1"; exit 1; }
pass() { printf '\033[32mPASS\033[0m  %s\n' "$1"; }

# --- expected statuses come from the fixtures, not from literals here ---------
FIXTURES="$(cd "$(dirname "${BASH_SOURCE[0]}")/../tests/expected" 2>/dev/null && pwd || true)"
expect() {
  local f="${FIXTURES:-}/$1" v=""
  [ -n "${FIXTURES:-}" ] && [ -f "$f" ] && \
    v="$(sed -n 's/.*"status"[[:space:]]*:[[:space:]]*\([0-9][0-9]*\).*/\1/p' "$f" | head -1)"
  printf '%s' "${v:-$2}"
}
EXP_LIST="$(expect list-customers-200.json 200)"
EXP_LIMITED="$(expect list-limited-200.json 200)"
EXP_ONE="$(expect get-customer-200.json 200)"
EXP_ORDERS="$(expect customer-orders-200.json 200)"
EXP_ORDERS_LIMITED="$(expect orders-limited-200.json 200)"
EXP_BACKEND_404="$(expect unknown-customer-404.json 404)"
EXP_NO_ROUTE="$(expect route-not-found-404.json 404)"

# get PATH → sets CODE; body in $BODY, headers in $HDRS. --path-as-is keeps
# "../" in the path exactly as written, so case 10 tests the gateway, not curl.
get() { CODE="$(curl -s --path-as-is -o "$BODY" -D "$HDRS" -w '%{http_code}' "${GW}$1")"; }
body_is() { jq -e "$1" "$BODY" >/dev/null 2>&1; }
short()   { tr -d '\n' < "$BODY" | cut -c1-160; }
no_route() { # $1 path → the gateway's own 404: no route serves this path
  get "$1"
  [[ "$CODE" == "$EXP_NO_ROUTE" ]] && grep -q 'Route Not Found' "$BODY"
}

# --- 1: the list -------------------------------------------------------------
get /v1/customers
case "$CODE" in
  "$EXP_LIST") ;;
  000) fail "could not reach ${GW} at all. Check GATEWAY." ;;
  404) fail "GET /v1/customers → 404 ($(short)). \"Route Not Found\" means the API isn't
     deployed in this environment; {} means the rewrite didn't run and the backend
     was asked for /v1/customers." ;;
  *)   fail "GET /v1/customers → ${CODE}, expected ${EXP_LIST}. Body: $(short)" ;;
esac
body_is 'type == "array" and length == 10 and .[0].id == 1 and (.[0].email | type) == "string"' \
  || fail "GET /v1/customers → 200 but not the customer list: $(short)"
grep -qi '^x-request-id:' "$HDRS" || fail "GET /v1/customers has no X-Request-Id header. Is request-id on the API?"
pass "GET /v1/customers → ${CODE}, 10 customers from the backend's /users, X-Request-Id set"

# --- 2: query string through "uri" -------------------------------------------
get '/v1/customers?_limit=2'
[[ "$CODE" == "$EXP_LIMITED" ]] || fail "GET /v1/customers?_limit=2 → ${CODE}, expected ${EXP_LIMITED}."
body_is 'type == "array" and length == 2 and .[0].id == 1 and .[1].id == 2' \
  || fail "GET /v1/customers?_limit=2 → $(jq -r 'length' "$BODY" 2>/dev/null) customers, expected 2.
     The query string did not reach the backend."
pass "GET /v1/customers?_limit=2 → ${CODE}, exactly 2: the query string was kept"

# --- 3: the id is carried ----------------------------------------------------
get /v1/customers/3
[[ "$CODE" == "$EXP_ONE" ]] || fail "GET /v1/customers/3 → ${CODE}, expected ${EXP_ONE}. Body: $(short)"
body_is '.id == 3 and .username == "Samantha"' \
  || fail "GET /v1/customers/3 returned a different record: $(jq -c '{id, username}' "$BODY" 2>/dev/null).
     A fixed \"uri\" sends every caller to the same record; the route needs \"regex_uri\"."
pass "GET /v1/customers/3 → ${CODE}, customer 3 (Samantha)"

# --- 4: one level deeper -----------------------------------------------------
get /v1/customers/1/orders
[[ "$CODE" == "$EXP_ORDERS" ]] || fail "GET /v1/customers/1/orders → ${CODE}, expected ${EXP_ORDERS}. Body: $(short)"
body_is 'type == "array" and length == 20 and all(.[]; .userId == 1)' \
  || fail "GET /v1/customers/1/orders is not customer 1's 20 orders: $(short)"
pass "GET /v1/customers/1/orders → ${CODE}, 20 orders, all customer 1's"

# --- 5: query string through "regex_uri" -------------------------------------
get '/v1/customers/1/orders?_limit=3'
[[ "$CODE" == "$EXP_ORDERS_LIMITED" ]] || fail "GET /v1/customers/1/orders?_limit=3 → ${CODE}, expected ${EXP_ORDERS_LIMITED}."
body_is 'type == "array" and length == 3 and all(.[]; .userId == 1)' \
  || fail "GET /v1/customers/1/orders?_limit=3 → $(jq -r 'length' "$BODY" 2>/dev/null) orders, expected 3 of customer 1's."
pass "GET /v1/customers/1/orders?_limit=3 → ${CODE}, exactly 3: the query string was kept"

# --- 6: an added parameter doesn't widen the list ----------------------------
get '/v1/customers/1/orders?userId=2'
[[ "$CODE" == "$EXP_ORDERS" ]] || fail "GET /v1/customers/1/orders?userId=2 → ${CODE}, expected ${EXP_ORDERS}."
body_is 'type == "array" and length > 0 and all(.[]; .userId == 1)' \
  || fail "GET /v1/customers/1/orders?userId=2 returned other customers' orders:
     users $(jq -c '[.[].userId] | unique' "$BODY" 2>/dev/null). The rewrite target carries the id in its
     query string, so the caller's ?userId=2 was added after it. See the guides,
     \"The backend moved\"."
pass "GET /v1/customers/1/orders?userId=2 → ${CODE}, still only customer 1's orders"

# --- 7: the backend's own 404 ------------------------------------------------
get /v1/customers/999
[[ "$CODE" == "$EXP_BACKEND_404" ]] || fail "GET /v1/customers/999 → ${CODE}, expected ${EXP_BACKEND_404}."
grep -q 'Route Not Found' "$BODY" && fail "GET /v1/customers/999 → the gateway's Route Not Found, expected the
     backend's own 404. The route for /v1/customers/:customerId is missing."
pass "GET /v1/customers/999 → ${CODE} from the backend (no such customer), passed through"

# --- 8: outside the contract -------------------------------------------------
no_route /v1/accounts \
  && pass "GET /v1/accounts → ${CODE} Route Not Found: not part of the contract" \
  || fail "GET /v1/accounts → ${CODE}, expected the gateway's ${EXP_NO_ROUTE} Route Not Found. Body: $(short)"

# --- 9: the backend's own paths are not reachable ----------------------------
for p in $BACKEND_PATHS; do
  no_route "$p" || fail "GET ${p} → ${CODE}, expected the gateway's ${EXP_NO_ROUTE} Route Not Found.
     A route serves the backend's own path. If it belongs to another API in this
     environment, leave it out with BACKEND_PATHS. Body: $(short)"
done
pass "the backend's own paths (${BACKEND_PATHS}) → ${EXP_NO_ROUTE} Route Not Found"

# --- 10: "../" can't climb out of the contract -------------------------------
no_route /v1/customers/../../users/1/todos \
  && pass "GET /v1/customers/../../users/1/todos → ${CODE} Route Not Found" \
  || fail "GET /v1/customers/../../users/1/todos → ${CODE}, expected ${EXP_NO_ROUTE} Route Not Found. Body: $(short)"

echo
printf '\033[32mAll checks passed.\033[0m Callers reach the backend only through the public contract.\n'
