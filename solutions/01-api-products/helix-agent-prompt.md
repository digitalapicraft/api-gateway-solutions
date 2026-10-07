# Agent-mode prompt — rate limiting with an API Product quota

> [Overview](README.md) · [Business need](business-need.md) · [Architecture](architecture.md) · [Guides](guides.md) · **Agent prompt** · [Tests](tests.md) · [API reference](api-reference.md)

---

Paste this to the Helix Agent as one message, replacing the `{{...}}` values.

**If the run ends early, paste the three steps one at a time instead** — this
build asks for a lot in a single turn, and splitting it changes nothing about the
words. When it finishes, read the deployed revision back and check that
`api-product-enforcer` is on the API and that no `limit-count` was added. See
[Troubleshooting](guides.md#troubleshooting) if something looks off.

## Prompt

```text
Step 1:
Create a REST API called "{{api_name}}" in the {{environment}} environment, proxying
https://jsonplaceholder.typicode.com. Two routes — GET /posts and GET
/posts/{postId} — passed straight through to the upstream.

Step 2:
Callers should identify themselves with an API key. I want to sell this API in two
tiers: a free tier capped at 5 requests a minute, and a pro tier at 1000. Enforce
those limits per product.

Step 3:
Create a developer "{{developer_name}}" with two separate apps, one on the free
tier and one on the pro tier, and give me both keys. Then a curl loop showing the
free app getting 429s while the pro app is still getting 200s.
```
