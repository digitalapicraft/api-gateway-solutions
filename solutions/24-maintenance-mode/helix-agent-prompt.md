# Agent-mode prompt — a maintenance switch for an API

> [Overview](README.md) · [Business need](business-need.md) · [Architecture](architecture.md) · [Guides](guides.md) · **Agent prompt** · [Tests](tests.md) · [API reference](api-reference.md)

---

Replace the `{{...}}` values, then send each step to the Helix Agent as its own
message, at its own time: step 1 whenever you like, step 2 when the maintenance
window starts, step 3 when it ends. The agent asks you to confirm each deploy.
After steps 1 and 2, read the deployed revision back and check that
`/bookings/:bookingId` was stored with a colon, not braces. See
[Troubleshooting](guides.md#troubleshooting) if something looks off.

## Prompt

```text
Step 1:
Create a REST API called "{{api_name}}" in the {{environment}} environment, proxying
https://jsonplaceholder.typicode.com. Callers use three routes: GET /bookings,
GET /bookings/:bookingId and POST /bookings. The backend calls bookings "posts",
so /bookings must reach /posts and /bookings/:bookingId must reach
/posts/:bookingId. Put a request id on every response. Deploy it.

Step 2:
We are taking the bookings backend down for maintenance until {{maintenance_end}}.
Put the "{{api_name}}" API in the {{environment}} environment into maintenance mode
until then. Do it in a new revision and deploy that, and leave the revision that is
live now unchanged, so switching back is just deploying it again. In maintenance
mode every call to the API gets a 503 from the gateway and the backend is not
called. The 503 carries a Retry-After header with that end time as a date, not a
number of seconds, and a short JSON body saying the service is down for planned
maintenance and when to try again.

Step 3:
Maintenance is over. Switch the "{{api_name}}" API in the {{environment}}
environment back to the revision it was running before maintenance mode.
```
