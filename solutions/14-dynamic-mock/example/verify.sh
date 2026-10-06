#!/usr/bin/env bash
# Solution 14 — proof that a mocked route answers each caller with that caller's
# own stored values, and that changing a value needs no deploy.
#
# Exits 0 only if ALL of the following hold:
#   1. Register              → POST /sandbox/partners returns 202
#   2. Per-caller read       → partner A's profile carries partner A's values
#   3. Isolation             → partner B's profile carries B's, not A's
#   4. Miss                  → an unregistered partner gets 200 with empty values
#   5. Change without deploy → re-registering A changes A's answer immediately
#   6. Grammar               → the bare $ctx form resolves and ${...} does not
#
# Case 6 is the one worth keeping. It is the difference between a package that
# works and one whose reader silently writes the other grammar and gets empty
# strings with a 200 and no error anywhere.
#
# Usage:
#   GATEWAY=https://<YOUR_GATEWAY_HOST> ./verify.sh
#
# Optional overrides:
#   REGISTER_PATH    default /sandbox/partners
#   PROFILE_PATH     default /sandbox/profile
#   DIAGNOSTICS_PATH default /sandbox/diagnostics

set -uo pipefail

GATEWAY="${GATEWAY:?set GATEWAY to the gateway base URL, e.g. https://<YOUR_GATEWAY_HOST>}"
REGISTER_PATH="${REGISTER_PATH:-/sandbox/partners}"
PROFILE_PATH="${PROFILE_PATH:-/sandbox/profile}"
DIAGNOSTICS_PATH="${DIAGNOSTICS_PATH:-/sandbox/diagnostics}"

REGISTER_URL="${GATEWAY%/}${REGISTER_PATH}"
PROFILE_URL="${GATEWAY%/}${PROFILE_PATH}"
DIAG_URL="${GATEWAY%/}${DIAGNOSTICS_PATH}"

# Unique ids per run, so a re-run is not answered by the previous run's values.
RUN="$(date +%s)"
A="acme-${RUN}"
B="globex-${RUN}"
MISSING="nobody-${RUN}"

BODY_FILE="$(mktemp)"
trap 'rm -f "$BODY_FILE"' EXIT

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
EXP_REGISTER="$(expect register-202.json 202)"
EXP_PROFILE="$(expect profile-registered-200.json 200)"
EXP_MISS="$(expect profile-unregistered-200.json 200)"
EXP_ROTATED="$(expect profile-rotated-200.json 200)"
EXP_DIAG="$(expect diagnostics-200.json 200)"

register() { # id tier account
  curl -s -o "$BODY_FILE" -w '%{http_code}' -X POST "$REGISTER_URL" \
    -H "x-partner-id: $1" -H "x-tier: $2" -H "x-settlement-account: $3"
}
profile() { # id
  curl -s -o "$BODY_FILE" -w '%{http_code}' "$PROFILE_URL" -H "x-partner-id: $1"
}

# 1 -----------------------------------------------------------------------------
code="$(register "$A" gold "GB29-SANDBOX-0001")"
[ "$code" = "$EXP_REGISTER" ] || fail "register $A returned $code, expected $EXP_REGISTER"
pass "1. register -> $EXP_REGISTER"

code="$(register "$B" bronze "GB29-SANDBOX-0002")"
[ "$code" = "$EXP_REGISTER" ] || fail "register $B returned $code, expected $EXP_REGISTER"

# 2 -----------------------------------------------------------------------------
code="$(profile "$A")"; body="$(cat "$BODY_FILE")"
[ "$code" = "$EXP_PROFILE" ] || fail "profile $A returned $code, expected $EXP_PROFILE"
case "$body" in
  *'"tier":"gold"'*) ;;
  *) fail "profile $A did not carry its own tier: $body" ;;
esac
case "$body" in
  *'"settlement":"GB29-SANDBOX-0001"'*) ;;
  *) fail "profile $A did not carry its own settlement account: $body" ;;
esac
pass "2. the caller's own values came back"

# 3 -----------------------------------------------------------------------------
code="$(profile "$B")"; body="$(cat "$BODY_FILE")"
case "$body" in
  *'"tier":"bronze"'*) ;;
  *) fail "profile $B did not carry its own tier: $body" ;;
esac
case "$body" in
  *gold*) fail "partner isolation broken — $B can see $A's tier: $body" ;;
esac
pass "3. a second partner got its own values, not the first's"

# 4 -----------------------------------------------------------------------------
code="$(profile "$MISSING")"; body="$(cat "$BODY_FILE")"
[ "$code" = "$EXP_MISS" ] || fail "unregistered partner returned $code, expected $EXP_MISS"
case "$body" in
  *'"tier":""'*) ;;
  *) fail "a store miss should yield an empty tier, got: $body" ;;
esac
pass "4. an unregistered partner is an empty value, not an error"

# 5 -----------------------------------------------------------------------------
register "$A" platinum "GB29-SANDBOX-0009" >/dev/null
code="$(profile "$A")"; body="$(cat "$BODY_FILE")"
[ "$code" = "$EXP_ROTATED" ] || fail "profile after change returned $code, expected $EXP_ROTATED"
case "$body" in
  *'"tier":"platinum"'*) ;;
  *) fail "re-registering did not change the answer: $body" ;;
esac
pass "5. a value changed with no revision, no route change and no deploy"

# 6 -----------------------------------------------------------------------------
code="$(curl -s -o "$BODY_FILE" -w '%{http_code}' "$DIAG_URL" -H "x-partner-id: $A")"
body="$(cat "$BODY_FILE")"
[ "$code" = "$EXP_DIAG" ] || fail "diagnostics returned $code, expected $EXP_DIAG"
case "$body" in
  *"bare_form   = platinum"*) ;;
  *) fail "the bare \$ctx form did not resolve: $body" ;;
esac
if printf '%s' "$body" | grep -q 'brace_form  = .\+'; then
  fail "the \${...} form resolved, which contradicts this package's central claim: $body"
fi
pass "6. bare \$ctx resolves; \${...} does not — the grammar claim holds"

printf '\n\033[32mAll 6 checks passed.\033[0m\n'
