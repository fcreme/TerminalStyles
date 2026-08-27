# kitty

Soft pastel CRT styling with a pink-lavender palette and a retro-terminal
effect. Acrylic background blur, vintage cursor, GIF anchored to the
bottom-right corner so it feels like a sticker.

## Includes

- **scheme.json** — pastel pink/lavender Windows Terminal color scheme.
- **theme.json** — vintage cursor, retro CRT effect, acrylic at 80%, GIF
  placed bottom-right at native size (no stretch).
- **profile.ps1** — sets the tab title to `KITTY TERMINAL`, resets the pwsh
  prompt to a plain `PS <path> `, and pins PSReadLine's syntax colors to the
  kitty palette so the previous theme's colors do not bleed through after a
  live `tstyles` switch.
- **prompt.sh** — the same, for zsh and bash.

This style keeps no custom prompt *shape* — it deliberately restores the stock
one — but it does replace whatever prompt was active, so `tstyles kitty
-KeepPrompt` is the flag to reach for if you have your own.

## Best paired with

A small, looped GIF that reads well as a corner accent — a cat, an
animated sprite, or any short loop with a transparent or matching
background.
