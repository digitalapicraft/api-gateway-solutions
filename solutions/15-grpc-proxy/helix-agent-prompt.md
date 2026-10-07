# Agent-mode prompt — front a gRPC stream with the gateway

> [Overview](README.md) · [Business need](business-need.md) · [Architecture](architecture.md) · [Guides](guides.md) · **Agent prompt** · [Tests](tests.md) · [API reference](api-reference.md)

---

Paste each step to the Helix Agent as its own message, in order, replacing the
`{{...}}` values: `{{grpc_upstream_host}}` and `{{grpc_upstream_port}}` are your
gRPC backend's address, and `{{upstream_id}}` is the id the agent gives you in
Step 1.

The read-back in Step 4 is not optional: three of the four known agent-mode
defects report success at every step the agent shows you. These steps route
`Ping` only; [Guides](guides.md#build-it-with-the-helix-agent) covers the
streaming methods and the reflection routes, and
[Troubleshooting](guides.md#troubleshooting) what to do if something looks off.

## Prompt

### Step 1 — the upstream (this is not in the spec)

```text
Create an upstream in my environment called "timing-grpc" whose specification has
scheme "grpc", type "roundrobin", pass_host "node", and one node with host
{{grpc_upstream_host}} and port {{grpc_upstream_port}}. Tell me its id.
```

### Step 2 — the API

```text
Create an API called "Timing Unit Stream API". Don't add routes or plugins yet —
just create it and tell me its id.
```

### Step 3 — the Ping route

```text
On the Timing Unit Stream API, add a route POST /timing.TimingUnit/Ping with
exactly one plugin, keeping the plugin-name level explicit — a "plugins" object
whose key is "helix-auth":

helix-auth:
  mode: validate
  validate_auth_type: key-auth
  apikey:
    source: header
    key: X-Unit-Key

The path contains a dot and a slash and is the gRPC method path — do not
normalise it, do not strip the dot, and do not add a leading segment.
```

### Step 4 — bind, deploy, and read it back

```text
Bind upstream {{upstream_id}} to the current revision of the Timing Unit Stream
API in my environment, then deploy that revision. Then read the revision back and
show me the plugins stored on each route.
```
