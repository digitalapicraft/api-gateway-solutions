# Configuration — Solution 10 — mask the values, not just the log line

[Overview](readme.md) · [Business need](business-need.md) · [How it works](how-it-works.md) · [Install](install.md) · **Configuration** · [Test & verify](testing.md) · [Changelog](changelog.md)

---

## Configuration

Source of truth: [`gateway/api-spec.yaml`](gateway/api-spec.yaml).

What the caller sees:

```yaml
response-rewrite:
  filters:
    - regex: '("email"\s*:\s*")[^"@]+@'
      replace: '$1***@'
      scope: global
    - regex: '("phone"\s*:\s*")[^"]*"'
      replace: '$1[redacted]"'
      scope: global
```

What a logger writes:

```yaml
log-data-mask:
  response:
    - { type: body, name: email, action: replace, value: "[redacted]", body_format: json }
    - { type: body, name: phone, action: replace, value: "[redacted]", body_format: json }
  request:
    - { type: header, name: authorization, action: remove }
```

### `scope: global` is not optional

`scope` defaults to **`once`**. A filter without it masks the **first** match in
the body and leaves every other one.

On a ten-record list that is one masked record and nine in the clear. Verified
deliberately during this package's validation: with the default scope, **1 of 10**
records was masked. And because it is the *first* record, it is the one in every
screenshot, every demo and every code-review sample — the configuration looks
correct in exactly the view people check it in.

If you take one thing from this package, take that.

### The mask is a regex, not a parser

That is the strength — it needs no knowledge of your schema, and it works on a
response shape you have never seen. It is also the limit, and the limit is sharp:

- **A value under a different key is not masked.** The filter is anchored on
  `"email"`. A copy of the same address in `contactEmail`, or in a free-text note,
  or in an error message, passes straight through.
- **A value inside an encoded string is not masked.** Base64, URL-encoded,
  a nested JSON string — the regex sees text, not meaning.
- **A pattern that is too broad corrupts data silently.** Every filter here is
  anchored on its own field name for that reason, and one test asserts that
  unfiltered fields come back untouched.

Run the encoded-and-renamed-fields case in
[`tests/test-plan.yaml`](tests/test-plan.yaml) against **real** payloads before
you rely on this. Error messages and audit-trail fields are where copies hide.

### Why the email keeps its domain

`***@april.biz`, not `[redacted]`. Support uses the domain to tell which customer
organisation a person belongs to; the local part is the identifying half. A mask
that removes the whole address makes the console worse at its job, and a control
that makes the job harder without a visible benefit is a control that gets
switched off two sprints later.

Mask what is sensitive. Keep what is useful. They are usually different halves of
the same field.
