# API reference — Request tracing

> [Overview](README.md) · [Business need](business-need.md) · [Architecture](architecture.md) · [Guides](guides.md) · [Agent prompt](helix-agent-prompt.md) · [Tests](tests.md) · **API reference**

---

The raw control-plane calls behind [Install it directly](guides.md#install-it-directly)
and `example/verify.sh`, listed for lookup rather than as a walkthrough. Every
call takes `authorization: Bearer <token>`. The full control-plane and plugin
documentation is at [docs.digitalapi.ai/api-gateway](https://docs.digitalapi.ai/api-gateway).

## Deploy the sample API

| Step | Call | Body | Notes |
|---|---|---|---|
| Import the spec | `POST /api/orgs/{orgId}/apis/from-spec` | `multipart/form-data`, part `file`, or a JSON body `{"spec": <document>}` | Response is `{"api", "revision"}`. Keep both ids. A raw `application/yaml` body is rejected with 415. |
| Create an upstream | `POST /orgs/{orgId}/envs/{envId}/upstreams` | `{"name","specification":{"scheme","nodes":[{"host","port","weight"}]}}` | No `/api` prefix on this one call. |
| Bind it to the revision | `PATCH /api/orgs/{orgId}/apis/{apiId}/revisions/{revisionId}/upstream-bindings/add` | `{"environmentUpstreams":[{"environmentId","upstreamId"}]}` | Before the deploy. |
| Deploy the revision | `POST /api/orgs/{orgId}/apis/{apiId}/revisions/{revisionId}/deploy` | `{"environmentId","force":false}` | A session can only be opened on a deployed API. |

## Trace sessions

| Step | Call | Body | Notes |
|---|---|---|---|
| Start a session | `POST /api/orgs/{orgId}/apis/{apiId}/envs/{envId}/trace/sessions` | `{"ttl_seconds", "filter", "trace_vars", "trace_ctx_vars"}`, all optional | Returns `session_id`, `status`, `expires_at` (epoch seconds), `max_requests`, `requests_traced`, `filter`. If a session is already open on this API in this environment, returns **that** one, unchanged. A disallowed filter variable is `400` with its name. |
| Read its records | `GET /api/orgs/{orgId}/trace/sessions/{sessionId}/traces?limit=100` | — | `limit` 1 to 1000. Returns `active`, `environment_id`, `traces[]`, `has_more`, `next_cursor_timestamp` (pass it back as `cursor_timestamp` for the next page). Each item's `raw_json` is the full record as a JSON string. Records arrive a few seconds after the request, so poll. |
| Read one record | `GET /api/orgs/{orgId}/trace/traces/{traceId}` | — | `trace_id`, `session_id`, `timestamp`, `raw_json`. |
| Stop it | `POST /api/orgs/{orgId}/apis/{apiId}/envs/{envId}/trace/sessions/{sessionId}/stop` | — | Returns `status: "disabled"`. Requests after this are not recorded. |
| List sessions | `GET /api/orgs/{orgId}/trace/sessions` | — | Paged. Each has `session_id`, `api_id`, `api_name`, `created_by`, `expires_at`, `max_requests`, `disabled_at`, `filter`. **No `status` field**: a stopped session has `disabled_at` set. |
| List one API's sessions | `GET /api/orgs/{orgId}/trace/apis/{apiId}/sessions` | — | Same shape. |

## Session body

| Field | Type | Default | Notes |
|---|---|---|---|
| `ttl_seconds` | integer | `300` | Up to 3,600. The UI allows 60 to 3,600. |
| `filter` | array of `[variable, operator, value]` | none | All conditions must match. Checked after the response, so `status` and `upstream_response_time` work. `route_id` and `service_id` are refused. |
| `trace_vars` | array of strings | the gateway's core set | Extra nginx variables. `upstream_*` and `http_*` wildcards work; `*` records everything. |
| `trace_ctx_vars` | array of strings | none | Plugin values, as `helix.<namespace>.<key>`. |

## Record fields worth knowing

Inside `raw_json`:

| Field | What it holds |
|---|---|
| `outcome` | `ok`, `short_circuit`, `client_error`, `server_error`, `upstream_error` or `plugin_error` |
| `short_circuit` | `{"plugin", "code", "phase"}` when a plugin answered the request itself, otherwise `null` |
| `anomalies[]` | `{"type", ...}` for each thing worth a look: a short circuit, an error status, a plugin that should have run and didn't |
| `request` | `method`, `uri`, `args`, `query_params`, `headers`, `body`, `body_size`, `body_truncated` |
| `phases[]` | `{"name", "duration_ms", "plugins": [{"name", "duration_ms", "changes": [...]}]}` in the order they ran |
| `upstream` | `upstream_host`, `addr`, `status`, `connect_time_ms`, `response_time_ms`. Absent fields mean the backend was never called. |
| `response` | `status`, `headers`, `body` (cut at the capture size), `body_size` |
| `duration_ms` | the whole request, end to end |

`jq` to summarise a session:

```bash
curl -s -H "authorization: Bearer $TOKEN" \
  "$CP/api/orgs/$ORG/trace/sessions/<SESSION_ID>/traces?limit=100" \
  | jq '.traces[].raw_json | fromjson | {method: .request.method, uri: .request.uri,
        status: .response.status, outcome, by: (.short_circuit.plugin // "backend"),
        backend_ms: .upstream.response_time_ms, total_ms: .duration_ms}'
```
