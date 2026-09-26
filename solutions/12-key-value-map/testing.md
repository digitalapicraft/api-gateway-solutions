# Test & verify — Solution 12 — one route, fourteen partners, and rotation without a deploy

[Overview](readme.md) · [Business need](business-need.md) · [How it works](how-it-works.md) · [Install](install.md) · [Configuration](configuration.md) · **Test & verify** · [Changelog](changelog.md)

---

## Testing

Exit 0 means all of these held:

| # | Case | Expected |
|---|---|---|
| 1 | **A partner with no registered key** | `500` — and **no document**, in any form |
| 2 | Registering a key | `200` — **but read it back**; see the gotchas |
| 3 | That partner's document | `200`, base64 of armor |
| 4 | **A different, unregistered partner** | still `500` — entries are per partner |
| 5 | Decrypting with that partner's key | succeeds |
| 6 | **Re-registering, then fetching again** | the **new** key decrypts it; the old one cannot |

**Case 1 is the security case** — a 200 there means the document went out in the
clear. **Case 6 is the whole solution**: rotation with no revision, no route change
and no deploy, asserted rather than claimed.

Cases 1-4 need only bash, curl, base64 and a public key, so they run in a pipeline
that holds no private key material.

## A registered key can be unusable, and the status will not tell you

The sharpest edge in this package, found by running it.

| Partner id | Status | Body |
|---|---|---|
| never registered | **500** | `{"message":"no usable key is registered for this partner"}` |
| registered with a **sign-only** key | **200** | *identical body* |
| registered with a usable key | **200** | base64 PGP |

`fail_close_status` fires only on a store **miss**. When the store returns a value
the crypto cannot use, the failure goes out as a **success**, with the error
message in the body. Neither the status nor the message distinguishes "wrong kind
of key" from "no key".

**This is the ordinary case, not an edge case.** `gpg --quick-generate-key` — what
almost everyone reaches for — produces a primary key with **no encryption
subkey**, and adding `default never` does not change that. A partner following the
obvious path sends you a signing key, and you store it happily.

Check before you register, and put this in the note you send them:

```bash
gpg --list-keys --with-colons "$UID" | awk -F: '/^(pub|sub)/{print $1, $12}'
# want:  pub scESC        e = encrypt, s = sign, c = certify
#        sub e            no `sub e` row means the route cannot encrypt to it
```

Repair an existing key rather than regenerating it:

```bash
FPR=$(gpg --list-keys --with-colons "$UID" | awk -F: '/^fpr/{print $10; exit}')
gpg --quick-add-key "$FPR" rsa3072 encr never
```

Then **re-register** — the stored copy is still the broken one until you overwrite
it.

**For your tests: assert on the body, never on the status.** A check for `200`
passes while the caller receives no document at all.
