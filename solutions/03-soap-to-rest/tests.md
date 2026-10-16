# Tests — SOAP/XML backend served as REST/JSON

> [Overview](README.md) · [Business need](business-need.md) · [Architecture](architecture.md) · [Guides](guides.md) · [Agent prompt](helix-agent-prompt.md) · **Tests** · [API reference](api-reference.md)

---

8 test cases in total: **2 automated**, run by `example/verify.sh` against a live
deployment, and **6 manual**, for behaviour that needs a handler you can make
return a particular shape, or a failure you cause on purpose. The full
machine-readable plan is [`tests/test-plan.yaml`](tests/test-plan.yaml); this page
is the readable walkthrough of what it checks and why.

You need your own SOAP backend to run any of them — there is no public sample
upstream for this solution. None of the cases sends a credential, because this
package has no sign-in.

## Running the automated tests

```bash
GATEWAY=https://<YOUR_GATEWAY_HOST> ./example/verify.sh
```

Optional settings: `API_PATH` (default `/locations`); `REQ_BODY` (default `{}` —
set it to a real query body if your handler needs one); and `CURL_OPTS` for extra
`curl` arguments, such as a token header if you've put
[solution 02](../02-oauth-jwt/) in front of the route. Every request the script
sends carries `accept: application/json`, because the response conversion does
nothing without it.

Exit code 0 means both held:

| # | Case | Expected |
|---|---|---|
| 1 | A JSON call to `/locations` | `200` + `content-type: application/json` |
| 2 | **The body contains no XML markup** | proof the conversion actually ran |

**Case 2 is the one that matters, and the one people skip.** A content-type header
is a *claim*; a body with no angle brackets is *evidence*. Labelling unconverted
XML as `application/json` is a real and easy mistake, and it passes any check that
only looks at headers. Partners then receive XML with a JSON content type, and
their parser's error points nowhere near your gateway.

The script also:

- checks the body parses as JSON, if `jq` is installed;
- **warns, rather than fails,** when the JSON parses but is empty — usually the
  handler returned an empty envelope because your request body's field names
  didn't match what it reads;
- explains the likely cause when the status isn't 200 — for example, a 415 means
  check for a `SOAPAction` header, **not** a `Content-Type` setting on
  `proxy-rewrite`.

Raw fixtures, if you want to run one case by hand instead of the whole script:
[`tests/requests/`](tests/requests/) (the HTTP request) and
[`tests/expected/`](tests/expected/) (the expected status for each — the single
source both `verify.sh` and the plan read from, so they can't drift apart).

## The manual tests

These need a handler you control, or a failure you cause deliberately — so they're
a checklist, not a script. Run the failure cases in a **throwaway** test
environment only.

| Case | What it proves | How to run it |
|---|---|---|
| **Empty result** | "No results" comes back as valid, empty JSON rather than an error — so you can tell it apart from a broken conversion. | Send a query that matches nothing (for example a region code that doesn't exist). Expect `200` with empty JSON. If you get this for a query that *should* match, check your field names first. |
| **One item vs several** | What your setup does when a collection has exactly one member. XML can't tell an item from a list of one. | Query so the handler returns exactly one `<Site>`, then several. Record both JSON shapes, and publish **both** in your developer docs. The most valuable manual case — run it before you onboard anyone. |
| **Namespaces and attributes** | How namespace prefixes and XML attributes survive the conversion, since defaults often flatten or drop them. | Call an operation whose response has prefixes and attributes. Check whether prefixes are kept, stripped or mangled, and whether attributes appear as fields or vanish. Adjust the settings if the defaults don't suit you. |
| **Double conversion** | What the most common misconfiguration looks like, so you recognise it. | Add a `json-to-xml` plugin next to `xml-to-json` and call the route. Expect a `500` from a handler that works when called directly. |
| **Backend down** *(optional)* | The gateway returns an error status, not a broken 200, when the SOAP handler is unreachable. | Point the upstream at an unreachable host, or stop the handler. Expect `502`. |
| **Slow handler** | What happens when the handler is slower than the gateway timeout. | Call an operation known to take longer than the route's timeout. Expect `504` — which looks like an outage but isn't. Knowing your handler's real response times before go-live matters more than the test. |

Full procedures, plus the exact assertions each one makes:
[`tests/test-plan.yaml`](tests/test-plan.yaml).

## Coverage

| Type | Cases |
|---|---|
| Positive | valid call converted, response really converted |
| Negative | backend down |
| Boundary | empty result, one item vs several, namespaces and attributes |
| Failure | double conversion, backend down, slow handler |
