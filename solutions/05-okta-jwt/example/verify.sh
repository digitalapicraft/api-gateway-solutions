#!/usr/bin/env bash
# Solution 05 — proof that the gateway verifies OKTA-issued access tokens.
#
# Exits 0 only if ALL of the following hold:
#   1. No token          -> 401  (and specifically NOT a 302 to Okta's login page)
#   2. Okta client creds -> a token from YOUR Okta, RS256-signed, with a kid
#   3. Valid token       -> the protected route returns 200
#   4. Forged token      -> 401 (a JWT no Okta key signed)
#   5. alg=none token    -> 401 (the "unsigned token" attack)
#   6. Bearer omitted    -> 401
#   7. Wrong issuer      -> 401 (only if OTHER_ISSUER_TOKEN is supplied)
#
# Case 1 is the one people skip, and it is the one that proves you configured
# this for an API rather than for a browser. The plugin's unauth_action DEFAULTS
# to "auth", which answers an unauthenticated API call with a 302 redirect to
# Okta's HTML login form. Everything still "works" in a browser and every API
# client breaks. If case 1 reports 302, unauth_action is not set to deny.
#
# Case 5 matters because accept_none_alg exists and accept_unsupported_alg
# DEFAULTS TO TRUE. A token whose header says {"alg":"none"} and which carries no
# signature at all must be rejected.
#
# Usage — let the script fetch a token from Okta (client credentials):
#   GATEWAY=https://<YOUR_GATEWAY_HOST> \
#   OKTA_TOKEN_URL=https://<your-okta-domain>/oauth2/<authServerId>/v1/token \
#   OKTA_CLIENT_ID=<CLIENT_ID> \
#   OKTA_CLIENT_SECRET=<CLIENT_SECRET> \
#   OKTA_SCOPE=<the scope your authorization server grants> \
#   TOKEN_AUDIENCE=<the API's audience, if your server needs one> \
#   ./verify.sh
#
# TOKEN_AUDIENCE matters more than it looks. Auth0 ALWAYS requires an audience to
# issue a JWT — without one it errors, or returns an opaque token that cannot be
# verified locally at all. Okta custom authorization servers usually want one too.
#
# Or bring your own token (any grant, including a user-obtained one):
#   GATEWAY=https://<YOUR_GATEWAY_HOST> ACCESS_TOKEN=<paste> ./verify.sh
#
# Optional:
#   API_PATH            default /posts
#   TOKEN_AUDIENCE      audience parameter for the token request (see above)
#   OTHER_ISSUER_TOKEN  a valid token from a DIFFERENT authorization server;
#                       enables case 7, the issuer-pinning check
#   PACE                seconds to wait between requests (default 7). Environments
#                       commonly rate-limit; a burst of cases returns 429, which
#                       reads like a failure and isn't one. Set 0 to disable.
#
# WHAT THIS SCRIPT DOES NOT TEST, BECAUSE IT CANNOT PASS:
# a token whose `aud` is a DIFFERENT API is ACCEPTED by this plugin. Verified
# against a deployed route: aud=https://totally-unrelated-api.example.com/ -> 200.
# claim_validator.audience only checks that the claim is PRESENT (a missing aud
# gives 403). There is no expected-value field. If you need to tell APIs in one
# tenant apart, use required_scopes — see README section Gotchas.

set -uo pipefail

GATEWAY="${GATEWAY:?set GATEWAY to the gateway base URL, e.g. https://<YOUR_GATEWAY_HOST>}"
API_PATH="${API_PATH:-/posts}"
ACCESS_TOKEN="${ACCESS_TOKEN:-}"
OKTA_TOKEN_URL="${OKTA_TOKEN_URL:-}"
OKTA_CLIENT_ID="${OKTA_CLIENT_ID:-}"
OKTA_CLIENT_SECRET="${OKTA_CLIENT_SECRET:-}"
OKTA_SCOPE="${OKTA_SCOPE:-}"
TOKEN_AUDIENCE="${TOKEN_AUDIENCE:-}"
OTHER_ISSUER_TOKEN="${OTHER_ISSUER_TOKEN:-}"
PACE="${PACE:-7}"

API_URL="${GATEWAY%/}${API_PATH}"
BODY_FILE="$(mktemp)"
trap 'rm -f "$BODY_FILE"' EXIT

pace() { [[ "$PACE" -gt 0 ]] && sleep "$PACE"; return 0; }
fail() { printf '\033[31mFAIL\033[0m  %s\n' "$1"; exit 1; }
pass() { printf '\033[32mPASS\033[0m  %s\n' "$1"; }
info() { printf '\033[34mNOTE\033[0m  %s\n' "$1"; }

