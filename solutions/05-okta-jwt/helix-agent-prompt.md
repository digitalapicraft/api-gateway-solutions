# Agent-mode prompt — verify Okta-issued tokens at the gateway

Paste this to the Helix Agent as one message, replacing the `{{...}}` values.
Bring an Okta authorization server's discovery URL and the client id and secret
of an Okta application. Why it is worded this way and what to check before you
trust it are in the [README](README.md#build-it-with-the-helix-agent).

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
