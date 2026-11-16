#!/usr/bin/env bash
# Solution 20 — proof that every response leaves the gateway with the security
# headers set, the stack's name removed, and the data untouched.
#
# Exits 0 only if ALL of the following hold:
#   1. Before         the backend, called directly, is what the pen test saw:
#                     X-Powered-By present, Cache-Control not no-store.
#                     (A NOTE, not a failure, if your own backend differs.)
#   2. GET /users/1   → 200 · every security header present with its configured
#                     value, exactly once · every stack header absent ·
#                     an X-Request-Id
#   3. Same call      → the body is byte-identical to the backend's
#   4. GET /users     → 200 · the same headers on the list · body identical
#   5. GET /users/999999 → 404 from the backend · the same headers on the error
#                     too · body identical
#
# Case 5 is the one people forget. An error response is still a response, and
# the pen tester's scanner requests plenty of things that don't exist.
#
# The expected statuses AND header values are read from ../tests/expected/*.json,
# so the script and the fixtures can't drift apart. In a fixture, a string means
# "exactly this value, once", true means "present, any value", null means
# "absent".
#
# Usage:
#   GATEWAY=https://<YOUR_GATEWAY_HOST> ./verify.sh
#
# Optional: BACKEND — the upstream your API proxies, called directly for cases 1
# and the body comparisons. Default https://jsonplaceholder.typicode.com.
#
# Needs bash, curl, awk and cmp. No jq.

set -uo pipefail

GATEWAY="${GATEWAY:?set GATEWAY to the gateway base URL, e.g. https://<YOUR_GATEWAY_HOST>}"
BACKEND="${BACKEND:-https://jsonplaceholder.typicode.com}"
GW="${GATEWAY%/}"
BE="${BACKEND%/}"

FIXTURES="$(cd "$(dirname "${BASH_SOURCE[0]}")/../tests/expected" 2>/dev/null && pwd || true)"
[ -n "$FIXTURES" ] || { echo "cannot find ../tests/expected next to this script"; exit 1; }

WORK="$(mktemp -d)"
trap 'rm -rf "$WORK"' EXIT

PASSED=0; FAILED=0
pass() { printf '\033[32mPASS\033[0m  %s\n' "$1"; PASSED=$((PASSED + 1)); }
fail() { printf '\033[31mFAIL\033[0m  %s\n' "$1"; FAILED=$((FAILED + 1)); }
note() { printf '\033[34mNOTE\033[0m  %s\n' "$1"; }

status_of() { # $1 fixture → its "status"
  sed -n 's/.*"status"[[:space:]]*:[[:space:]]*\([0-9][0-9]*\).*/\1/p' "$FIXTURES/$1" | head -1
}

fixture_headers() { # $1 fixture → lines "name<TAB>equals|present|absent<TAB>value"
  awk '
    /"headers"[ \t]*:/ { inh = 1; next }
    inh && /^[ \t]*}/  { inh = 0 }
    inh {
      line = $0; sub(/^[ \t]*"/, "", line)
      name = line; sub(/".*/, "", name)
      val = line; sub(/^[^"]*"[ \t]*:[ \t]*/, "", val); sub(/,[ \t]*$/, "", val)
      if (val == "null")      print name "\tabsent\t-"
      else if (val == "true") print name "\tpresent\t-"
      else { sub(/^"/, "", val); sub(/"$/, "", val); print name "\tequals\t" val }
    }' "$FIXTURES/$1"
}

header_values() { # $1 dumped headers, $2 name → every value of that header, one per line
  tr -d '\r' < "$1" | awk -v n="$2" '
    BEGIN { n = tolower(n) }
    { i = index($0, ":"); if (i > 1 && tolower(substr($0, 1, i - 1)) == n) {
        v = substr($0, i + 1); sub(/^[ \t]+/, "", v); print v } }'
}

fetch() { # $1 url, $2 name → status; headers in $WORK/$2.h, body in $WORK/$2.b
  curl -s --max-time 30 -D "$WORK/$2.h" -o "$WORK/$2.b" -w '%{http_code}' "$1"
}

check_headers() { # $1 label, $2 dumped headers, $3 fixture
  local label="$1" dump="$2" bad="" name kind want got count
  while IFS="$(printf '\t')" read -r name kind want; do
    got="$(header_values "$dump" "$name")"
    count="$(printf '%s' "$got" | grep -c . || true)"
    case "$kind" in
      equals)  [ "$count" = 1 ] && [ "$got" = "$want" ] \
                 || bad="${bad}
        ${name}: expected \"${want}\" once, got ${count:-0}: $(printf '%s' "$got" | tr '\n' '|')" ;;
      present) [ "$count" -ge 1 ] || bad="${bad}
        ${name}: expected, missing" ;;
      absent)  [ "$count" = 0 ] || bad="${bad}
        ${name}: must be removed, got \"$(printf '%s' "$got" | tr '\n' '|')\"" ;;
    esac
  done <<EOF
