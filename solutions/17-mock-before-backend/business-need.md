# Unblock the frontend before the backend exists

> [Overview](README.md) · **Business need** · [Architecture](architecture.md) · [Guides](guides.md) · [Agent prompt](helix-agent-prompt.md) · [Tests](tests.md) · [API reference](api-reference.md)

---

> The screen is designed, the contract is agreed, and the frontend team has
> nothing to call. The backend is three weeks out, so the feature is six weeks
> out: three of waiting, three of building.
>
> **The missing piece is a real URL that answers the contract today.**

- **The two teams work at the same time.** Before: the frontend waits for the
  backend. After: both build against the same contract from day one.
- **No throwaway code in the client.** Before: sample data is hard-coded in the
  app and has to be found and removed before release. After: the app calls the
  real URL from the start, and the switch-over happens at the gateway.
- **One shared answer.** Before: each developer runs a different local mock.
  After: developers, testers and demos all call the same host and get the same
  agreed response.

| Decision | This package's answer |
|---|---|
| Same answer for every id? | Yes. That is enough to build a screen. For per-caller answers, use [solution 12](../12-key-value-store/). |
| How does the frontend know it's a mock? | Every mocked answer carries an `x-mock-by` header. |
| What changes at release? | One deploy at the gateway. Nothing in the client. |

A mock doesn't check what it is sent and can't fail the way a real backend
does, so error handling still needs the real thing. [What the mock does and
doesn't do is in the architecture page](architecture.md#limits).

*Also searched as: mock API endpoint · API mocking · fake API for frontend ·
stub API before backend is ready · contract-first API development · mock server
at the API gateway · switch from mock to real backend · sample API responses.*
