# Your API needs OAuth. Your backend team has a roadmap through Q3.

There's a conversation that happens in every company with a partner API, and it
goes the same way every time.

Someone points out that the partner API authenticates with a static key that was
emailed to eleven integrators at various points since 2019. Everyone agrees this
is bad. Someone estimates the fix: authentication is cross-cutting, so it touches
every request handler in a service that ships quarterly, and every existing
integrator needs migrating. Six weeks of engineering, minimum, plus change
management.

The roadmap is full. It goes on the risk register.

Two years later the register entry has a small note appended to it.

## The mistake is in the estimate

The six weeks isn't wrong. Threading authentication through a mature service
really does cost that, and the team giving the number isn't sandbagging.

The mistake is earlier: **authentication was treated as application logic.**

Ask what verifying a caller's identity actually requires. It needs to check a
credential against a store, decide yes or no, and reject before anything
expensive happens. It does not need to know what an order is. It does not touch
your domain model, your database schema, or a single business rule.

So why is it in the code that owns all of those things?

Because that's where the request arrives — historically. But it isn't any more. If
there's an API gateway between your partners and your service, the request arrives
*there* first, and that's a place where "check the credential, reject if bad" is a
configuration decision rather than a release.

## What we're building

An OAuth 2.0 client-credentials flow where the gateway does both halves:

- **Issues tokens.** A partner sends their client id and secret to
  `POST /oauth/token` and gets back a JWT that expires in fifteen minutes.
- **Verifies them.** Every other route requires that token, checks the signature,
  checks the expiry, and rejects anything else before your service is contacted.

The backend service is not modified. It doesn't know any of this happened.

Here's the whole thing, in the two blocks that matter.

On the token endpoint:

```yaml
helix-auth:
  mode: generate
  token_ttl: 900
  signing_secret: "<YOUR_JWT_SIGNING_SECRET>"
```

On every protected route:

```yaml
helix-auth:
  mode: validate
  validate_auth_type: jwt-auth
  signing_secret: "<YOUR_JWT_SIGNING_SECRET>"
```

That's it. `generate` mode looks up the app by its client id, verifies the secret,
and signs a JWT. `validate` mode verifies the signature with the same secret and
rejects everything that fails, in the access phase — before your upstream is
touched at all.

The full document, with the routes and the correlation id and the CORS block, is
in the [solution package](./gateway/api-spec.yaml).

## Actually, don't write that YAML

I showed you the config because you should know what the solution *is*. But
writing it by hand is not the recommended path, and it's not how this was built.

You describe the outcome:

```text
Add OAuth 2.0 client-credentials authentication to my Orders API.

Add an endpoint POST /oauth/token that verifies an app's client id and secret and
issues a signed JWT access token, with a 15-minute lifetime.

Protect every other endpoint so it requires a valid Bearer token issued by that
endpoint, and rejects anything else before it reaches the upstream.

The gateway is the token issuer here, so use helix-auth in generate mode for the
token endpoint and validate mode with jwt-auth for the protected routes — not the
jwt-auth plugin on its own, which is for an external issuer.

Both must reference the same signing secret via the JWT_SIGNING_SECRET
environment variable. Never write the secret into the spec.

Show me the spec, run validate_route and dry_run_deploy, and wait for me to
confirm before deploying.
```

The Helix Agent finds the API, reads the *real* plugin schema from your
organisation rather than pattern-matching one from memory, proposes the
specification, and stops. You read it. You say go. It validates, dry-runs, and
deploys.

Then:

```text
Create a developer "Partner Integrations" with an app subscribed to this API, and
give me the client id and secret so I can test the token exchange.
```

And you have a working credentials flow with something to test it with.

Two details in that prompt are doing more work than they look like they are, and
they're worth understanding because they're the two ways this goes wrong.

## Wrong turn one: which plugin issues a token

If you ask a general-purpose model to "add JWT authentication", it will reach for
the plugin with `jwt` in its name. That's `jwt-auth`, and it is the wrong half of
this flow.

`jwt-auth` **verifies tokens that somebody else signed.** It holds a public key or
a JWKS URL. It's what you use when Keycloak or Auth0 or Entra ID is your issuer
and the gateway's job is to check their work.

`helix-auth` in `generate` mode **is the issuer.** It holds the signing secret, so
it can mint as well as verify.

These aren't two ways to do the same thing — they sit on opposite sides of a
boundary:

| Your situation | Use | The gateway is |
|---|---|---|
| No identity provider; you want partners to exchange a client id and secret for a token | `helix-auth` generate + validate | the authorization server |
| An IdP already issues tokens to these partners | `jwt-auth` against that issuer; no token route at all | a verifier only |

Pick wrong in the second direction and you've built a second authorization server
competing with your real one — two systems both authoritative about identity,
which you discover during an incident. So the prompt says it explicitly: *the
gateway is the token issuer. There is no external identity provider involved.*

## Wrong turn two: protecting the token endpoint

This one is almost funny, and the symptom is spectacular.

An agent optimising for tidy configuration will notice that `helix-auth: validate`
appears on three routes and hoist it to the document root, where it applies
API-wide. Cleaner. Less repetition. Obviously correct.

Except `/oauth/token` is one of those routes. And now obtaining a token requires
already having a token.

Every single request to the API returns 401. Including the one whose entire job is
to fix that. The configuration looks immaculate.

So the prompt says: *apply validate per route on the protected endpoints — do NOT
apply it API-wide.* And the [spec](./gateway/api-spec.yaml) carries a comment
saying why, because the next person to tidy it up will be tempted too.

