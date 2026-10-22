# PGP file exchange without a keyring script in the middle

> [Overview](README.md) · **Business need** · [Architecture](architecture.md) · [Guides](guides.md) · [Agent prompt](helix-agent-prompt.md) · [Tests](tests.md) · [API reference](api-reference.md)

---

> A partner's contract requires PGP in both directions, so a script on a server
> decrypts, forwards and re-encrypts. It holds your private key, it is in no
> pipeline and no monitoring, and nobody owns it.
>
> **The problem is not the encryption. It is where the encryption lives.**

- **The keys move off the server** into the control plane, stored encrypted, under
  the same access control and audit trail as everything else.
- **The change becomes a revision**: reviewed, dry-run, deployed and rolled back
  like any other.
- **Failures become ordinary gateway failures**, on the dashboards you already
  watch, with a request id the partner can quote.

Neither your backend nor the partner changes. The one decision that shapes the
design:

| | One partner | Many partners |
|---|---|---|
| Where the key goes | Written into the route — this package | Fetched per request — [solution 12](../12-key-value-map/) |
| Rotating a key | Edit, review, deploy, hard cutover | One request |
| Keys in configuration documents | One pair | None |

The key material in this package is a **literal in the route configuration**: no
environment-variable lookup, so keep the filled-in file out of version control.
That is fine for one long-lived partner and does not scale past a few. This is
confidentiality only — not authentication and not a signature. What it does not
protect is covered in [Architecture](architecture.md#what-this-does-not-do).

*Also searched as: PGP encryption API gateway · OpenPGP decrypt request · encrypt
API response with partner key · replace PGP script · bank file encryption API ·
GPG at the edge · encrypted partner file exchange.*
