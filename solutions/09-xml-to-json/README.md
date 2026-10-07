# Solution 09 — XML to JSON: give JSON clients a JSON API on a backend that only speaks XML

> **Overview** · [Business need](business-need.md) · [Architecture](architecture.md) · [Guides](guides.md) · [Agent prompt](helix-agent-prompt.md) · [Tests](tests.md) · [API reference](api-reference.md)

**In short:** convert between XML and JSON at the gateway, so your clients send
and receive JSON while the backend keeps speaking the XML it always has — and
existing XML clients keep working, untouched.

| | |
|---|---|
| **Time to try it** | About 15 minutes |
| **Difficulty** | 🟢 Beginner — no coding needed |
| **What you'll need** | A free test account (its default `test` environment). No backend of your own: the example uses the public httpbin service, which echoes requests back, so you can *see* the XML your backend would have received |

---

## What is XML-to-JSON mediation?

Many older backends answer in XML. Most modern clients — web apps, mobile apps,
partner integrations — want JSON. Normally every client converts the XML itself.

Here the gateway does the conversion, in both directions:

- **Responses:** when a client asks for JSON (by sending the header
  `Accept: application/json`), the gateway turns the backend's XML into JSON.
- **Requests:** when a client sends a JSON body, the gateway turns it into XML
  before the backend sees it.

The backend never changes. It keeps receiving and returning XML.

**This is not the SOAP solution.** Two different people land here from two
different searches:

| | [Solution 03 — SOAP to REST](../03-soap-to-rest/) | **This one** |
|---|---|---|
| The backend | A SOAP service: envelope, `SOAPAction`, one handler path, a WSDL | Plain HTTP that happens to carry XML — an inventory API, a payments file feed, an industry schema |
| What the gateway must build | A whole envelope around your data | Nothing. Element for element, key for key |
| Route shape | Every operation collapses onto one upstream path | Ordinary REST paths |
| Reach for it when | There is a `<soap:Envelope>` anywhere in the conversation | There isn't |

If your backend has an envelope, use 03 — this package would send XML the SOAP
handler rejects. If it doesn't, 03 would wrap your data in an envelope nothing is
expecting.

## The use case

> *"Our stock system is REST. It's just REST that answers in XML, because it was
> written in 2009 and that was the house style. Every SOAP-to-REST guide we find
> starts by telling us to build an envelope we don't have. Meanwhile the web team
> wrote an XML parser, the iOS team wrote a different one, the Android team found
> a library, and the partner integration team gave up and asked for a nightly CSV.
> Four implementations of the same conversion, and the one that breaks is always
> the one nobody owns."*

The cost isn't the format. It is that the conversion lives in every client, four
times, in four languages, each with its own idea of what an empty element means.

## What this gives you

- **One conversion, in configuration**, instead of one parser per client.
- **Both directions** on the same API: XML responses become JSON, JSON request
  bodies become XML.
- **No backend change.** It keeps speaking XML.
- **Existing XML clients keep working.** The response is converted only when a
  client asks for JSON, so the old clients are untouched on the same route.

## Benefits

- **A new client costs nothing extra.** It calls a JSON endpoint; there's no
  parser number five to write.
- **No migration project.** Because conversion is opt-in per request, you can
  open the JSON front door without moving the XML clients first.
- **Conversion problems land in one place**, with one owner, instead of on
  whichever client team saw them first.

## Example

The example API has two routes on a public test backend:

| Call | What comes back |
|---|---|
| `GET /catalog/items` with `Accept: application/json` | The backend's XML document, converted to JSON |
| `GET /catalog/items` with `Accept: application/xml` | The backend's XML, untouched |
| `POST /catalog/orders` with a JSON body | The backend receives `<order xmlns="urn:example:catalog">…</order>` |

**Setting this up in the gateway's UI takes two short steps:** import the API,
then give it an upstream and deploy it. The conversion settings come with the
imported spec. [Full click-by-click walkthrough →](guides.md#build-it-in-the-ui)

[Build it any of three ways, then see it work →](guides.md)

## Where to go next

- **Want the business case first?** [Business need](business-need.md) explains why
  this matters, in plain terms.
- **Want to understand how it works?** [Architecture](architecture.md) covers the
  two switches that decide whether anything is converted, and what the conversion
  does to your document.
- **Ready to build it?** [Guides](guides.md) walks you through it step by step.
- **Want the full product documentation?** Every plugin, screen and API call is
  covered at [docs.digitalapi.ai/api-gateway](https://docs.digitalapi.ai/api-gateway).

## Related solutions

- **[03 — SOAP to REST](../03-soap-to-rest/)** — the envelope case. Read the table
  above before choosing.
- **[08 — API keys](../08-api-key/)** · **[02 — OAuth 2.0 with JWT](../02-oauth-jwt/)** —
  this package ships without authentication so the conversion is the only thing
  being shown. Put one of these in front before it carries anything real.
- **[10 — Data masking](../10-data-mask/)** — for when the converted response
  contains more than the client should see.