# --- expected statuses come from the fixtures, not from literals here ---------
# tests/expected/*.json is the single source of truth for what each case expects,
# so this script and the fixtures cannot drift apart. Parsed with sed, so verify.sh
# still needs nothing beyond bash and curl. If a fixture is missing (someone copied
# this script on its own) the second argument is used instead.
FIXTURES="$(cd "$(dirname "${BASH_SOURCE[0]}")/../tests/expected" 2>/dev/null && pwd || true)"
expect() {
  local f="${FIXTURES:-}/$1" v=""
  [ -n "${FIXTURES:-}" ] && [ -f "$f" ] && \
    v="$(sed -n 's/.*"status"[[:space:]]*:[[:space:]]*\([0-9][0-9]*\).*/\1/p' "$f" | head -1)"
  printf '%s' "${v:-$2}"
}
EXP_UNAUTH="$(expect unauthenticated.json 401)"
EXP_TOKEN="$(expect okta-token-200.json 200)"
EXP_VALID="$(expect valid-200.json 200)"
EXP_REJECTED="$(expect rejected-401.json 401)"
EXP_NOSCHEME="$(expect no-scheme-400.json 400)"

# Decode a JWT segment (base64url, no padding) without any dependency but base64.
b64url() { local s="${1//-/+}"; s="${s//_//}"; case $(( ${#s} % 4 )) in 2) s="$s==";; 3) s="$s=";; esac; printf '%s' "$s" | base64 -d 2>/dev/null; }

echo "→ Protected API: $API_URL"
echo

# --- 1: no token -------------------------------------------------------------
status="$(curl -s -o "$BODY_FILE" -w '%{http_code}' "$API_URL")"
[[ "$status" == "000" ]] && fail "could not reach $API_URL at all — curl got no HTTP
     response. Check GATEWAY, DNS and network reachability before anything else."
case "$status" in
  "$EXP_UNAUTH") pass "no token → ${status} (rejected in the access phase, never reached upstream)" ;;
  302|303|307) fail "no token → ${status}, a REDIRECT. unauth_action is still \"auth\" (its
     default), so the gateway is bouncing API clients to Okta's login page instead
     of refusing them. Set unauth_action: deny (and bearer_only: true)." ;;
  200) fail "no token → 200. The route is not protected at all — is the
     openid-connect block present at the document root of the deployed revision?" ;;
  *)   fail "no token → ${status} (expected 401)." ;;
esac

# --- 2: obtain a token from Okta ---------------------------------------------
echo
if [[ -z "$ACCESS_TOKEN" ]]; then
  [[ -n "$OKTA_TOKEN_URL" && -n "$OKTA_CLIENT_ID" && -n "$OKTA_CLIENT_SECRET" ]] \
    || fail "no ACCESS_TOKEN given and OKTA_TOKEN_URL / OKTA_CLIENT_ID / OKTA_CLIENT_SECRET
     are not all set. Supply one or the other — see the usage block above."
  extra=()
  [[ -n "$OKTA_SCOPE"     ]] && extra+=(--data-urlencode "scope=${OKTA_SCOPE}")
  [[ -n "$TOKEN_AUDIENCE" ]] && extra+=(--data-urlencode "audience=${TOKEN_AUDIENCE}")
  status="$(curl -s -o "$BODY_FILE" -w '%{http_code}' -X POST "$OKTA_TOKEN_URL" \
    -u "${OKTA_CLIENT_ID}:${OKTA_CLIENT_SECRET}" \
    -H 'content-type: application/x-www-form-urlencoded' \
    --data-urlencode 'grant_type=client_credentials' "${extra[@]}")"
  [[ "$status" == "$EXP_TOKEN" ]] \
    || fail "token request → ${status} (expected 200). Body: $(tr -d '\n' < "$BODY_FILE")
     This is the IdP refusing, not the gateway. Common causes: the app is not
     enabled for the client-credentials grant; the scope is not granted to it; or
     no audience was supplied and the tenant has no default (Auth0 reports exactly
     that — set TOKEN_AUDIENCE). 'not authorized to access resource server' means
     the app has no grant for that API — create one in the IdP."
  ACCESS_TOKEN="$(tr -d '\n' < "$BODY_FILE" | sed -n 's/.*"access_token"[[:space:]]*:[[:space:]]*"\([^"]*\)".*/\1/p')"
  [[ -n "$ACCESS_TOKEN" ]] || fail "200 from Okta but no access_token in the body."
  pass "Okta issued an access token via client credentials"
else
  info "using the ACCESS_TOKEN supplied in the environment"
fi

# The token must be a JWT, and Okta must have signed it with RS256.
if [[ "$ACCESS_TOKEN" =~ ^[A-Za-z0-9_-]+\.[A-Za-z0-9_-]+\.[A-Za-z0-9_-]+$ ]]; then
  pass "access_token is a well-formed JWT (three segments)"
else
  fail "access_token is not a three-segment JWT — got '${ACCESS_TOKEN:0:32}...'.
     An opaque token means this Okta authorization server issues opaque tokens, and
     local JWKS verification cannot work. You would need introspection instead."
fi
hdr="$(b64url "${ACCESS_TOKEN%%.*}")"
case "$hdr" in
  *'"alg":"RS256"'*|*'"alg": "RS256"'*) pass "token header declares alg RS256" ;;
  *) info "token header is ${hdr:-<undecodable>} — this solution pins RS256 via token_signing_alg_values_expected" ;;
