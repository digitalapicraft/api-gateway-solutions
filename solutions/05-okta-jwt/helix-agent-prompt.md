# Agent-mode prompt — verify Okta-issued tokens at the gateway

> [Overview](README.md) · [Business need](business-need.md) · [Architecture](architecture.md) · [Guides](guides.md) · **Agent prompt** · [Tests](tests.md) · [API reference](api-reference.md)

---

Paste this to the Helix Agent as one message, replacing the `{{...}}` values. You
need an org that includes the `openid-connect` plugin, an Okta authorization
server's discovery URL, and the client id and secret of an Okta application.

**If the run ends early, paste the two steps one at a time instead.** When it
finishes, read the deployed revision back and check that `openid-connect` carries
`bearer_only: true` and your real client id and secret, not placeholders. Then
check for `use_jwks: true`: the agent often leaves it out, and without it every
token is refused, so add it yourself if it is missing. See
[Troubleshooting](guides.md#troubleshooting) if something looks off.

## Prompt

```text
Step 1:
Create a REST API called "{{api_name}}" in the "{{environment}}" environment, proxying
https://jsonplaceholder.typicode.com. Two routes — GET /albums and POST /albums — passed straight through to the upstream.

Step 2:
Update the API so every route accepts only access tokens issued by our Okta
authorization server, whose discovery document is {{okta_discovery_url}}. The
gateway verifies these tokens and never issues any — there is no token endpoint
here. The Okta application is {{okta_client_id}}, secret {{okta_client_secret}},
use the literal values for the configuration.

Refuse a call without a valid token with a 401, never redirect it to a login page.
Accept tokens only from the issuer that discovery document reports, signed with RS256,
and verify Okta's certificate when fetching its keys. Verify each token locally against Okta's published jwks.
```
