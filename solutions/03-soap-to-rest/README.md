# Solution 03 — SOAP to REST: let partners use JSON while your old system keeps speaking XML

> **Overview** · [Business need](business-need.md) · [Architecture](architecture.md) · [Guides](guides.md) · [Agent prompt](helix-agent-prompt.md) · [Tests](tests.md) · [API reference](api-reference.md)

**In short:** partners send and receive JSON; your SOAP system keeps receiving and
answering in XML. The gateway converts between the two on every call, so neither
side changes and you run no adapter service in between.

| | |
|---|---|
| **Time to try it** | About 25 minutes |
| **Difficulty** | 🟡 Intermediate — no coding, but you need your own SOAP service |
| **What you'll need** | A free test account, a SOAP service the gateway can reach, and the path its handler answers on (for example `/Service.asmx`). A public sample backend can't stand in here — this needs real SOAP. |

---

## What is SOAP-to-REST mediation?

**SOAP** is an older style of web service: requests and responses are XML
documents wrapped in an "envelope", described by a WSDL file. **REST/JSON** is
what most developers expect today: a simple URL and a JSON body.

**Mediation** means the gateway translates between the two in the middle. A
partner sends JSON to a REST-style route. The gateway turns that JSON into XML,
sends it to your SOAP service on its real path, then turns the XML answer back
into JSON on the way out.

It works like an interpreter at a meeting. Each side speaks its own language, and
neither has to learn the other's. One call in means exactly one call to the SOAP
service — only the format changes.

## The use case

> *"Our system of record is SOAP. It has been SOAP since 2004, it is correct, it
> is fast, and it has never lost a transaction. Every fintech partner who wants to
> integrate asks for JSON and OAuth, and every one of them is a project: write an
> adapter service, deploy it, monitor it, keep it in step with the WSDL. We now
> have four adapters, two of which nobody owns. The alternative is rewriting the
> system of record, which nobody will sign off, correctly."*

There are three usual options, and none is good:

- **Rewrite the backend.** A big project, a migration, and a real risk of losing
  behaviour nobody wrote down.
- **Write an adapter for each partner.** Each one is another service to deploy,
  monitor and keep in step with the WSDL.
- **Make partners speak SOAP.** Some will. Most will quietly put the integration
  at the bottom of their list.

## What this solution gives you

- **One REST route**, `POST /locations`, that accepts and returns JSON.
- **Conversion in both directions** by one plugin: JSON to XML on the way in, XML
  to JSON on the way out.
- **A path rewrite**, so partners call a clean route while your SOAP handler keeps
  its own path.
- **A tracking id on every call**, so you can match the JSON a partner saw with the
  XML your system returned.
- **No change to the SOAP system.** It doesn't know a REST client exists.

**What it does not include: sign-in.** As shipped, the route is open to anyone who
can reach the gateway. Add [solution 02](../02-oauth-jwt/) in front of it before
partners call it — [Variations](guides.md#variations) shows how.

## Benefits

- **No new services to run.** The translation is a setting on a route, not a
  deployment with its own monitoring and on-call.
- **Onboarding a partner becomes an app record**, not an adapter project.
- **Your system of record is untouched**, and its team is not on the critical path
  for a commercial decision.
- **One place for the translation**, instead of several adapters that slowly drift
  apart.

## Example

A partner sends plain JSON — no envelope, no WSDL:

```http
POST /locations
content-type: application/json
accept: application/json

{"region":"EMEA","activeOnly":true}
```

and gets JSON back, converted from your system's XML:

```json
{"Locations":{"Site":[{"id":"1","name":"Frankfurt"},{"id":"2","name":"Dublin"}]}}
```

Note the shape: names like `Locations` and `Site` come straight from the XML. The
JSON is a mechanical copy of your system's XML, not a contract someone designed —
[Architecture](architecture.md#why-the-json-shape-is-derived-not-designed) explains
what that means for your partners.

**Setting this up in the gateway's UI takes three short steps:** put your SOAP
handler's path into the spec and import it, point an upstream at your SOAP service,
then deploy. [Full click-by-click walkthrough →](guides.md#build-it-in-the-ui)

[Build it any of three ways, then see it work →](guides.md)

## Where to go next

- **Want the business case first?** [Business need](business-need.md) explains why
  this matters, in plain terms.
- **Want to understand how it works?** [Architecture](architecture.md) covers the
  conversion, the one setting everybody gets wrong, and when *not* to use this.
- **Ready to build it?** [Guides](guides.md) walks you through it step by step.
- **Want the full product documentation?** Every plugin, screen and API call is
  covered at [docs.digitalapi.ai/api-gateway](https://docs.digitalapi.ai/api-gateway).

## Related solutions

- **[02 — OAuth 2.0 with JWT](../02-oauth-jwt/)** — the sign-in layer this package
  doesn't include, and the one to add before partners call it.
- **[01 — API Products](../01-api-products/)** — give each partner calling your old
  system a usage limit, and sell tiers. It needs sign-in first, so add 02 before 01.
- **[04 — Analytics](../04-analytics/)** — see which partner calls the old system,
  and how often.
- **[09 — XML to JSON](../09-xml-to-json/)** — for an XML backend that isn't SOAP.
  Choose between the two before you start.
