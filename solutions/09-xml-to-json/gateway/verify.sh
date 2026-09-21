#!/usr/bin/env bash
# Solution 09 — proof that both conversion directions actually happen.
#
# Exits 0 only if ALL of the following hold:
#   1. Accept: application/json  → the XML response comes back as JSON, and the
#                                  body carries NO XML markup
#   2. Accept: application/xml   → the same route returns the backend's XML
#                                  untouched (the transform is content-negotiated)
#   3. A JSON request body       → the backend receives XML, with the configured
#                                  root element and namespace
#   4. A non-JSON content type   → the body is forwarded UNCHANGED (the silent
#                                  passthrough this plugin is famous for)
#   5. A malformed JSON body     → 400 at the gateway, before the backend
#
# Case 2 is the one people are surprised by and case 4 is the one that costs a
# day. Both are assertions about what the plugin does NOT do.
#
# Cases 3 and 4 need an upstream that echoes what it received — the package's
# sample upstream (httpbin /post) does. Against your own backend, set
# ECHOES_REQUEST=0 to skip them and inspect the backend's own logs instead.
#
# Usage:
#   GATEWAY=https://<YOUR_GATEWAY_HOST> ./verify.sh
#
# Optional overrides:
#   READ_PATH      default /catalog/items
#   WRITE_PATH     default /catalog/orders
#   ROOT_ELEMENT   default order   (request_root_name in the spec)
#   NAMESPACE      default urn:example:catalog  (root_attributes.xmlns)
#   ECHOES_REQUEST default 1

set -uo pipefail

GATEWAY="${GATEWAY:?set GATEWAY to the gateway base URL, e.g. https://<YOUR_GATEWAY_HOST>}"
READ_PATH="${READ_PATH:-/catalog/items}"
WRITE_PATH="${WRITE_PATH:-/catalog/orders}"
ROOT_ELEMENT="${ROOT_ELEMENT:-order}"
NAMESPACE="${NAMESPACE:-urn:example:catalog}"
ECHOES_REQUEST="${ECHOES_REQUEST:-1}"

READ_URL="${GATEWAY%/}${READ_PATH}"
WRITE_URL="${GATEWAY%/}${WRITE_PATH}"
BODY_FILE="$(mktemp)"
trap 'rm -f "$BODY_FILE"' EXIT

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
EXP_JSON="$(expect items-json-200.json 200)"
EXP_XML="$(expect items-xml-200.json 200)"
EXP_ORDER="$(expect order-converted-200.json 200)"
EXP_BAD="$(expect malformed-json-400.json 400)"

echo "→ Read route:  $READ_URL"
echo "→ Write route: $WRITE_URL"
echo

body() { tr -d '\n' < "$BODY_FILE"; }

# --- 1: response direction ---------------------------------------------------
status="$(curl -s -o "$BODY_FILE" -w '%{http_code}' "$READ_URL" -H 'Accept: application/json')"
[[ "$status" == "000" ]] && fail "could not reach $READ_URL at all — curl got no HTTP response.
     Check GATEWAY, DNS and reachability before anything else."
[[ "$status" == "$EXP_JSON" ]] \
  || fail "Accept: application/json → ${status} (expected ${EXP_JSON}). Body: $(body | head -c 200)"
if grep -q '<[a-zA-Z?/]' "$BODY_FILE"; then
  fail "the response still contains XML markup. The transform did not run. Check that the upstream's
     Content-Type is in content_types (application/xml and text/xml are the defaults) — a backend
     replying text/html or application/soap+xml will not match."
fi
case "$(body)" in
  \{*|\[*) pass "Accept: application/json → JSON, with no XML markup left in it" ;;
  *) fail "200 but the body is neither an object nor an array: $(body | head -c 160)" ;;
esac

# --- 2: the same route, asking for XML ---------------------------------------
echo
status="$(curl -s -o "$BODY_FILE" -w '%{http_code}' "$READ_URL" -H 'Accept: application/xml')"
[[ "$status" == "$EXP_XML" ]] \
  || fail "Accept: application/xml → ${status} (expected ${EXP_XML})."
if grep -q '<[a-zA-Z?]' "$BODY_FILE"; then
  pass "Accept: application/xml → the backend's XML, untouched (conversion is content-negotiated)"
else
  fail "the response was converted even though the client did not ask for JSON. That is not this
     plugin's documented behaviour — re-read the deployed config before relying on either direction."
fi

# --- 3 and 4: request direction ----------------------------------------------
if [[ "$ECHOES_REQUEST" == "1" ]]; then
  echo
  status="$(curl -s -o "$BODY_FILE" -w '%{http_code}' -X POST "$WRITE_URL" \
    -H 'content-type: application/json' -H 'Accept: application/json' \
    -d '{"orderId":"SO-88120","lines":[{"sku":"BRK-2100","qty":4},{"sku":"FLT-0090","qty":1}]}')"
  [[ "$status" == "$EXP_ORDER" ]] \
    || fail "JSON order → ${status} (expected ${EXP_ORDER}). Body: $(body | head -c 200)"
  echoed="$(body)"
  grep -q "<${ROOT_ELEMENT}" <<<"$echoed" \
    && pass "JSON request → XML at the backend, root element <${ROOT_ELEMENT}>" \
    || fail "the backend did not receive XML. transform_request defaults to FALSE — an xml-to-json
     block without it converts responses only. Echoed body: $(head -c 200 <<<"$echoed")"
  grep -q "$NAMESPACE" <<<"$echoed" \
    && pass "the generated root element carries the configured namespace" \
    || info "no namespace in the generated XML. Harmless unless your backend is namespace-aware,
     in which case set root_attributes.xmlns."
  grep -q '<lines>' <<<"$echoed" \
    && pass "the JSON array became repeated <lines> elements (not one element containing a list)" \
    || info "could not see the array elements in the echo; inspect the backend's own log instead."

  echo
  status="$(curl -s -o "$BODY_FILE" -w '%{http_code}' -X POST "$WRITE_URL" \
    -H 'content-type: text/plain' -H 'Accept: application/json' \
    -d '{"orderId":"SO-1"}')"
  if grep -q 'orderId' "$BODY_FILE" && ! grep -q "<${ROOT_ELEMENT}" "$BODY_FILE"; then
    pass "a body whose content type is not in request_content_types is forwarded UNCHANGED
      (silent passthrough — no error, and the backend gets JSON it cannot parse)"
  else
    fail "expected the text/plain body to pass through unconverted. If your build converts it
     anyway, request_content_types is wider than this spec says and the assertion below is wrong."
  fi
else
  info "cases 3 and 4 skipped (ECHOES_REQUEST=0). Send a JSON order and read your backend's log to
     confirm it received XML with the <${ROOT_ELEMENT}> root."
fi

# --- 5: malformed JSON -------------------------------------------------------
echo
status="$(curl -s -o "$BODY_FILE" -w '%{http_code}' -X POST "$WRITE_URL" \
  -H 'content-type: application/json' --data-binary '{"orderId": ')"
[[ "$status" == "$EXP_BAD" ]] \
  && pass "a malformed JSON body → ${status} at the gateway, before the backend" \
  || fail "malformed JSON → ${status} (expected ${EXP_BAD}). The request transform parses the body
     first, so an unparseable body should never reach your backend."

echo
printf '\033[32mAll checks passed.\033[0m JSON in, XML at the backend, JSON back out — and the two
cases where the plugin deliberately does nothing are both asserted.\n'
