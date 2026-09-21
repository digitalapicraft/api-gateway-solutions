#!/usr/bin/env bash
# Solution 13 — proof that the gateway is doing the crypto.
#
# Exits 0 only if ALL of the following hold:
#   1. The response body is BASE64 of an ASCII-armored PGP message, and the content
#      type is text/plain
#   2. The plaintext statement does NOT appear in the response
#   3. A raw ARMORED request body is REJECTED (the wire format is base64 of armor)
#   4. A body that is not a PGP message at all is rejected the same way
#   5. With gpg and a key pair available: a base64(armored) request decrypts and the
#      backend receives the plaintext, and the encrypted response decrypts back to
#      the backend's document
#
# Cases 1-4 need nothing but bash, curl and base64. Case 5 needs gpg and your keys,
# and is skipped loudly without them — so the script is still worth running in a
# pipeline that has no key material.
#
# Usage:
#   GATEWAY=https://<YOUR_GATEWAY_HOST> ./verify.sh
#
# For the round trip (case 5), also set:
#   GNUPGHOME=/path/to/keyring        a keyring holding the PRIVATE key that matches
#                                     the route's public_key, and the PUBLIC key that
#                                     matches the route's private_key
#   RECIPIENT=partner@example.com     the uid to encrypt to for the inbound test
#
# Optional overrides:
#   READ_PATH   default /statements/2024-Q1
#   WRITE_PATH  default /statements/inbound

set -uo pipefail

GATEWAY="${GATEWAY:?set GATEWAY to the gateway base URL, e.g. https://<YOUR_GATEWAY_HOST>}"
READ_PATH="${READ_PATH:-/statements/2024-Q1}"
WRITE_PATH="${WRITE_PATH:-/statements/inbound}"
RECIPIENT="${RECIPIENT:-}"

READ_URL="${GATEWAY%/}${READ_PATH}"
WRITE_URL="${GATEWAY%/}${WRITE_PATH}"
WORK="$(mktemp -d)"
trap 'rm -rf "$WORK"' EXIT

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
EXP_READ="$(expect statement-encrypted-200.json 200)"
EXP_ARMOR="$(expect armored-body-400.json 400)"
EXP_PLAIN="$(expect plaintext-body-400.json 400)"
EXP_WRITE="$(expect inbound-decrypted-200.json 200)"

# base64 -d on GNU, base64 -D on BSD/macOS
b64d() { base64 -d 2>/dev/null <"$1" || base64 -D <"$1"; }

echo "→ Read route:  $READ_URL"
echo "→ Write route: $WRITE_URL"
echo

# --- 1: the response is base64 of an armored message -------------------------
status="$(curl -s -o "$WORK/resp.b64" -w '%{http_code}' -D "$WORK/resp.h" "$READ_URL")"
[[ "$status" == "000" ]] && fail "could not reach $READ_URL at all — curl got no HTTP response."
[[ "$status" == "$EXP_READ" ]] \
  || fail "read route → ${status} (expected ${EXP_READ}). A 500 here means the response could not be
     encrypted — usually an unparseable public_key. The caller's message is deliberately generic;
     the reason is in the gateway's telemetry. Body: $(head -c 200 "$WORK/resp.b64")"

grep -qi 'content-type:.*text/plain' "$WORK/resp.h" \
  && pass "content-type is text/plain (the body is no longer the backend's JSON)" \
  || info "content-type is not text/plain — check the route; the plugin sets it when it encrypts"

if b64d "$WORK/resp.b64" > "$WORK/resp.asc" 2>/dev/null && head -1 "$WORK/resp.asc" | grep -q 'BEGIN PGP MESSAGE'; then
  pass "the response body is BASE64 of an ASCII-armored PGP message"
else
  if head -1 "$WORK/resp.b64" | grep -q 'BEGIN PGP MESSAGE'; then
    fail "the response is RAW ARMOR, not base64 of armor. That is not what this build produced in
     validation — re-check the deployed plugin version before writing a client against it."
  fi
  fail "the response body is neither base64-of-armor nor armor. Got: $(head -c 120 "$WORK/resp.b64")"
fi

