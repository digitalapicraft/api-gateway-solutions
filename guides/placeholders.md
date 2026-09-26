# Placeholders

Every value you must replace before deploying, and the one substitution rule that will cost you a signing key if you get it wrong.

---

No secrets, hostnames, org identifiers or customer names appear anywhere in this
repo. You will see:

| Placeholder | Replace with |
|---|---|
| `<YOUR_GATEWAY_HOST>` | the host your environment serves traffic on |
| `<ORG_ID>` · `<ENV_ID>` · `<API_ID>` | identifiers from your control plane |
| `<CLIENT_ID>` · `<CLIENT_SECRET>` | your app's credentials — the control plane issues these |
| `<UPSTREAM_URL>` · `<SOAP_UPSTREAM_URL>` | your backend |
| `<YOUR_JWT_SIGNING_SECRET>` · `<YOUR_REDIS_HOST>` | a **literal** value you fill in — see the warning below |
| `<OKTA_DISCOVERY_URL>` · `<OKTA_ISSUER_URL>` | your IdP's discovery document, and the `issuer` value that document reports |
| `<OKTA_CLIENT_ID>` · `<OKTA_CLIENT_SECRET>` | the IdP application's credentials — also **literals**, see the warning below |
| `<KEY_ID>` · `<SECRET_KEY>` | an app credential's HMAC key pair — the control plane generates these; they never appear in a spec |
| `<YOUR_KAFKA_BROKER>` | a broker hostname the **gateway** can reach. Not a secret |
| `<DEVICE_API_KEY>` · `<APP_SECRET>` | an app credential's key and secret — the control plane issues these; they never appear in a spec |
| `<PGP_PUBLIC_KEY>` · `<PGP_PRIVATE_KEY>` | armored OpenPGP key blocks. **Literals**, like the signing secret — see the warning below |

App **keys and secrets** (the `client_id`/`client_secret` on an app) are
provisioned on the credential by the control plane and never belong in a spec.

> **⚠️ The signing secret is different, and this matters.** Verified against a live
> gateway, this build does **not** resolve `<ENV:...>` or `${...}`
> syntax. Whatever string sits in `signing_secret` is used *verbatim* as the HMAC
> key. So `<YOUR_JWT_SIGNING_SECRET>` is a fill-in-the-blank, **not** an
> environment-variable reference — replace it with a real, high-entropy secret
> before deploy, and keep the filled-in spec out of version control. If you ship
> the placeholder literally, your signing key is a publicly known constant and
> anyone can forge tokens. The same applies to `<OKTA_CLIENT_SECRET>` in solution
> 05 — it is a literal too, and the control plane stores it encrypted only after
> you have supplied a real one.
>
> **Solution 06 has no such footgun, by construction.** `hmac-auth`'s route schema
> has no secret field at all, so there is nothing to fill in and nothing to leak —
> `key_id` and `secret_key` live only on the app credential. **Solution 08 has the
> same property** for the same structural reason: the route names the *header* an
> API key arrives in, never the key.
>
> **Solution 13 has the worst version of it.** `private_key` and `public_key` are
> literals too, and a private key outlives a signing secret and is usually shared
> with a counterparty. That limitation is the entire reason
> [solution 12](solutions/12-key-value-map/) exists: it fetches the key per request
> so no key material is in the document at all.
