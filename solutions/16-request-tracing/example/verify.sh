#!/usr/bin/env bash
# Solution 16 — proof that a trace session captures, and correctly attributes,
# what happened to real requests on a deployed API.
#
# Exits 0 only if ALL of the following hold:
#   1. Start a session          → 200, a session id, status active
#   2. Start it again           → the SAME session id (one session per API and
#                                 environment; a second start does not stack)
#   3. POST /posts, no title    → 400, and its record says the GATEWAY answered:
#                                 outcome short_circuit, plugin request-validation,
#                                 no upstream status
#   4. GET /posts/1             → 200, and its record shows proxy-rewrite adding
#                                 X-Partner-Channel on the way to the backend
#   5. GET /posts/999999        → 404, and its record says the BACKEND answered:
#                                 upstream status 404, no short circuit
#   6. Tracing is invisible     → the traced GET /posts/1 body is byte-identical
#                                 to an untraced one
#   7. Stop                     → 200, and a request after it is not recorded
#
# Cases 3 and 5 are the point. Both are failures a partner would report the same
# way ("I got an error"); the record is what tells you whose error it was.
#
# Uses 3 of a session's recorded requests, under the default cap of 10.
#
# Usage:
#   GATEWAY=https://<YOUR_GATEWAY_HOST> \
#   CONTROL_PLANE=https://<YOUR_CONTROL_PLANE_API> \
#   TOKEN=<control-plane bearer token> \
#   ORG=<ORG_ID> API_ID=<API_ID> ENV_ID=<ENV_ID> \
#   ./verify.sh
#
# Needs bash, curl and jq. Optional: POLL_SECONDS (default 90) — how long to wait
# for records to arrive, since they are written asynchronously.

set -uo pipefail

GATEWAY="${GATEWAY:?set GATEWAY to the gateway base URL, e.g. https://<YOUR_GATEWAY_HOST>}"
CONTROL_PLANE="${CONTROL_PLANE:?set CONTROL_PLANE to the control-plane base URL, e.g. https://<YOUR_CONTROL_PLANE_API>}"
TOKEN="${TOKEN:?set TOKEN to a control-plane bearer token}"
ORG="${ORG:?set ORG to your org id}"
API_ID="${API_ID:?set API_ID to the id of the deployed API}"
ENV_ID="${ENV_ID:?set ENV_ID to the environment the API is deployed in}"
POLL_SECONDS="${POLL_SECONDS:-90}"

command -v jq >/dev/null || { echo "verify.sh needs jq"; exit 1; }

GW="${GATEWAY%/}"
CP="${CONTROL_PLANE%/}/api/orgs/${ORG}"
SESSIONS="${CP}/apis/${API_ID}/envs/${ENV_ID}/trace/sessions"
BODY_FILE="$(mktemp)"
SESSION_ID=""

fail() { printf '\033[31mFAIL\033[0m  %s\n' "$1"; exit 1; }
pass() { printf '\033[32mPASS\033[0m  %s\n' "$1"; }
info() { printf '\033[34mNOTE\033[0m  %s\n' "$1"; }

cleanup() {
  # Never leave a session running: it would record the next ten real requests.
  [[ -n "$SESSION_ID" ]] && curl -s -o /dev/null -X POST "${SESSIONS}/${SESSION_ID}/stop" \
    -H "authorization: Bearer ${TOKEN}"
  rm -f "$BODY_FILE"
}
trap cleanup EXIT

# --- expected statuses come from the fixtures, not from literals here ---------
FIXTURES="$(cd "$(dirname "${BASH_SOURCE[0]}")/../tests/expected" 2>/dev/null && pwd || true)"
expect() {
  local f="${FIXTURES:-}/$1" v=""
  [ -n "${FIXTURES:-}" ] && [ -f "$f" ] && \
    v="$(sed -n 's/.*"status"[[:space:]]*:[[:space:]]*\([0-9][0-9]*\).*/\1/p' "$f" | head -1)"
  printf '%s' "${v:-$2}"
}
EXP_REJECTED="$(expect missing-title-400.json 400)"
EXP_OK="$(expect get-post-200.json 200)"
EXP_BACKEND="$(expect unknown-post-404.json 404)"

cp_post() { # $1 url, $2 body → prints the status; response in $BODY_FILE
  curl -s -o "$BODY_FILE" -w '%{http_code}' -X POST "$1" \
    -H "authorization: Bearer ${TOKEN}" -H 'content-type: application/json' -d "${2:-}"
}
records() { # all records of the session, one decoded JSON object per line
  curl -s "${CP}/trace/sessions/${SESSION_ID}/traces?limit=100" \
    -H "authorization: Bearer ${TOKEN}" | jq -c '.traces[]?.raw_json | fromjson'
}
record_for() { # $1 method, $2 uri → the matching record
  records | jq -c --arg m "$1" --arg u "$2" 'select(.request.method == $m and .request.uri == $u)' | head -1
}

# --- baseline, before any session: what an untraced call returns --------------
untraced="$(curl -s "${GW}/posts/1")"
[[ -z "$untraced" ]] && fail "could not reach ${GW}/posts/1 at all. Check GATEWAY and
     that the API is deployed in this environment before anything else."

# --- 1: start ----------------------------------------------------------------
status="$(cp_post "$SESSIONS" '{"ttl_seconds":300}')"
case "$status" in
  200) ;;
  401|403) fail "start → ${status}. The token is expired, or your role lacks trace-session.create
     (org admins and gateway admins have it; product owners do not)." ;;
  404) fail "start → 404. Check API_ID and ENV_ID, and that the environment has a gateway." ;;
  *) fail "start → ${status}. Body: $(tr -d '\n' < "$BODY_FILE")" ;;