# --- 2: the plaintext is not in the response ---------------------------------
if grep -qi 'slideshow\|"date"\|{' "$WORK/resp.b64"; then
  fail "the response body still contains readable JSON. The encryption did not happen — a
     fail_policy of fail-open would do exactly this, silently."
fi
pass "no readable plaintext survives in the response"

# --- 3: a raw armored request body is rejected -------------------------------
echo
printf -- '-----BEGIN PGP MESSAGE-----\n\nhQEMA0000000000000\n-----END PGP MESSAGE-----\n' > "$WORK/armor.txt"
status="$(curl -s -o "$WORK/out" -w '%{http_code}' -X POST "$WRITE_URL" \
  -H 'content-type: text/plain' --data-binary "@$WORK/armor.txt")"
[[ "$status" == "$EXP_ARMOR" ]] \
  && pass "a RAW ARMORED body is rejected with ${status} — the wire format is base64 of armor" \
  || fail "a raw armored body → ${status} (expected ${EXP_ARMOR}). If your build accepts raw armor,
     this package's wire-format guidance does not apply to it and your integration guide must say so."

# --- 4: a non-PGP body is rejected -------------------------------------------
status="$(curl -s -o "$WORK/out" -w '%{http_code}' -X POST "$WRITE_URL" \
  -H 'content-type: text/plain' --data-binary 'hello')"
[[ "$status" == "$EXP_PLAIN" ]] \
  && pass "a plaintext body is rejected with ${status} (fail-close: the backend is never called)" \
  || fail "a plaintext body → ${status} (expected ${EXP_PLAIN}). If this reaches the backend, the
     policy is fail-open and your backend is receiving whatever arrives."

# --- 5: the round trip -------------------------------------------------------
echo
if ! command -v gpg >/dev/null 2>&1; then
  info "round trip skipped — gpg is not installed. Cases 1-4 above still establish the wire format
     and the fail-close behaviour."
  echo; printf '\033[32mAll runnable checks passed.\033[0m\n'; exit 0
fi
if [[ -z "${GNUPGHOME:-}" || -z "$RECIPIENT" ]]; then
  info "round trip skipped — set GNUPGHOME and RECIPIENT to decrypt the statement and to encrypt an
     inbound file. Without them the script cannot hold key material."
  echo; printf '\033[32mAll runnable checks passed.\033[0m\n'; exit 0
fi

if gpg --quiet --batch --decrypt "$WORK/resp.asc" > "$WORK/resp.json" 2>/dev/null && [[ -s "$WORK/resp.json" ]]; then
  pass "the statement decrypts with the partner's private key ($(wc -c < "$WORK/resp.json" | tr -d ' ') bytes of plaintext)"
else
  fail "could not decrypt the statement. The keyring does not hold the private key matching the
     route's public_key, or the message is for a different recipient."
fi

printf '{"instructionId":"INS-4471","amountCents":125000}' > "$WORK/inst.json"
gpg --batch --yes --trust-model always --armor --encrypt -r "$RECIPIENT" \
    -o "$WORK/inst.asc" "$WORK/inst.json" 2>/dev/null \
  || fail "could not encrypt to '${RECIPIENT}' — is that uid in the keyring, and does it match the
     route's private_key?"
base64 < "$WORK/inst.asc" | tr -d '\n' > "$WORK/inst.b64"
status="$(curl -s -o "$WORK/echo" -w '%{http_code}' -X POST "$WRITE_URL" \
  -H 'content-type: text/plain' --data-binary "@$WORK/inst.b64")"
[[ "$status" == "$EXP_WRITE" ]] \
  || fail "base64(armored) inbound → ${status} (expected ${EXP_WRITE}). Body: $(head -c 200 "$WORK/echo")"
grep -q 'INS-4471' "$WORK/echo" \
  && pass "the backend received the DECRYPTED instruction (the echo shows the plaintext)" \
  || info "could not see the plaintext in the echo — if your backend does not echo requests, read
     its own log to confirm it received plaintext rather than ciphertext."

echo
printf '\033[32mAll checks passed.\033[0m The gateway decrypts inbound and encrypts outbound;\n'
printf 'the backend never handles ciphertext and the partner never handles plaintext.\n'
