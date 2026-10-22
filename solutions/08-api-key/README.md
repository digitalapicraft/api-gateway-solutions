# Solution 08 — API keys: know which device or partner is calling, and switch any one of them off in seconds

> **Overview** · [Business need](business-need.md) · [Architecture](architecture.md) · [Guides](guides.md) · [Agent prompt](helix-agent-prompt.md) · [Tests](tests.md) · [API reference](api-reference.md)

**In short:** give every caller its own key. The caller sends it in one header
(a named line of extra information that travels with each request). The gateway
works out which caller sent each request before it reaches your backend. You can
cut off any one caller without changing code, deploying again or updating the
device's software.

| | |
|---|---|
| **Time to try it** | About 15 minutes |
| **Difficulty** | 🟢 Beginner — no coding needed |
| **What you'll need** | A free test account (its default `test` environment), one product that includes this API, and one app per caller. The example uses a public test service, so you need no backend of your own. |

---

## What is an API key?

An **API key** is a long random value that a caller sends with every request.
Here it goes in a header called `X-Device-Key`. Each caller gets its own key.

The key belongs to an **app**. An app stands for one caller: one device, one
partner, or one scheduled job. The **control plane** (the part of the platform
where you manage APIs, products, developers and apps) creates the key when you
create the app.

When a request arrives, the gateway looks up the key and finds the app it
belongs to:

- **A known key:** the request goes through, marked with the name of that app.
- **A missing or unknown key:** the gateway refuses the request. Your backend
  never sees it.

It works like a building pass. Everyone has their own card. The door reader knows
whose card it is. Reception can cancel one lost card without changing the locks
for everyone else.

**How this differs from [solution 01](../01-api-products/):** 01 does the same
key check. It also sets a usage limit for each app. This solution does only the
first part: it finds out who the caller is. Each app still needs a **product** (a
bundle of APIs that apps sign up to), because signing up to a product is how an
app gets its key. But no usage limit is applied, and the key check doesn't look
at which product the app is on: a key from any app in the environment is
accepted. You can add 01's check later if you need either.

## The use case

> *"We have about four thousand payment terminals in service stations. Each one
> pulls its price list in the morning and pushes its takings at close. They can't
> do an OAuth exchange — there's no reliable clock, nowhere safe to keep a
> refresh loop, and changing the firmware is a quarter of work plus an engineer
> in a van. Right now the only thing protecting that endpoint is that the URL
> isn't published. Last month one terminal was stolen out of a forecourt and
> nobody could tell me whether it was still calling us."*

(A payment terminal is the card machine at the till. "An OAuth exchange" means
swapping a secret for a short-lived token before calling the API.)

Three needs apply at the same time:

- **The caller can't swap a secret for a token.** Small devices, old software
  that sits between systems, and a partner's scheduled script can set one header
  and nothing more.
- **You still need to know who is calling.** "Which device?" is the first
  question when something goes wrong. An IP address doesn't answer it.
- **You must be able to stop a stolen or misused caller today**, not at the next
  device software update.

## What API keys give you

- **Every request names its caller.** The gateway finds the app before your
  backend is touched.
- **You can switch off one caller at once.** Delete that app, or give it a new
  key. Its next request with the old key is refused.
- **No secret in the API's configuration.** The route only names the header the
  key arrives in. The keys are stored on the apps.
- **Nothing to change on the caller** except one header, and nothing to change on
  the backend.

## Benefits

- **A stolen device is a short task in the control plane.** It does not stay an
  open risk.
- **When something goes wrong, you already know who is involved.** Every request
  is tied to one named app.
- **A leaked key affects one caller**, not all your devices.
- **It prepares the ground for usage limits and reports.** Per-app usage limits
  ([solution 01](../01-api-products/)) and per-app reports
  ([solution 04](../04-analytics/)) need an app to count each request under. This
  solution creates it.

## Example

A set of payment terminals calls two routes: `GET /fleet/price-list` and
`POST /fleet/takings`.

| A terminal sends… | It gets back |
|---|---|
| No key | HTTP 401 (not authenticated), *Missing API key in request* |
| Its own key in `X-Device-Key` | 200 and the price list |
| A key that doesn't exist, or belongs to a deleted app | 401, *Invalid API key in request* |
| Its own key, but in the URL instead of the header | 401 |

**Setting this up in the gateway's UI takes eight short steps:** create the API
(from scratch, or from an OpenAPI spec), add the plugins that check the key and
point each route at your backend, give it an upstream and deploy it, create a
product with the API in it, deploy the product, add a developer, create one app
per caller, then copy each app's key.
[Full click-by-click walkthrough →](guides.md#build-it-in-the-ui)

(A plugin is a ready-made feature you switch on for a route. The upstream is your
backend service, where the gateway forwards requests that pass.)

[Build it any of three ways, then see it work →](guides.md)

## Where to go next

- **Want the business case first?** [Business need](business-need.md) explains why
  this matters, in plain terms.
- **Want to understand how it works?** [Architecture](architecture.md) covers how a
  key is checked, and which kind of credential (key, token or signature) fits
  which caller.
- **Ready to build it?** [Guides](guides.md) walks you through it step by step.
- **Want the full product documentation?** Every plugin, screen and API call is
  covered at [docs.digitalapi.ai/api-gateway](https://docs.digitalapi.ai/api-gateway).

## Related solutions

- **[02 — OAuth 2.0 with JWT](../02-oauth-jwt/)** · **[05 — OAuth with Okta](../05-okta-jwt/)** ·
  **[06 — Signed requests](../06-hmac-auth/)** — the other three ways to answer
  "who is calling?". Pick one by what the caller can store and do.
- **[01 — API Products](../01-api-products/)** — add a usage limit to the apps
  this solution identifies. The limit is counted per app, the same app this
  solution creates.
- **[04 — Analytics](../04-analytics/)** — reports for each app. They only work
  because this solution has already found out which app is calling.
