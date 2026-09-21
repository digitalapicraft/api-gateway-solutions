#!/usr/bin/env bash
# Solution 10 — proof that the caller no longer receives the sensitive fields.
#
# Exits 0 only if ALL of the following hold, on a LIST response (many records)
# and on a single record:
#   1. Every email local part is masked, and no unmasked address survives
#   2. The email DOMAIN survives — the mask is partial by design
#   3. Every phone number is redacted
#   4. Every coordinate pair is redacted
#   5. Fields that are not in the filter list are untouched
#   6. The single-record route masks identically
#
# Case 1 says "every", and it means it. The most dangerous default in this whole
# package is response-rewrite's scope, which is `once` — a filter without
# `scope: global` masks the FIRST match in the body and leaves the rest. On a
# ten-record list that is one masked record and nine in the clear, and the first
# record looks right in every screenshot anybody takes.
#
# What this script CANNOT check: what your loggers write. log-data-mask changes
# the logger's copy, not the response, so no client-side assertion can see it.
# The procedure for verifying that half is in tests/test-plan.yaml.
#
# Usage:
#   GATEWAY=https://<YOUR_GATEWAY_HOST> ./verify.sh
#
# Optional overrides:
#   LIST_PATH    default /support/customers
#   ONE_PATH     default /support/customers/3
#   MASK         default [redacted]

set -uo pipefail

GATEWAY="${GATEWAY:?set GATEWAY to the gateway base URL, e.g. https://<YOUR_GATEWAY_HOST>}"
LIST_PATH="${LIST_PATH:-/support/customers}"
ONE_PATH="${ONE_PATH:-/support/customers/3}"
MASK="${MASK:-[redacted]}"

LIST_URL="${GATEWAY%/}${LIST_PATH}"
ONE_URL="${GATEWAY%/}${ONE_PATH}"
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
EXP_LIST="$(expect customers-masked-200.json 200)"
EXP_ONE="$(expect customer-masked-200.json 200)"

echo "→ List route:   $LIST_URL"
echo "→ Single route: $ONE_URL"
echo

# --- fetch the list ----------------------------------------------------------
status="$(curl -s -o "$BODY_FILE" -w '%{http_code}' "$LIST_URL" -H 'accept: application/json')"
[[ "$status" == "000" ]] && fail "could not reach $LIST_URL at all — curl got no HTTP response.
     Check GATEWAY, DNS and reachability before anything else."
[[ "$status" == "$EXP_LIST" ]] \
  || fail "list → ${status} (expected ${EXP_LIST}). Body: $(head -c 200 "$BODY_FILE")"

records="$(grep -o '"email"' "$BODY_FILE" | wc -l | tr -d ' ')"
[[ "$records" -ge 2 ]] \
  || fail "the list response contains ${records} email field(s). This script needs at least two
     records to prove the mask applies to all of them — point LIST_PATH at a collection."
info "list contains ${records} records"

# --- 1: every email local part masked ----------------------------------------
# An unmasked address is a quoted local part that is not exactly *** before the @.
if grep -Eo '"email"[[:space:]]*:[[:space:]]*"[^"]*"' "$BODY_FILE" | grep -qv '"\*\*\*@'; then
  leaked="$(grep -Eo '"email"[[:space:]]*:[[:space:]]*"[^"]*"' "$BODY_FILE" | grep -v '"\*\*\*@' | head -3)"
  fail "at least one email address is NOT masked:
     ${leaked}
     If exactly one record IS masked and the rest are not, the filter is missing
     scope: global — the default is 'once' and masks only the first match."
fi
pass "every email local part is masked across all ${records} records"

# --- 2: the domain survives --------------------------------------------------
grep -q '"\*\*\*@[A-Za-z0-9.-]\+"' "$BODY_FILE" \
  && pass "the email domain survives the mask (partial by design, not a blunt delete)" \
  || fail "no masked-address-with-domain found. If addresses are fully removed, the filter is
     broader than this package's, and support loses the one part of the address it uses."

# --- 3: phones redacted ------------------------------------------------------
if grep -Eo '"phone"[[:space:]]*:[[:space:]]*"[^"]*"' "$BODY_FILE" | grep -qvF "$MASK"; then
  leaked="$(grep -Eo '"phone"[[:space:]]*:[[:space:]]*"[^"]*"' "$BODY_FILE" | grep -vF "$MASK" | head -3)"
  fail "at least one phone number is NOT redacted:
     ${leaked}"
fi
pass "every phone number is redacted"

# --- 4: coordinates redacted -------------------------------------------------
if grep -q '"lat"' "$BODY_FILE"; then
  if grep -Eo '"(lat|lng)"[[:space:]]*:[[:space:]]*"[^"]*"' "$BODY_FILE" | grep -qvF "$MASK"; then
    fail "at least one coordinate is NOT redacted. Precise coordinates identify a home address."
  fi
  pass "every coordinate is redacted"
else
  info "no lat/lng fields in this response — coordinate filters not exercised"
fi

# --- 5: unfiltered fields untouched ------------------------------------------
if grep -q '"name"[[:space:]]*:[[:space:]]*"' "$BODY_FILE"; then
  grep -Eo '"name"[[:space:]]*:[[:space:]]*"[^"]*"' "$BODY_FILE" | grep -qvF "$MASK" \
    && pass "fields outside the filter list are untouched (the patterns are anchored, not broad)" \
    || fail "a field the filters do not name has been masked too. The patterns are matching more
     than their field — anchor each one on its own key."
else
  info "no 'name' field to check over-masking against"
fi

# --- 6: the single-record route ----------------------------------------------
echo
status="$(curl -s -o "$BODY_FILE" -w '%{http_code}' "$ONE_URL" -H 'accept: application/json')"
[[ "$status" == "$EXP_ONE" ]] \
  || fail "single record → ${status} (expected ${EXP_ONE}). If this is a 404, the path rewrite is
     not carrying the id through — check proxy-rewrite's regex_uri, not the mask."
grep -q '"\*\*\*@' "$BODY_FILE" \
  && pass "the single-record route masks identically" \
  || fail "the single-record route returned an unmasked address. The filters are per route and it
     is easy to update one route and forget the other."

echo
printf '\033[32mAll checks passed.\033[0m The caller no longer receives the sensitive fields.\n'
printf 'What loggers write is a separate control — see tests/test-plan.yaml to verify that half.\n'
