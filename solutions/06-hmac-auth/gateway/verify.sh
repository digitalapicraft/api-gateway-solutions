#!/usr/bin/env bash
# Solution 06 — proof that HMAC request signing is enforced at the edge.
#
# Exits 0 only if ALL of the following hold:
#   1. No signature       → 401
#   2. Correct signature  → 201 (the signing base below is the one the gateway builds)
#   3. Body tampered      → 401 (the Digest binds the body to the signature)
#   4. Date 20 min old    → 401 (clock_skew is enforced)
#   5. Wrong secret       → 401 (the secret is verified, not just the key_id)
#   6. Weak signed set    → 401 (signed_headers is enforced — the caller cannot opt out)
#   7. Exact replay       → 201 (NOT a bug. See below. This is the limitation, demonstrated.)
#   8. Signed GET         → 200 (the no-digest signing set on the read route)
#
# Case 6 is the one people skip, and it is the one that proves the configuration is
# actually secure. Without signed_headers the CLIENT chooses what its own signature
# covers, and a signature over nothing but the keyId validates against any body and
# any path forever.
#
# Case 7 is expected to PASS by returning 201. hmac-auth has no nonce and no replay
# cache: a captured request can be replayed until its Date leaves the clock_skew
# window. If this case ever returns 401, replay protection has appeared on your
# build and this package's Limitations section is out of date — that is worth knowing,
# which is why it is asserted rather than described.
#
# Usage:
#   GATEWAY=https://<YOUR_GATEWAY_HOST> \
#   KEY_ID=<KEY_ID> \
#   SECRET_KEY=<SECRET_KEY> \
#   ./verify.sh
#
# KEY_ID and SECRET_KEY come from the app credential the control plane minted — see
# ../README.md § Getting a credential. They are never in the spec.
#
# Optional overrides:
#   WRITE_PATH   default /posts
#   READ_PATH    default /posts/1

set -uo pipefail

GATEWAY="${GATEWAY:?set GATEWAY to the gateway base URL, e.g. https://<YOUR_GATEWAY_HOST>}"
KEY_ID="${KEY_ID:?set KEY_ID to the app credential's key_id}"
SECRET_KEY="${SECRET_KEY:?set SECRET_KEY to the app credential's secret_key}"
WRITE_PATH="${WRITE_PATH:-/posts}"
READ_PATH="${READ_PATH:-/posts/1}"

WRITE_URL="${GATEWAY%/}${WRITE_PATH}"
READ_URL="${GATEWAY%/}${READ_PATH}"
BODY_FILE="$(mktemp)"
trap 'rm -f "$BODY_FILE"' EXIT

fail() { printf '\033[31mFAIL\033[0m  %s\n' "$1"; exit 1; }
pass() { printf '\033[32mPASS\033[0m  %s\n' "$1"; }
info() { printf '\033[34mNOTE\033[0m  %s\n' "$1"; }

# --- expected statuses come from the fixtures, not from literals here ---------
# tests/expected/*.json is the single source of truth for what each case expects,
# so this script and the fixtures cannot drift apart. Parsed with sed, so verify.sh
# still needs nothing beyond bash, curl and openssl.
FIXTURES="$(cd "$(dirname "${BASH_SOURCE[0]}")/../tests/expected" 2>/dev/null && pwd || true)"
expect() {
  local f="${FIXTURES:-}/$1" v=""
  [ -n "${FIXTURES:-}" ] && [ -f "$f" ] && \
    v="$(sed -n 's/.*"status"[[:space:]]*:[[:space:]]*\([0-9][0-9]*\).*/\1/p' "$f" | head -1)"
  printf '%s' "${v:-$2}"
}
EXP_UNSIGNED="$(expect unauthenticated.json 401)"
EXP_SIGNED="$(expect signed-post-201.json 201)"
EXP_TAMPERED="$(expect tampered-body-401.json 401)"
EXP_STALE="$(expect stale-date-401.json 401)"
EXP_BADSECRET="$(expect wrong-secret-401.json 401)"
EXP_WEAKSET="$(expect weak-signed-set-401.json 401)"
EXP_REPLAY="$(expect replay-201.json 201)"
EXP_GET="$(expect signed-get-200.json 200)"

# --- signing ------------------------------------------------------------------
# The signing base is:
#     <keyId>\n
#     <METHOD> <path-and-query>\n        (for the @request-target entry)
#     <name>: <value>\n                  (for every other entry, in headers= order)
# joined by \n AND TERMINATED BY A FINAL \n.
#
# That trailing newline is load-bearing and `$( )` strips trailing newlines — so
# printf is piped STRAIGHT into openssl and the base is never captured in a
# variable. Capturing it first signs a different string and every request 401s.
#
# This is NOT draft-cavage. cavage omits the keyId from the base, has no trailing
# newline, and writes "(request-target): post /path" in lowercase. An off-the-shelf
# cavage client library will not interoperate — see ../README.md.

