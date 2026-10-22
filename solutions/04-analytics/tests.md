# Tests — read what your gateway already captured

> [Overview](README.md) · [Business need](business-need.md) · [Architecture](architecture.md) · [Guides](guides.md) · [Agent prompt](helix-agent-prompt.md) · **Tests** · [API reference](api-reference.md)

---

This solution has **no test suite** — no `verify.sh` and no test plan. It changes
nothing on any API, so there is no configuration to prove. What you can check is
that *your* reads work: that your token is accepted and your traffic comes back
the way you expect.

## Before you start

- **`CP` is your control-plane API address**: the one the portal calls behind the
  scenes, usually beginning with `api-`. It is not the address of the portal page
  you log in to. With the wrong one, every view shows "no data" and no error. See
  [Guides](guides.md#run-the-script) for how to find it.
- **The token lasts about 1 hour.** If a check that worked earlier now shows no
  data, get a fresh token first.
- **Use short names.** `API_NAME` and any filter take the short internal name,
  such as `posts-api`, not the name shown in the portal ("Posts API").

## Checking it works

Run the script for a window you know had traffic:

```bash
CP=https://<YOUR_CONTROL_PLANE_API> \
ORG=<YOUR_ORG_ID> \
TOKEN=<control-plane bearer token> \
WINDOW_HOURS=24 \
./scripts/query-analytics.sh
```

| What you see | What it means |
|---|---|
| Six tables with rows: requests by API, app, product and status code, then slowest and fastest APIs | Your token works and analytics is returning your traffic. |
| `(no data in the window)` under every heading | No rows came back. Either there was no traffic in the window, or the API returned an error — the script prints the same line for both. Check that `CP` is the control-plane API address, widen `WINDOW_HOURS`, and get a fresh token if yours may have expired. |
| Rows under **Requests by API**, but only `(unattributed)` under **Requests by app** | Analytics works; your APIs just don't identify their callers. See [Architecture](architecture.md#two-things-about-attribution). |
| A Python error instead of tables | The response wasn't the JSON the script expects. Check `CP` and `ORG`, then try one call by hand from [Guides](guides.md#call-the-metrics-api-directly) to see the raw response. |

## The known-calls check

The best way to trust the numbers is to send calls you have counted yourself, then
see whether analytics reports exactly those counts.

**What you need for per-app rows.** In a new org, every call is "unattributed"
until you have an API that checks keys and you send a few calls with a valid key.
An API that doesn't check keys has no app to put on its rows. If you only want to
check counts by API and status, any API will do.

1. Pick a quiet API that checks keys, and note its short name (such as
   `posts-api`) and the short name of an app subscribed to it (such as
   `free-app`).
2. Send exactly **10 calls**: for example 7 with the app's valid key and 3 with a
   wrong key. Write down how many of each you sent.
3. Wait **30 seconds** for the calls to be recorded.
4. Ask for that API on its own:

   ```bash
   API_NAME=<short API name> WINDOW_HOURS=1 \
   CP=https://<YOUR_CONTROL_PLANE_API> ORG=<YOUR_ORG_ID> TOKEN=<control-plane bearer token> \
   ./scripts/query-analytics.sh
   ```

5. Compare with what you sent:

| View | What you should see |
|---|---|
| **Requests by API** | Exactly 10 for your API (plus any other traffic in the window). |
| **Requests by status code** | 7 × `200` and 3 × `401` (or whatever codes your API returns for a good and a bad key). |
| **Requests by app** | 7 under your app's short name, and 3 under `(unattributed)` — a call with a wrong key has no app. |

If a count is off, look first at the cautions in
[Before you trust a number](guides.md#before-you-trust-a-number) and
[Troubleshooting](guides.md#troubleshooting). For example, a call to a path the
API doesn't have (`404 Route Not Found`) is never recorded, so it won't appear in
any count.
