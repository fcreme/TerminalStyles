# eva

> *"Anta baka?"*

Neon Genesis Evangelion aesthetic — coral-red CRT palette with mustard
yellow overlay (Eva's status displays) over pale pink-white text, pulled
directly from Asuka / Unit-02 stills.

## Includes

- **scheme.json** — coral-red / yellow / pink-white palette on near-black.
- **theme.json** — filledBox cursor (CRT block feel), Cascadia Code
  semi-bold, GIF stretched to fill, centered at 0.35 opacity.
- **profile.ps1** — replaces `$PROFILE` with:
  - 2-line prompt: `[PILOT // EVA-02] [LOC: <path>]` / `>`
  - Startup banner: NERV operations readout with Asuka's signature line
  - PSReadLine syntax colors tuned to the palette
  - History-based inline predictions
  - Tab title set to `EVA // NERV`
- **background.gif** — the bundled body-scan loop (3.0 MB).
  Not in this folder: background images live flat-named on the
  [`gifs` branch](https://github.com/fcreme/TerminalStyles/tree/gifs) and are
  fetched into your cache on first use, so `main` stays binary-free.

## Best paired with

The bundled `background.gif` (Asuka / Eva-02), or any cool-warm pixel-art
animation with strong red CRT scanlines.

## Preview

```
+----------------------------------------------+
|  NERV // EVA-02 PILOT INTERFACE              |
|  SOHRYU, ASUKA LANGLEY :: SYNC: 89%          |
|  ANTA BAKA?                                  |
+----------------------------------------------+

[PILOT // EVA-02] [LOC: C:\Users\felip]
> _
```
