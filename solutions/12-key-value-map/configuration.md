# Configuration — Solution 12 — one route, fourteen partners, and rotation without a deploy

[Overview](readme.md) · [Business need](business-need.md) · [How it works](how-it-works.md) · [Install](install.md) · **Configuration** · [Test & verify](testing.md) · [Changelog](changelog.md)

---

## Configuration

Source of truth: [`gateway/api-spec.yaml`](gateway/api-spec.yaml).

Registration — the value comes from the **request body**, never from this file:

```yaml
key-value-map:
  fail_action: close
  inserts:
    - key: "$request.headers.x-partner-id"
      value: "$request.body.public_key"
```

Use — fetch, then let the crypto plugin resolve the same reference:

```yaml
key-value-map:
  fail_action: close
  fetch:
    keys:
      - key: "$request.headers.x-partner-id"

pgp-crypto:
  keys_ctx_namespace: key_value_map
  encrypt:
    target: response
    source: body
    public_key: "$request.headers.x-partner-id"
    fail_policy: fail-close
    fail_close_status: 500
```

**A missing entry is not an error to `key-value-map`.** It does not know whether
the value mattered. The failure is raised by the *consuming* plugin — so
`fail_policy` on `pgp-crypto` is the control that decides what an unregistered
partner gets, and `fail-open` there would return the backend's document **in the
clear**. One of the tests asserts the 500 for exactly that reason.
