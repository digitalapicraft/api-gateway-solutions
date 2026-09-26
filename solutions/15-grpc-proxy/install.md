# Install — Solution 15 — A bidirectional gRPC stream, authenticated at the edge

[Overview](readme.md) · [Business need](business-need.md) · [How it works](how-it-works.md) · **Install** · [Configuration](configuration.md) · [Test & verify](testing.md) · [Changelog](changelog.md)

---

## Build it with the Helix Agent

```text
Create an upstream in my environment called "timing-grpc" whose specification has
scheme "grpc", type "roundrobin", pass_host "node", and one node with host
<<GRPC_UPSTREAM_HOST>> and port <<GRPC_UPSTREAM_PORT>>. Tell me its id.
```

```text
Create an API called "Timing Unit Stream API". Don't add routes or plugins yet —
just create it and tell me its id.
```

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

```text
Bind upstream <<UPSTREAM_ID>> to the current revision of the Timing Unit Stream
API in my environment, then deploy that revision. Then read the revision back and
show me the plugins stored on each route.
```

The read-back is not optional — three of the four known agent-mode defects report
success at every step the agent shows you.

## Step 1 — the upstream (this is not in the spec)

```text
Create an upstream in my environment called "timing-grpc" whose specification has
scheme "grpc", type "roundrobin", pass_host "node", and one node with host
<<GRPC_UPSTREAM_HOST>>, port <<GRPC_UPSTREAM_PORT>>, weight 1 and priority 1.
Tell me the upstream id when it is created.

The scheme must be exactly "grpc" — not "http", not "https". That field is the
only thing that makes this a gRPC proxy.
```

## Step 2 — the API

```text
Create an API called "Timing Unit Stream API" in my organisation. Don't add any
routes or plugins yet — just create the API and tell me its id.
```

## Step 3 — one route at a time

```text
On the Timing Unit Stream API, add a route POST /timing.TimingUnit/Ping with
exactly one plugin, and keep the plugin-name level explicit — a "plugins" object
whose key is "helix-auth":

helix-auth:
  mode: validate
  validate_auth_type: key-auth
  apikey:
    source: header
    key: X-Unit-Key

The path is a gRPC method path. It contains a dot and a slash on purpose — do not
normalise it, do not strip the dot, do not URL-encode it, and do not add a
leading segment. The method must be POST.
```

Repeat for each streaming method, one step each.

Then the two reflection routes, so clients can discover the schema:

```text
On the same API, add two more POST routes, each with the same single
"helix-auth" plugin block as above:

  /grpc.reflection.v1.ServerReflection/ServerReflectionInfo
  /grpc.reflection.v1alpha.ServerReflection/ServerReflectionInfo

Both are needed. A client tries v1 first and falls back to v1alpha only if the
v1 call gets a clean gRPC answer.
```

## Step 4 — bind, deploy, and read it back

```text
Bind upstream <<UPSTREAM_ID>> to the current revision of the Timing Unit Stream
API in my environment, then deploy that revision. Then read the revision back and
show me the plugins stored on each route, and the upstream binding.
```

**Not optional.** Three of the four known agent-mode defects report success at
every step the agent shows you.

---

## Why it's shaped this way

| Choice | Reason |
|---|---|
| **The upstream is its own step, first** | It is the only place the gRPC-ness exists. An agent asked to "create a gRPC API" will happily produce routes with an HTTP upstream, and the result fails as though the backend were broken. |
| **"the scheme must be exactly grpc"** | `http`/`https` are the values every other solution uses, and are what an agent defaults to. |
| **"do not normalise the path"** | `/timing.TimingUnit/Ping` looks like a typo to a model trained on REST paths. An agent that "tidies" it to `/timing/TimingUnit/Ping` produces a route that never matches. |
| **One route per step** | A prompt carrying several routes and plugin blocks reaches the nesting depth that triggers the `update_route_spec` delimiter defect, which surfaces as `stream closed with reason: error` and writes nothing. |
| **"keep the plugin-name level explicit"** | The agent can drop that level and promote a plugin's fields into the `plugins` map; the route then deploys carrying plugins that do not exist. |
| **Ask for `dry_run_deploy`, never `validate_route`** | `validate_route` always fails on this build — the tool posts `{"route": …}` where the endpoint requires `{"routeSpec": [ … ]}`. |

## Tweak knobs

- **Paths** — replace `timing.TimingUnit` with your own package and service. They
  must match the wire paths exactly.
- **Key header** — `X-Unit-Key` is arbitrary; any header works, and it travels as
  gRPC metadata.
- **TLS upstream** — use `grpcs` and your backend's TLS port on the upstream
  object; everything else in the package is unchanged.

## When it goes wrong

| Symptom | Cause |
|---|---|
| Every call 502s | The upstream scheme is `http`, or it was changed without an undeploy/deploy cycle. A scheme edit does not reach a deployed revision. |
| Route never matches | The gRPC method path was normalised. Restore the dot and the single slash. |
| `Unauthenticated` with a content-type complaint | Working as designed — a gateway 401 is not a valid gRPC response. Check the HTTP status directly. |
| Client cannot discover the service | Reflection is not proxied unless you route it. Ship a proto or protoset. |
| A client cannot discover the service | Route **both** reflection versions. v1alpha alone leaves the v1 attempt on no route, and the client stops rather than falling back. |
| Stream breaks as soon as it carries data | A body-touching plugin is on the route. Remove it. |
