# Agent-mode prompt — retire an old API version in stages

> [Overview](README.md) · [Business need](business-need.md) · [Architecture](architecture.md) · [Guides](guides.md) · **Agent prompt** · [Tests](tests.md) · [API reference](api-reference.md)

---

Paste this to the Helix Agent as one message, replacing the `{{...}}` values,
or one step at a time if the run ends early. It builds the API and asks you to
confirm before it deploys. Then read the revision back: every path should use
`:productId`, not `{productId}`, and the retired route should be a mock
response, not code. See [Troubleshooting](guides.md#troubleshooting) if
something looks off.

## Prompt

```text
Step 1:
Create a REST API called "{{api_name}}" in the {{environment}} environment, proxying
https://jsonplaceholder.typicode.com. A product is one of its posts and a review is
one of its comments. Four GET routes:
- /v2/products/:productId, sent to /posts/:productId
- /v2/products/:productId/reviews, sent to /posts/:productId/comments
- /v1/products/:productId, sent to /posts/:productId
- /v1/products/:productId/reviews (retired, see step 2)

Step 2:
We are retiring v1 in stages and must tell callers in standard headers a program
can read. Every response from /v1/products/:productId must carry
Deprecation: @1777593600 (RFC 9745: v1 was deprecated on 1 May 2026),
Sunset: Wed, 31 Mar 2027 23:59:59 GMT (RFC 8594), and a Link header pointing at
the same product in v2, so product 1 gets </v2/products/1>; rel="successor-version".
/v1/products/:productId/reviews is already retired: the gateway answers it itself
with a mock response, 410 Gone as application/json, and never calls the backend.
The body is short JSON with a "successor" field holding the v2 address. It carries
Sunset: Wed, 30 Sep 2026 23:59:59 GMT and a Link to the v2 reviews of the same
product. No code is needed for the product id: the gateway fills in
$uri_param_productId from the path, in response headers and in a mock response
alike. v2 responses carry none of these headers. Put a request id on every
response. Deploy it.
```