esac
case "$hdr" in
  *'"kid"'*) pass "token header carries a kid (the gateway can select the right JWKS key)" ;;
  *) info "no kid in the token header — key selection relies on there being a single key" ;;
esac

pace
# --- 3: valid token ----------------------------------------------------------
echo
status="$(curl -s -o "$BODY_FILE" -w '%{http_code}' "$API_URL" \
  -H "authorization: Bearer ${ACCESS_TOKEN}")"
case "$status" in
  200|201) pass "valid Okta token → ${status}" ;;
  401) fail "valid Okta token → 401. Most likely causes, in order:
     (a) claim_validator.issuer.valid_issuers does not exactly match the \"issuer\"
         in your discovery document — it must match character for character;
     (b) discovery points at a different authorization server than the one that
         minted this token;
     (c) the JWKS cache is stale after an Okta key rotation (jwk_expires_in)." ;;
  403) fail "valid token → 403. Authentication passed, a claim check did not.
     Two known causes: (a) required_scopes is set and this token lacks them;
     (b) the token has NO aud claim — claim_validator.audience.required rejects a
     missing audience with 403, not 401. Decode the token and check." ;;
  502|503|504) fail "valid token → ${status}. Auth passed but the upstream errored — check the upstream binding." ;;
  *)   fail "valid token → ${status} (expected 200). Body: $(tr -d '\n' < "$BODY_FILE")" ;;
esac

pace
# --- 4: forged token ---------------------------------------------------------
echo
forged="${ACCESS_TOKEN%.*}.bm90LWEtdmFsaWQtc2lnbmF0dXJl"
status="$(curl -s -o "$BODY_FILE" -w '%{http_code}' "$API_URL" -H "authorization: Bearer ${forged}")"
[[ "$status" == "$EXP_REJECTED" ]] \
  && pass "forged signature → 401 (the RS256 signature is actually verified against Okta's JWKS)" \
  || fail "forged signature → ${status} (expected 401). This is the most serious possible
     failure: the header is being parsed but the signature is not being checked."

pace
# --- 5: alg=none -------------------------------------------------------------
echo
none_tok="eyJhbGciOiJub25lIiwidHlwIjoiSldUIn0.eyJzdWIiOiJhdHRhY2tlciIsImlzcyI6ImF0dGFja2VyIn0."
status="$(curl -s -o "$BODY_FILE" -w '%{http_code}' "$API_URL" -H "authorization: Bearer ${none_tok}")"
[[ "$status" == "$EXP_REJECTED" ]] \
  && pass "alg=none token → 401 (unsigned tokens are refused)" \
  || fail "alg=none token → ${status} (expected 401). Check accept_none_alg is false and
     accept_unsupported_alg is false — the latter DEFAULTS TO TRUE."

pace
# --- 6: malformed authorization header ---------------------------------------
echo
status="$(curl -s -o "$BODY_FILE" -w '%{http_code}' "$API_URL" -H "authorization: ${ACCESS_TOKEN}")"
# Observed against a live gateway: a value with NO recognised auth scheme is
# rejected at header-parse time with 400, before the plugin sees it — not 401.
# Deterministic, and independent of the value's length. Accept either, because
# the point of the case is that a scheme-less credential never reaches upstream.
case "$status" in
  "$EXP_NOSCHEME") pass "token without the Bearer prefix → ${status} (rejected at header parse, before the plugin)" ;;
  401) pass "token without the Bearer prefix → 401" ;;
  200|201) fail "token without the Bearer prefix → ${status}. A credential with no auth
     scheme was ACCEPTED. The route is not parsing the Authorization header correctly." ;;
  *)   fail "token without the Bearer prefix → ${status} (expected 400 or 401)." ;;
esac

pace
# --- 7: wrong issuer (optional) ----------------------------------------------
echo
if [[ -n "$OTHER_ISSUER_TOKEN" ]]; then
  status="$(curl -s -o "$BODY_FILE" -w '%{http_code}' "$API_URL" -H "authorization: Bearer ${OTHER_ISSUER_TOKEN}")"
  [[ "$status" == "$EXP_REJECTED" ]] \
    && pass "token from a different issuer → 401 (valid_issuers pinning holds)" \
    || fail "token from a different issuer → ${status} (expected 401). A correctly
     signed token from ANOTHER authorization server is being accepted. Check
     claim_validator.issuer.valid_issuers."
else
  info "case 7 skipped — set OTHER_ISSUER_TOKEN to a valid token from a DIFFERENT Okta
     authorization server to prove issuer pinning. This is the check that proves the
     token is specific to THIS API, so run it at least once per environment."
fi

echo
printf '\033[32mAll checks passed.\033[0m Okta-issued tokens are verified at the gateway.\n'
