# Solution 22 — Hide a backend API key: keep your supplier's key at the gateway, out of every app

> **Overview** · [Business need](business-need.md) · [Architecture](architecture.md) · [Guides](guides.md) · [Agent prompt](helix-agent-prompt.md) · [Tests](tests.md) · [API reference](api-reference.md)

**In short:** your apps call the gateway with keys of their own. The gateway
adds the supplier's one key on the way out, so no app ever holds it. Changing
the supplier key becomes one change at the gateway instead of a release of every
app.

| | |
|---|---|
| **Time to try it** | About 15 minutes |
| **Difficulty** | 🟢 Beginner — no coding needed |
| **What you'll need** | A free test account (its default `test` environment), one product and one app per client. The example uses postman-echo.com, a public test service that echoes back the request it received, so you can see exactly what "the supplier" got. |

---

## What is a backend key held at the gateway?

Many outside services (weather, maps, payments, data feeds) give you one **API
key**: a long secret value you send with every request to prove it's you. The
easy thing is to put that key into every app that calls the service. Then the
key is everywhere.

Here the key lives in one place only: the gateway's configuration. Your apps
call the gateway, not the supplier. Each app sends a **key of its own** in the
`X-Api-Key` header (a named value sent with the request). The gateway checks
that key, removes it, adds the supplier's key, and passes the request on.

It works like a company account at a courier. Staff don't each get the account
password. They hand parcels to reception, and reception books them on the one
company account.

## The use case

> *"Our weather data comes from a supplier that gives us ONE API key. Right now
> that key is compiled into our mobile app, our web app and two partner
> integrations. Rotating it means four releases, and anyone with a decompiler
> has it."*

(A decompiler turns a released app back into readable code. A key inside an app
is readable by anyone who downloads it.)

Three needs at the same time:

- **The supplier key must leave the apps.** Code that runs on phones and in
  browsers can't keep a secret.
- **Changing the key must not need four releases.** One change, in one place.
- **You still need to tell your clients apart**, and stop one without
  affecting the others.

## What keeping the key at the gateway gives you

- **No client holds the supplier key.** It isn't in any app, so it can't be
  pulled out of one.
- **One place to change it.** A new supplier key is one configuration change at
  the gateway. No app release.
- **A key for each client.** The mobile app, the web app and each partner get
  their own key, so every call names its client.
- **The supplier sees only its own key.** The client's key is removed before the
  request leaves the gateway.

## Benefits

- **A leaked client key affects one client.** Switch off that app. The supplier
  key and every other client keep working.
- **Changing the supplier key is a routine task**, not a coordinated release.
- **Your supplier relationship stays one account**, while you still know which
  of your clients made each call.

## Example

A client calls `GET /forecast?city=London`. The supplier stands behind the
gateway at postman-echo.com.

| The client sends… | It gets back | What the supplier receives |
|---|---|---|
| No key | HTTP 401 (not authenticated), *Missing API key in request* | nothing: it isn't called |
| A key no app owns | 401, *Invalid API key in request* | nothing |
| Its own app's key in `X-Api-Key` | 200 and the forecast | `X-Supplier-Key` with your supplier key, and **no** `X-Api-Key` |
| Its own key, plus an `X-Supplier-Key` of its choosing | 200 | only your configured supplier key |

**In the UI it takes seven short steps:** create the API, add three plugins
(check the client's key; set the supplier key and remove the client's key; an
optional request id), give it an upstream and deploy it, create a product and
deploy it, add a developer, create one app per client, and copy each app's key.
[Full click-by-click walkthrough →](guides.md#build-it-in-the-ui)

[Build it any of three ways, then see it work →](guides.md)

## Where to go next

- **Want the business case first?** [Business need](business-need.md) explains why
  this matters, in plain terms.
- **Want to understand how it works?** [Architecture](architecture.md) shows the
  request flow, the order the plugins run in, and what the supplier receives.
- **Ready to try it?** [Guides](guides.md) walks you through it step by step.
- **Want the full product documentation?** Every plugin, screen and API call is
  covered at [docs.digitalapi.ai/api-gateway](https://docs.digitalapi.ai/api-gateway).

## Related solutions

- **[08 — API keys](../08-api-key/)** — the same client key check, in depth:
  which key to send, switching a caller off, and changing a key.
- **[01 — API Products](../01-api-products/)** — add a usage limit for each
  client, so one app can't spend your whole supplier allowance.
- **[16 — Request tracing](../16-request-tracing/)** — see the headers the
  gateway changed on a live call. A trace shows the supplier key, so limit who
  can read traces.
- **[21 — Public reads, protected writes](../21-public-reads-protected-writes/)** —
  the same per-app key on some routes only, with the rest left open.
