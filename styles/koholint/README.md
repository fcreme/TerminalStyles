# koholint

The one that is mostly sky.

*Link's Awakening* opens with a shipwreck: Link face-down on driftwood,
the Wind Fish's island somewhere past the horizon. Four fifths of that
frame is water and sky, so four fifths of this style is too.

The palette is taken from the frames rather than chosen — `#182098` is
the sea, and it is 40% of every pixel in the source; `#f0f848` is the
band on the hat, 0.3% of the picture and the only yellow in it, which is
why it is the cursor and nothing else.

## Includes

- **scheme.json** — 16-color GBC palette sampled from the source frames.
  Cloud white on sea blue measures 11.6:1, and every bright slot clears
  the 4.5 body-text threshold. The normal slots sit under it on purpose:
  those are the un-emphasised half of an ANSI pair.
- **theme.json** — block cursor, Cascadia Code regular, padding 12,
  background at 0.28 so the driftwood reads without competing with text.
- **profile.ps1** — title `KOHOLINT`, two-line prompt: a `~~~~` waterline
  and the folder in shallow-water cyan, then `>>` with the second chevron
  in hat yellow. PSReadLine takes the same palette.
- **prompt.sh** — the same two-line prompt for zsh and bash.
- **meta.json** — the one-line description and quote `tstyles` shows when
  you pick it.

Not in this folder: background images live flat-named on the
[`gifs` branch](https://github.com/fcreme/TerminalStyles/tree/gifs) and are
fetched into your cache on first use, so `main` stays binary-free.

## Preview

```
~~~~ TerminalStyles
>> _
```

`docs/screenshots/koholint.png` is **rendered**, not captured. Every other
screenshot in that folder came from `scripts/capture-screenshots.ps1`, which
needs `$env:WT_SESSION` and a Windows box; this one is drawn by
`scripts/make-preview.py` from the style's own files — colours from
scheme.json, the background from the `gifs` branch at the opacity theme.json
asks for. It is reproducible on any machine, which a screen capture is not.
