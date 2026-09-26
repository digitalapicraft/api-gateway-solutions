# Configuration — Solution 09 — JSON in, JSON out, in front of a backend that only speaks XML

[Overview](readme.md) · [Business need](business-need.md) · [How it works](how-it-works.md) · [Install](install.md) · **Configuration** · [Test & verify](testing.md) · [Changelog](changelog.md)

---

## Two switches decide whether anything happens at all

Both defaults are reasonable and both surprise people, so they are the first
thing to check when "the plugin isn't doing anything".

**The response transform is content-negotiated.** It fires only when the client
sends `Accept: application/json`. A client that omits the header gets the
backend's XML and concludes the gateway is misconfigured. That behaviour is also
the feature in the table above — it is what lets existing XML consumers keep
working — but it has to be in your client documentation, in bold.

**The request transform is off by default.** `transform_request` defaults to
`false`, so an `xml-to-json: {}` block converts responses *only*. Worse, when it
is on, a body whose `Content-Type` is not in `request_content_types` is forwarded
**unchanged and without an error**. The gateway returns 200; your backend gets
JSON it cannot parse and complains in its own log. Alert on backend parse
failures, not on gateway status codes.

## Configuration

Source of truth: [`gateway/api-spec.yaml`](gateway/api-spec.yaml).

Response direction — the minimum useful block:

```yaml
xml-to-json:
  transform_response: true
  content_types: [application/xml, text/xml]
```

Both directions, on the write route:

```yaml
xml-to-json:
  transform_request: true
  transform_response: true
  request_content_types: [application/json]
  content_types: [application/xml, text/xml]
  request_root_name: order
  array_item_name: item
  root_attributes:
    xmlns: "urn:example:catalog"
  max_body_size: 1048576
```

`request_root_name` names the root element of the document you generate, and
`root_attributes` puts the namespace on it. A namespace-aware backend rejects an
otherwise-correct document without that declaration, usually with a message that
does not mention namespaces.

**Do not set `pretty: true`.** Verified on this build: a route with it enabled
returns **503** and the connection is terminated before headers. `root_name` and
`property_naming` are fine; `pretty` is not.

**Do not set `Content-Type` in `proxy-rewrite`.** `proxy-rewrite` (priority 1008)
runs before `xml-to-json` (997) in the rewrite phase, so an override there
changes the header the transform is about to match on, and the request direction
silently stops converting. This exact mistake is on the record against
[solution 03](../03-soap-to-rest/).
