#!/usr/bin/env bash
# Solution 23 — proof that each stage of the v1 retirement answers the way the
# spec says, and that v2 is untouched.
#
# Exits 0 only if ALL of the following hold:
#   1. GET /v1/products/1         → 200, the backend's product, and the three
#                                   headers with the configured values:
#                                   Deprecation, Sunset, Link (to /v2/products/1)
#   2. GET /v1/products/999999    → the backend's own 404, and STILL the
#                                   Deprecation and Sunset headers, with a Link
#                                   that names the id the caller asked for
#   3. GET /v1/products/7/reviews → 410, JSON naming the successor, Sunset and
#                                   Link headers, and the backend NOT called
#   4. The Link from case 1       → following it gives 200, the same product,
#                                   and no Deprecation or Sunset
#   5. The successor from case 3  → following it gives 200, product 7's reviews,
#                                   and no Deprecation or Sunset
#   Every response carries X-Request-Id.
#
# Cases 4 and 5 are what a caller's code would do with the headers: read the
# address, go there, and get a normal answer from the current version.
#
# Usage:
#   GATEWAY=https://<YOUR_GATEWAY_HOST> ./verify.sh
#
# Optional, if you changed the dates in api-spec.yaml:
#   DEPRECATION     default @1777593600                    (v1 route, RFC 9745)
#   SUNSET          default "Wed, 31 Mar 2027 23:59:59 GMT" (v1 route, RFC 8594)
#   RETIRED_SUNSET  default "Wed, 30 Sep 2026 23:59:59 GMT" (retired route)
#   BACKEND_MARKER  default X-Powered-By. A header your backend always sends and
#                   the gateway never adds. jsonplaceholder sends this one. Its
#                   absence on the 410 is how the script knows the backend
#                   was not called.
#
# Needs bash and curl. Works with the bash 3.2 that ships on macOS.

set -uo pipefail

GATEWAY="${GATEWAY:?set GATEWAY to the gateway base URL, e.g. https://<YOUR_GATEWAY_HOST>}"
DEPRECATION="${DEPRECATION:-@1777593600}"
SUNSET="${SUNSET:-Wed, 31 Mar 2027 23:59:59 GMT}"
RETIRED_SUNSET="${RETIRED_SUNSET:-Wed, 30 Sep 2026 23:59:59 GMT}"
BACKEND_MARKER="${BACKEND_MARKER:-X-Powered-By}"
GW="${GATEWAY%/}"

HDRS="$(mktemp)"; BODY="$(mktemp)"
trap 'rm -f "$HDRS" "$BODY"' EXIT

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
EXP_DEPRECATED="$(expect deprecated-200.json 200)"
EXP_NOT_FOUND="$(expect deprecated-not-found-404.json 404)"
EXP_RETIRED="$(expect retired-410.json 410)"
EXP_CURRENT="$(expect current-200.json 200)"
EXP_REVIEWS="$(expect current-reviews-200.json 200)"

get() { # $1 path → prints the status; headers in $HDRS, body in $BODY
  curl -s --max-time 20 -D "$HDRS" -o "$BODY" -w '%{http_code}' "${GW}$1"
}
header() { # $1 name → the value of that response header, or nothing
  grep -i "^$1:" "$HDRS" | head -1 | sed 's/^[^:]*:[[:space:]]*//' | tr -d '\r'
}
has_header() { grep -qi "^$1:" "$HDRS"; }
same() { # $1 label, $2 got, $3 want
  [ "$2" = "$3" ] || fail "$1 is '${2:-<missing>}', expected '$3'."
}
request_id() {
  [ -n "$(header X-Request-Id)" ] || fail "$1 has no X-Request-Id. Is request-id on the API?"
}

# --- 1: deprecated v1 still works, and says so --------------------------------
s="$(get /v1/products/1)"
[ "$s" = "000" ] && fail "could not reach ${GW} at all. Check GATEWAY and that the API is deployed."
[ "$s" = "404" ] && grep -q 'Route Not Found' "$BODY" && \
  fail "GET /v1/products/1 → 404 Route Not Found. The route is missing, or stored as
     /v1/products/{productId} instead of /v1/products/:productId."
