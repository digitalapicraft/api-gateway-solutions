# Plugin index

Every plugin these solutions configure, what each solution uses it *for*, and
a link to its field reference.

This page is generated from each solution's manifest and its OpenAPI document,
so it cannot claim a plugin a solution does not actually configure. It is an
index, not a reference — field-by-field documentation lives in the plugin
reference each row links to.

**16 of 106 plugins are covered by a solution.**

---

## Authentication

| Plugin | Used by | What it does there | Reference |
|---|---|---|---|
| `helix-auth` | [01-api-products](../solutions/01-api-products/) · [02-oauth-jwt](../solutions/02-oauth-jwt/) · [03-soap-to-rest](../solutions/03-soap-to-rest/) · [08-api-key](../solutions/08-api-key/) · [15-grpc-proxy](../solutions/15-grpc-proxy/) | Configured on this solution's routes · Verifies client_id and client_secret, then signs and returns the JWT · Verifies the signature and expiry of a token this gateway minted, in the… | [reference ↗](https://docs.digitalapi.ai/api-gateway/plugin-reference/plugins-authentication#helix-auth) |
| `hmac-auth` | [06-hmac-auth](../solutions/06-hmac-auth/) | Configured on this solution's routes | [reference ↗](https://docs.digitalapi.ai/api-gateway/plugin-reference/plugins-authentication#hmac-auth) |
| `openid-connect` | [05-okta-jwt](../solutions/05-okta-jwt/) | Configured on this solution's routes | [reference ↗](https://docs.digitalapi.ai/api-gateway/plugin-reference/plugins-authentication#openid-connect) |

## General

| Plugin | Used by | What it does there | Reference |
|---|---|---|---|
| `key-value-map` | [12-key-value-map](../solutions/12-key-value-map/) · [14-dynamic-mock](../solutions/14-dynamic-mock/) | Configured on this solution's routes | [reference ↗](https://docs.digitalapi.ai/api-gateway/plugin-reference/plugins-general#key-value-map) |
| `service-callout` | [11-service-callout](../solutions/11-service-callout/) | Configured on this solution's routes | [reference ↗](https://docs.digitalapi.ai/api-gateway/plugin-reference/plugins-general#service-callout) |

## Observability

| Plugin | Used by | What it does there | Reference |
|---|---|---|---|
| `kafka-logger` | [07-http-to-kafka](../solutions/07-http-to-kafka/) | Configured on this solution's routes | [reference ↗](https://docs.digitalapi.ai/api-gateway/plugin-reference/plugins-observability#kafka-logger) |

## Security

| Plugin | Used by | What it does there | Reference |
|---|---|---|---|
| `cors` | [01-api-products](../solutions/01-api-products/) · [02-oauth-jwt](../solutions/02-oauth-jwt/) · [03-soap-to-rest](../solutions/03-soap-to-rest/) · [05-okta-jwt](../solutions/05-okta-jwt/) · [09-xml-to-json](../solutions/09-xml-to-json/) · [14-dynamic-mock](../solutions/14-dynamic-mock/) | Configured on this solution's routes · Browser access. `authorization` must appear in allow_headers or the preflight rejects every authenticated call | [reference ↗](https://docs.digitalapi.ai/api-gateway/plugin-reference/plugins-security#cors) |
| `log-data-mask` | [10-data-mask](../solutions/10-data-mask/) | Configured on this solution's routes | [reference ↗](https://docs.digitalapi.ai/api-gateway/plugin-reference/plugins-security#log-data-mask) |

## Traffic

| Plugin | Used by | What it does there | Reference |
|---|---|---|---|
| `api-product-enforcer` | [01-api-products](../solutions/01-api-products/) | Configured on this solution's routes | [reference ↗](https://docs.digitalapi.ai/api-gateway/plugin-reference/plugins-traffic#api-product-enforcer) |
| `request-id` | [01-api-products](../solutions/01-api-products/) · [02-oauth-jwt](../solutions/02-oauth-jwt/) · [03-soap-to-rest](../solutions/03-soap-to-rest/) · [05-okta-jwt](../solutions/05-okta-jwt/) · [06-hmac-auth](../solutions/06-hmac-auth/) · [07-http-to-kafka](../solutions/07-http-to-kafka/) · [08-api-key](../solutions/08-api-key/) · [09-xml-to-json](../solutions/09-xml-to-json/) · [10-data-mask](../solutions/10-data-mask/) · [11-service-callout](../solutions/11-service-callout/) · [12-key-value-map](../solutions/12-key-value-map/) · [13-pgp-encryption](../solutions/13-pgp-encryption/) · [14-dynamic-mock](../solutions/14-dynamic-mock/) · [15-grpc-proxy](../solutions/15-grpc-proxy/) | Configured on this solution's routes · Correlates an auth failure with the backend call that followed it | [reference ↗](https://docs.digitalapi.ai/api-gateway/plugin-reference/plugins-traffic#request-id) |
| `request-validation` | [07-http-to-kafka](../solutions/07-http-to-kafka/) | Configured on this solution's routes | [reference ↗](https://docs.digitalapi.ai/api-gateway/plugin-reference/plugins-traffic#request-validation) |

