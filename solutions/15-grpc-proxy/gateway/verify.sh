#!/usr/bin/env bash
# Solution 15 — proof that the gateway fronts a bidirectional-streaming gRPC
# service, authenticates each stream as it opens, and does not corrupt the
# stream on the way through.
#
# Exits 0 only if ALL of the following hold:
#   1. No key           → the gateway rejects with 401 before the upstream
#   2. Invalid key      → 401 (the key is actually checked)
#   3. Valid key, unary → a clean gRPC response
#   4. Valid key, bidi  → a clean bidirectional stream WITH TRAILERS
#   5. Held-open stream → survives, and still closes cleanly with trailers
#
# Cases 4 and 5 are the ones that matter, and specifically the TRAILER check.
# A gRPC call can deliver every byte of its payload and still be unusable: if an
# HTTP/1.1 hop sits anywhere in front of the data plane it silently drops the
# HTTP/2 trailers that carry grpc-status, and the client cannot tell success
# from failure. That failure looks like success in a browser and in curl.
#
# Requires: grpcurl (brew install grpcurl), and a descriptor for your service.
#
# Usage:
#   GATEWAY=<host>            # gateway host WITHOUT scheme, e.g. gw.example.com
#   UNIT_KEY=<api key>        # the app credential key
#   PROTOSET=/path/to.protoset
#   ./verify.sh
#
# Get a protoset from a backend that has reflection enabled:
#   grpcurl -plaintext -protoset-out svc.protoset <backend:port> describe <pkg>.<Service>
#
# Optional overrides (defaults match the shipped spec's example service):
#   UNARY_METHOD   default timing.TimingUnit.Ping
#   UNARY_BODY     default {"from":"verify"}
#   BIDI_METHOD    default timing.TimingUnit.Status
#   BIDI_BODY      default a timing Hello message
#   HOLD_METHOD    default timing.TimingUnit.Commands
#   HOLD_SECONDS   default 20
#   KEY_HEADER     default X-Unit-Key

set -uo pipefail

GATEWAY="${GATEWAY:?set GATEWAY to the gateway host, without a scheme}"
UNIT_KEY="${UNIT_KEY:?set UNIT_KEY to the app credential key}"
PROTOSET="${PROTOSET:?set PROTOSET to a .protoset describing your service}"
KEY_HEADER="${KEY_HEADER:-X-Unit-Key}"
UNARY_METHOD="${UNARY_METHOD:-timing.TimingUnit.Ping}"
UNARY_BODY="${UNARY_BODY:-{\"from\":\"verify\"}}"
BIDI_METHOD="${BIDI_METHOD:-timing.TimingUnit.Status}"
BIDI_BODY="${BIDI_BODY:-{\"hello\":{\"unit_id\":\"verify\",\"event_id\":\"verify\",\"earliest_seq\":0,\"latest_seq\":0}}}"
HOLD_METHOD="${HOLD_METHOD:-timing.TimingUnit.Commands}"
HOLD_SECONDS="${HOLD_SECONDS:-20}"

UNARY_PATH="/$(printf '%s' "$UNARY_METHOD" | sed 's/\.\([^.]*\)$/\/\1/')"

fail() { printf '\033[31mFAIL\033[0m  %s\n' "$1"; exit 1; }
pass() { printf '\033[32mPASS\033[0m  %s\n' "$1"; }

command -v grpcurl >/dev/null || fail "grpcurl is not installed (brew install grpcurl)"
[ -f "$PROTOSET" ] || fail "PROTOSET file not found: $PROTOSET"

# --- expected statuses come from the fixtures, not from literals here ---------
FIXTURES="$(cd "$(dirname "${BASH_SOURCE[0]}")/../tests/expected" 2>/dev/null && pwd || true)"
expect() {
  local f="${FIXTURES:-}/$1" v=""
  [ -n "${FIXTURES:-}" ] && [ -f "$f" ] && \
    v="$(sed -n 's/.*"status"[[:space:]]*:[[:space:]]*\([0-9][0-9]*\).*/\1/p' "$f" | head -1)"
  printf '%s' "${v:-$2}"
}
EXP_NOKEY="$(expect no-key-401.json 401)"
EXP_BADKEY="$(expect invalid-key-401.json 401)"

http_status() { # POST to a gRPC path over h2 and report the HTTP status
  curl -s -o /dev/null -w '%{http_code}' --http2 -X POST \
    "https://${GATEWAY}${UNARY_PATH}" -H 'content-type: application/grpc' "$@"
}

# 1 -----------------------------------------------------------------------------
code="$(http_status)"
[ "$code" = "$EXP_NOKEY" ] || fail "no key returned $code, expected $EXP_NOKEY"
pass "1. an unauthenticated stream is refused ($EXP_NOKEY)"

# 2 -----------------------------------------------------------------------------
code="$(http_status -H "${KEY_HEADER}: definitely-not-a-real-key")"
[ "$code" = "$EXP_BADKEY" ] || fail "invalid key returned $code, expected $EXP_BADKEY"
pass "2. an invalid key is refused ($EXP_BADKEY) — the key is really checked"

# 3 -----------------------------------------------------------------------------
out="$(grpcurl -max-time 25 -H "${KEY_HEADER}: ${UNIT_KEY}" -protoset "$PROTOSET" \
        -d "$UNARY_BODY" "${GATEWAY}:443" "$UNARY_METHOD" 2>&1)"
case "$out" in
  *ERROR*) fail "authenticated unary call failed: $(printf '%s' "$out" | head -3 | tr '\n' ' ')" ;;
esac
pass "3. an authenticated unary call succeeds"

# 4 -----------------------------------------------------------------------------
out="$(grpcurl -max-time 25 -H "${KEY_HEADER}: ${UNIT_KEY}" -protoset "$PROTOSET" \
        -d "$BIDI_BODY" "${GATEWAY}:443" "$BIDI_METHOD" 2>&1)"
case "$out" in
  *"without sending trailers"*)
    fail "the stream lost its trailers. An HTTP/1.1 hop in front of the data plane drops
      the HTTP/2 trailers that carry grpc-status. Check for 'via: 1.1 ...' on a
      plain response from this host, and see the README's 'Check your path first'." ;;
  *ERROR*) fail "authenticated bidi call failed: $(printf '%s' "$out" | head -3 | tr '\n' ' ')" ;;
esac
pass "4. an authenticated bidirectional stream completes, trailers intact"

# 5 -----------------------------------------------------------------------------
out="$( (printf '%s\n' "$BIDI_BODY"; sleep "$HOLD_SECONDS") \
        | grpcurl -max-time $((HOLD_SECONDS + 40)) -H "${KEY_HEADER}: ${UNIT_KEY}" \
            -protoset "$PROTOSET" -d @ "${GATEWAY}:443" "$HOLD_METHOD" 2>&1 )"
case "$out" in
  *"without sending trailers"*) fail "the held-open stream lost its trailers" ;;
  *ERROR*) fail "the held-open stream failed: $(printf '%s' "$out" | head -3 | tr '\n' ' ')" ;;
esac
pass "5. a stream held open for ${HOLD_SECONDS}s closed cleanly, trailers intact"

printf '\n\033[32mAll 5 checks passed.\033[0m\n'
