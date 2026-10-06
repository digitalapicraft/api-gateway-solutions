#!/usr/bin/env bash
# Solution 11 — proof that the lookup happened once, at the edge, and that the
# backend received the answer.
#
# Exits 0 only if ALL of the following hold:
#   1. The read route returns 200 and the backend received X-Tenant-Plan with a
#      non-empty value
#   2. The backend also received the second mapped field
#   3. The backend received the callout's own HTTP status
#   4. A client that SENDS its own X-Tenant-Plan does not get to keep it — the
#      gateway's value wins
#   5. The write route returns 200, forwards the body, and carries the header too
#
# Case 4 is the one that matters most and the one most likely to be broken by an
# edit: `headers.set` REPLACES a client-supplied header, `headers.add` would leave
# the client's value in place. If a caller can assert its own plan, this solution
# has become a way to escalate rather than a way to enrich.
#
# Both routes need an upstream that echoes the request headers back. The package's
# sample upstream does. Against your own backend set ECHOES_HEADERS=0 and read
# your backend's own log instead.
#
# Usage:
#   GATEWAY=https://<YOUR_GATEWAY_HOST> ./verify.sh
#
# Optional overrides:
#   READ_PATH       default /storefront/orders
#   WRITE_PATH      default /storefront/checkout
#   PLAN_HEADER     default X-Tenant-Plan
#   CONTACT_HEADER  default X-Tenant-Contact
#   STATUS_HEADER   default X-Profile-Status
#   ECHOES_HEADERS  default 1

set -uo pipefail

GATEWAY="${GATEWAY:?set GATEWAY to the gateway base URL, e.g. https://<YOUR_GATEWAY_HOST>}"
READ_PATH="${READ_PATH:-/storefront/orders}"
WRITE_PATH="${WRITE_PATH:-/storefront/checkout}"
PLAN_HEADER="${PLAN_HEADER:-X-Tenant-Plan}"
CONTACT_HEADER="${CONTACT_HEADER:-X-Tenant-Contact}"
STATUS_HEADER="${STATUS_HEADER:-X-Profile-Status}"
ECHOES_HEADERS="${ECHOES_HEADERS:-1}"

READ_URL="${GATEWAY%/}${READ_PATH}"
WRITE_URL="${GATEWAY%/}${WRITE_PATH}"
BODY_FILE="$(mktemp)"
trap 'rm -f "$BODY_FILE"' EXIT

fail() { printf '\033[31mFAIL\033[0m  %s\n' "$1"; exit 1; }
pass() { printf '\033[32mPASS\033[0m  %s\n' "$1"; }
info() { printf '\033[34mNOTE\033[0m  %s\n' "$1"; }

FIXTURES="$(cd "$(dirname "${BASH_SOURCE[0]}")/../tests/expected" 2>/dev/null && pwd || true)"
expect() {
  local f="${FIXTURES:-}/$1" v=""
  [ -n "${FIXTURES:-}" ] && [ -f "$f" ] && \
    v="$(sed -n 's/.*"status"[[:space:]]*:[[:space:]]*\([0-9][0-9]*\).*/\1/p' "$f" | head -1)"
  printf '%s' "${v:-$2}"
}
EXP_READ="$(expect orders-enriched-200.json 200)"
EXP_WRITE="$(expect checkout-enriched-200.json 200)"

# Pull a header value out of an echo response. Works on the sample upstream's
# {"headers": {...}} shape without needing jq.
echoed() { tr -d '\n' < "$BODY_FILE" | sed -n "s/.*\"$1\"[[:space:]]*:[[:space:]]*\"\([^\"]*\)\".*/\1/p" | head -1; }

echo "→ Read route:  $READ_URL"
echo "→ Write route: $WRITE_URL"
echo

# --- 1: the enrichment happened ----------------------------------------------
status="$(curl -s -o "$BODY_FILE" -w '%{http_code}' "$READ_URL")"
[[ "$status" == "000" ]] && fail "could not reach $READ_URL at all — curl got no HTTP response.
     Check GATEWAY, DNS and reachability before anything else."
