## What & why

<!-- The problem, then the change. -->

## Solution package

- Slug: `solutions/<NN-slug>/`
- [ ] README carries a mermaid diagram that declares a diagram type
- [ ] No secrets — placeholders only. The gateway uses `signing_secret` and
      `redis_host` **verbatim**; it does not resolve `<ENV:...>` or `${...}`.
- [ ] `solution.yaml`, `gateway/api-spec.yaml`, `gateway/products.json` parse
- [ ] No non-public artifacts (`blog.md`, `video-script.md`, `infographic.md`,
      `marketplace-publish.md`, `VERIFICATION.md`)

## Validation status

<!-- Exact vocabulary. Never promote a rung without something that actually ran. -->

Reached: `Configuration generated` / `Locally validated` / `Gateway dry-run passed` /
`Gateway deployed` / `Functional test passed`

## After this merges

This repo is consumed as a submodule. Once merged, the pin must be moved to
**this** merged commit on `main` — never to the branch tip, which a squash merge
leaves unreachable and which breaks `git submodule update` on a fresh clone.

```bash
git -C public checkout main && git -C public pull --ff-only
git add public && git commit -m "Pin <slug>" && git push -u origin <branch>
```
