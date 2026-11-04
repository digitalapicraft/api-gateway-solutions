#!/usr/bin/env bash
# Solution 18 — proof that a bad request body is refused at the gateway and never
# reaches the ticket service, while a good one goes through.
#
# Exits 0 only if ALL of the following hold:
#   1. A valid new ticket           → 201 from the ticket service
#   2. No priority                  → 400, and the message names "priority"
#   3. title is null (wrong type)   → 400, and the message names "title"
#   4. priority not in the list     → 400, and the message names "priority"
#   5. A body that is not JSON      → 400
#   6. A change with one field      → 200 from the ticket service (PATCH requires nothing)
#   7. A change with a bad priority → 400 (the rule still applies to what is sent)
#
# HOW THIS SCRIPT KNOWS WHO ANSWERED. The ticket service in the sample
# (jsonplaceholder) adds an X-Powered-By header to every response, and it never
# answers 400 to these calls. So:
#   - cases 1 and 6 must CARRY that header: the call reached the service;
#   - cases 2-5 and 7 must NOT carry it: the gateway answered, and the service
#     never saw the call.
# If your own backend sends a different header on every response, set
# BACKEND_HEADER to it. If it sends none, a trace session shows the same thing
# (see solution 16).
#
# Usage:
#   GATEWAY=https://<YOUR_GATEWAY_HOST> ./verify.sh
#
# Optional overrides:
#   TICKETS_PATH    default /tickets
#   TICKET_ID       default 1
#   BACKEND_HEADER  default X-Powered-By

set -uo pipefail

GATEWAY="${GATEWAY:?set GATEWAY to the gateway base URL, e.g. https://<YOUR_GATEWAY_HOST>}"
TICKETS_PATH="${TICKETS_PATH:-/tickets}"
TICKET_ID="${TICKET_ID:-1}"
BACKEND_HEADER="${BACKEND_HEADER:-X-Powered-By}"

CREATE_URL="${GATEWAY%/}${TICKETS_PATH}"
CHANGE_URL="${GATEWAY%/}${TICKETS_PATH}/${TICKET_ID}"
BODY_FILE="$(mktemp)"
HDR_FILE="$(mktemp)"
trap 'rm -f "$BODY_FILE" "$HDR_FILE"' EXIT

fail() { printf '\033[31mFAIL\033[0m  %s\n' "$1"; exit 1; }
pass() { printf '\033[32mPASS\033[0m  %s\n' "$1"; }

# Expected statuses come from the fixtures, so the script and tests/expected/
# cannot drift apart. The second argument is used only if a fixture is missing.
FIXTURES="$(cd "$(dirname "${BASH_SOURCE[0]}")/../tests/expected" 2>/dev/null && pwd || true)"
expect() {
  local f="${FIXTURES:-}/$1" v=""
  [ -n "${FIXTURES:-}" ] && [ -f "$f" ] && \
    v="$(sed -n 's/.*"status"[[:space:]]*:[[:space:]]*\([0-9][0-9]*\).*/\1/p' "$f" | head -1)"
  printf '%s' "${v:-$2}"
}
EXP_VALID="$(expect create-valid-201.json 201)"
EXP_MISSING="$(expect missing-priority-400.json 400)"
EXP_NULL="$(expect title-null-400.json 400)"
EXP_ENUM="$(expect priority-not-allowed-400.json 400)"
EXP_NOTJSON="$(expect not-json-400.json 400)"
EXP_CHANGE="$(expect change-priority-200.json 200)"
EXP_CHANGE_BAD="$(expect change-bad-priority-400.json 400)"

# send METHOD URL CONTENT-TYPE BODY → sets $status; headers in $HDR_FILE, body in $BODY_FILE
send() {
  status="$(curl -s -D "$HDR_FILE" -o "$BODY_FILE" -w '%{http_code}' -X "$1" "$2" \
    -H "content-type: $3" --data-binary "$4")"
  [ "$status" = "000" ] && fail "could not reach $2 at all — curl got no HTTP response.
     Check GATEWAY, DNS and reachability before anything else."
  return 0
}
has_header() { grep -qi "^$1:" "$HDR_FILE"; }
body_has() { grep -qF "$1" "$BODY_FILE"; }
body() { head -c 200 "$BODY_FILE"; }

