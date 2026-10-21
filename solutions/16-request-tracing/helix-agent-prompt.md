# Agent-mode prompt — build an API to investigate with a trace session

> [Overview](README.md) · [Business need](business-need.md) · [Architecture](architecture.md) · [Guides](guides.md) · **Agent prompt** · [Tests](tests.md) · [API reference](api-reference.md)

---

Paste this to the Helix Agent as one message, replacing the `{{...}}` values. It
builds and deploys the API. **The agent cannot start a trace session**, so when
it finishes, open **Observability → Traces** and start one yourself, as
[Guides](guides.md#start-a-trace-session) shows. Read the deployed revision back
first and check that `/posts/:postId` was stored with a colon, not braces. See
[Troubleshooting](guides.md#troubleshooting) if something looks off.

## Prompt

```text
Step 1:
Create a REST API called "{{api_name}}" in the {{environment}} environment, proxying
https://jsonplaceholder.typicode.com. Two routes, POST /posts and GET
/posts/:postId, passed straight through to the upstream.

Step 2:
A new post with no title must be rejected at the gateway with a 400 before it
reaches the backend. Every post lookup must tell the backend it came through the
API channel, with the header X-Partner-Channel: api. Put a request id on every
response. Deploy it.
```