$(fixture_headers "$3")
EOF
  if [ -z "$bad" ]; then
    pass "${label}: every security header set, every stack header gone"
  else
    fail "${label}: header problems:${bad}"
  fi
}

check_body() { # $1 label, $2 gateway name, $3 backend name
  if cmp -s "$WORK/$2.b" "$WORK/$3.b"; then
    pass "$1: body byte-identical to the backend's ($(wc -c < "$WORK/$2.b" | tr -d ' ') bytes)"
  else
    fail "$1: body differs from the backend's. Something on this API rewrites the body:
        a response-rewrite with \"body\" or \"filters\", or another plugin."
  fi
}

# --- 0: can we reach the API at all? ------------------------------------------
s="$(fetch "${GW}/users/1" probe)"
if [ "$s" = "000" ]; then
  echo "could not reach ${GW}. Check GATEWAY."; exit 1
fi
if grep -q 'Route Not Found' "$WORK/probe.b" 2>/dev/null; then
  echo "${GW}/users/1 → 404 Route Not Found. The API isn't deployed in this environment,"
  echo "or its route was stored as /users/{userId} instead of /users/:userId."
  exit 1
fi

# --- 1: before — what the backend sends on its own ----------------------------
echo "Before: ${BE}/users/1, called directly"
s="$(fetch "${BE}/users/1" be1)"
want="$(status_of backend-direct-200.json)"
if [ "$s" != "$want" ]; then
  fail "the backend answered ${s}, expected ${want}. Check BACKEND."
else
  powered="$(header_values "$WORK/be1.h" X-Powered-By | head -1)"
  cache="$(header_values "$WORK/be1.h" Cache-Control | head -1)"
  if [ -n "$powered" ] && [ "$cache" != "no-store" ]; then
    pass "the backend sends X-Powered-By: ${powered} and Cache-Control: ${cache:-(none)}"
  else
    note "the backend sends X-Powered-By: ${powered:-(none)}, Cache-Control: ${cache:-(none)}.
        Not the sample backend, so the before picture differs. The checks below still apply."
  fi
fi
fetch "${BE}/users" be-list >/dev/null
fetch "${BE}/users/999999" be-404 >/dev/null

# --- 2 + 3: one customer -------------------------------------------------------
echo
echo "After: through the gateway"
s="$(fetch "${GW}/users/1" gw1)"
want="$(status_of one-customer-200.json)"
[ "$s" = "$want" ] && pass "GET /users/1 → ${s}" || fail "GET /users/1 → ${s}, expected ${want}"
check_headers "GET /users/1" "$WORK/gw1.h" one-customer-200.json
check_body "GET /users/1" gw1 be1

# --- 4: the list ---------------------------------------------------------------
s="$(fetch "${GW}/users" gw-list)"
want="$(status_of customer-list-200.json)"
[ "$s" = "$want" ] && pass "GET /users → ${s}" || fail "GET /users → ${s}, expected ${want}"
check_headers "GET /users" "$WORK/gw-list.h" customer-list-200.json
check_body "GET /users" gw-list be-list

# --- 5: an error from the backend ---------------------------------------------
s="$(fetch "${GW}/users/999999" gw-404)"
want="$(status_of unknown-customer-404.json)"
[ "$s" = "$want" ] && pass "GET /users/999999 → ${s}, the backend's own error" \
  || fail "GET /users/999999 → ${s}, expected ${want}"
check_headers "GET /users/999999" "$WORK/gw-404.h" unknown-customer-404.json
check_body "GET /users/999999" gw-404 be-404

echo
if [ "$FAILED" -eq 0 ]; then
  printf '\033[32mAll %d checks passed.\033[0m Headers changed, data not.\n' "$PASSED"
  exit 0
fi
printf '\033[31m%d of %d checks failed.\033[0m\n' "$FAILED" $((PASSED + FAILED))
exit 1
