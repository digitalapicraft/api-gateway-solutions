#!/usr/bin/env bash
# Solution 17 — proof that the mock answers the agreed contract today, and that
# the same calls reach the backend after the switch-over, with no client change.
#
# Run it twice against the same gateway host:
#
#   STAGE=mock (default) — after deploying example/api-spec.yaml
#     1. GET  /shipments/SHP-1001  → 200, the sample shipment, x-mock-by present
#     2. GET  /shipments/1         → 200, the SAME body: every id gets one answer
#     3. POST /shipments           → 201, Location /shipments/SHP-1001, the sample
#     4. DELETE /shipments/SHP-1001 → 404: only the agreed routes exist
#
#   STAGE=backend — after deploying example/api-spec-basic.yaml as a new
#   revision of the same API (the switch-over)
#     5. GET  /shipments/1         → 200 from the backend: no x-mock-by, not the sample
#     6. POST /shipments           → 201 from the backend: no x-mock-by, not the sample
#
# Cases 2 and 5 send the same call to the same host and path, and so do cases 3
# and 6. Only the answer's source changes, which is the point: the frontend
# changes nothing.
#
# Usage:
#   GATEWAY=https://<YOUR_GATEWAY_HOST> ./verify.sh
#   GATEWAY=https://<YOUR_GATEWAY_HOST> STAGE=backend ./verify.sh
#
# MOCK_HEADER names the header that marks a mocked answer (default x-mock-by,
# which the mock adds itself). An agent build may switch that off and add its
# own marker under another name, such as X-Mock: read it back and pass it here.
#
# Needs bash, curl and jq. Exits 0 only if every case of the stage holds.

set -uo pipefail

GATEWAY="${GATEWAY:?set GATEWAY to the gateway base URL, e.g. https://<YOUR_GATEWAY_HOST>}"
STAGE="${STAGE:-mock}"
MOCK_HEADER="${MOCK_HEADER:-x-mock-by}"
case "$STAGE" in mock|backend) ;; *) echo "STAGE must be mock or backend, not '$STAGE'"; exit 1;; esac
command -v jq >/dev/null || { echo "verify.sh needs jq"; exit 1; }

GW="${GATEWAY%/}"
HDR="$(mktemp)"; BODY="$(mktemp)"
trap 'rm -f "$HDR" "$BODY"' EXIT

fail() { printf '\033[31mFAIL\033[0m  %s\n' "$1"; exit 1; }
pass() { printf '\033[32mPASS\033[0m  %s\n' "$1"; }

# --- expected values come from the fixtures, not from literals here ----------
FIXTURES="$(cd "$(dirname "${BASH_SOURCE[0]}")/../tests/expected" 2>/dev/null && pwd || true)"
[ -n "$FIXTURES" ] && [ -f "$FIXTURES/get-shipment-200.json" ] \
  || fail "tests/expected/ not found next to this script. Run it from the package folder."
fx() { jq -r "$2" "$FIXTURES/$1"; }        # $1 fixture, $2 jq path
fxbody() { jq -S -c '.body' "$FIXTURES/$1"; }

call() { # $1 method, $2 path, [$3 body] → prints the status; headers in $HDR, body in $BODY
  if [ -n "${3:-}" ]; then
    curl -s -D "$HDR" -o "$BODY" -w '%{http_code}' -X "$1" "${GW}$2" \
      -H 'content-type: application/json' -d "$3"
  else
    curl -s -D "$HDR" -o "$BODY" -w '%{http_code}' -X "$1" "${GW}$2"
  fi
}
has_header() { grep -qi "^$1:" "$HDR"; }
header() { grep -i "^$1:" "$HDR" | head -1 | sed 's/^[^:]*:[[:space:]]*//' | tr -d '\r'; }
body_norm() { jq -S -c . "$BODY" 2>/dev/null; }

NEW='{"origin":"Rotterdam","destination":"Leeds"}'
MOCK_GET="$(fxbody get-shipment-200.json)"
MOCK_POST="$(fxbody create-shipment-201.json)"