# A refusal must be the gateway's: right status, no backend header, the field named.
refused() { # label expected-status field-or-empty
  [ "$status" = "$2" ] || fail "$1 → ${status} (expected $2). Body: $(body)
     If this is 201 or 200, the request reached the ticket service: check that
     request-validation is on this route and that the revision is deployed."
  has_header "$BACKEND_HEADER" && fail "$1 → $2, but the response carries ${BACKEND_HEADER}.
     The ticket service answered, not the gateway. The rule is not on this route."
  if [ -n "$3" ]; then
    body_has "\"$3\"" || fail "$1 → $2, but the message does not name \"$3\": $(body)
     If the message is a fixed text, the route sets rejected_msg. That is a
     choice, not a fault: see guides.md, Variations."
    pass "$1 → $2 from the gateway, naming \"$3\": $(body)"
  else
    pass "$1 → $2 from the gateway: $(body)"
  fi
}

echo "→ Create: POST  $CREATE_URL"
echo "→ Change: PATCH $CHANGE_URL"
echo

# --- 1: a valid ticket reaches the service -----------------------------------
send POST "$CREATE_URL" application/json '{"title":"Printer on fire","priority":"high"}'
[ "$status" = "$EXP_VALID" ] || fail "valid ticket → ${status} (expected ${EXP_VALID}). Body: $(body)
     A 400 here means the rule refuses a good ticket. A 404 means no route at
     ${TICKETS_PATH}. A 502 means the upstream is wrong."
has_header "$BACKEND_HEADER" || fail "valid ticket → ${status}, but the response has no ${BACKEND_HEADER} header.
     This script uses that header to tell the backend's answers from the gateway's.
     Set BACKEND_HEADER to a header your backend sends on every response."
pass "valid ticket → ${status} from the ticket service (${BACKEND_HEADER} present)"

# --- 2: missing field ---------------------------------------------------------
send POST "$CREATE_URL" application/json '{"title":"Printer on fire"}'
refused "no priority" "$EXP_MISSING" priority

# --- 3: wrong type ------------------------------------------------------------
send POST "$CREATE_URL" application/json '{"title":null,"priority":"high"}'
refused "title is null" "$EXP_NULL" title

# --- 4: value outside the list ------------------------------------------------
send POST "$CREATE_URL" application/json '{"title":"Printer on fire","priority":"urgent"}'
refused "priority \"urgent\"" "$EXP_ENUM" priority

# --- 5: not JSON --------------------------------------------------------------
send POST "$CREATE_URL" text/plain 'title=Printer on fire&priority=high'
refused "body is not JSON" "$EXP_NOTJSON" ""

# --- 6: PATCH requires nothing ------------------------------------------------
send PATCH "$CHANGE_URL" application/json '{"priority":"low"}'
[ "$status" = "$EXP_CHANGE" ] || fail "change with one field → ${status} (expected ${EXP_CHANGE}). Body: $(body)
     A 400 naming a field means the PATCH route requires it: its rule should
     have no \"required\" list. A 404 means the path rewrite is not carrying the
     id through to the backend."
has_header "$BACKEND_HEADER" || fail "change with one field → ${status}, but without ${BACKEND_HEADER}."
pass "change with one field → ${status} from the ticket service (nothing is required on PATCH)"

# --- 7: PATCH still checks what is sent ---------------------------------------
send PATCH "$CHANGE_URL" application/json '{"priority":"urgent"}'
refused "change with priority \"urgent\"" "$EXP_CHANGE_BAD" priority

echo
printf '\033[32mAll 7 checks passed.\033[0m Bad bodies are refused at the gateway; good ones reach the service.\n'
