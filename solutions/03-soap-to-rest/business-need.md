# SOAP to REST/JSON mediation at the API gateway

> Your system of record speaks SOAP. It is correct, it is fast, and it has never
> lost a transaction — and every partner who wants to integrate asks for JSON. So
> each one becomes an adapter service, or a rewrite nobody will sign off on.
>
> **At the edge it is a configuration change, and you deploy nothing new.**

- **Services to operate: one per integration pattern → zero.** The translation is
  a plugin on a route, not a deployment with an on-call rotation, an owner who
  changed teams, and a WSDL it can drift from.
- **Onboarding a partner: a project → an app record.** Integration count stops
  dragging operational surface along with it.
- **Backend code changed: none.** The team that owns the legacy system leaves the
  critical path for a commercial decision that was never about the backend.

Mediating the protocol is the easy part. The decision is what the derived JSON
commits you to, because it is a mechanical projection of the XML rather than a
contract anyone designed:

| Question | The rule |
|---|---|
| Publish the derived shape as-is? | Fine while the consumer is internal or singular. The day you rename anything, it is a breaking change. |
| Document both result shapes? | Not optional — XML has no arrays, so one result is an object and two are a list. Code written against the multi-result example breaks on the single. |
| Expose the envelope's vocabulary? | `PascalCase` names and vendor prefixes become your public contract. Decide before partners integrate, not after. |

It handles **bodies, not the WS-\* stack** — WS-Security, SOAP headers,
attachments and MTOM are out of scope — and it does not make a slow handler fast.
[The three alternatives it replaces, and what this does not buy you, are in the
README](README.md#business-need).

*Also searched as: SOAP to REST gateway · XML to JSON API · expose SOAP as REST ·
legacy SOAP modernization · WSDL to REST API · API gateway protocol mediation ·
SOAP facade.*
