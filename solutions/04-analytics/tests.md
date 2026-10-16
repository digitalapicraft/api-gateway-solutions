# Tests — read what your gateway already captured

> [Overview](README.md) · [Business need](business-need.md) · [Architecture](architecture.md) · [Guides](guides.md) · [Agent prompt](helix-agent-prompt.md) · **Tests** · [API reference](api-reference.md)

---

This solution has **no test suite** — no `verify.sh` and no test plan. It changes
nothing on any API, so there is no configuration to prove. What you can check is
that *your* reads work: that your token is accepted and your traffic comes back
the way you expect.

## Checking it works

Run the script for a window you know had traffic:

```bash
CP=https://<YOUR_CONTROL_PLANE_HOST> \
ORG=<YOUR_ORG_ID> \
TOKEN=<control-plane bearer token> \
WINDOW_HOURS=24 \
./scripts/query-analytics.sh
```

| What you see | What it means |
|---|---|
| Six tables with rows: requests by API, app, product and status code, then slowest and fastest APIs | Your token works and analytics is returning your traffic. |
| `(no data in the window)` under every heading | No rows came back. Either there was no traffic in the window, or the API returned an error — the script prints the same line for both. Widen `WINDOW_HOURS`, and get a fresh token if yours may have expired. |
| Rows under **Requests by API**, but only `(unattributed)` under **Requests by app** | Analytics works; your APIs just don't identify their callers. See [Architecture](architecture.md#two-things-about-attribution). |
| A Python error instead of tables | The response wasn't the JSON the script expects. Check `CP` and `ORG`, then try one call by hand from [Guides](guides.md#call-the-metrics-api-directly) to see the raw response. |

## A quick end-to-end check

To confirm a call you made shows up, send a few requests to one of your APIs, then
ask for that API on its own:

```bash
API_NAME=<your API name> WINDOW_HOURS=1 \
CP=https://<YOUR_CONTROL_PLANE_HOST> ORG=<YOUR_ORG_ID> TOKEN=<control-plane bearer token> \
./scripts/query-analytics.sh
```

Your calls should appear under **Requests by API** and **Requests by status code**
for that API. If the API identifies its callers, they also appear under your app's
name in **Requests by app**.
