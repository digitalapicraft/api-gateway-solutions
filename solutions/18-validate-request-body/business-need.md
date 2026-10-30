# Stop bad requests from crashing your backend

> [Overview](README.md) · **Business need** · [Architecture](architecture.md) · [Guides](guides.md) · [Agent prompt](helix-agent-prompt.md) · [Tests](tests.md) · [API reference](api-reference.md)

---

> A caller leaves out one field. The service crashes with a 500, someone is
> paged, and the caller gets an error that tells them nothing. The fix in the
> service is weeks away.
>
> **The request was wrong, and nobody told the caller what was wrong with it.**

- **Fewer pages for the on-call team.** Before: a missing field is a 500 and an
  alert. After: it is a 400 at the gateway, and the service never sees it.
- **Callers fix their own mistakes.** Before: "your API returned 500". After:
  `property "priority" is required`, and the next request is right.
- **Protection today, not next release.** The rule is gateway configuration, so
  it goes live with a deploy of the API, not of the service.

One choice to make, per route:

| What the caller sees on a 400 | Good for |
|---|---|
| The checker's own message, naming the field (the sample's choice) | Partners and your own teams, who need to know what to fix |
| One fixed message you write | Public APIs where you'd rather not describe your rules in errors |

The gateway checks the shape of a body, not what it means: it can't tell
whether ticket `7` exists. [What it catches and what it doesn't is in the
architecture page](architecture.md#what-the-check-does-not-catch).

*Also searched as: API request validation · JSON schema validation at the API
gateway · reject invalid request body · 400 instead of 500 · required field
missing · enum validation · validate POST body · API input validation.*
