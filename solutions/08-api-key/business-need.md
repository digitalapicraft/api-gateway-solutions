# API keys for callers that can't run a token exchange

> [Overview](README.md) · **Business need** · [Architecture](architecture.md) · [Guides](guides.md) · [Agent prompt](helix-agent-prompt.md) · [Tests](tests.md) · [API reference](api-reference.md)

---

> Four thousand terminals call an endpoint whose only protection is that its URL
> isn't published. When one is stolen, nobody can tell whether it is still
> calling, and the only way to stop it is to change the URL for all of them.
>
> **Revoking one caller should be a control-plane action, not a deployment.**

- **"Which caller?" gets an answer.** Every request is tied to one app before the
  backend sees it, so incidents start with a name, not a research project.
- **One caller can be switched off without affecting the rest.** Delete or
  rotate that app; its next request is refused. No config change, no redeploy,
  nothing shipped to the device.
- **No backend change**, and it creates the per-app identity that quotas and
  analytics need.

The decision is set by what the caller can do:

| Your caller | Use |
|---|---|
| Can set a header, nothing more: a device, old middleware, a scheduled job | An API key — this solution |
| Can keep a secret and run a token exchange | A token — [solution 02](../02-oauth-jwt/) |
| Already gets tokens from your identity provider | [Solution 05](../05-okta-jwt/) |
| Can keep a secret, and the body's integrity matters | Signed requests — [solution 06](../06-hmac-auth/) |

The trade: the key never expires and travels on every request, so anyone who
sees a request can reuse it. Fast switch-off is what pays for that. No savings
figures are claimed: the benefits describe how the system works, not measured
results. More in [Architecture](architecture.md#when-to-use-this).

*Also searched as: API key authentication · device API key · revoke an API key ·
per-client API key · IoT device authentication · API key in header · machine to
machine API key.*
