#!/usr/bin/env bash
# Solution 24 — proof that the maintenance switch does what it says, in each
# state. It checks ONE state per run, so it needs only the gateway address:
# switching is done in the UI, by the Helix Agent or with the calls in
# guides.md, and this script checks the result.
#
#   MODE=normal (the default) — every call reaches the backend:
#     1. GET  /bookings          → 200 from the backend, no Retry-After
#     2. GET  /bookings/1        → 200, booking 1
#     3. POST /bookings          → 201 from the backend
#     4. GET  /bookings/999999   → 404, the backend's own answer passed through
#
#   MODE=maintenance — the gateway answers every call itself:
#     5. GET  /bookings          → 503
#     6. GET  /bookings/1        → 503
#     7. POST /bookings          → 503
#     8. GET  /bookings/999999   → 503: the gateway answers before the backend
#                                  could say 404
#     and every 503 carries a Retry-After (a date or a number of seconds), a JSON
#     body, and no header from the backend.
#
# Every response, in both modes, carries an X-Request-Id.
#
# "From the backend" is checked with X-Powered-By, which the sample backend
# (jsonplaceholder) adds to every answer and the gateway's maintenance response
# does not. With your own backend, use a header it always sends: set
# BACKEND_HEADER.
#
# Usage:
#   GATEWAY=https://<YOUR_GATEWAY_HOST> ./verify.sh                  # normal
#   GATEWAY=https://<YOUR_GATEWAY_HOST> MODE=maintenance ./verify.sh
#
# The full rehearsal: run it with MODE=normal, switch maintenance on, run it with
# MODE=maintenance, switch back, run it with MODE=normal again.
#
# Needs bash and curl. Expected statuses come from ../tests/expected/*.json.

set -uo pipefail

GATEWAY="${GATEWAY:?set GATEWAY to the gateway base URL, e.g. https://<YOUR_GATEWAY_HOST>}"
MODE="${MODE:-normal}"
BACKEND_HEADER="${BACKEND_HEADER:-X-Powered-By}"
GW="${GATEWAY%/}"

case "$MODE" in
  normal|maintenance) ;;
  *) echo "MODE must be normal or maintenance, not '${MODE}'"; exit 2 ;;
esac

HEADERS="$(mktemp)"; BODY="$(mktemp)"
trap 'rm -f "$HEADERS" "$BODY"' EXIT
FAILED=0

pass() { printf '\033[32mPASS\033[0m  %s\n' "$1"; }
fail() { printf '\033[31mFAIL\033[0m  %s\n' "$1"; FAILED=$((FAILED + 1)); }
note() { printf '\033[34mNOTE\033[0m  %s\n' "$1"; }

# --- expected statuses come from the fixtures, not from literals here --------
FIXTURES="$(cd "$(dirname "${BASH_SOURCE[0]}")/../tests/expected" 2>/dev/null && pwd || true)"
expect() {
  local f="${FIXTURES:-}/$1" v=""
  [ -n "${FIXTURES:-}" ] && [ -f "$f" ] && \
    v="$(sed -n 's/.*"status"[[:space:]]*:[[:space:]]*\([0-9][0-9]*\).*/\1/p' "$f" | head -1)"
  printf '%s' "${v:-$2}"
}
EXP_LIST="$(expect normal-list-200.json 200)"
EXP_GET="$(expect normal-get-200.json 200)"
EXP_CREATE="$(expect normal-create-201.json 201)"
EXP_UNKNOWN="$(expect unknown-booking-404.json 404)"
EXP_MAINT="$(expect maintenance-503.json 503)"

# call METHOD PATH [JSON body] → prints the status; headers and body to files
call() {
  if [ -n "${3:-}" ]; then
    curl -s -D "$HEADERS" -o "$BODY" -w '%{http_code}' -X "$1" "${GW}$2" \
      -H 'content-type: application/json' -d "$3"
  else
    curl -s -D "$HEADERS" -o "$BODY" -w '%{http_code}' -X "$1" "${GW}$2"
  fi
}
header() { # value of response header $1, case-insensitive, or empty
  grep -i "^$1:" "$HEADERS" | head -1 | cut -d: -f2- | sed 's/^[[:space:]]*//' | tr -d '\r'
}

