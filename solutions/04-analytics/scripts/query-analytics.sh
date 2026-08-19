#!/usr/bin/env bash
# Read your gateway analytics — no API changes required.
#
# Analytics is captured for every request automatically. This script pulls the
# common views for the last hour straight from the analytics metrics API and
# prints them: requests by API, by app, by product; the slowest and fastest APIs;
# and errors by status. It only READS — it changes nothing.
#
# Auth: the analytics API uses a control-plane bearer token (the same session
# token the portal uses). Get one from the portal (DevTools → a request's
# Authorization header) or your own login flow, then:
#
#   CP=https://<YOUR_CONTROL_PLANE_HOST> \
#   ORG=<YOUR_ORG_ID> \
#   TOKEN=<bearer token> \
#   ./query-analytics.sh
#
# Optional:
#   WINDOW_HOURS   default 1     how far back to look
#   API_NAME       if set, filter every view to this one API
#   TOP            default 20    max rows per grouped view
#
# Requires: curl, python3.

set -uo pipefail
CP="${CP:?set CP to the control-plane base URL, e.g. https://<YOUR_CONTROL_PLANE_HOST>}"
ORG="${ORG:?set ORG to your org id}"
TOKEN="${TOKEN:?set TOKEN to a control-plane bearer token (see header)}"
WINDOW_HOURS="${WINDOW_HOURS:-1}"
API_NAME="${API_NAME:-}"
TOP="${TOP:-20}"

ST="$(python3 -c "import datetime;print((datetime.datetime.now(datetime.UTC)-datetime.timedelta(hours=$WINDOW_HOURS)).strftime('%Y-%m-%dT%H:%M:%SZ'))")"
ET="$(python3 -c "import datetime;print(datetime.datetime.now(datetime.UTC).strftime('%Y-%m-%dT%H:%M:%SZ'))")"

# Build a filters[] fragment when API_NAME is set.
FILTER=""
[ -n "$API_NAME" ] && FILTER=",\"filters\":[{\"column\":\"api_name\",\"operator\":\"EQ\",\"value\":[\"$API_NAME\"]}]"

# metric  dimension  aggregation("" for count)  sortOrder("" none)
call() {
  local metric="$1" dim="$2" agg="$3" order="$4"
  local aggf="" sortf=""
  [ -n "$agg" ] && aggf=",\"aggregation\":\"$agg\""
  [ -n "$order" ] && sortf=",\"sort\":{\"field\":\"value\",\"order\":\"$order\"}"
  curl -s --max-time 60 -X POST "$CP/api/orgs/$ORG/analytics/metrics/$metric" \
    -H "authorization: Bearer $TOKEN" -H 'content-type: application/json' \
    -d "{\"startTime\":\"$ST\",\"endTime\":\"$ET\",\"dimensions\":[\"$dim\"]${FILTER}${aggf},\"excludeTimeUnit\":true,\"pageRequest\":{\"page\":1,\"size\":$TOP${sortf:+${sortf}}}}"
}
show() { # title dim json label unit
  local title="$1" dim="$2"; shift 2
  printf '\n\033[1m%s\033[0m\n' "$title"
  python3 -c "
import sys,json
d=json.load(sys.stdin); rows=d.get('groupedResults') or []
if not rows: print('  (no data in the window)'); sys.exit()
rows.sort(key=lambda r:-(r['value'] or 0))
for r in rows:
    k=r['dimensions'].get('$dim'); k='(unattributed)' if k in (None,'') else k
    v=r['value'] or 0
    print('  %-42s %s' % (k, (('%.1f'%v) if isinstance(v,float) and v!=int(v) else int(v))))
"
}

echo "→ org: $ORG"
echo "→ window: $ST → $ET  (last ${WINDOW_HOURS}h)"
[ -n "$API_NAME" ] && echo "→ filtered to API: $API_NAME"

call requests-count api_name       ""    DESC | show "Requests by API"      api_name
call requests-count app_name       ""    DESC | show "Requests by app"      app_name
call requests-count product_name   ""    DESC | show "Requests by product"  product_name
call requests-count response_status_code "" DESC | show "Requests by status code" response_status_code
call response-time  api_name       AVG   DESC | show "Slowest APIs (AVG response time, ms)" api_name
call response-time  api_name       AVG   ASC  | show "Fastest APIs (AVG response time, ms)" api_name

echo
echo "Done — read-only. See ../charts.md for more queries and the API's limits"
echo "(no percentiles; no quota-usage metric; correlate single requests in your own logs)."
