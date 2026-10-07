# XML to JSON conversion for a legacy REST backend

> [Overview](README.md) · **Business need** · [Architecture](architecture.md) · [Guides](guides.md) · [Agent prompt](helix-agent-prompt.md) · [Tests](tests.md) · [API reference](api-reference.md)

---

> Your backend answers in XML and nobody can change it. So the web team wrote a
> parser, the iOS team wrote another, the Android team found a library, and the
> partner team asked for a nightly file. Each one answers the same questions
> differently — what an empty element means, whether one item is a list — and
> they agree until the data changes.
>
> **The conversion is being solved four times, in the wrong place.**

- **A new client calls an endpoint** instead of writing parser number five, so
  integration time stops growing with every new consumer.
- **The XML clients don't have to move.** The response is converted only when a
  client asks for JSON, so the new front door opens without a migration project —
  usually the difference between "approved" and "next year".
- **Conversion bugs land in one place**, with one owner, instead of on a client
  team that did nothing wrong.

| Before | After |
|---|---|
| One conversion per client | One, in configuration |
| Adding JSON means migrating everyone | XML clients keep working through the same route |
| The backend rewrite is the only "real" fix | Backend untouched; the change is a revision deploy |

No figures here are measured savings; they are the reasoning. It is not an API
redesign — the JSON mirrors the XML, element for element — and it is not
lossless. [What it does not do is in Architecture](architecture.md#what-it-does-not-do).

*Also searched as: XML to JSON API · convert XML response to JSON · JSON to XML
request · legacy XML API modernization · REST XML backend JSON clients · API
content negotiation · XML mediation without SOAP.*
