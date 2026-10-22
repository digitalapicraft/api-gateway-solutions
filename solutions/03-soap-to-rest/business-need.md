# SOAP to REST/JSON mediation at the API gateway

> [Overview](README.md) · **Business need** · [Architecture](architecture.md) · [Guides](guides.md) · [Agent prompt](helix-agent-prompt.md) · [Tests](tests.md) · [API reference](api-reference.md)

---

> Your system of record speaks SOAP. It is correct, it is fast, and it has never
> lost a transaction — and every partner who wants to integrate asks for JSON. So
> each one becomes an adapter service, or a rewrite nobody will sign off on.
>
> **At the edge it is a configuration change, and you deploy nothing new.**

- **Services to run: one per integration pattern → zero.** The translation is a
  plugin on a route, not a deployment with its own on-call rotation, an owner who
  changed teams, and a WSDL it can drift away from.
- **Onboarding a partner: a project → an app record.** Adding integrations stops
  adding things to operate.
- **Backend code changed: none.** The team that owns the legacy system leaves the
  critical path for a commercial decision that was never about the backend.

Converting the format is the easy part. The decision is what the converted JSON
commits you to, because it is a mechanical copy of the XML rather than a contract
anyone designed:

| Question | The rule |
|---|---|
| Publish the converted shape as-is? | Fine while the consumer is internal or there's only one. The day you rename anything, it is a breaking change. |
| Document both result shapes? | Not optional — XML has no arrays, so one result is an object and two are a list. Code written against the multi-result example breaks on the single one. |
| Expose the envelope's vocabulary? | `PascalCase` names and vendor prefixes become your public contract. Decide before partners integrate, not after. |

## Before and after

| | An adapter per partner | Converted at the edge |
|---|---|---|
| **New services to run** | One per integration pattern, each with deploys and on-call | None |
| **Time to onboard a partner** | An adapter project | Create an app; they call the existing endpoint |
| **Risk to the backend** | None from the adapter — but the rewrite alternative is serious | None. The SOAP service is unchanged |
| **Where the translation lives** | Several codebases, drifting apart | One configuration block |
| **Sign-in** | Built into each adapter, slightly differently each time | Once, at the edge — see [solution 02](../02-oauth-jwt/) |
| **Traffic reporting** | Per adapter, if someone built it | Every call captured, per app — see [solution 04](../04-analytics/) |

The structural point: **the number of things you run stops growing with the
number of partners you onboard.** That is not a speed claim; it is about how many
moving parts you own, and it adds up over time. No return-on-investment figure is
claimed here — use your own adapter count and onboarding times.

It handles **message bodies, not the full SOAP standards stack** — WS-Security,
SOAP headers, attachments and MTOM are out of scope — and it does not make a slow
handler fast. [What this does not buy you is on the Architecture
page](architecture.md#limitations).

*Also searched as: SOAP to REST gateway · XML to JSON API · expose SOAP as REST ·
legacy SOAP modernization · WSDL to REST API · API gateway protocol mediation ·
SOAP facade.*
