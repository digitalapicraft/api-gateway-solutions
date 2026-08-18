# Infographic spec — Solution 02, SOAP to REST

**Status:** specification only. `assets/infographic.html` is **not yet built** for
this package — this file is the brief a designer or a generator works from.
**Test before shipping:** shrink the render to 300px wide. If the XML/JSON boundary
isn't readable at that size, it fails — that's how it appears in a feed.

**Headline:** `Partners send JSON. A 2004 system answers.`
**Sub:** `Protocol mediation at the edge — no adapter services, no rewrite, no backend change`

---

### Panel 1 — BEFORE (muted / legacy)

A single box labelled **SOAP / XML — system of record**, drawn in muted slate,
emitting a small snippet of `<soap:Envelope>`. It is deliberately **not** rendered
as broken or alarming: it works, it's just speaking a different language.

Around it, four partner icons tagged `REST / JSON`, each separated from the box by
its own small adapter service — four little boxes labelled
`adapter-1`, `adapter-2`, `adapter-3`, `adapter-4`. Grey out two of them and tag
those `unowned`.

The honest point this encodes: the fleet is what's wrong, not the backend.

Caption beneath: *"Four adapters. Two nobody owns. Or rewrite the system of record
— a quarter, and nobody will sign it off."*

### Panel 2 — AFTER (signal / healthy)

The same SOAP box, **drawn identically to panel 1** — this matters, the whole claim
is that nothing behind the gateway moved. The four adapter boxes are **gone**. In
their place, one gateway band, with a single lane through it:

| Stage | Chip |
|---|---|
| 1 | `helix-auth` validate — *reject here* |
| 2 | `proxy-rewrite` → `<SOAP_HANDLER_PATH>` |
| 3 | `xml-to-json` — **JSON⇄XML** |

The four partner icons now connect straight through the band, each holding a
`client_id`. One rejection arrow bounces off stage 1 and never reaches stages 2–3 —
label it `401 · nothing transformed, nothing called`.

The **JSON⇄XML flip icon on the single transform chip is the most important visual
in the piece.** JSON on the partner side of that chip, XML on the backend side, one
bidirectional arrow. Make the boundary unmistakable.

Verdict line: **Four services became three lines of config.**

### Panel 2b — THE TOPOLOGY ARC (the hero)

Two small line charts side by side, same axes: *partners* on x, *services you
operate* on y.

```
adapter-per-partner            mediated at the edge
     services                       services
        ▲     ╱                        ▲
        │   ╱                          │
        │ ╱                            │────────────────
        └───────► partners             └───────► partners
```

Left: a diagonal. Right: flat. Caption: *"The number of things you operate stops
growing with the number of partners you onboard."*

This is the panel that makes the business case, and it's the one to give room. It's
a topology claim, not a performance claim — don't let a designer add a "faster"
chip.

### Panel 3 — THE ONE THING TO GET RIGHT (dark, diff-style)

```
+ xml-to-json      ONE plugin, BOTH directions
                   JSON→XML on the request · XML→JSON on the response

- json-to-xml      ← never add this alongside it
                   ↳ the body converts twice, the handler gets nonsense,
                     and you get a 500 that looks like a backend fault
```

One pair, big. This is the mistake everybody makes, including every model you ask,
and the panel exists solely to prevent it. Do not crowd it with the other gotchas.

### Footer

`xml-to-json · proxy-rewrite · helix-auth · request-id` · `~25 min` ·
`no backend change · no new services` · Solution 02 · repo URL.

---

## Design notes

- **Colour:** structural blue as the "signal/fix" colour, green for healthy, red
  reserved for the single thing that breaks (the `500` in panel 3). The legacy SOAP
  box is muted slate, **never red** — it isn't the villain, and rendering it as one
  contradicts the entire argument.
- **The SOAP box must be pixel-identical in panels 1 and 2.** The claim is "nothing
  behind the gateway moved." If a designer redraws, recolours or modernises it, the
  claim is visually contradicted.
- **The JSON⇄XML flip is the hero visual of panel 2.** One chip, one bidirectional
  arrow, format labels on either side. If a reader takes one thing away, it's that
  the boundary is a single place.
- **Panel 2b is the hero of the piece overall.** Mechanism is panel 2; outcome is
  panel 2b.
- **Panel 3 gets exactly one gotcha.** The bidirectional-transform mistake. The
  SOAPAction header, the array semantics and the content-type traps are all real and
  all belong in the README, not here — a feed graphic that lists four caveats
  communicates none of them.
- Don't draw the full pipeline as an inventory. Three chips on the lane reads as
  *pipeline*; six reads as *complexity*.
- **Do not imply rate limiting, quota or metering.** This solution applies no
  `api-product-enforcer`. It mediates and authenticates; it does not meter. Claiming
  a quota the config doesn't enforce would break the rule that the infographic
  describes the actual implementation.
- **Do not imply a designed REST contract.** If example JSON appears anywhere in the
  art, it must show the *derived* shape — `{"Locations":{"Site":[...]}}` with
  PascalCase intact, not an idealised `{"locations":[...]}`. Showing clean JSON
  would be the piece's one dishonest moment, and it's the exact expectation that
  causes disappointment later.
- **Do not imply request composition.** One inbound arrow, one backend call. Fan-out
  is a different pattern.
- Keep the underlying gateway/runtime unnamed.
- Placeholders only in any rendered text — no real hosts, org ids or partner names.
