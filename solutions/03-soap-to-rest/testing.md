# Test & verify — Solution 03 — Serve a SOAP backend as REST/JSON

[Overview](readme.md) · [Business need](business-need.md) · [How it works](how-it-works.md) · [Install](install.md) · [Configuration](configuration.md) · **Test & verify** · [Changelog](changelog.md)

---

## What the caller actually sees

Request — plain JSON, no envelope, no WSDL:

```http
POST /locations
Authorization: Bearer eyJ...
content-type: application/json

{"region":"EMEA","activeOnly":true}
```

Response — JSON, shaped by how the XML was structured:

```http
HTTP/1.1 200 OK
content-type: application/json
X-Request-Id: 7f3c...

{"Locations":{"Site":[{"id":"1","name":"Frankfurt"},{"id":"2","name":"Dublin"}]}}
```

**The JSON shape is derived from the XML, not designed.** This is the honest part
that surprises people:

- **Element names come through as-is**, including `PascalCase` and any vendor
  prefixes. You get `{"Locations":{"Site":[...]}}`, not the `{"locations":[...]}`
  a REST API designer would have written.
- **Single-element collections may not be arrays.** XML has no notion of an array,
  so one `<Site>` can transform to an object where two transform to a list. This
  breaks partner code that assumes a list, and it breaks it on the edge case
  rather than the common one — which is the worst time to find out.
- **Namespaces and attributes need handling.** Default settings often flatten or
  drop them.

Tell integrators this is a *mediated* API and publish real example payloads for
both the single-result and multi-result cases. If you need a hand-designed REST
contract instead of a derived one, that's a response-shaping layer on top of this,
not a setting in it.

## Testing

```bash
GATEWAY=https://<YOUR_GATEWAY_HOST> \
CLIENT_ID=<CLIENT_ID> CLIENT_SECRET=<CLIENT_SECRET> ./gateway/verify.sh
```

Exit 0 means all five held:

| # | Case | Expected |
|---|---|---|
| 1 | No token | `401` — before the transform, before the SOAP call |
| 2 | Client credentials | `200` + `access_token` |
| 3 | Valid token | `200` + `content-type: application/json` |
| 4 | **The body contains no XML markup** | proof the transform actually ran |
| 5 | Forged token | `401` |

**Case 4 is the one that matters and the one people skip.** A content-type header
is a *claim*; a body with no angle brackets is *evidence*. Relabelling unconverted
XML as `application/json` is a real and easy misconfiguration, and it sails past
any check that only looks at headers. Partners then receive XML with a JSON
content-type, and their parser's error message won't point anywhere near your
gateway.

`verify.sh` also warns (rather than fails) when the JSON parses but is empty —
usually the handler returned an empty envelope because your request body's element
names didn't match what it reads.

Full plan, including the XML-edge cases worth checking by hand:
[`tests/test-plan.yaml`](tests/test-plan.yaml).