same "GET /v1/products/1 status" "$s" "$EXP_DEPRECATED"
grep -Eq '"id":[[:space:]]*1[,}[:space:]]' "$BODY" || fail "GET /v1/products/1 did not return the backend's product 1."
same "Deprecation on /v1/products/1" "$(header Deprecation)" "$DEPRECATION"
same "Sunset on /v1/products/1" "$(header Sunset)" "$SUNSET"
LINK1="$(header Link)"
same "Link on /v1/products/1" "$LINK1" '</v2/products/1>; rel="successor-version"'
request_id "GET /v1/products/1"
has_header "$BACKEND_MARKER" || fail "the backend's response carries no ${BACKEND_MARKER} header, so case 3
     cannot tell whether the backend was called. Set BACKEND_MARKER to a header
     your backend always sends."
pass "GET /v1/products/1 → ${s}, the product, Deprecation ${DEPRECATION}, Sunset and Link to /v2/products/1"

# --- 2: the headers are on every v1 answer, the backend's errors included -------
s="$(get /v1/products/999999)"
same "GET /v1/products/999999 status" "$s" "$EXP_NOT_FOUND"
grep -q 'Route Not Found' "$BODY" && fail "GET /v1/products/999999 → the gateway's 404 Route Not Found, expected the backend's own 404."
same "Deprecation on the 404" "$(header Deprecation)" "$DEPRECATION"
same "Sunset on the 404" "$(header Sunset)" "$SUNSET"
same "Link on the 404" "$(header Link)" '</v2/products/999999>; rel="successor-version"'
request_id "GET /v1/products/999999"
pass "GET /v1/products/999999 → the backend's ${s}, still with Deprecation, Sunset, and a Link for that id"

# --- 3: the retired endpoint answers 410 itself --------------------------------
s="$(get /v1/products/7/reviews)"
same "GET /v1/products/7/reviews status" "$s" "$EXP_RETIRED"
SUCCESSOR="$(sed -n 's/.*"successor"[[:space:]]*:[[:space:]]*"\([^"]*\)".*/\1/p' "$BODY" | head -1)"
same "successor in the 410 body" "$SUCCESSOR" "/v2/products/7/reviews"
case "$(header Content-Type)" in
  application/json*) ;;
  *) fail "the 410's Content-Type is '$(header Content-Type)', expected application/json." ;;
esac
same "Sunset on the 410" "$(header Sunset)" "$RETIRED_SUNSET"
same "Link on the 410" "$(header Link)" '</v2/products/7/reviews>; rel="successor-version"'
request_id "GET /v1/products/7/reviews"
has_header "$BACKEND_MARKER" && fail "the 410 carries the backend's ${BACKEND_MARKER} header: the backend WAS called."
pass "GET /v1/products/7/reviews → ${s}, JSON naming /v2/products/7/reviews, Sunset and Link, backend not called"

# --- 4: follow the Link from case 1 --------------------------------------------
target="$(printf '%s' "$LINK1" | sed -n 's/^<\([^>]*\)>.*/\1/p')"
s="$(get "$target")"
same "GET ${target} (from the Link header) status" "$s" "$EXP_CURRENT"
grep -Eq '"id":[[:space:]]*1[,}[:space:]]' "$BODY" || fail "GET ${target} did not return product 1."
has_header Deprecation && fail "GET ${target} carries a Deprecation header. v2 is current."
has_header Sunset && fail "GET ${target} carries a Sunset header. v2 is current."
request_id "GET ${target}"
pass "GET ${target} (the Link from case 1) → ${s}, the same product, no Deprecation or Sunset"

# --- 5: follow the successor from case 3 ----------------------------------------
s="$(get "$SUCCESSOR")"
same "GET ${SUCCESSOR} (from the 410 body) status" "$s" "$EXP_REVIEWS"
grep -Eq '"postId":[[:space:]]*7[,}[:space:]]' "$BODY" || fail "GET ${SUCCESSOR} did not return product 7's reviews."
has_header Deprecation && fail "GET ${SUCCESSOR} carries a Deprecation header. v2 is current."
has_header Sunset && fail "GET ${SUCCESSOR} carries a Sunset header. v2 is current."
request_id "GET ${SUCCESSOR}"
pass "GET ${SUCCESSOR} (the successor from case 3) → ${s}, product 7's reviews, no Deprecation or Sunset"

echo
printf '\033[32mAll checks passed.\033[0m v1 announces its end, the retired endpoint says where to go, and v2 is clean.\n'
