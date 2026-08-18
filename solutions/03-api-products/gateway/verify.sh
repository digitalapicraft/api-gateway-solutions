#!/usr/bin/env bash
# Solution 03 — proof that API Product quota is enforced, and enforced PER APP.
#
# Exits 0 only if ALL of the following hold:
#   1. No key            → 401
#   2. Unknown key       → 401
#   3. Valid Free key    → 200 (the app is subscribed to a product covering this API)
#   4. Over the window   → the Free app eventually returns 429
#   5. ISOLATION         → at that same moment, a SECOND app on a different
#                          product still returns 200
#
# CASE 5 IS THE WHOLE POINT. Cases 1-4 only prove a rate limit exists; any
# limiter can do that. Case 5 proves the limit is scoped to the offending app and
# not to your API — which is the entire business case. Do not skip it.
#
# The two keys MUST belong to TWO SEPARATE APPS. Quota is counted per app
# (credential), so two keys on the same app share one bucket and correct
# isolation will look broken.
#
# Usage:
#   GATEWAY=https://<YOUR_GATEWAY_HOST> \
#   FREE_KEY=<client id of the app subscribed to Free> \
#   PRO_KEY=<client id of a DIFFERENT app subscribed to Pro> \
#   FREE_LIMIT=60 \
#   ./verify.sh
#
# Optional overrides:
#   API_PATH     default /orders
#   HEADER       default apikey
#   MAX_TRIES    default = FREE_LIMIT * 2 + 10 (safety stop)

set -uo pipefail

GATEWAY="${GATEWAY:?set GATEWAY to the gateway base URL, e.g. https://<YOUR_GATEWAY_HOST>}"
FREE_KEY="${FREE_KEY:?set FREE_KEY to the client id of the app subscribed to the Free product}"
PRO_KEY="${PRO_KEY:?set PRO_KEY to the client id of a DIFFERENT app subscribed to the Pro product}"
FREE_LIMIT="${FREE_LIMIT:?set FREE_LIMIT to the Free product quota limit, e.g. 60}"
API_PATH="${API_PATH:-/orders}"
HEADER="${HEADER:-apikey}"
MAX_TRIES="${MAX_TRIES:-$(( FREE_LIMIT * 2 + 10 ))}"

API_URL="${GATEWAY%/}${API_PATH}"
BODY_FILE="$(mktemp)"
trap 'rm -f "$BODY_FILE"' EXIT

fail() { printf '\033[31mFAIL\033[0m  %s\n' "$1"; exit 1; }
pass() { printf '\033[32mPASS\033[0m  %s\n' "$1"; }
info() { printf '\033[34mNOTE\033[0m  %s\n' "$1"; }

if [[ "$FREE_KEY" == "$PRO_KEY" ]]; then
  fail "FREE_KEY and PRO_KEY are identical. They must be keys from TWO SEPARATE APPS —
     quota is counted per app, so two keys on one app share a bucket and case 5
     cannot prove anything."
fi

echo "→ Metered API: $API_URL"
echo "→ Free limit:  $FREE_LIMIT per window"
echo

call() { # $1 = key (may be empty), prints the status code
  if [[ -z "$1" ]]; then
    curl -s -o "$BODY_FILE" -w '%{http_code}' "$API_URL"
  else
    curl -s -o "$BODY_FILE" -w '%{http_code}' "$API_URL" -H "${HEADER}: $1"
  fi
}

# --- 1: no key ---------------------------------------------------------------
status="$(call "")"
[[ "$status" == "000" ]] && fail "could not reach $API_URL at all — curl got no HTTP
     response. Check GATEWAY, DNS and network reachability before anything else;
     every assertion below depends on the gateway answering."
[[ "$status" == "401" ]] \
  && pass "no key → 401" \
  || fail "no key → ${status} (expected 401 — is helix-auth validate on this API?)"

# --- 2: unknown key ----------------------------------------------------------
echo
status="$(call "definitely-not-a-real-client-id")"
[[ "$status" == "401" ]] \
  && pass "unknown key → 401" \
  || fail "unknown key → ${status} (expected 401)."

