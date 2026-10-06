#!/usr/bin/env bash
# Solution 07 — proof of the edge contract for HTTP-to-Kafka ingest.
#
# WHAT THIS SCRIPT CAN AND CANNOT PROVE
#
# It proves everything observable from the caller's side:
#   1. A valid event      → 202 {"accepted":true}
#   2. Correlation        → the 202 carries X-Request-Id
#   3. A malformed event  → 400, rejected at the edge
#   4. No x-mock-by       → the mock does not advertise itself
#
# It CANNOT prove the event reached Kafka, and deliberately does not try. The
# gateway publishes from the log phase, AFTER this response was flushed — so
# nothing in the response, at any point, reflects whether the produce succeeded.
# A script that inferred delivery from a 202 would be asserting exactly the thing
# this solution's headline limitation says you must not assume.
#
# The Kafka half is verified in YOUR topic browser, using the request id this
# script prints. See ../README.md § Verifying the Kafka leg.
#
# Usage:
#   GATEWAY=https://<YOUR_GATEWAY_HOST> ./verify.sh
#
# Optional overrides:
#   EVENTS_PATH   default /events

set -uo pipefail

GATEWAY="${GATEWAY:?set GATEWAY to the gateway base URL, e.g. https://<YOUR_GATEWAY_HOST>}"
EVENTS_PATH="${EVENTS_PATH:-/events}"
EVENTS_URL="${GATEWAY%/}${EVENTS_PATH}"

BODY_FILE="$(mktemp)"; HDR_FILE="$(mktemp)"
trap 'rm -f "$BODY_FILE" "$HDR_FILE"' EXIT

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
EXP_ACCEPTED="$(expect accepted-202.json 202)"
EXP_CORRELATION="$(expect request-id-202.json 202)"
EXP_NOMOCKHDR="$(expect no-mock-header-202.json 202)"
EXP_REJECTED="$(expect invalid-event-400.json 400)"

# A marker unique to this run, so the message this script produces is findable in
# a busy topic even if the request id is lost.
MARKER="verify-$(date +%s)-$$"
EVENT="{\"event_id\":\"$MARKER\",\"event_type\":\"order.created\",\"occurred_at\":\"$(date -u +%Y-%m-%dT%H:%M:%SZ)\",\"payload\":{\"sku\":\"sku-1\",\"qty\":2}}"

echo "→ Ingest endpoint: $EVENTS_URL"
echo "→ event_id for this run: $MARKER"
echo

# --- 1: a valid event is accepted --------------------------------------------
status="$(curl -s -o "$BODY_FILE" -D "$HDR_FILE" -w '%{http_code}' -X POST "$EVENTS_URL" \
  -H 'content-type: application/json' --data-binary "$EVENT")"
[[ "$status" == "000" ]] && fail "could not reach $EVENTS_URL at all — curl got no HTTP
     response. Check GATEWAY, DNS and network reachability before anything else."
[[ "$status" == "$EXP_ACCEPTED" ]] \
  || fail "valid event → ${status} (expected 202). Body: $(tr -d '\n' < "$BODY_FILE")
     A 404 means the route is not deployed. A 400 means request-validation rejected
     an event that matches the shipped schema — compare body_schema with the payload."
grep -q '"accepted"' "$BODY_FILE" \
  && pass "valid event → 202, body is the gateway's own {\"accepted\":true}" \
  || fail "202 but the body is not the configured mock: $(tr -d '\n' < "$BODY_FILE")
     Something other than the mocking plugin answered — check that no upstream is
     being proxied for this route."

# --- 2: correlation id --------------------------------------------------------
echo
REQ_ID="$(sed -n 's/^[Xx]-[Rr]equest-[Ii][Dd]:[[:space:]]*\(.*\)$/\1/p' "$HDR_FILE" | tr -d '\r' | head -1)"
if [[ -n "$REQ_ID" && "$status" == "$EXP_CORRELATION" ]]; then
  pass "202 carries X-Request-Id: $REQ_ID"
else
  fail "no X-Request-Id on the 202. request-id is missing from the API-level plugins,
     and without it you cannot match a message on the topic to the request that
     produced it — which is how the Kafka half of this solution is verified."
fi

# --- 3: a malformed event is rejected at the edge -----------------------------
echo
status="$(curl -s -o "$BODY_FILE" -w '%{http_code}' -X POST "$EVENTS_URL" \
  -H 'content-type: application/json' --data-binary '{"event_type":"order.created"}')"
[[ "$status" == "$EXP_REJECTED" ]] \
  && pass "event missing required fields → 400 (rejected before anything is published)" \
  || fail "malformed event → ${status} (expected 400). request-validation is missing or its
     body_schema is too permissive. Without it, malformed events are acknowledged with
     202 AND published to your topic — the _meta.filter only screens on status, and
     with nothing rejecting them there is no non-202 to screen."

# --- 4: the mock does not advertise itself ------------------------------------
echo
status="$(curl -s -o /dev/null -D "$HDR_FILE" -w '%{http_code}' -X POST "$EVENTS_URL" \
  -H 'content-type: application/json' --data-binary "$EVENT")"
if [[ "$status" == "$EXP_NOMOCKHDR" ]] && ! grep -qi '^x-mock-by:' "$HDR_FILE"; then
  pass "no x-mock-by header (with_mock_header is false)"
else
  fail "the response carries an x-mock-by header. with_mock_header defaults to TRUE and
     must be set false — a production ingest endpoint should not announce that its
     acknowledgement is generated by a mocking plugin."
fi

echo
printf '\033[32mThe edge contract holds.\033[0m Valid events are acknowledged, malformed ones are rejected,\n'
printf 'and every acknowledgement is correlatable.\n\n'
info "NOT PROVEN HERE — and not provable from this side:"
info "  • that the event reached Kafka. The publish happens in the log phase, after"
info "    the 202 was already sent. A broker outage produces an identical 202."
info "Open your topic and look for event_id \"$MARKER\" with request_id \"$REQ_ID\"."
info "See ../README.md § Verifying the Kafka leg."
