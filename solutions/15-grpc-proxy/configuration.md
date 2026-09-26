# Configuration — Solution 15 — A bidirectional gRPC stream, authenticated at the edge

[Overview](readme.md) · [Business need](business-need.md) · [How it works](how-it-works.md) · [Install](install.md) · **Configuration** · [Test & verify](testing.md) · [Changelog](changelog.md)

---

## The upstream is not in the spec

This package is shaped differently from every other one in the library, and it is
worth saying plainly: **`gateway/api-spec.yaml` is only half the configuration.**

OpenAPI has no way to express "this upstream speaks gRPC". That lives on the
upstream object in the control plane:

```bash
POST /api/orgs/{orgId}/envs/{envId}/upstreams
{
  "name": "timing-grpc",
  "specification": {
    "scheme": "grpc",                       # grpcs for a TLS backend
    "type": "roundrobin",
    "pass_host": "node",
    "nodes": [{"host": "<GRPC_UPSTREAM_HOST>", "port": <GRPC_UPSTREAM_PORT>,
               "weight": 1, "priority": 1}]
  }
}
```

Then bind that upstream to the revision and deploy. Import the document on its
own and you get routes that proxy over HTTP to a gRPC port, which fails in a way
that looks like a backend problem.

**A scheme change does not propagate to a deployed revision.** Editing the
upstream and redeploying is not enough — you must **undeploy and deploy again**.
Nothing warns you; the route simply keeps its old behaviour.

## Route paths are gRPC method paths

```yaml
paths:
  /timing.TimingUnit/Ping:      # /<package>.<Service>/<Method>
    post:                        # always POST
```

Not a convention — that is literally what a gRPC client puts on the wire.

Note that the gateway does **not** proxy the gRPC reflection service unless you
route it. Clients talking to the gateway cannot discover your schema, so ship
them a proto or a protoset.
