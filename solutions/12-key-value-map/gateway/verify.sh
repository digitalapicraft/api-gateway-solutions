#!/usr/bin/env bash
# Solution 12 — proof that the key is fetched per request, and that rotation is a
# data change rather than a deploy.
#
# Exits 0 only if ALL of the following hold:
#   1. A partner with no registered key gets an ERROR, not a document in the clear
#   2. Registering a key succeeds
#   3. That partner then receives base64 of an armored PGP message
#   4. A DIFFERENT partner id, still unregistered, still gets the error — the store
#      is keyed per partner and one registration does not serve everybody
#   5. With gpg: the document decrypts with that partner's private key
#   6. With a SECOND key: re-registering the same partner changes which key is used,
#      with no deploy — and the old key can no longer read the new document
#
# Case 1 is the security case and case 6 is the whole point of the solution.
#
# Usage:
#   GATEWAY=https://<YOUR_GATEWAY_HOST> \
#   PUBLIC_KEY_FILE=/path/to/partner-public.asc \
#   ./verify.sh
#
# For cases 5 and 6, also set:
#   GNUPGHOME=/path/to/keyring           holds the PRIVATE key matching PUBLIC_KEY_FILE
#   SECOND_PUBLIC_KEY_FILE=/path/to/b.asc
#   SECOND_GNUPGHOME=/path/to/keyring-b  holds the private key matching it
#
# Optional overrides:
#   REGISTER_PATH  default /partners/keys
#   DOCUMENT_PATH  default /partners/documents
#   PARTNER_ID     default verify-partner-a
#   ABSENT_ID      default verify-partner-absent
#   ID_HEADER      default X-Partner-Id

set -uo pipefail

GATEWAY="${GATEWAY:?set GATEWAY to the gateway base URL, e.g. https://<YOUR_GATEWAY_HOST>}"
PUBLIC_KEY_FILE="${PUBLIC_KEY_FILE:?set PUBLIC_KEY_FILE to an ASCII-armored OpenPGP public key}"
REGISTER_PATH="${REGISTER_PATH:-/partners/keys}"
DOCUMENT_PATH="${DOCUMENT_PATH:-/partners/documents}"
PARTNER_ID="${PARTNER_ID:-verify-partner-a}"
ABSENT_ID="${ABSENT_ID:-verify-partner-absent}"
ID_HEADER="${ID_HEADER:-X-Partner-Id}"
SECOND_PUBLIC_KEY_FILE="${SECOND_PUBLIC_KEY_FILE:-}"
SECOND_GNUPGHOME="${SECOND_GNUPGHOME:-}"

REGISTER_URL="${GATEWAY%/}${REGISTER_PATH}"
DOCUMENT_URL="${GATEWAY%/}${DOCUMENT_PATH}"
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
EXP_NOKEY="$(expect no-key-registered-500.json 500)"
EXP_REG="$(expect key-registered-200.json 200)"
EXP_DOC="$(expect document-encrypted-200.json 200)"

b64d() { base64 -d 2>/dev/null <"$1" || base64 -D <"$1"; }

# Build the registration body without needing jq: JSON-escape the armored key.
reg_body() {
  awk 'BEGIN{printf "{\"public_key\": \""} {gsub(/\\/,"\\\\"); gsub(/"/,"\\\""); printf "%s\\n", $0} END{printf "\"}"}' "$1"
}

echo "→ Register route: $REGISTER_URL"
echo "→ Document route: $DOCUMENT_URL"
echo "→ Partner id:     $PARTNER_ID"
echo

# --- 1: no key registered ----------------------------------------------------
status="$(curl -s -o "$WORK/out" -w '%{http_code}' "$DOCUMENT_URL" -H "${ID_HEADER}: ${ABSENT_ID}")"
[[ "$status" == "000" ]] && fail "could not reach $DOCUMENT_URL at all — curl got no HTTP response."
if [[ "$status" == "200" ]]; then
  fail "a partner with NO registered key received 200. Check fail_policy on pgp-crypto: with
     fail-open the backend's document is returned IN THE CLEAR to a caller who was supposed to
     receive ciphertext. That is the worst outcome this solution can produce."
fi
[[ "$status" == "$EXP_NOKEY" ]] \
  && pass "an unregistered partner → ${status} ($(tr -d '\n' < "$WORK/out"))" \
  || fail "an unregistered partner → ${status} (expected ${EXP_NOKEY})."

# --- 2: register -------------------------------------------------------------
echo
reg_body "$PUBLIC_KEY_FILE" > "$WORK/reg.json"
status="$(curl -s -o "$WORK/out" -w '%{http_code}' -X POST "$REGISTER_URL" \
  -H "${ID_HEADER}: ${PARTNER_ID}" -H 'content-type: application/json' --data-binary "@$WORK/reg.json")"
