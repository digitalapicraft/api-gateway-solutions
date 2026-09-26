# Test & verify — Solution 09 — JSON in, JSON out, in front of a backend that only speaks XML

[Overview](readme.md) · [Business need](business-need.md) · [How it works](how-it-works.md) · [Install](install.md) · [Configuration](configuration.md) · **Test & verify** · [Changelog](changelog.md)

---

## What the conversion actually does to your document

XML and JSON do not have the same shape, so a converter has to make choices. Here
are the ones this plugin makes, observed against a real document rather than read
off a schema.

| XML | Becomes | Watch out for |
|---|---|---|
| A repeated element | A JSON array | **A single occurrence becomes an object, not a one-item array.** The classic intermittent client bug |
| Attributes on the **root** element | Ordinary keys next to the child elements | Indistinguishable from elements once converted |
| Attributes on **child** elements | **Were not present in the converted output** | If data lives in child attributes, check your own document before depending on it |
| An empty element | `null` | Not `""`, and not an absent key |
| Mixed content (`Why <em>X</em> is great`) | Reshaped into separate keys, with the text rejoined | Do not put meaning in mixed content |
| A hyphenated name | An underscored key | `order-id` → `order_id` |

And in the other direction, JSON → XML:

| JSON | Becomes | Watch out for |
|---|---|---|
| An array under a key | Repeated sibling elements named after the key | Not a wrapper element containing children |
| A top-level array | `request_root_name` wrapping `array_item_name` children | Both names are yours to choose |
| Object key order | **Not preserved** | A backend whose schema is an `xs:sequence` can reject a document containing every field it asked for |

That last row is the one to check before promising the request direction to
anyone. If your backend validates against a strict sequence, this plugin is not
the right tool for the request side — a template-based transform is.

## Testing

Exit 0 means all five cases held:

| # | Case | Expected |
|---|---|---|
| 1 | `Accept: application/json` on the read route | `200` JSON, no XML markup left |
| 2 | **`Accept: application/xml` on the same route** | `200` the backend's XML, untouched |
| 3 | A JSON order body | `200`, and the backend received `<order>` with the namespace |
| 4 | **The same body sent as `text/plain`** | `200`, forwarded **unchanged** |
| 5 | A malformed JSON body | `400` at the gateway |

**Cases 2 and 4 are the ones worth keeping.** Both assert what the plugin
deliberately does *not* do, and both are the behaviour people later mistake for a
bug. Case 4 in particular is the failure that reaches production: nothing in the
gateway's response indicates the transform was skipped.

The single-element-array and attribute-fidelity cases are manual, because the
answer depends on your document rather than on the configuration —
[`tests/test-plan.yaml`](tests/test-plan.yaml) has the procedure for both.
