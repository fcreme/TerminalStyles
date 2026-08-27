# ex-machina

> *"You've been programmed and fed by another. Are you bothered? It would bother me."*

Ex Machina aesthetic — cold electric cyan wireframe with a coral pink
accent, recalling Ava's body scans during the consciousness-test
sessions. Pale cyan default text on near-black, vintage cursor.

## Includes

- **scheme.json** — electric cyan / coral pink / near-black palette,
  built from the body-scan stills.
- **theme.json** — vintage cursor, Cascadia Code semi-bold, no retro
  effect or acrylic so the GIF carries the mood. Background image
  stretched to fill, centered.
- **profile.ps1** — replaces `$PROFILE` with:
  - 2-line prompt: `[AVA // BLUEBOOK] [LOC: <path>]` / `>`
  - Startup banner: BLUEBOOK research session readout
  - PSReadLine syntax colors tuned to the palette
  - History-based inline predictions
  - Tab title set to `EX MACHINA // BLUEBOOK`
- **prompt.sh** — the same prompt and banner for zsh and bash.
- **background.gif** — the body-scan loop bundled with the style; auto
  Not in this folder: background images live flat-named on the
  [`gifs` branch](https://github.com/fcreme/TerminalStyles/tree/gifs) and are
  fetched into your cache on first use, so `main` stays binary-free.
  applied when you select this style in `tstyles`.

## Best paired with

The bundled `background.gif`, or any cool-toned cyan-on-dark animation:
digital rain, oscilloscope traces, holographic glitches.

## Preview

```
+----------------------------------------------+
|  BLUEBOOK RESEARCH // SESSION 06 -- ACTIVE   |
|  SUBJECT: AVA   ::  PROTOCOL: TURING TEST    |
|  STATUS: CONSCIOUS  ::  TRUST: ??            |
+----------------------------------------------+

[AVA // BLUEBOOK] [LOC: C:\Users\felip]
> _
```