## Transformation

| Plugin | Used by | What it does there | Reference |
|---|---|---|---|
| `mocking` | [07-http-to-kafka](../solutions/07-http-to-kafka/) · [14-dynamic-mock](../solutions/14-dynamic-mock/) | Configured on this solution's routes | [reference ↗](https://docs.digitalapi.ai/api-gateway/plugin-reference/plugins-transformation#mocking) |
| `pgp-crypto` | [12-key-value-map](../solutions/12-key-value-map/) · [13-pgp-encryption](../solutions/13-pgp-encryption/) | Configured on this solution's routes | [reference ↗](https://docs.digitalapi.ai/api-gateway/plugin-reference/plugins-transformation#pgp-crypto) |
| `proxy-rewrite` | [03-soap-to-rest](../solutions/03-soap-to-rest/) · [08-api-key](../solutions/08-api-key/) · [09-xml-to-json](../solutions/09-xml-to-json/) · [10-data-mask](../solutions/10-data-mask/) · [11-service-callout](../solutions/11-service-callout/) · [12-key-value-map](../solutions/12-key-value-map/) · [13-pgp-encryption](../solutions/13-pgp-encryption/) | Configured on this solution's routes | [reference ↗](https://docs.digitalapi.ai/api-gateway/plugin-reference/plugins-transformation#proxy-rewrite) |
| `response-rewrite` | [10-data-mask](../solutions/10-data-mask/) | Configured on this solution's routes | [reference ↗](https://docs.digitalapi.ai/api-gateway/plugin-reference/plugins-transformation#response-rewrite) |
| `xml-to-json` | [03-soap-to-rest](../solutions/03-soap-to-rest/) · [09-xml-to-json](../solutions/09-xml-to-json/) | Configured on this solution's routes | [reference ↗](https://docs.digitalapi.ai/api-gateway/plugin-reference/plugins-transformation#xml-to-json) |

---

## Not yet covered by a solution

90 plugins exist that no solution here uses yet. This is the backlog, stated
honestly rather than hidden.

<details>
<summary>Show all 90</summary>


