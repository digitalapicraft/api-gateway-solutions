# Agent-mode prompt — JSON clients for an XML backend

Paste this to the Helix Agent as one message, replacing the `{{...}}` values. It
works from a fresh, empty org on a public upstream that serves XML and echoes what
it receives, so you can see both directions with nothing of your own. If your
backend is SOAP, use [solution 03](../03-soap-to-rest/) instead. Why the prompt is
worded this way, what the agent decides on its own, and what to check before you
trust it are in the [README](README.md#build-it-with-the-helix-agent).

## Prompt

```text
Step 1:
Create a REST API called "{{api_name}}" in the {{environment}} environment, proxying
https://httpbin.org. Two routes: GET /catalog/items, which the upstream serves at
/xml, and POST /catalog/orders, which it serves at /post. Keep my paths.

Step 2:
The backend only speaks XML and my clients speak JSON. Update the routes so that:
- a client that asks for JSON gets the backend's XML response as JSON, and a
  client that asks for XML still gets the backend's XML untouched.
- on POST /catalog/orders, a JSON body reaches the backend as XML: root element
  <order> in the namespace urn:example:catalog, with array items named <item>.
  Don't set a Content-Type when retargeting the path; the conversion relies on the
  client's.
- browser clients can call both routes and send the Accept header.
```
