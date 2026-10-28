# API reference — Request tracing

> [Overview](README.md) · [Business need](business-need.md) · [Architecture](architecture.md) · [Guides](guides.md) · [Agent prompt](helix-agent-prompt.md) · [Tests](tests.md) · **API reference**

---

The raw control-plane calls behind [Install it directly](guides.md#install-it-directly)
and `example/verify.sh`, listed for lookup rather than as a walkthrough. Every
call takes `authorization: Bearer <token>`. The full control-plane and plugin
documentation is at [docs.digitalapi.ai/api-gateway](https://docs.digitalapi.ai/api-gateway).

| Step | Call | Body | Notes |
|---|---|---|---|
| Import the spec | `POST /api/orgs/{orgId}/apis/from-spec` | `multipart/form-data`, part `file`, or a JSON body `{"spec": <document>}` | Response is `{"api", "revision"}`. Keep both ids. A raw `application/yaml` body is rejected with 415. |
| Create an upstream | `POST /api/orgs/{orgId}/envs/{envId}/upstreams` | `{"name","specification":{"scheme","pass_host":"rewrite","upstream_host","nodes":[{"host","port","weight"}]}}` | Upstreams are created **per environment**. Set `upstream_host` to the backend's own host name (`jsonplaceholder.typicode.com` for the sample). Without `pass_host` and `upstream_host`, the backend receives your gateway's host name and every call returns 502. |
| Bind it to the revision | `PATCH /api/orgs/{orgId}/apis/{apiId}/revisions/{revisionId}/upstream-bindings/add` | `{"environmentUpstreams":[{"environmentId","upstreamId"}]}` | Before the deploy. |
| Deploy the revision | `POST /api/orgs/{orgId}/apis/{apiId}/revisions/{revisionId}/deploy` | `{"environmentId","force":false}` | A session can only be opened on a deployed API. The UI uses `POST /api/orgs/{orgId}/apis/{apiId}/revisions/{revisionId}/envs/{envId}/deploy` instead; both work. |
| Start a session | `POST /api/orgs/{orgId}/apis/{apiId}/envs/{envId}/trace/sessions` | `{"ttl_seconds", "filter", "trace_vars", "trace_ctx_vars"}`, all optional | Returns `session_id`, `status`, `expires_at` (epoch seconds), `max_requests`, `requests_traced`, `filter`. If a session is already open on this API in this environment and isn't full, returns **that** one, unchanged. `ttl_seconds` above 3600 is `400`; a value below 60 is accepted (10 worked), although the UI allows only 60 to 3,600. A disallowed filter variable is `400` with its name, and so is an unknown operator. An unknown filter variable is accepted without error, and then nothing is recorded. |
| Read its records | `GET /api/orgs/{orgId}/trace/sessions/{sessionId}/traces?limit=100` | — | `limit` 1 to 1000; above 1000 is `400`. Returns `active`, `environment_id`, `traces[]`, `has_more`, `next_cursor_timestamp`, a date-and-time string such as `2026-10-22 11:36:05.154` (pass it back as `cursor_timestamp` for the next page). Each item's `raw_json` is the full record as a JSON string. Records arrive a few seconds after the request, so poll. |
| Read one record | `GET /api/orgs/{orgId}/trace/traces/{traceId}` | — | `trace_id`, `session_id`, `timestamp`, `raw_json`. |
| Stop it | `POST /api/orgs/{orgId}/apis/{apiId}/envs/{envId}/trace/sessions/{sessionId}/stop` | — | Returns `status: "disabled"`. Requests after this are not recorded. The `service_id` in this response is the gateway's own internal id, not the API id. |
| List sessions | `GET /api/orgs/{orgId}/trace/sessions` | — | Paged. Each has `session_id`, `api_id`, `api_name`, `created_by`, `expires_at`, `max_requests`, `disabled_at`, `filter`. **No `status` field**: a stopped session has `disabled_at` set. Here `expires_at` is a date-and-time string with no time zone, not epoch seconds as in the start response. |
| List one API's sessions | `GET /api/orgs/{orgId}/trace/apis/{apiId}/sessions` | — | Same shape. |

The session body's four fields (`ttl_seconds`, `filter`, `trace_vars`,
`trace_ctx_vars`) are described in
[Configuration reference](guides.md#configuration-reference).

Each record's `raw_json` holds these fields:

| Field | What it holds |
|---|---|
| `outcome` | `ok`, `short_circuit`, `client_error`, `server_error`, `upstream_error` or `plugin_error` |
| `short_circuit` | `{"plugin", "code", "phase"}` when a plugin answered the request itself, otherwise `null` |
| `anomalies[]` | `{"type", ...}` for each thing worth a look: a short circuit, an error status, a plugin that should have run and didn't |
| `request` | `method`, `uri`, `args`, `query_params`, `headers`, `body`, `body_size`, `body_truncated` |
| `phases[]` | `{"name", "duration_ms", "plugins": [{"name", "duration_ms", "changes": [...]}]}` in the order they ran. When a phase ran no plugins, `plugins` is an empty object `{}`, not an empty list `[]`. |
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