# --- 3: valid Free key -------------------------------------------------------
echo
status="$(call "$FREE_KEY")"
case "$status" in
  200|201) pass "valid Free key → ${status}" ;;
  401) fail "valid Free key → 401. You are probably sending the app's SECRET where its KEY (client id) belongs — key-auth validate resolves on the credential key." ;;
  403) fail "valid Free key → 403. Two usual causes, in order:
       (a) the route has no service_id — the enforcer returns 403 before quota is
           even considered, and nothing in the plugin config hints at this;
       (b) the app is not subscribed to a product covering this API, or that
           product has no quota object (which is a 403, NOT 'unlimited').
       Also check helix-auth is used rather than raw key-auth: key-auth resolves no
       product subscription, so there is nothing for the enforcer to enforce." ;;
  503) fail "valid Free key → 503. The quota backend is unreachable and error_policy is fail_close. Check plugin_attr.api-product-enforcer in the gateway config." ;;
  *) fail "valid Free key → ${status} (expected 200). Body: $(tr -d '\n' < "$BODY_FILE")" ;;
esac

# --- 4: spend the Free window ------------------------------------------------
echo
info "spending the Free app's window (up to ${MAX_TRIES} calls)…"
free_429_at=0
for (( i=2; i<=MAX_TRIES; i++ )); do
  status="$(call "$FREE_KEY")"
  if [[ "$status" == "429" ]]; then free_429_at=$i; break; fi
  if [[ "$status" != "200" && "$status" != "201" ]]; then
    fail "unexpected ${status} on Free call #${i} while filling the window. Body: $(tr -d '\n' < "$BODY_FILE")"
  fi
done

if (( free_429_at == 0 )); then
  fail "the Free app never hit 429 in ${MAX_TRIES} calls (limit is supposedly ${FREE_LIMIT}).
     Three usual causes:
       (a) the quota is higher than you think — check the product actually deployed
           to this environment, not the one you edited;
       (b) quota_policy is 'local' on a multi-node gateway, so each node counts
           separately and the cluster serves roughly N x the quota you sold. This
           is set in plugin_attr.api-product-enforcer in the gateway config.yaml,
           NOT on the route, and it is the most common cause;
       (c) the app is subscribed to a higher-ranked product than you expect — only
           the top-ranked covering product is evaluated."
fi
pass "Free app → 429 at call #${free_429_at} (quota is enforced)"

body="$(tr -d '\n' < "$BODY_FILE")"
info "the 429 body is: ${body:-<empty>}"
info "note there is no Retry-After and no X-RateLimit-* header — see the README."

# --- 5: isolation — the case that matters ------------------------------------
echo
status="$(call "$PRO_KEY")"
case "$status" in
  200|201)
    pass "ISOLATION: a second app on a different product still gets ${status} while the Free app is throttled"
    ;;
  429)
    fail "ISOLATION FAILED: the second app is ALSO 429 while the Free app is throttled.
     The limit is not scoped per app, which means it is not doing the one thing
     this solution exists to do. Check, in order:
       (a) are FREE_KEY and PRO_KEY really from two SEPARATE APPS? Two keys on one
           app share a bucket;
       (b) is the second app subscribed to a DIFFERENT product with its own quota?
       (c) is there a limit-count on this route keyed on something global (a
           shared remote_addr behind a load balancer, for instance) that is
           throttling everyone?"
    ;;
  403)
    fail "ISOLATION inconclusive: the second app got 403, so it is not subscribed to a
     product covering this API. Fix the subscription and re-run — a 403 here proves
     nothing about isolation either way."
    ;;
  *)
    fail "second app → ${status} (expected 200). Body: $(tr -d '\n' < "$BODY_FILE")"
    ;;
esac

echo
printf '\033[32mAll checks passed.\033[0m Quota is enforced, and the blast radius is one app.\n'
printf 'Reminder: on more than one gateway node, confirm quota_policy is redis in\n'
printf 'plugin_attr.api-product-enforcer — otherwise each node counts separately.\n'
