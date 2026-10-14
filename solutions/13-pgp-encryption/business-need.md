# PGP encryption and decryption at the API gateway

> Our settlement partner is a bank. It only accepts PGP-encrypted files, and
> everything it sends back is encrypted too. In between sits a Python script on a
> VM with a keyring, written by someone who left in 2022. It isn't in our pipeline
> or our monitoring, and it pages us at 2am on the last working day of the month.
>
> **Move the crypto onto the gateway the traffic already passes through; the
> backend keeps handling plaintext.**

- **Where the private key lives: a home directory on a VM → the gateway's
  configuration**, encrypted at rest, behind the same access control and audit
  trail as everything else.
- **A change to the crypto: a manual edit on a server → a reviewed revision**,
  dry-run, deployed and rolled back like any other route change.
- **Backend and partner changes: none.** The backend still handles plaintext, and
  the partner still sends and receives what the contract says.

Two keys are involved, and they are not a pair:

| Direction | The gateway uses | Whose key |
|---|---|---|
| inbound: the partner sends you an encrypted file | your private key, to decrypt | yours; the partner encrypts to its public half |
| outbound: you send the partner a document | the partner's public key, to encrypt | theirs; you never hold its private half |

It holds one key pair per route, so a second counterparty means a second route,
and rotation is a release. At more than one partner, see
[14 — Per-partner PGP keys](../14-per-partner-pgp-keys/). The private key is a
literal in the route, so keep the filled-in configuration out of version control.
[Before/after, the wire format, and what this does not buy you are in the
README](README.md#business-need).

*Also searched as: PGP encryption at the API gateway · OpenPGP decrypt request
body · encrypt API responses with PGP · bank file encryption integration · replace
a PGP script with the gateway · GPG at the edge · encrypted file exchange with a
partner.*
