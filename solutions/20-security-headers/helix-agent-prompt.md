# Agent-mode prompt — security headers on every response

> [Overview](README.md) · [Business need](business-need.md) · [Architecture](architecture.md) · [Guides](guides.md) · **Agent prompt** · [Tests](tests.md) · [API reference](api-reference.md)

---

Paste this to the Helix Agent as one message, replacing the `{{...}}` values. It
builds and deploys the sample API on a fresh, empty org. Point it at your own
API by changing step 1.

When it finishes, read the deployed revision back: the header rules should be
set once for the whole API, not on each route, and `/users/:userId` should be
stored with a colon, not braces. Then run [`example/verify.sh`](example/verify.sh)
against it. See [Troubleshooting](guides.md#troubleshooting) if something looks
off.

## Prompt

```text
Step 1:
Create a REST API called "{{api_name}}" in the {{environment}} environment, proxying
https://jsonplaceholder.typicode.com. Two routes, GET /users and GET /users/:userId,
passed straight through to the upstream.

Step 2:
A pen test flagged this API. Fix it at the gateway, once for the whole API rather
than route by route, so every response carries the fix, errors included:
- Every response carries X-Content-Type-Options: nosniff, Cache-Control: no-store,
  X-Frame-Options: DENY, Content-Security-Policy: default-src 'none';
  frame-ancestors 'none', and Referrer-Policy: no-referrer. Where the backend
  already sends one of these headers, replace its value rather than adding a
  second one.
- No response names the backend's software: remove X-Powered-By, Server, Via,
  X-AspNet-Version and X-AspNetMvc-Version.
- The response body stays exactly as the backend sent it.
Put a request id on every response. Deploy it.
```