esac
SESSION_ID="$(jq -r '.session_id // empty' "$BODY_FILE")"
[[ -n "$SESSION_ID" && "$(jq -r .status "$BODY_FILE")" == "active" ]] \
  || fail "start returned no active session. Body: $(tr -d '\n' < "$BODY_FILE")"
if [[ "$(jq -r '.requests_traced // 0' "$BODY_FILE")" != "0" || "$(jq -r '.filter' "$BODY_FILE")" != "null" ]]; then
  SESSION_ID=""   # not ours; leave it alone
  fail "a session was already running on this API, with a filter or records of its own.
     Stop it (Observability → Traces → Stop session) and re-run."
fi
pass "start → session ${SESSION_ID}, active, cap $(jq -r .max_requests "$BODY_FILE") requests"

# --- 2: start again ----------------------------------------------------------
cp_post "$SESSIONS" '{"ttl_seconds":60}' >/dev/null
again="$(jq -r '.session_id // empty' "$BODY_FILE")"
[[ "$again" == "$SESSION_ID" ]] \
  && pass "second start → the same session (one per API and environment)" \
  || fail "second start → ${again:-no session}, expected ${SESSION_ID}."

# --- drive three requests ----------------------------------------------------
echo
s3="$(curl -s -o "$BODY_FILE" -w '%{http_code}' -X POST "${GW}/posts" \
      -H 'content-type: application/json' -d '{"body":"a post with no title"}')"
[[ "$s3" == "$EXP_REJECTED" ]] || fail "POST /posts with no title → ${s3}, expected ${EXP_REJECTED}.
     Is request-validation on POST /posts?"
s4="$(curl -s -o "$BODY_FILE" -w '%{http_code}' "${GW}/posts/1")"
traced="$(cat "$BODY_FILE")"
[[ "$s4" == "$EXP_OK" ]] || fail "GET /posts/1 → ${s4}, expected ${EXP_OK}."
s5="$(curl -s -o /dev/null -w '%{http_code}' "${GW}/posts/999999")"
[[ "$s5" == "$EXP_BACKEND" ]] || fail "GET /posts/999999 → ${s5}, expected ${EXP_BACKEND}."
info "sent POST /posts → ${s3}, GET /posts/1 → ${s4}, GET /posts/999999 → ${s5}"

# --- wait for the records: they are written asynchronously --------------------
n=0
for (( waited=0; waited<POLL_SECONDS; waited+=5 )); do
  n="$(records | wc -l | tr -d ' ')"
  (( n >= 3 )) && break
  sleep 5
done
(( n >= 3 )) || fail "only ${n} of 3 records arrived in ${POLL_SECONDS}s. The gateway answered all
     three, so it is serving but its records are not reaching the control plane —
     an environment problem, not a configuration one."
pass "3 records arrived"

# --- 3: the gateway said no --------------------------------------------------
echo
r="$(record_for POST /posts)"
[[ "$(jq -r .outcome <<<"$r")" == "short_circuit" && \
   "$(jq -r .short_circuit.plugin <<<"$r")" == "request-validation" && \
   "$(jq -r '.upstream.status // "none"' <<<"$r")" == "none" ]] \
  && pass "POST /posts 400 → answered by the GATEWAY: request-validation, backend never called" \
  || fail "the 400's record does not attribute it to request-validation:
     $(jq -c '{outcome, short_circuit, upstream}' <<<"$r")"

# --- 4: the gateway changed it -----------------------------------------------
r="$(record_for GET /posts/1)"
change="$(jq -c '[.phases[].plugins[]? | select(.name == "proxy-rewrite") | .changes[]?
                 | select(.name == "x-partner-channel")] | first' <<<"$r")"
[[ "$(jq -r .outcome <<<"$r")" == "ok" && "$(jq -r .new_value <<<"$change")" == "api" ]] \
  && pass "GET /posts/1 200 → the record shows proxy-rewrite adding X-Partner-Channel: api" \
  || fail "the 200's record does not show the header change: $(jq -c '{outcome}' <<<"$r") ${change}"
info "time at the backend: $(jq -r .upstream.response_time_ms <<<"$r") ms of $(jq -r .duration_ms <<<"$r") ms total"

# --- 5: the backend said no --------------------------------------------------
r="$(record_for GET /posts/999999)"
[[ "$(jq -r .upstream.status <<<"$r")" == "404" && "$(jq -r .short_circuit <<<"$r")" == "null" ]] \
  && pass "GET /posts/999999 404 → answered by the BACKEND: upstream status 404, no plugin said no" \
  || fail "the 404's record does not attribute it to the backend: $(jq -c '{outcome, short_circuit, upstream}' <<<"$r")"

# --- 6: tracing does not change the response ---------------------------------
[[ "$traced" == "$untraced" ]] \
  && pass "the traced response is byte-identical to an untraced one" \
  || fail "the traced GET /posts/1 body differs from the untraced one."

# --- 7: stop -----------------------------------------------------------------
echo
status="$(cp_post "${SESSIONS}/${SESSION_ID}/stop")"
[[ "$status" == "200" ]] || fail "stop → ${status}. Body: $(tr -d '\n' < "$BODY_FILE")"
stopped="$SESSION_ID"; SESSION_ID=""
curl -s -o /dev/null "${GW}/posts/2"
sleep 15
SESSION_ID="$stopped"; n="$(records | wc -l | tr -d ' ')"; SESSION_ID=""
(( n == 3 )) \
  && pass "stop → 200, and a request after it was not recorded" \
  || fail "after stop the session holds ${n} records, expected 3."

echo
printf '\033[32mAll checks passed.\033[0m The session captured each request and named who answered it.\n'
