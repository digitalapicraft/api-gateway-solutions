# Validation status — what the badges mean

Five statuses that are deliberately not interchangeable. A solution says exactly how far it was taken, and by what.

---

These are five different things and this library never blurs them:

`Configuration generated` · `Locally validated` · `Gateway dry-run passed` ·
`Gateway deployed` · `Functional test passed`

Every package's `validation/` directory records which of these actually happened,
who performed it, and whether it was re-run when the package was last touched.
Where a status came from an earlier run rather than the current one, it says so.
**Nothing in this repo claims a result that wasn't produced by a real gateway.**

Each solution README carries the same table:

| Stage | Status | Provenance |
|---|---|---|

Overall status is one of **READY** · **READY WITH WARNINGS** · **UNVALIDATED**
(generated and structurally reviewed, but not confirmed against a gateway) ·
**NOT READY** (a dry-run failed).

Whatever a package says, **re-run `gateway/verify.sh` against your own
environment before you rely on it.** Plugin builds differ between orgs.
