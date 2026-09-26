# Prerequisites

What you need in place before building any solution in this library.

---

- A provisioned gateway, with an organisation and at least one environment you can deploy to.
- The API you want to protect, reachable from the gateway.
- Access to Helix **Agent Mode**, if you're building the recommended way.
- `curl` for `verify.sh`; `jq` is optional but makes failures easier to read.
- **Confirm each plugin exists in your org before using it** — ask the agent
  `get_plugin_config` for it, or check the control plane's plugin-schema
  endpoint. Builds vary, and a plugin that isn't there fails at deploy time with
  an unhelpful message.