http_date() { LC_ALL=C date -u +'%a, %d %b %Y %H:%M:%S GMT'; }

stale_http_date() {   # 20 minutes ago — BSD date first, then GNU
  LC_ALL=C date -u -v-20M +'%a, %d %b %Y %H:%M:%S GMT' 2>/dev/null \
    || LC_ALL=C date -u -d '20 minutes ago' +'%a, %d %b %Y %H:%M:%S GMT'
}

body_digest() { printf 'SHA-256=%s' "$(printf '%s' "$1" | openssl dgst -sha256 -binary | openssl base64 -A)"; }

# auth_header <method> <path> <date> <digest|""> <secret>
# A non-empty digest produces headers="@request-target date digest"; an empty one
# produces headers="@request-target date" (the read route's set).
auth_header() {
  local method="$1" path="$2" date="$3" digest="$4" secret="$5" headers sig
  if [ -n "$digest" ]; then
    headers="@request-target date digest"
    sig="$(printf '%s\n%s %s\ndate: %s\ndigest: %s\n' "$KEY_ID" "$method" "$path" "$date" "$digest" \
           | openssl dgst -sha256 -hmac "$secret" -binary | openssl base64 -A)"
  else
    headers="@request-target date"
    sig="$(printf '%s\n%s %s\ndate: %s\n' "$KEY_ID" "$method" "$path" "$date" \
           | openssl dgst -sha256 -hmac "$secret" -binary | openssl base64 -A)"
  fi
  printf 'Signature keyId="%s",algorithm="hmac-sha256",headers="%s",signature="%s"' \
    "$KEY_ID" "$headers" "$sig"
}

BODY='{"title":"order-created","body":"sku-1","userId":1}'
DIGEST="$(body_digest "$BODY")"

echo "→ Signed write: POST $WRITE_URL"
echo "→ Signed read:  GET  $READ_URL"
echo

# --- 1: no signature ----------------------------------------------------------
status="$(curl -s -o "$BODY_FILE" -w '%{http_code}' -X POST "$WRITE_URL" \
  -H 'content-type: application/json' --data-binary "$BODY")"
[[ "$status" == "000" ]] && fail "could not reach $WRITE_URL at all — curl got no HTTP
     response. Check GATEWAY, DNS and network reachability before anything else;
     every assertion below depends on the gateway answering."
[[ "$status" == "$EXP_UNSIGNED" ]] \
  && pass "no signature → 401 (rejected in the rewrite phase, never reached upstream)" \
  || fail "no signature → ${status} (expected 401 — is hmac-auth on ${WRITE_PATH}?)"

# --- 2: correct signature -----------------------------------------------------
echo
DATE="$(http_date)"
AUTH="$(auth_header POST "$WRITE_PATH" "$DATE" "$DIGEST" "$SECRET_KEY")"
status="$(curl -s -o "$BODY_FILE" -w '%{http_code}' -X POST "$WRITE_URL" \
  -H 'content-type: application/json' -H "Date: $DATE" -H "Digest: $DIGEST" \
  -H "Authorization: $AUTH" --data-binary "$BODY")"
case "$status" in
  "$EXP_SIGNED"|200) pass "correct signature → ${status} (the signing base we document is the one the gateway builds)" ;;
  401) fail "correct signature → 401. In order of likelihood: the trailing newline was
     dropped from the signing base; the keyId line is missing; the Date is outside
     clock_skew (check the gateway's clock); or KEY_ID/SECRET_KEY are not this app's." ;;
  403) fail "correct signature → 403. Authentication succeeded but authorization did not — is api-product-enforcer on this route with no subscription behind it? See solution 03." ;;
  502|503|504) fail "correct signature → ${status}. Auth passed but the upstream errored — check the upstream binding." ;;
  *)   fail "correct signature → ${status} (expected ${EXP_SIGNED}). Body: $(tr -d '\n' < "$BODY_FILE")" ;;
esac

# --- 3: body tampered after signing -------------------------------------------
echo
status="$(curl -s -o "$BODY_FILE" -w '%{http_code}' -X POST "$WRITE_URL" \
  -H 'content-type: application/json' -H "Date: $DATE" -H "Digest: $DIGEST" \
  -H "Authorization: $AUTH" --data-binary '{"title":"TAMPERED","body":"x","userId":1}')"
[[ "$status" == "$EXP_TAMPERED" ]] \
  && pass "body tampered after signing → 401 (Digest binds the body)" \
  || fail "body tampered → ${status} (expected 401). A 2xx here means validate_request_body is off,
     or 'digest' is missing from signed_headers — in which case the signature protects
     the path and nothing else."

