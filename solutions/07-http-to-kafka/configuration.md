# Configuration — Solution 07 — HTTP to Kafka: accept events at the edge, publish them without an ingest service

[Overview](readme.md) · [Business need](business-need.md) · [How it works](how-it-works.md) · [Install](install.md) · **Configuration** · [Test & verify](testing.md) · [Changelog](changelog.md)

---

## Adding authentication

**The route as shipped is unauthenticated.** That is deliberate — it is the
smallest thing that demonstrates the mechanism — and it is not what you should
run. Anyone who learns the URL can put anything on your topic.

Close it with **[solution 06](../06-hmac-auth/)**, and note what it costs:

> `hmac-auth`'s `validate_request_body` and `request-validation` **cannot share a
> route.** `request-validation` re-encodes the parsed JSON with `set_body_data`
> (deliberately, against parser-differential attacks) before `hmac-auth` hashes
> it, so the client's `Digest` and the gateway's disagree on key order and
> whitespace. Symptom: a bare 401 with `Invalid digest` in the log.

So when you add signing, **drop `request-validation`**. You trade edge schema
validation for body integrity; validate the shape in your consumer, where an
invalid event is a poison-message problem you have to handle anyway. The
published event stays complete either way — that was tested.

If you only need to know *who* is calling and do not need the signature to cover
the body, `helix-auth` in `validate` mode is the lighter option and does not
touch the body at all — then `request-validation` can stay.

## Configuration

| Field | Value here | Why |
|---|---|---|
| `producer_type` | `sync` | A real broker round trip, so a rejection is logged rather than vanishing into a ring buffer. Also removes the async producer's 1-second linger |
| `required_acks` | `-1` | All in-sync replicas. The default is `1` — leader only — which loses the event if the leader fails before replicating |
| `max_retry_count` | `3` | The default is **0**: a failed batch is dropped, not retried |
| `batch_max_size` | `1` | Publish per event rather than per batch. Costs ordering — see Limitations |
| `_meta.filter` | `status == 202` | Without it, a 400 is published too, and rejected events reach the topic by the back door |
| `with_mock_header` | `false` | Defaults to **true**, stamping every response with a header naming the mocking plugin and the gateway version |
