# Agent-mode prompt — read your analytics by asking

Paste any of these to the Helix Agent, replacing the `{{...}}` values. It pulls
the numbers and renders a chart in the chat; nothing is added to your APIs and
nothing is changed, because every one of these only reads. What the agent can and
cannot answer, what to do when a result comes back empty or unattributed, and the
follow-ups worth asking next are in the
[README](README.md#read-it-with-the-helix-agent).

## Prompt

"Last hour" is a `1h` range — widen it to `24h`, `7d` and so on.

**Requests in the last hour, by API**
```text
Show me requests to all my APIs in the last hour, broken down by API and sorted
busiest first.
```

**By app, or by product**
```text
Show me requests in the last hour grouped by app.
```
```text
Show me requests in the last hour grouped by product.
```

**For one specific API**
```text
For the API {{api_name}}, show me requests in the last hour broken down by app.
```

**Slowest and fastest**
```text
Which of my APIs were slowest in the last hour? Rank them by average response
time, slowest first.
```
```text
Which APIs were fastest by average response time in the last hour?
```

**Errors, and who is being throttled**
```text
Show me requests in the last 24 hours grouped by API and status code, so I can
see 4xx and 5xx per API.
```
```text
Show me 429 responses in the last hour grouped by app.
```

**Traffic over time**
```text
Plot total requests across all my APIs per hour for the last 24 hours.
```

**Data transfer**
```text
Show me total bytes transferred by API over the last 24 hours.
```
