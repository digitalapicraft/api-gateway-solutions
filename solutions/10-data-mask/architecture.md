# Architecture — two masks, two audiences

## Request path

```
Support console ──▶ Gateway ──▶ Customer backend (returns everything)
                       │
                       ├── request-id       (API-wide, correlation)
                       ├── proxy-rewrite    (rewrite phase — path only)
                       ├── response-rewrite (priority 899, response path)
                       │     regex over the body -> what the CALLER receives
                       └── log-data-mask    (priority 999, log phase)
                             named fields + headers -> what a LOGGER writes
```

1. **rewrite phase** — `proxy-rewrite` retargets the path. The collection route
   uses a fixed `uri`; the single-record route uses `regex_uri` so the id is
   carried through.
2. **upstream** — the backend returns its full record. Nothing about this design
   asks it to change.
3. **response path** — `response-rewrite` applies its filters to the body. This is
   the copy the caller receives.
4. **log phase** — `log-data-mask` publishes its rules into the request context.
   The shared log helper that every logger plugin uses reads them and masks the
   entry it is about to write.

## The two plugins are not alternatives

They act on different artifacts, at different times, for different audiences, and
neither implies the other.

| | `response-rewrite` | `log-data-mask` |
|---|---|---|
| Acts on | The response body | The log entry a logger is about to write |
| Selects by | A regex over body text | Named fields and headers, parsed |
| Needs a logger on the route | No | **Yes.** With none, it has no effect at all |
| Changes the response | Yes | **No** |
| Changes analytics | No | No — analytics does not use the log helper |
| Can mask request headers | No | Yes, and that is where the credential is |

Verified live on two routes differing only in this: a route with **only**
`log-data-mask` returned the caller the full email and phone while its log entry
carried the mask in both places and no `Authorization` header. A route with only
`response-rewrite` does the reverse.

## Native vs custom

Native, and the choice between the two native masking approaches matters.

- **`response-rewrite` filters** — a regex substitution over the body. No schema
  knowledge, works on any shape, one line per rule. The right tool when the fields
  are identifiable by name in the serialised body, which is the common case.
- **`body-transformer`** — a template that rebuilds the document. The right tool
  when you need to *restructure* rather than redact, when the same value appears
  under several keys, or when the masked output must remain schema-valid in a way
  a substitution cannot guarantee. It costs a template per operation.
- **A custom policy** — rejected. Redaction rules that live in code are rules that
  need a release to change, and the entire value here is that they do not.

## Why a regex, and where that stops

The regex has no idea what a field *means*; it matches text. Three consequences,
all of which the test plan turns into procedures:

- **Renamed copies are missed.** `"email"` is matched; `"contactEmail"` is not.
- **Encoded copies are missed.** A value inside a base64 or URL-encoded string is
  invisible to the pattern.
- **Broad patterns corrupt.** A pattern not anchored to its field name will match
  somewhere else eventually, and the corruption is silent.

Every filter in this package is anchored on its own key, and one test asserts that
fields outside the filter list come back untouched — the check that catches an
over-broad pattern before it reaches production.

## The `scope` default

`scope` defaults to `once`: the filter replaces the **first** match and stops.

On a single-record response that is invisible. On a collection it masks one record
and leaves the rest, and the one it masks is the first — the record in every
screenshot and code-review sample. Reproduced deliberately during validation: 1 of
10 records masked.

Every filter in this package sets `scope: global`. Treat a filter without it as a
review finding.

## When not to use this shape

- **The caller should not see the record at all.** Identity and authorization, not
  masking.
- **The value must never leave the backend.** The upstream still returns it; the
  gateway still holds it to rewrite it.
- **You need reversible tokenisation** — a masked value that remains a valid
  identifier a downstream system can correlate on.
- **Sensitive values live in free text.** Regex masking cannot find what it was
  not given the name of.
- **Very large payloads.** Body rewriting buffers the response.

## Failure modes and what they look like

| Symptom | Cause |
|---|---|
| The first record is masked, the rest are not | A filter is missing `scope: global` |
| Nothing is masked at all | The pattern does not match the serialised body — check whitespace, key spelling, and whether something upstream converted the format first |
| A field nobody asked to mask is mangled | An over-broad pattern; anchor it to its key |
| The logs are still full of PII | There is no logger on the route, so `log-data-mask` has nothing to act on; or the logger was added to a different route |
| The response is still full of PII | Only `log-data-mask` was configured. It does not touch the response |
| Analytics still shows the values | Expected. Analytics does not pass through the log helper |
| The single-record route 404s | `proxy-rewrite`'s `regex_uri` is not carrying the id — a routing fault, not a masking one |