[[ "$status" == "$EXP_REG" ]] \
  && pass "registered a public key for '${PARTNER_ID}'" \
  || fail "registration → ${status} (expected ${EXP_REG}). A 503 means the store could not be
     written — fail_action is close, so nothing was saved. Body: $(head -c 200 "$WORK/out")"

# --- 3: the document is now encrypted ----------------------------------------
echo
status="$(curl -s -o "$WORK/doc.b64" -w '%{http_code}' "$DOCUMENT_URL" -H "${ID_HEADER}: ${PARTNER_ID}")"
[[ "$status" == "$EXP_DOC" ]] \
  || fail "document → ${status} (expected ${EXP_DOC}). The key was registered a moment ago; if this
     is still an error, check that the fetch reference and the encrypt reference are the SAME
     template, and that it is \$request.headers.<name> — 'headers' plural."
if b64d "$WORK/doc.b64" > "$WORK/doc.asc" 2>/dev/null && head -1 "$WORK/doc.asc" | grep -q 'BEGIN PGP MESSAGE'; then
  pass "the document is base64 of an ASCII-armored PGP message"
else
  fail "the document is not base64-of-armor. Got: $(head -c 120 "$WORK/doc.b64")"
fi
grep -q '{' "$WORK/doc.b64" && fail "readable JSON survives in the response — the encryption did not happen."

# --- 4: isolation ------------------------------------------------------------
echo
status="$(curl -s -o "$WORK/out" -w '%{http_code}' "$DOCUMENT_URL" -H "${ID_HEADER}: ${ABSENT_ID}")"
[[ "$status" == "$EXP_NOKEY" ]] \
  && pass "a different, unregistered partner still gets ${status} (entries are per partner)" \
  || fail "the unregistered partner now gets ${status}. One registration is serving every caller —
     check that the fetch key is a reference and not a fixed string."

# --- 5: decrypt --------------------------------------------------------------
echo
if ! command -v gpg >/dev/null 2>&1 || [[ -z "${GNUPGHOME:-}" ]]; then
  info "decryption skipped — needs gpg and GNUPGHOME holding the private key that matches
     PUBLIC_KEY_FILE. Cases 1-4 still establish the per-partner behaviour."
  echo; printf '\033[32mAll runnable checks passed.\033[0m\n'; exit 0
fi
if gpg --quiet --batch --decrypt "$WORK/doc.asc" > "$WORK/doc.json" 2>/dev/null && [[ -s "$WORK/doc.json" ]]; then
  pass "the document decrypts with that partner's private key"
else
  fail "could not decrypt. The stored key is not the one this keyring holds the private half of —
     which is exactly the failure that is invisible from the gateway's side."
fi

# --- 6: rotation -------------------------------------------------------------
echo
if [[ -z "$SECOND_PUBLIC_KEY_FILE" || -z "$SECOND_GNUPGHOME" ]]; then
  info "rotation skipped — set SECOND_PUBLIC_KEY_FILE and SECOND_GNUPGHOME to prove that
     re-registering changes which key is used, with no deploy. This is the case the solution
     exists for; run it once per environment."
  echo; printf '\033[32mAll runnable checks passed.\033[0m\n'; exit 0
fi
reg_body "$SECOND_PUBLIC_KEY_FILE" > "$WORK/reg2.json"
status="$(curl -s -o /dev/null -w '%{http_code}' -X POST "$REGISTER_URL" \
  -H "${ID_HEADER}: ${PARTNER_ID}" -H 'content-type: application/json' --data-binary "@$WORK/reg2.json")"
[[ "$status" == "$EXP_REG" ]] || fail "re-registration → ${status} (expected ${EXP_REG})."
curl -s -o "$WORK/doc2.b64" "$DOCUMENT_URL" -H "${ID_HEADER}: ${PARTNER_ID}"
b64d "$WORK/doc2.b64" > "$WORK/doc2.asc" || fail "the post-rotation document is not base64."
if GNUPGHOME="$SECOND_GNUPGHOME" gpg --quiet --batch --decrypt "$WORK/doc2.asc" >/dev/null 2>&1; then
  pass "after re-registering, the document is encrypted to the NEW key — no deploy involved"
else
  fail "the new key cannot decrypt the document. The rotation did not take effect; check that the
     registration overwrote the entry rather than creating a second one."
fi
if gpg --quiet --batch --decrypt "$WORK/doc2.asc" >/dev/null 2>&1; then
  fail "the OLD key still decrypts the new document. The rotation did not replace the entry."
else
  pass "the OLD key can no longer read it — the entry was replaced, not appended"
fi

echo
printf '\033[32mAll checks passed.\033[0m One route, per-partner keys, and rotation without a deploy.\n'
