# Agent-mode prompt — HMAC request signing

Paste this to the Helix Agent as one message, replacing the `{{...}}` values. It
works from a fresh, empty org on a public upstream, so you need nothing of your
own. Why it is worded this way, what the agent decides on its own, and what to
check before you trust it are in the
[README](README.md#build-it-with-the-helix-agent).

## Prompt

```text
Step 1:
Create a REST API called "{{api_name}}" in the {{environment}} environment, proxying
https://jsonplaceholder.typicode.com. Two routes — POST /albums and GET
/albums/:albumId — passed straight through to the upstream.

Step 2:
Update both routes to accept only requests the calling app has signed with an
HMAC over the request, using a secret that never travels on the wire. Each route
decides what the signature must cover, not the caller: on POST /albums the method
and path, the Date header and a digest of the body, and a body that doesn't match
its digest is rejected; on GET /albums/:albumId, which has no body, the method and
path and the Date header. On this gateway the method and path is called
@request-target, not (request-target). Reject a request whose Date is more than 5 minutes off.

Step 3:
Create a developer "{{developer_name}}", a corresponding product and an app that
signs its requests, to work with the above API. Give me the app's key id and
secret.
```
