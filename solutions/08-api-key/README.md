# Solution 08 — API keys: identify every device or partner job with one header, and switch any of them off in seconds

> **Overview** · [Business need](business-need.md) · [Architecture](architecture.md) · [Guides](guides.md) · [Agent prompt](helix-agent-prompt.md) · [Tests](tests.md) · [API reference](api-reference.md)

**In short:** give every caller its own key, sent in one header. The gateway
works out which caller each request comes from before it reaches your backend,
and you can cut off any single caller without a code change, a redeploy or a
firmware update.

| | |
|---|---|
| **Time to try it** | About 15 minutes |
| **Difficulty** | 🟢 Beginner — no coding needed |
| **What you'll need** | A free test account (its default `test` environment), one product that includes this API, and one app per caller. The example uses a public test service, so you need no backend of your own. |

---

## What is API-key identity?

An **API key** is a long random value a caller sends with every request, here in
an `X-Device-Key` header. Each caller gets its own key, issued by the gateway's
control plane on that caller's **app** (one app per device, partner or job).

When a request arrives, the gateway looks the key up and finds the app it belongs
to. Known key: the request goes through, labelled with that app. Missing or
unknown key: it is refused before your backend sees it.

It works like a building pass. Everyone has their own card, the door reader knows
whose card it is, and reception can cancel one lost card without changing the
locks for everyone else.

**How this differs from [solution 01](../01-api-products/):** 01 uses the same
key check *and* enforces a usage limit per app. This solution does only the first
half: it identifies the caller. The app still needs a product (that is how an app
gets a key), but no usage limit is enforced. Add 01's quota check later if you
need one.

## The use case

> *"We have about four thousand payment terminals in service stations. Each one
> pulls its price list in the morning and pushes its takings at close. They can't
> do an OAuth exchange — there's no reliable clock, nowhere safe to keep a
> refresh loop, and changing the firmware is a quarter of work plus an engineer
> in a van. Right now the only thing protecting that endpoint is that the URL
> isn't published. Last month one terminal was stolen out of a forecourt and
> nobody could tell me whether it was still calling us."*

Three needs hold at once:

- **The caller can't run a token exchange.** Embedded devices, old middleware and
  a partner's scheduled script can set one header and nothing more.
- **You still need to know who is calling.** "Which terminal?" is the first
  question in every incident, and an IP address doesn't answer it.
- **A compromised caller must be stoppable today**, not at the next firmware
  release.

## What it gives you

- **A per-caller identity** on every request, found before the backend is touched.
- **Instant, per-caller switch-off.** Delete or rotate one app; that caller's
  next request is refused.
- **No secret in the API's configuration.** The route only names the header the
  key arrives in. Keys live on the apps.
- **Nothing to change on the caller** beyond one header, and nothing on the
  backend.

## Benefits

- **A stolen device becomes a short task in the control plane**, not an open-ended
  exposure.
- **Incidents start with an answer.** Every request is tied to a specific app.
- **One leaked key affects one caller**, not the whole fleet.
- **Sets up metering and analytics.** Per-app quotas
  ([solution 01](../01-api-products/)) and per-app analytics
  ([solution 04](../04-analytics/)) need an app to count against. This creates it.

## Example

A fleet of terminals calls two routes: `GET /fleet/price-list` and
`POST /fleet/takings`.

| A terminal sends… | It gets back |
|---|---|
| No key | HTTP 401 (not authenticated), *Missing API key in request* |
| Its own key in `X-Device-Key` | 200 and the price list |
| A key that doesn't exist, or belongs to a deleted app | 401, *Invalid API key in request* |
| Its own key, but in the URL instead of the header | 401 |

**Setting this up in the gateway's UI takes seven short steps:** import the API,
give it an upstream and deploy it, create a product with the API in it, deploy
the product, add a developer, create one app per caller, then copy each app's key.
[Full click-by-click walkthrough →](guides.md#build-it-in-the-ui)

[Build it any of three ways, then see it work →](guides.md)

## Where to go next

- **Want the business case first?** [Business need](business-need.md) explains why
  this matters, in plain terms.
- **Want to understand how it works?** [Architecture](architecture.md) covers how a
  key is checked, and which credential type fits which caller.
- **Ready to build it?** [Guides](guides.md) walks you through it step by step.
- **Want the full product documentation?** Every plugin, screen and API call is
  covered at [docs.digitalapi.ai/api-gateway](https://docs.digitalapi.ai/api-gateway).

## Related solutions

- **[02 — OAuth 2.0 with JWT](../02-oauth-jwt/)** · **[05 — OAuth with Okta](../05-okta-jwt/)** ·
  **[06 — Signed requests](../06-hmac-auth/)** — the other three answers to "who
  is calling?". Pick by what the caller can hold.
- **[01 — API Products](../01-api-products/)** — add a usage limit to the apps
  this solution identifies. The quota is counted per app, the same object.
- **[04 — Analytics](../04-analytics/)** — per-app reporting, which only works
  because the caller was identified here.
