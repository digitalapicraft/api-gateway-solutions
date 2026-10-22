# Tests — XML and JSON mediation at the edge

> [Overview](README.md) · [Business need](business-need.md) · [Architecture](architecture.md) · [Guides](guides.md) · [Agent prompt](helix-agent-prompt.md) · **Tests** · [API reference](api-reference.md)

---

8 test cases in total: **5 automated**, run by `example/verify.sh` against a live
deployment, and **3 manual**, because their answer depends on your own document
or needs a deliberately broken route. The full machine-readable plan is
[`tests/test-plan.yaml`](tests/test-plan.yaml); this page is the readable
walkthrough of what it checks and why.

## Running the automated tests

```bash
GATEWAY=https://<YOUR_GATEWAY_HOST> ./example/verify.sh
```

Exit code 0 means all five held:

| # | Case | Expected |
|---|---|---|
| 1 | `Accept: application/json` on the read route | `200` JSON, with no XML markup left |
| 2 | **`Accept: application/xml` on the same route** | `200`, the backend's XML, untouched |
| 3 | A JSON order body | `200`, and the backend received `<order>` with the namespace |
| 4 | **The same body sent as `text/plain`** | `200`, forwarded **unchanged** |
| 5 | A malformed JSON body | `400` at the gateway, before the backend |

**Cases 2 and 4 are the ones worth keeping.** Both check what the plugin
deliberately does *not* do, and both are behaviours people later mistake for a
bug. Case 4 especially is the failure that reaches production: nothing in the
gateway's response shows the conversion was skipped.

Cases 3 and 4 check what the **backend** received, so they need a backend that
echoes the request. The example backend does. Against your own backend, run
`ECHOES_REQUEST=0 ./example/verify.sh` to skip them, and read your backend's log
instead.

Case 1's expected body is only an example — yours is your backend's document,
converted. Check the status, the content type and the absence of XML markup
rather than a particular shape.

Raw fixtures, if you want to run one case by hand instead of the whole script:
[`tests/requests/`](tests/requests/) (the HTTP requests) and
[`tests/expected/`](tests/expected/) (the expected status and body for each — the
single source both `verify.sh` and the plan read from, so they can't drift apart).

## The manual tests

| Case | What it proves | How to run it |
|---|---|---|
| **One item versus a list** | What a repeatable element that occurs once turns into, for your own document. XML has no list type, so the converter has to guess. | Fetch a document where a repeating element appears exactly once, then one where it appears twice, and compare the JSON. Expect an object for one, an array for two or more. Fix it in the client or normalise in your own layer — there's no "always array" option. |
| **Attributes** | What happens to XML attributes in your own document, before a client depends on one. | Convert a document whose **root** element and **child** elements both carry attributes. Root attributes appear as ordinary JSON keys; attributes on child elements were **not** present in the output. Mixed content is reshaped, not kept. |
| **`pretty` option** | That one formatting option is not safe to switch on, on this build. | In a **throwaway** environment only, set `pretty: true` on the read route and call it. Expect **503**, with the connection closed before headers. `root_name` and `property_naming` both work. |

Full procedures, plus the exact assertions each one makes:
[`tests/test-plan.yaml`](tests/test-plan.yaml).

## Coverage

| Type | Cases |
|---|---|
| Positive | response converted, request converted |
| Negative | malformed JSON |
| Boundary | response not converted without `Accept: application/json`, one item versus a list, attributes |
| Failure | silent passthrough of a non-JSON body, `pretty` option |
