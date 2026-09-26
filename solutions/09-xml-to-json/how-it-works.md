# How it works — Solution 09 — JSON in, JSON out, in front of a backend that only speaks XML

[Overview](readme.md) · [Business need](business-need.md) · **How it works** · [Install](install.md) · [Configuration](configuration.md) · [Test & verify](testing.md) · [Changelog](changelog.md)

---

## Request path

```
JSON client ──▶ Gateway ──▶ XML backend
                  │
                  ├── request-id     (API-wide, correlation)
                  ├── cors           (API-wide; accept must be allowed)
                  ├── proxy-rewrite  (rewrite phase, priority 1008 — path only)
                  └── xml-to-json    (priority 997)
                        request  : JSON body  -> XML   (transform_request)
                        response : XML body   -> JSON  (transform_response)
```

What happens to a request, in the order it actually happens:

1. **rewrite phase, priority 1008** — `proxy-rewrite` retargets the upstream path.
2. **rewrite phase, priority 997** — `xml-to-json` inspects the request's
   `Content-Type`. If it matches `request_content_types` *and* `transform_request`
   is true, the JSON body is converted to XML and the upstream-bound `Content-Type`
   is set to `application/xml`. If either condition fails, the body is forwarded
   unchanged.
3. **upstream** — the backend receives the document in the form it has always
   received.
4. **response** — if the client sent `Accept: application/json` and the upstream's
   `Content-Type` is in `content_types`, the XML is converted to JSON. Otherwise
   the response is passed through as-is.

**The ordering between `proxy-rewrite` and `xml-to-json` is load-bearing, and the
trap is well documented.** Both run in the rewrite phase; `proxy-rewrite` has the
higher priority, so it runs first. Retargeting the path there is safe. Setting
`Content-Type` there is not: the transform would then inspect a header
`proxy-rewrite` has already rewritten, stop matching `request_content_types`, and
silently skip the conversion. That exact failure is on the record against
[solution 03](../03-soap-to-rest/).

## Native vs custom

Native, and deliberately the *simpler* of the two native options.

- **`xml-to-json`** — a structural converter. Element names become keys, repeated
  elements become arrays, and the document's shape is preserved. No template to
  write and no template to maintain, and it works on documents you have not seen
  yet. That is the right trade when the backend's structure is acceptable as a
  JSON contract.
- **`body-transformer`** — template-based. You write the exact output document.
  Correct when you need a JSON contract that is *independent* of the XML, when key
  order matters on the way back (a strict `xs:sequence`), or when meaning lives in
  attributes or mixed content. It costs a template per operation, and the template
  is a thing that can rot.
- **`json-to-xml`** — solves the opposite problem, despite the name reading like
  the request-side counterpart of this plugin. It converts a JSON *upstream
  response* to XML for clients that want XML. It is not how you send XML to your
  backend; `transform_request` is.

This package uses the structural converter because the backend's document shape is
a reasonable JSON contract and the value is in removing four client-side parsers,
not in designing a new API. When the requirement is a stable public JSON contract,
layer a template on top rather than reaching for it instead.

No custom code is required, and none is included.

## Why conversion is content-negotiated

It looks like an inconvenience and it is the feature that makes adoption possible.

| | Unconditional conversion | Content-negotiated |
|---|---|---|
| Existing XML consumers | Break on the day you deploy | Unaffected — same route, same response |
| Rollout | A migration project, coordinated across every consumer | A configuration change |
| New JSON clients | Work | Work, if they send `Accept: application/json` |
| Cost | A cutover | One line in your client documentation |

The price is exactly one gotcha: a client that forgets the header gets XML and
concludes the gateway is broken. That is a documentation problem, and it buys the
absence of a migration.

## When not to use this shape

- **There is a SOAP envelope** — [solution 03](../03-soap-to-rest/).
- **A strict `xs:sequence` on the request side.** Key order is not preserved. Use
  a template.
- **Meaning in attributes or mixed content.** The conversion is lossy there;
  measured, documented, and not fixable by configuration.
- **A JSON contract that must outlive the backend's structure.** This mirrors the
  backend. A backend refactor becomes a client-visible change.
- **Large documents.** Conversion buffers the body, and anything over
  `max_body_size` is forwarded unconverted — silently.

## Failure modes and what they look like

| Symptom | Cause |
|---|---|
| The response is still XML | The client did not send `Accept: application/json`, or the upstream's `Content-Type` is not in `content_types` |
| The backend rejects the request body as "not XML" | `transform_request` is `false` (the default), or the client's `Content-Type` is not in `request_content_types` |
| The backend rejected it, and the gateway returned 200 | Both passthroughs fail open. Alert on backend parse errors, not gateway status |
| It worked yesterday, and today the client crashes on one field | A repeatable element occurred exactly once and became an object instead of an array |
| The backend complains about an unexpected element or namespace | `request_root_name` or `root_attributes.xmlns` does not match what its parser expects |
| The route returns 503, connection terminated before headers | `pretty: true`. Verified on this build. Remove it |
| The request direction silently stopped working after an edit | Something set `Content-Type` in `proxy-rewrite` |