# --- 4: stale Date ------------------------------------------------------------
echo
OLD_DATE="$(stale_http_date)"
OLD_AUTH="$(auth_header POST "$WRITE_PATH" "$OLD_DATE" "$DIGEST" "$SECRET_KEY")"
status="$(curl -s -o "$BODY_FILE" -w '%{http_code}' -X POST "$WRITE_URL" \
  -H 'content-type: application/json' -H "Date: $OLD_DATE" -H "Digest: $DIGEST" \
  -H "Authorization: $OLD_AUTH" --data-binary "$BODY")"
[[ "$status" == "$EXP_STALE" ]] \
  && pass "Date 20 minutes old → 401 (clock_skew enforced)" \
  || fail "stale Date → ${status} (expected 401). clock_skew may be 0 or very large — it is the
     ONLY bound on how long a captured request stays replayable."

# --- 5: wrong secret ----------------------------------------------------------
echo
BAD_DATE="$(http_date)"
BAD_AUTH="$(auth_header POST "$WRITE_PATH" "$BAD_DATE" "$DIGEST" "definitely-not-the-secret")"
status="$(curl -s -o "$BODY_FILE" -w '%{http_code}' -X POST "$WRITE_URL" \
  -H 'content-type: application/json' -H "Date: $BAD_DATE" -H "Digest: $DIGEST" \
  -H "Authorization: $BAD_AUTH" --data-binary "$BODY")"
[[ "$status" == "$EXP_BADSECRET" ]] \
  && pass "correct key_id, wrong secret → 401 (the secret is verified, not just the id)" \
  || fail "wrong secret → ${status} (expected 401). If a wrong secret is accepted, the signature
     is decorative and the security model of this solution is void."

# --- 6: weak signed set (headers= omits digest) -------------------------------
echo
WEAK_DATE="$(http_date)"
WEAK_AUTH="$(auth_header POST "$WRITE_PATH" "$WEAK_DATE" "" "$SECRET_KEY")"
status="$(curl -s -o "$BODY_FILE" -w '%{http_code}' -X POST "$WRITE_URL" \
  -H 'content-type: application/json' -H "Date: $WEAK_DATE" -H "Digest: $DIGEST" \
  -H "Authorization: $WEAK_AUTH" --data-binary "$BODY")"
[[ "$status" == "$EXP_WEAKSET" ]] \
  && pass "caller signs a weaker set than required → 401 (signed_headers enforced)" \
  || fail "weak signed set → ${status} (expected 401). signed_headers is missing from the route
     config. Without it the CLIENT decides what its signature covers: a signature over
     nothing but the keyId validates, and replays against any body and any path forever."

# --- 7: exact replay (EXPECTED to succeed — this is the limitation) -----------
echo
status="$(curl -s -o "$BODY_FILE" -w '%{http_code}' -X POST "$WRITE_URL" \
  -H 'content-type: application/json' -H "Date: $DATE" -H "Digest: $DIGEST" \
  -H "Authorization: $AUTH" --data-binary "$BODY")"
if [[ "$status" == "$EXP_REPLAY" || "$status" == "200" ]]; then
  pass "byte-identical replay → ${status}, ACCEPTED AGAIN (expected — there is no nonce)"
  info "hmac-auth authenticates; it does not de-duplicate. Within clock_skew (300s here)"
  info "a captured request replays freely. If that is unacceptable for your endpoint,"
  info "make the operation idempotent upstream, or shrink clock_skew. See README § Limitations."
else
  fail "replay → ${status}, expected ${EXP_REPLAY}. A rejection here would mean replay protection
     exists on your build that this package does not document — worth investigating, and
     worth telling us about, but it is not the behaviour this solution was written against."
fi

# --- 8: signed GET on the read route ------------------------------------------
echo
GET_DATE="$(http_date)"
GET_AUTH="$(auth_header GET "$READ_PATH" "$GET_DATE" "" "$SECRET_KEY")"
status="$(curl -s -o "$BODY_FILE" -w '%{http_code}' "$READ_URL" \
  -H "Date: $GET_DATE" -H "Authorization: $GET_AUTH")"
[[ "$status" == "$EXP_GET" ]] \
  && pass "signed GET → 200 (no-digest signing set on the read route)" \
  || fail "signed GET → ${status} (expected 200). The read route's signed_headers is
     [\"@request-target\", \"date\"] — no digest. Sending a digest the route does not require
     is harmless; omitting one it DOES require is case 6."

echo
printf '\033[32mAll checks passed.\033[0m Requests are authenticated by signature, the body is bound to it,\n'
printf 'and the caller cannot negotiate a weaker signing set. Replay within clock_skew is possible by design.\n'