# --- one request, checked against the state we expect -------------------------
check() { # $1 label, $2 method, $3 path, $4 expected status, $5 optional body
  local label="$1" status ra ct
  status="$(call "$2" "$3" "${5:-}")"
  if [ "$status" = "000" ]; then
    fail "${label} → no answer at all. Check GATEWAY and that the API is deployed."
    return 1
  fi
  if [ "$status" != "$4" ]; then
    if [ "$MODE" = "normal" ] && [ "$status" = "$EXP_MAINT" ]; then
      fail "${label} → ${status}, expected $4. The API looks like it is in maintenance: run with MODE=maintenance, or switch it back."
    elif [ "$MODE" = "maintenance" ] && [ "$status" != "$EXP_MAINT" ]; then
      fail "${label} → ${status}, expected $4. Maintenance is not switched on: is the revision with the maintenance response the one deployed?"
    else
      fail "${label} → ${status}, expected $4. Body: $(head -c 200 "$BODY")"
    fi
    return 1
  fi
  [ -n "$(header X-Request-Id)" ] || { fail "${label} → ${status}, but no X-Request-Id header."; return 1; }
  ra="$(header Retry-After)"

  if [ "$MODE" = "normal" ]; then
    [ -n "$(header "$BACKEND_HEADER")" ] || { fail "${label} → ${status}, but no ${BACKEND_HEADER} header: did the backend answer?"; return 1; }
    [ -z "$ra" ] || { fail "${label} → ${status}, but it carries Retry-After: ${ra}"; return 1; }
    pass "${label} → ${status}, answered by the backend"
    return 0
  fi

  # maintenance: the gateway answered, with a time and a JSON message
  [ -z "$(header "$BACKEND_HEADER")" ] || { fail "${label} → ${status}, but it carries ${BACKEND_HEADER}: the backend answered."; return 1; }
  if [ -z "$ra" ]; then
    fail "${label} → ${status}, but no Retry-After header."; return 1
  fi
  if ! printf '%s' "$ra" | grep -Eq '^([0-9]+|[A-Z][a-z]{2}, [0-9]{2} [A-Z][a-z]{2} [0-9]{4} [0-9]{2}:[0-9]{2}:[0-9]{2} GMT)$'; then
    fail "${label} → Retry-After is '${ra}': neither a number of seconds nor a date like 'Sat, 07 Nov 2026 03:00:00 GMT'."; return 1
  fi
  ct="$(header Content-Type)"
  case "$ct" in
    application/json*) ;;
    *) fail "${label} → Content-Type is '${ct}', expected application/json."; return 1 ;;
  esac
  if ! tr -d '[:space:]' < "$BODY" | grep -q '^{.*}$'; then
    fail "${label} → the body is not a JSON object: $(head -c 120 "$BODY")"; return 1
  fi
  pass "${label} → ${status}, Retry-After: ${ra}, JSON body, backend not called"
}

# A Retry-After date in the past tells callers to retry straight away.
check_date() {
  local ra when now
  ra="$(header Retry-After)"
  printf '%s' "$ra" | grep -q 'GMT$' || return 0
  when="$(date -j -u -f '%a, %d %b %Y %H:%M:%S GMT' "$ra" +%s 2>/dev/null \
          || date -u -d "$ra" +%s 2>/dev/null || true)"
  now="$(date -u +%s)"
  if [ -z "$when" ]; then
    note "could not read the Retry-After date on this machine; check it by eye: ${ra}"
  elif [ "$when" -le "$now" ]; then
    note "Retry-After (${ra}) is in the past, so callers will retry straight away. Set it to the end of your window."
  else
    note "callers are told to come back at ${ra}"
  fi
}

echo "Checking ${GW} in ${MODE} mode"
echo
if [ "$MODE" = "normal" ]; then
  check "GET /bookings"          GET  /bookings        "$EXP_LIST"
  if check "GET /bookings/1"     GET  /bookings/1      "$EXP_GET" \
     && ! grep -Eq '"id"[[:space:]]*:[[:space:]]*1[,}[:space:]]' "$BODY"; then
    fail "GET /bookings/1 → not booking 1: $(head -c 120 "$BODY")"
  fi
  check "POST /bookings"         POST /bookings        "$EXP_CREATE" '{"title":"verify.sh booking"}'
  check "GET /bookings/999999"   GET  /bookings/999999 "$EXP_UNKNOWN"
else
  check "GET /bookings"          GET  /bookings        "$EXP_MAINT"
  check "GET /bookings/1"        GET  /bookings/1      "$EXP_MAINT"
  check "POST /bookings"         POST /bookings        "$EXP_MAINT" '{"title":"verify.sh booking"}'
  check "GET /bookings/999999"   GET  /bookings/999999 "$EXP_MAINT"
  if [ "$FAILED" -eq 0 ]; then
    echo
    note "the message callers get: $(head -c 200 "$BODY")"
    check_date
  fi
fi

echo
if [ "$FAILED" -eq 0 ]; then
  printf '\033[32mAll checks passed.\033[0m The API is in its %s state.\n' "$MODE"
  exit 0
fi
printf '\033[31m%s check(s) failed.\033[0m\n' "$FAILED"
exit 1
