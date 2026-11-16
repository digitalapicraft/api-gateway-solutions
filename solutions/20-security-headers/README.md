# Solution 20 — Security headers: close the pen test's header findings at the gateway

> **Overview** · [Business need](business-need.md) · [Architecture](architecture.md) · [Guides](guides.md) · [Agent prompt](helix-agent-prompt.md) · [Tests](tests.md) · [API reference](api-reference.md)

**In short:** add the response headers a security review expects to every
response from an API, and remove the ones that name your backend's software. One
block covers the whole API. No service changes, and the data itself is untouched.

| | |
|---|---|
| **Time to try it** | About 10 minutes |
| **Difficulty** | 🟢 Beginner — no coding needed |
| **What you'll need** | A free test account (its default `test` environment). No backend of your own: the example proxies public sample data that shows both findings. |

---

## What are security headers?

Every HTTP response carries headers: short instructions to whatever receives it.
A few of them matter for security, because a JSON API's responses still pass
through browsers, proxies and caches. `Cache-Control: no-store` tells every cache
on the way not to keep a copy. `X-Content-Type-Options: nosniff` tells a browser
not to guess that a JSON body is a web page.

Other headers do the opposite of helping. `X-Powered-By: Express` tells anyone
who asks which framework you run, so they can look up its known weaknesses
first.

## The use case

> *"The annual pen test flagged our API: no `X-Content-Type-Options`, no
> `Cache-Control: no-store` on responses carrying customer data, and every
> response announces `X-Powered-By: Express`. Twelve services, four teams, and
> the finding is due in two weeks."*

Fixing it in the services means twelve changes, four release trains, and a
thirteenth service next quarter that forgets. Every response already passes
through the gateway, so the fix can go there instead, once.

## What this gives you

- **Five headers on every response**, with the values OWASP recommends for a JSON
  API. Where the backend sends one already, the gateway replaces its value,
  so there is never a second copy.
- **The stack's name removed.** `X-Powered-By`, `Server`, `Via`,
  `X-AspNet-Version` and `X-AspNetMvc-Version` are taken off before the response
  leaves.
- **Errors covered too.** A 404 from your backend gets the same headers as a
  200. Scanners request plenty of things that don't exist.
- **The data untouched.** The rule changes headers only. The body your caller
  receives is byte-for-byte what the backend sent.

## Example

The sample API proxies public customer records. The backend answers
`GET /users/1` like this, and the gateway changes it like this:

| Header | The backend sends | The caller receives |
|---|---|---|
| `Cache-Control` | `max-age=43200` (keep for 12 hours) | `no-store` |
| `X-Powered-By` | `Express` | *(removed)* |
| `X-Content-Type-Options` | `nosniff` | `nosniff`, still one header |
| `X-Frame-Options` | *(none)* | `DENY` |
| `Content-Security-Policy` | *(none)* | `default-src 'none'; frame-ancestors 'none'` |
| `Referrer-Policy` | *(none)* | `no-referrer` |
| `X-Request-Id` | *(none)* | an id the caller can quote |
| **Body** | 509 bytes | **the same 509 bytes** |

**In the UI it takes four steps:** import the sample API, add two plugins with
**Entire Revision** scope, map an upstream, and deploy.
[Full walkthrough →](guides.md#build-it-in-the-ui)

[Build it any of three ways, then see it work →](guides.md)

## What it doesn't cover

- **HSTS** (`Strict-Transport-Security`). It belongs to the host and its TLS
  certificate, not to one API, so it is usually set where TLS ends. Check
  whether your callers already receive it.
  [Why, and how to add it →](guides.md#add-hsts)
- **Paths that match no route.** A request for a path the API doesn't have never
  reaches the API, so it gets the gateway's plain `404 Route Not Found` without
  these headers.
- **Your backend's other headers**, such as its CORS headers or its CDN's. They
  pass through unchanged unless you add them to the remove list.

## Where to go next

- **Want the business case first?** [Business need](business-need.md) explains
  why this matters, in plain terms.
- **Want to understand how it works?** [Architecture](architecture.md) covers
  where the rule runs and what each header does.
- **Ready to try it?** [Guides](guides.md) walks you through it step by step.
- **Want the full product documentation?** Every plugin, screen and API call is
  covered at [docs.digitalapi.ai/api-gateway](https://docs.digitalapi.ai/api-gateway).

## Related solutions

- **[10 — Data masking](../10-data-mask/)** — the same plugin, used the other
  way: it rewrites the response **body**. This package never touches the body.
  Put both on one route and read [the warning](architecture.md#one-rule-per-route) first.
- **[12 — Key-value store](../12-key-value-store/)** — a response the gateway answers
  itself, with no backend, gets these headers too when the rule is API-wide.
- **[08 — API keys](../08-api-key/)** — security headers are not access control.
  Put a key in front of customer data too.