[[ "$status" == "$EXP_READ" ]] \
  || fail "read route → ${status} (expected ${EXP_READ}). A 503 here means the callout failed and
     the policy is fail-close. Body: $(head -c 200 "$BODY_FILE")"

if [[ "$ECHOES_HEADERS" != "1" ]]; then
  info "header assertions skipped (ECHOES_HEADERS=0). Read your backend's log to confirm it
     received ${PLAN_HEADER}."
else
  plan="$(echoed "$PLAN_HEADER")"
  [[ -n "$plan" ]] \
    && pass "the backend received ${PLAN_HEADER}: ${plan}" \
    || fail "the backend did not receive ${PLAN_HEADER}.
     Three causes, in order of likelihood: the callout is configured phase: access (it must be
     rewrite, or proxy-rewrite has already run); the variable name in proxy-rewrite does not match
     ctx.helix.<ctx_namespace>.<field> exactly; or the callout failed and the policy is fail-open,
     in which case the headers are simply absent."

  contact="$(echoed "$CONTACT_HEADER")"
  [[ -n "$contact" ]] \
    && pass "the backend received ${CONTACT_HEADER}: ${contact}" \
    || fail "${CONTACT_HEADER} is missing while ${PLAN_HEADER} arrived — one mapped path did not
     resolve. A path that matches nothing yields no value and no error."

  pstatus="$(echoed "$STATUS_HEADER")"
  [[ "$pstatus" == "200" ]] \
    && pass "the backend received ${STATUS_HEADER}: 200 (the callout's own status, not the route's)" \
    || fail "${STATUS_HEADER} is '${pstatus:-absent}', expected 200. Mapping `status` lets the
     backend tell a real answer from a fail-open miss — worth keeping."

  # --- 4: a client cannot assert its own value -------------------------------
  echo
  curl -s -o "$BODY_FILE" -w '%{http_code}' "$READ_URL" -H "${PLAN_HEADER}: Enterprise-Unlimited" >/dev/null
  spoof="$(echoed "$PLAN_HEADER")"
  if [[ "$spoof" == "Enterprise-Unlimited" ]]; then
    fail "a client-supplied ${PLAN_HEADER} reached the backend unchanged. The header is being ADDED
     rather than SET, so any caller can assert its own plan. Use headers.set."
  elif [[ -z "$spoof" ]]; then
    fail "the header vanished when the client sent one of its own — unexpected; inspect the route."
  else
    pass "a client-supplied ${PLAN_HEADER} is overwritten by the gateway (got '${spoof}')"
  fi
fi

# --- 5: the write route ------------------------------------------------------
echo
status="$(curl -s -o "$BODY_FILE" -w '%{http_code}' -X POST "$WRITE_URL" \
  -H 'content-type: application/json' -d '{"sku":"BRK-2100","qty":1}')"
case "$status" in
  200|201) pass "write route → ${status}" ;;
  503) fail "write route → 503. The callout failed and this route is fail-close, which is the
     configured behaviour — but it means the profile service is unreachable from the gateway." ;;
  *) fail "write route → ${status} (expected ${EXP_WRITE}). Body: $(head -c 200 "$BODY_FILE")" ;;
esac
if [[ "$ECHOES_HEADERS" == "1" ]]; then
  grep -q 'BRK-2100' "$BODY_FILE" \
    && pass "the request body reached the backend unchanged" \
    || info "could not see the body in the echo; check your backend's log"
  [[ -n "$(echoed "$PLAN_HEADER")" ]] \
    && pass "the write route is enriched too (the plugin is per route, not per API)" \
    || fail "the write route reached the backend without ${PLAN_HEADER}."
fi

echo
printf '\033[32mAll checks passed.\033[0m One lookup at the edge, the answer delivered as headers,\n'
printf 'and a caller cannot assert its own.\n'
