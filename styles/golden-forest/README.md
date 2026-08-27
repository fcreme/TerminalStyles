# golden-forest

Warm sepia/forest styling. Gold-and-olive palette over near-black,
filled-box cursor, GIF stretched to fill the window for an immersive
woodland or autumn-light backdrop. No CRT effect, no acrylic — clean
and grounded.

## Includes

- **scheme.json** — gold / olive / forest Windows Terminal color scheme.
- **theme.json** — filledBox cursor, opaque background, GIF stretched
  `uniformToFill`, anchored top-left, 55% opacity (slightly stronger
  presence than umbrella/kitty).
- **profile.ps1** — sets the tab title to `GOLDEN FOREST`, resets the pwsh
  prompt to a plain `PS <path> `, and pins PSReadLine's syntax colors to the
  golden-forest palette so the previous theme's colors do not bleed through
  after a live `tstyles` switch.
- **prompt.sh** — the same, for zsh and bash.

This style keeps no custom prompt *shape* — it deliberately restores the stock
one — but it does replace whatever prompt was active, so `tstyles golden-forest
-KeepPrompt` is the flag to reach for if you have your own.

## Best paired with

A forest, autumn, or warm-light loop. Works well with cinematic
landscape GIFs where you want the imagery to feel like a window rather
than a sticker.