**AI** — [`ai-aliyun-content-moderation`](https://docs.digitalapi.ai/api-gateway/plugin-reference/plugins-ai#ai-aliyun-content-moderation), [`ai-aws-content-moderation`](https://docs.digitalapi.ai/api-gateway/plugin-reference/plugins-ai#ai-aws-content-moderation), [`ai-prompt-decorator`](https://docs.digitalapi.ai/api-gateway/plugin-reference/plugins-ai#ai-prompt-decorator), [`ai-prompt-guard`](https://docs.digitalapi.ai/api-gateway/plugin-reference/plugins-ai#ai-prompt-guard), [`ai-prompt-template`](https://docs.digitalapi.ai/api-gateway/plugin-reference/plugins-ai#ai-prompt-template), [`ai-proxy`](https://docs.digitalapi.ai/api-gateway/plugin-reference/plugins-ai#ai-proxy), [`ai-proxy-multi`](https://docs.digitalapi.ai/api-gateway/plugin-reference/plugins-ai#ai-proxy-multi), [`ai-rag`](https://docs.digitalapi.ai/api-gateway/plugin-reference/plugins-ai#ai-rag), [`ai-rate-limiting`](https://docs.digitalapi.ai/api-gateway/plugin-reference/plugins-ai#ai-rate-limiting), [`ai-request-rewrite`](https://docs.digitalapi.ai/api-gateway/plugin-reference/plugins-ai#ai-request-rewrite)

**Authentication** — [`authz-casbin`](https://docs.digitalapi.ai/api-gateway/plugin-reference/plugins-authentication#authz-casbin), [`authz-casdoor`](https://docs.digitalapi.ai/api-gateway/plugin-reference/plugins-authentication#authz-casdoor), [`authz-keycloak`](https://docs.digitalapi.ai/api-gateway/plugin-reference/plugins-authentication#authz-keycloak), [`basic-auth`](https://docs.digitalapi.ai/api-gateway/plugin-reference/plugins-authentication#basic-auth), [`cas-auth`](https://docs.digitalapi.ai/api-gateway/plugin-reference/plugins-authentication#cas-auth), [`forward-auth`](https://docs.digitalapi.ai/api-gateway/plugin-reference/plugins-authentication#forward-auth), [`jwe-decrypt`](https://docs.digitalapi.ai/api-gateway/plugin-reference/plugins-authentication#jwe-decrypt), [`jwt-auth`](https://docs.digitalapi.ai/api-gateway/plugin-reference/plugins-authentication#jwt-auth), [`key-auth`](https://docs.digitalapi.ai/api-gateway/plugin-reference/plugins-authentication#key-auth), [`ldap-auth`](https://docs.digitalapi.ai/api-gateway/plugin-reference/plugins-authentication#ldap-auth), [`multi-auth`](https://docs.digitalapi.ai/api-gateway/plugin-reference/plugins-authentication#multi-auth), [`opa`](https://docs.digitalapi.ai/api-gateway/plugin-reference/plugins-authentication#opa), [`wolf-rbac`](https://docs.digitalapi.ai/api-gateway/plugin-reference/plugins-authentication#wolf-rbac)

**General** — [`echo`](https://docs.digitalapi.ai/api-gateway/plugin-reference/plugins-general#echo), [`ext-plugin-post-req`](https://docs.digitalapi.ai/api-gateway/plugin-reference/plugins-general#ext-plugin-post-req), [`ext-plugin-post-resp`](https://docs.digitalapi.ai/api-gateway/plugin-reference/plugins-general#ext-plugin-post-resp), [`ext-plugin-pre-req`](https://docs.digitalapi.ai/api-gateway/plugin-reference/plugins-general#ext-plugin-pre-req), [`gzip`](https://docs.digitalapi.ai/api-gateway/plugin-reference/plugins-general#gzip), [`inspect`](https://docs.digitalapi.ai/api-gateway/plugin-reference/plugins-general#inspect), [`real-ip`](https://docs.digitalapi.ai/api-gateway/plugin-reference/plugins-general#real-ip), [`redirect`](https://docs.digitalapi.ai/api-gateway/plugin-reference/plugins-general#redirect), [`request-chain`](https://docs.digitalapi.ai/api-gateway/plugin-reference/plugins-general#request-chain)

**Miscellaneous** — [`ai`](https://docs.digitalapi.ai/api-gateway/plugin-reference/plugins-miscellaneous#ai), [`example-plugin`](https://docs.digitalapi.ai/api-gateway/plugin-reference/plugins-miscellaneous#example-plugin), [`mcp-bridge`](https://docs.digitalapi.ai/api-gateway/plugin-reference/plugins-miscellaneous#mcp-bridge), [`serverless-post-function`](https://docs.digitalapi.ai/api-gateway/plugin-reference/plugins-miscellaneous#serverless-post-function), [`serverless-pre-function`](https://docs.digitalapi.ai/api-gateway/plugin-reference/plugins-miscellaneous#serverless-pre-function)

**Observability** — [`clickhouse-logger`](https://docs.digitalapi.ai/api-gateway/plugin-reference/plugins-observability#clickhouse-logger), [`datadog`](https://docs.digitalapi.ai/api-gateway/plugin-reference/plugins-observability#datadog), [`elasticsearch-logger`](https://docs.digitalapi.ai/api-gateway/plugin-reference/plugins-observability#elasticsearch-logger), [`file-logger`](https://docs.digitalapi.ai/api-gateway/plugin-reference/plugins-observability#file-logger), [`google-cloud-logging`](https://docs.digitalapi.ai/api-gateway/plugin-reference/plugins-observability#google-cloud-logging), [`helix-analytics`](https://docs.digitalapi.ai/api-gateway/plugin-reference/plugins-observability#helix-analytics), [`http-logger`](https://docs.digitalapi.ai/api-gateway/plugin-reference/plugins-observability#http-logger), [`lago`](https://docs.digitalapi.ai/api-gateway/plugin-reference/plugins-observability#lago), [`loggly`](https://docs.digitalapi.ai/api-gateway/plugin-reference/plugins-observability#loggly), [`loki-logger`](https://docs.digitalapi.ai/api-gateway/plugin-reference/plugins-observability#loki-logger), [`prometheus`](https://docs.digitalapi.ai/api-gateway/plugin-reference/plugins-observability#prometheus), [`rocketmq-logger`](https://docs.digitalapi.ai/api-gateway/plugin-reference/plugins-observability#rocketmq-logger), [`skywalking-logger`](https://docs.digitalapi.ai/api-gateway/plugin-reference/plugins-observability#skywalking-logger), [`sls-logger`](https://docs.digitalapi.ai/api-gateway/plugin-reference/plugins-observability#sls-logger), [`splunk-hec-logging`](https://docs.digitalapi.ai/api-gateway/plugin-reference/plugins-observability#splunk-hec-logging), [`syslog`](https://docs.digitalapi.ai/api-gateway/plugin-reference/plugins-observability#syslog), [`tcp-logger`](https://docs.digitalapi.ai/api-gateway/plugin-reference/plugins-observability#tcp-logger), [`tencent-cloud-cls`](https://docs.digitalapi.ai/api-gateway/plugin-reference/plugins-observability#tencent-cloud-cls), [`udp-logger`](https://docs.digitalapi.ai/api-gateway/plugin-reference/plugins-observability#udp-logger), [`zipkin`](https://docs.digitalapi.ai/api-gateway/plugin-reference/plugins-observability#zipkin)

**Other protocols** — [`http-dubbo`](https://docs.digitalapi.ai/api-gateway/plugin-reference/plugins-other-protocols#http-dubbo), [`kafka-proxy`](https://docs.digitalapi.ai/api-gateway/plugin-reference/plugins-other-protocols#kafka-proxy)

**Security** — [`chaitin-waf`](https://docs.digitalapi.ai/api-gateway/plugin-reference/plugins-security#chaitin-waf), [`consumer-restriction`](https://docs.digitalapi.ai/api-gateway/plugin-reference/plugins-security#consumer-restriction), [`csrf`](https://docs.digitalapi.ai/api-gateway/plugin-reference/plugins-security#csrf), [`ip-restriction`](https://docs.digitalapi.ai/api-gateway/plugin-reference/plugins-security#ip-restriction), [`public-api`](https://docs.digitalapi.ai/api-gateway/plugin-reference/plugins-security#public-api), [`referer-restriction`](https://docs.digitalapi.ai/api-gateway/plugin-reference/plugins-security#referer-restriction), [`ua-restriction`](https://docs.digitalapi.ai/api-gateway/plugin-reference/plugins-security#ua-restriction), [`uri-blocker`](https://docs.digitalapi.ai/api-gateway/plugin-reference/plugins-security#uri-blocker)

**Serverless** — [`aws-lambda`](https://docs.digitalapi.ai/api-gateway/plugin-reference/plugins-serverless#aws-lambda), [`azure-functions`](https://docs.digitalapi.ai/api-gateway/plugin-reference/plugins-serverless#azure-functions), [`lua-callout`](https://docs.digitalapi.ai/api-gateway/plugin-reference/plugins-serverless#lua-callout), [`openfunction`](https://docs.digitalapi.ai/api-gateway/plugin-reference/plugins-serverless#openfunction), [`openwhisk`](https://docs.digitalapi.ai/api-gateway/plugin-reference/plugins-serverless#openwhisk)

**Traffic** — [`api-breaker`](https://docs.digitalapi.ai/api-gateway/plugin-reference/plugins-traffic#api-breaker), [`client-control`](https://docs.digitalapi.ai/api-gateway/plugin-reference/plugins-traffic#client-control), [`limit-conn`](https://docs.digitalapi.ai/api-gateway/plugin-reference/plugins-traffic#limit-conn), [`limit-count`](https://docs.digitalapi.ai/api-gateway/plugin-reference/plugins-traffic#limit-count), [`limit-req`](https://docs.digitalapi.ai/api-gateway/plugin-reference/plugins-traffic#limit-req), [`proxy-cache`](https://docs.digitalapi.ai/api-gateway/plugin-reference/plugins-traffic#proxy-cache), [`proxy-control`](https://docs.digitalapi.ai/api-gateway/plugin-reference/plugins-traffic#proxy-control), [`proxy-mirror`](https://docs.digitalapi.ai/api-gateway/plugin-reference/plugins-traffic#proxy-mirror), [`traffic-split`](https://docs.digitalapi.ai/api-gateway/plugin-reference/plugins-traffic#traffic-split), [`workflow`](https://docs.digitalapi.ai/api-gateway/plugin-reference/plugins-traffic#workflow)

**Transformation** — [`attach-consumer-label`](https://docs.digitalapi.ai/api-gateway/plugin-reference/plugins-transformation#attach-consumer-label), [`body-transformer`](https://docs.digitalapi.ai/api-gateway/plugin-reference/plugins-transformation#body-transformer), [`degraphql`](https://docs.digitalapi.ai/api-gateway/plugin-reference/plugins-transformation#degraphql), [`fault-injection`](https://docs.digitalapi.ai/api-gateway/plugin-reference/plugins-transformation#fault-injection), [`grpc-transcode`](https://docs.digitalapi.ai/api-gateway/plugin-reference/plugins-transformation#grpc-transcode), [`grpc-web`](https://docs.digitalapi.ai/api-gateway/plugin-reference/plugins-transformation#grpc-web), [`json-to-xml`](https://docs.digitalapi.ai/api-gateway/plugin-reference/plugins-transformation#json-to-xml), [`jsonp-wrapper`](https://docs.digitalapi.ai/api-gateway/plugin-reference/plugins-transformation#jsonp-wrapper)

</details>
