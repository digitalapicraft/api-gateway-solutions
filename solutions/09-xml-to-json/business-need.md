# JSON clients for an XML backend, at the API gateway

> The stock system is REST that answers in XML, because it was written in 2009.
> The web team wrote a parser, iOS wrote another, Android found a library, and the
> partner team gave up and asked for a nightly CSV. Four conversions of the same
> document, and the one that breaks is the one nobody owns.
>
> **Convert once, at the edge, and the backend keeps speaking XML.**

- **Conversions to maintain: one per client → one, in configuration.** A new
  client calls a JSON endpoint instead of writing parser number five.
- **Existing XML clients migrated: all of them → none.** The response is converted
  only when the caller asks for JSON, so XML callers keep using the same route.
- **Backend code changed: none.** It still receives and returns the XML it always
  has.

Pick the package by what the backend speaks, not by the word "XML":

| The backend | Use |
|---|---|
| plain HTTP carrying XML: an inventory API, a file feed, an industry schema | this package |
| SOAP: an envelope, a `SOAPAction`, a WSDL | [03 — SOAP to REST](../03-soap-to-rest/) |

The JSON mirrors the XML element for element, so it is not a redesigned API. It is
not lossless, and it does not keep key order on the way back to XML, so a backend
that validates a strict `xs:sequence` can reject a complete document. It ships
unauthenticated. [Before/after, what the conversion does to a document, and what
this does not buy you are in the README](README.md#business-need).

*Also searched as: XML to JSON at the API gateway · JSON to XML request transform ·
convert an XML API to JSON · modernise a legacy XML REST API · content negotiation
XML JSON · put a JSON front end on an XML backend · stop writing XML parsers in
every client.*
