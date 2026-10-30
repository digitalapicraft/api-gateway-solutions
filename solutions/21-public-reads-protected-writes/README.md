# Solution 21 — Public reads, protected writes: anyone can read the catalogue, only partners can change it

> **Overview** · [Business need](business-need.md) · [Architecture](architecture.md) · [Guides](guides.md) · [Agent prompt](helix-agent-prompt.md) · [Tests](tests.md) · [API reference](api-reference.md)

**In short:** leave the routes that read your data open to everyone, and put a
key check on the routes that change it. Search engines and comparison sites
keep reading with no key. A request to add, change or remove an item needs a
partner's key, and without one the gateway refuses it before your backend sees
it.

| | |
|---|---|
| **Time to try it** | About 15 minutes |
| **Difficulty** | 🟢 Beginner — no coding needed |
| **What you'll need** | A free test account (its default `test` environment), one product that includes this API, and one app per partner. The example uses a public test service, so you need no backend of your own. |

---

## What does "protect the writes" mean?

An API is a set of **routes**. A route is one method on one path:
`GET /catalog/items` (read the list) and `POST /catalog/items` (add an item)
are two different routes, even though the path is the same.

A **plugin** is a ready-made feature you switch on for routes. You can switch it
on for the **whole API**, which covers every route, or for **one route**. This
solution switches on the key check for the three routes that change data, and
for nothing else:

| Route | Who can call it |
|---|---|
| `GET /catalog/items`, `GET /catalog/items/:itemId` | Anyone. No key. |
| `POST /catalog/items`, `PUT /catalog/items/:itemId`, `DELETE /catalog/items/:itemId` | Partners only. A key in the `X-Api-Key` header. |

Where you switch the check on is the whole design. Switch it on for the whole
API and the catalogue disappears from every search engine overnight.

A partner's key belongs to an **app** (one caller). The **control plane**, where
you manage APIs, products, developers and apps, creates the key when you create
the app.

## The use case

> *"Our product catalogue is public. Anyone, including search engines and
> comparison sites, should be able to read it with no key. Only our partners
> should be able to add, change or remove items, and today anyone who finds the
> POST endpoint can."*

Two needs pull in opposite directions:

- **Reading must stay frictionless.** A crawler won't sign up for a key. Every
  hurdle on a read is lost traffic.
- **Writing must be locked down.** An open write route lets anyone change your
  prices or delete your products, and you can't tell who did it.

## What you get

- **Open reads, exactly as before.** No key, no sign-up, nothing for a search
  engine to do differently.
- **Closed writes.** No key, or a key that belongs to no app: HTTP 401 (not
  authenticated). Your backend never sees the request.
- **Every write names its partner.** Each partner has its own app and key, so
  you can switch one off without touching the others.
- **No code.** Nothing changes in your backend or in the partners' calls, apart
  from one header.

## Example

| A caller sends… | It gets back |
|---|---|
| `GET /catalog/items`, no key | 200 and the catalogue |
| `POST /catalog/items`, no key | 401, *Missing API key in request* |
| `PUT /catalog/items/1` with a key that belongs to no app | 401, *Invalid API key in request* |
| `DELETE /catalog/items/1` with a partner's key | 200 |
| `GET /catalog/items/1` with a partner's key | 200. A key never hurts a read. |
| `PATCH /catalog/items/1` | 404. The API has no `PATCH` route, so there is nothing to call. |

**In the UI it takes eight short steps:** create the API (from scratch or from
an OpenAPI spec), add one plugin to the whole API and the key check to each of
the three write routes, give it an upstream and deploy it, create a product
with the API in it, deploy the product, add a developer, create one app per
partner, then copy each app's key.
[Full click-by-click walkthrough →](guides.md#build-it-in-the-ui)

(The upstream is your backend service, where the gateway forwards requests that
pass.)

[Build it any of three ways, then see it work →](guides.md)

## Where to go next

- **Want the business case first?** [Business need](business-need.md) explains why
  this matters, in plain terms.
- **Want to understand how it works?** [Architecture](architecture.md) covers
  routes, where a plugin applies, and what the key check does and doesn't do.
- **Ready to build it?** [Guides](guides.md) walks you through it step by step.
- **Want the full product documentation?** Every plugin, screen and API call is
  covered at [docs.digitalapi.ai/api-gateway](https://docs.digitalapi.ai/api-gateway).

## Related solutions

- **[08 — API keys](../08-api-key/)** — the same key check on every route, with
  more on switching a caller off and changing a key.
- **[01 — API Products](../01-api-products/)** — add a usage limit for each
  partner on top of the key.
- **[02 — OAuth 2.0 with JWT](../02-oauth-jwt/)** — short-lived tokens instead
  of keys, for partners whose systems can fetch one.
- **[22 — Hide your backend's key](../22-hide-backend-key/)** — the same per-app
  key, when the backend behind it needs a key of its own that clients must never hold.
