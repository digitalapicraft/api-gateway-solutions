# Agent-mode prompt — rate limiting with an API Product quota

Paste this to the Helix Agent as one message, replacing the `<<...>>` values.

**If the run ends early, paste the three steps one at a time instead** — this
build asks for a lot in a single turn, and splitting it changes nothing about the
words. Why it is worded this way, what the agent decides on its own, and what to
check before you trust it are in the
[README](README.md#build-it-with-the-helix-agent).

## Prompt

```text
Step 1:
Create a REST API called "<<01-api-products>>" in the <<test>> environment, proxying
https://jsonplaceholder.typicode.com. Two routes — GET /posts and GET
/posts/{postId} — passed straight through to the upstream.

Step 2:
Callers should identify themselves with an API key. I want to sell this API in two
tiers: a free tier capped at 5 requests a minute, and a pro tier at 1000. Enforce
those limits per app on both routes.

Step 3:
Create a developer "<<api-products-user>>" with two separate apps, one on the free
tier and one on the pro tier, and give me both keys. Then a curl loop showing the
free app getting 429s while the pro app is still getting 200s.
```