if [ "$STAGE" = "mock" ]; then
  echo "Stage: mock (example/api-spec.yaml deployed)"
  echo

  # --- 1: the contract, answered by the gateway ------------------------------
  exp="$(fx get-shipment-200.json .status)"
  s="$(call GET /shipments/SHP-1001)"
  if [ "$s" = "404" ] && grep -q "Route Not Found" "$BODY"; then
    fail "GET /shipments/SHP-1001 → 404 Route Not Found. The API isn't deployed on this host,
     or the route was stored as /shipments/{shipmentId} instead of /shipments/:shipmentId."
  fi
  [ "$s" = "$exp" ] || fail "GET /shipments/SHP-1001 → ${s}, expected ${exp}."
  [ "$(body_norm)" = "$MOCK_GET" ] || fail "GET /shipments/SHP-1001 body is not the sample shipment:
     $(head -c 300 "$BODY")"
  has_header "$MOCK_HEADER" || fail "GET /shipments/SHP-1001 has no ${MOCK_HEADER} header. Is with_mock_header off,
     or did the backend answer instead of the mock? After an agent build, read the
     marker's name back and pass it as MOCK_HEADER=<name>."
  has_header X-Request-Id || fail "GET /shipments/SHP-1001 has no X-Request-Id header. Is request-id on the API?"
  pass "GET /shipments/SHP-1001 → ${s}, the sample shipment, ${MOCK_HEADER}: $(header "$MOCK_HEADER")"
  first="$(body_norm)"

  # --- 2: every id gets the same answer --------------------------------------
  s="$(call GET /shipments/1)"
  [ "$s" = "$exp" ] && [ "$(body_norm)" = "$first" ] \
    && pass "GET /shipments/1 → ${s}, the same body: a static mock answers every id alike" \
    || fail "GET /shipments/1 → ${s}, expected ${exp} and the same body as SHP-1001."

  # --- 3: create answers 201 with a Location ---------------------------------
  exp="$(fx create-shipment-201.json .status)"
  loc="$(fx create-shipment-201.json .headers.values.Location)"
  s="$(call POST /shipments "$NEW")"
  [ "$s" = "$exp" ] || fail "POST /shipments → ${s}, expected ${exp}."
  [ "$(header Location)" = "$loc" ] || fail "POST /shipments Location is '$(header Location)', expected '${loc}'."
  [ "$(body_norm)" = "$MOCK_POST" ] || fail "POST /shipments body is not the sample: $(head -c 300 "$BODY")"
  has_header "$MOCK_HEADER" || fail "POST /shipments has no ${MOCK_HEADER} header."
  pass "POST /shipments → ${s}, Location: ${loc}, the sample body"

  # --- 4: nothing outside the contract ---------------------------------------
  exp="$(fx outside-contract-404.json .status)"
  s="$(call DELETE /shipments/SHP-1001)"
  [ "$s" = "$exp" ] \
    && pass "DELETE /shipments/SHP-1001 → ${s}: only the agreed routes exist" \
    || fail "DELETE /shipments/SHP-1001 → ${s}, expected ${exp}. Something else serves this path."

  echo
  printf '\033[32mAll mock checks passed.\033[0m The frontend can build against this URL today.\n'
  exit 0
fi

echo "Stage: backend (example/api-spec-basic.yaml deployed as a new revision)"
echo

# --- 5: the same lookup now reaches the backend ------------------------------
exp="$(fx backend-get-200.json .status)"
s="$(call GET /shipments/1)"
[ "$s" = "$exp" ] || fail "GET /shipments/1 → ${s}, expected ${exp} from the backend."
has_header "$MOCK_HEADER" && fail "GET /shipments/1 still carries ${MOCK_HEADER}: the mock is still deployed.
     Deploy the revision without it (Force Deploy), then run this again."
[ "$(body_norm)" != "$MOCK_GET" ] || fail "GET /shipments/1 still returns the mock's sample."
has_header X-Request-Id || fail "GET /shipments/1 has no X-Request-Id header."
pass "GET /shipments/1 → ${s} from the backend, no ${MOCK_HEADER}"

# --- 6: the same create now reaches the backend ------------------------------
exp="$(fx backend-create-201.json .status)"
s="$(call POST /shipments "$NEW")"
[ "$s" = "$exp" ] || fail "POST /shipments → ${s}, expected ${exp} from the backend."
has_header "$MOCK_HEADER" && fail "POST /shipments still carries ${MOCK_HEADER}: the mock is still deployed."
[ "$(body_norm)" != "$MOCK_POST" ] || fail "POST /shipments still returns the mock's sample."
pass "POST /shipments → ${s} from the backend, Location: $(header Location)"

echo
printf '\033[32mAll backend checks passed.\033[0m Same host, same paths: the switch-over needed no client change.\n'
