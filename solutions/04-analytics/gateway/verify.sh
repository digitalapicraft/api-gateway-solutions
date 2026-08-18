#!/usr/bin/env bash
# Solution 04 — seed a known traffic pattern against the two simple routes, then
# tell you the analytics queries to run.
#
# This API is deliberately minimal: two routes returning real data, no
# auth. So verify.sh does two things:
#   1. Confirms both routes answer 200 and carry an X-Request-Id.
#   2. Sends a labelled burst — several distinct /posts/{postId} ids — so you can
#      then confirm in the analytics tool that they aggregate to ONE row by
#      route_id (templating), not one row per id.
#
# Analytics is captured asynchronously and read from the portal or the analytics
# API. No shell script can assert a chart, so exit 0 means "the routes work and a
# known pattern is seeded", NOT "analytics is verified". The manual query step is
# printed at the end and documented in ../charts.md.
#
# Usage:
#   GATEWAY=https://<YOUR_GATEWAY_HOST> ./verify.sh
#
# Optional overrides:
#   LIST_PATH  default /posts
#   ITEM_BASE  default /posts           (item route is <ITEM_BASE>/<id>)
#   SEED_IDS   default "a1 b2 c3 d4 e5"  (distinct ids to prove templating)

set -uo pipefail

GATEWAY="${GATEWAY:?set GATEWAY to the gateway base URL, e.g. https://<YOUR_GATEWAY_HOST>}"
LIST_PATH="${LIST_PATH:-/posts}"
ITEM_BASE="${ITEM_BASE:-/posts}"
SEED_IDS="${SEED_IDS:-a1 b2 c3 d4 e5}"

LIST_URL="${GATEWAY%/}${LIST_PATH}"
HDR_FILE="$(mktemp)"; BODY_FILE="$(mktemp)"
trap 'rm -f "$HDR_FILE" "$BODY_FILE"' EXIT

fail() { printf '\033[31mFAIL\033[0m  %s\n' "$1"; exit 1; }
pass() { printf '\033[32mPASS\033[0m  %s\n' "$1"; }
info() { printf '\033[34mNOTE\033[0m  %s\n' "$1"; }

START_UTC="$(date -u '+%Y-%m-%dT%H:%M:%SZ')"
echo "→ List route: $LIST_URL"
echo "→ Item route: ${GATEWAY%/}${ITEM_BASE}/{id}"
echo

# --- 1: list route answers with real data + correlation id ---------
status="$(curl -s -o "$BODY_FILE" -D "$HDR_FILE" -w '%{http_code}' "$LIST_URL")"
[[ "$status" == "000" ]] && fail "could not reach ${LIST_URL} — check GATEWAY, DNS and reachability."
[[ "$status" == "200" ]] \
  && pass "GET ${LIST_PATH} → 200 (real data)" \
  || fail "GET ${LIST_PATH} → ${status} (expected 200). Is the API deployed and the upstream bound?"

if grep -qi '^x-request-id:' "$HDR_FILE"; then
  RID="$(grep -i '^x-request-id:' "$HDR_FILE" | head -1 | tr -d '\r' | sed 's/^[^:]*:[[:space:]]*//')"
  pass "X-Request-Id present: ${RID}"
else
  fail "no X-Request-Id on the response — add the request-id plugin API-wide."
fi

# --- 2: seed distinct item ids to prove templating later ---------------------
echo
info "seeding distinct ids on the templated route: ${SEED_IDS}"
n=0
for id in $SEED_IDS; do
  s="$(curl -s -o /dev/null -w '%{http_code}' "${GATEWAY%/}${ITEM_BASE}/${id}")"
  [[ "$s" == "200" ]] && n=$(( n + 1 )) || info "  ${ITEM_BASE}/${id} → ${s}"
done
[[ "$n" -gt 0 ]] \
  && pass "seeded ${n} calls across distinct order ids on ${ITEM_BASE}/{id}" \
  || fail "no item-route call returned 200 — check the templated route is deployed."

END_UTC="$(date -u '+%Y-%m-%dT%H:%M:%SZ')"

cat <<REPORT

$(printf '\033[32mRoutes work and a known pattern is seeded.\033[0m')

$(printf '\033[1mWindow:\033[0m') ${START_UTC} → ${END_UTC}
$(printf '\033[1mSeeded:\033[0m') 1x GET ${LIST_PATH}, plus $(echo $SEED_IDS | wc -w | tr -d ' ')x GET ${ITEM_BASE}/{distinct id}

$(printf '\033[1mNOW VERIFY ANALYTICS (manual — no script can assert a chart):\033[0m')

  1. Per-route breakdown grouped by route_id — the ${ITEM_BASE}/{id} calls must
     collapse to ONE row (templating), not one row per id:
       "Show me requests to this API since ${START_UTC}, grouped by route_id."
     Then repeat grouped by api_path — you should see one row per concrete id,
     which is why route-level charts group by route_id. See ../charts.md.

  2. If you want per-APP attribution rather than per-IP, add helix-auth to the
     routes (see solution 01). This minimal API has no identity, so rows attribute
     to a source IP by design.

  3. Correlate a single request in your OWN logs via the forwarded X-Request-Id
     (e.g. ${RID}); it is not an analytics dimension.
REPORT
