# API keys for callers that can't swap a secret for a token

> [Overview](README.md) · **Business need** · [Architecture](architecture.md) · [Guides](guides.md) · [Agent prompt](helix-agent-prompt.md) · [Tests](tests.md) · [API reference](api-reference.md)

---

> Four thousand card terminals call an endpoint protected only by an
> unpublished address. When one is stolen, nobody can tell whether it is still
> calling. Stopping it means changing the address for all of them.
>
> **Switching off one caller should take a few clicks, not a new release.**

- **You can tell which caller sent a request.** Every request is tied to one app
  before your backend sees it. A problem starts with a name, not a search.
- **One caller can be switched off on its own.** Before: stopping one device meant
  changing the address for every device. After: delete that app, or give it a new
  key, and its next request is refused. No configuration change, no new deploy,
  nothing sent to the device.
- **No backend change.** And each app gets its own identity, which usage limits
  and reports need.

The right choice depends on what the caller can do:

| Your caller | Use |
|---|---|
| Can set a header (one extra named value on the request), nothing more: a device, older software that links two systems, a scheduled job | An API key — this solution |
| Can keep a secret and swap it for a short-lived token | A token — [solution 02](../02-oauth-jwt/) |
| Already gets tokens from your identity provider | [Solution 05](../05-okta-jwt/) |
| Can keep a secret, and you need proof the request body wasn't changed | Signed requests — [solution 06](../06-hmac-auth/) |

The cost: the key never expires and is sent with every request, so anyone who
sees a request can reuse it. Quick switch-off is what makes that acceptable. More in [Architecture](architecture.md#when-to-use-this).

*Also searched as: API key authentication · device API key · revoke an API key ·
per-client API key · IoT device authentication · API key in header · machine to
machine API key.*