## The number that is actually a decision

`token_ttl: 900`. Fifteen minutes. This is the only genuinely interesting value in
the configuration, because it's the only bound on how long a leaked token stays
useful.

| TTL | A leaked token is usable for | Token requests per client per hour |
|---|---|---|
| 300s | up to 5 minutes | ~12 |
| 900s | up to 15 minutes | ~4 |
| 3600s | up to an hour | ~1 |
| 24h | up to a day | you have reinvented the static API key |

Left unspecified, an agent takes the platform default — which is a reasonable
number chosen without knowledge of your risk tolerance. So the prompt names it,
with the reason attached: *a leaked token should be worthless within fifteen
minutes, so do not default this to an hour.* The reason survives into the agent's
summary and stops a later change from quietly undoing it.

One thing to tell your integrators, because it's the difference between a token
endpoint and your busiest route: **cache the token and refresh at around 80% of
its lifetime.** A client that fetches a fresh token per API call doubles the
latency of everything and turns the auth endpoint into your hottest path.

## Testing the case everybody skips

Six assertions, in [`verify.sh`](./gateway/verify.sh):

1. No token → 401
2. Valid client credentials → 200 with a three-segment JWT
3. That token → 200 on a protected route
4. Forged token → 401
5. **Correct client id, wrong client secret → 401**
6. Token without the `Bearer ` prefix → 401

Case 5 is the one people don't write, and it's the one that proves you built what
you think you built.

Here's why it matters. In `key-auth` validate mode, the credential is resolved by
its **key** alone — the secret isn't consulted. `generate` mode is the only mode
that checks the secret. So if you've wired something up slightly wrong, you can
end up with a token endpoint that happily issues tokens to anyone who knows a
client id, which is not a secret at all. It looks like OAuth. It's a static key
with a JWT-shaped costume.

One test tells you which one you have.

Case 4 is the same principle from the other side: send a JWT with a valid shape
and a garbage signature. If that returns 200, the route isn't verifying anything —
it's parsing a header and passing traffic through while appearing configured. That
is the most serious way this solution can fail, and it fails silently.

## The thing your integrators will complain about

Every rejection is a bare 401. No token, malformed header, expired token, wrong
signature — all identical.

That's correct. A response that distinguishes them tells an attacker which half of
their guess was right. But it is genuinely painful for a partner engineer at 6pm
who is certain their credentials are correct, and "it just returns 401" is not a
debuggable symptom.

Two things make it survivable:

- **Document the four causes** in your developer portal, since the response can't.
- **Give them the correlation id.** `X-Request-Id` is stamped on every call
  including the token exchange, so a support ticket can carry something you can
  search on instead of a description of a feeling.

And know the operator-side version of the same symptom: if *everything* returns
401, including calls with tokens issued seconds ago, it's almost never the client.
It's the signing secret differing between the issue route and the validate route,
and neither plugin block gives you any hint that the value is shared. It's the
most common way this deploys wrong.

## What this doesn't do

Being straight about the boundary, because overclaiming here is how you lose
somebody's afternoon:

- **It authenticates applications, not users.** Client credentials proves which
  *integration* is calling. If your question is "may this user see this record",
  that's the authorization code flow plus an authorization layer, and this is
  neither.
- **It is not authorization.** You now know who's calling. What they may do is a
  separate concern — deliberately, because that's the genuinely
  application-specific part and burying it in the auth layer produces policy
  nobody can audit.
- **Tokens can't be revoked mid-life.** Disabling an app stops new tokens; issued
  ones live until they expire. Which is exactly why the TTL is the control.
- **It doesn't retire your existing static keys.** They stay dangerous until you
  migrate partners off them. That's real work — much less than a backend release,
  but not free.

## Where this goes next

Identity at the edge is the foundation the rest of the stack sits on, and that's
the real argument for doing it first:

- **[Metering](../03-api-products/).** Once every request is attributable to a
  named app, you can attach a quota to it — and sell tiers that are technically
  enforced rather than contractually asserted.
- **[Analytics](../04-analytics/).** "Which of our 400 integrations caused the 3am
  pager?" is answerable in seconds instead of hours, but only because calls
  attribute to an app rather than an IP address. Analytics is already capturing
  every request; identity is what makes the capture useful.
- **[Protocol mediation](../02-soap-to-rest/).** This exact auth layer sits in
  front of a SOAP backend without modification. The partner sends JSON with a
  Bearer token; a twenty-year-old system answers.

Each of those is impossible, or merely decorative, without knowing who is calling.

## Try it

The full package — importable spec, agent prompt, tests, and an honest record of
what has and hasn't been validated — is in
[`solutions/01-oauth-jwt/`](./).

Two ways in:

- **[The agent prompt](./helix-agent-prompt.md).** Recommended. It carries the
  constraints that prevent both wrong turns above, a table explaining why each one
  is there, and the failure modes we hit running it.
- **[The spec](./gateway/api-spec.yaml).** Import it directly if you'd rather read
  YAML than prose.

Then run [`verify.sh`](./gateway/verify.sh) against your own environment. Note that
the package is labelled **UNVALIDATED**: the auth mechanism was proven in an
earlier internal build, but this particular document has not been dry-run, and we'd
rather say so than let you find out. The
[validation record](./validation/gateway-validation.yaml) spells out exactly what
was and wasn't established.

Six weeks of backend work, or an afternoon and a configuration change. The
difference isn't effort. It's noticing that authentication was never application
logic in the first place.
