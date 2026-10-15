# Agent-mode prompt — authenticate gRPC streams at the gateway

Paste this to the Helix Agent as one message, replacing the `{{...}}` values.
Bring a gRPC service the gateway can reach, with server reflection enabled. The
method paths below are the example timing service's; replace them with your own
`/<package>.<Service>/<Method>` paths. Why the prompt is worded this way, what the
agent decides on its own, and what to check before you trust it are in the
[README](README.md#build-it-with-the-helix-agent).

## Prompt

```text
Step 1:
Create an API called "{{api_name}}" in the {{environment}} environment, in front of
our gRPC service at {{grpc_upstream_host}}:{{grpc_upstream_port}}. Route the
service's methods /timing.TimingUnit/Ping, /timing.TimingUnit/Status and
/timing.TimingUnit/Commands exactly as written, plus server reflection so clients
can discover the service.

Step 2:
Our units hold these streams open for hours. Update every route so a connection
is accepted only if it carries an app's API key.

Step 3:
Create a developer "{{developer_name}}", a corresponding product and an app to work
with the above API. Give me the app's API key.
```
