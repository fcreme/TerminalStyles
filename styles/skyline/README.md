# skyline

A balcony, after everyone has gone in.

Someone leaning on a railing above a city that is still lit — a crescent
moon, a strip of green signage running along the far bank, towers with
about a third of their windows still on. The palette is taken from those
frames rather than chosen: `#130047` is the indigo the whole frame sits
in and a quarter of every pixel, and `#42ff8e` is the green strip, 2% of
the picture, which is why the cursor is that and nothing else.

Nothing else in the set is indigo. `lain` is the nearest and reads
black-violet; this one is saturated.

## Includes

- **scheme.json** — 16-color palette sampled from the source frames. The
  foreground measures 15.98:1 on the background and 6.54:1 on the
  selection, and every slot clears the 3:1 accent floor.
- **theme.json** — bar cursor, Cascadia Code regular, padding 14,
  background at 0.32. The source is 492×270, which is already close to a
  terminal's shape, so it covers with a 93px crop rather than the 2× blow-up
  a square image needs.
- **profile.ps1** — title `SKYLINE`, two-line prompt: the folder in
  lit-window blue under a dim `..`, then a green `|` bar. PSReadLine takes
  the same palette, with the neon pink kept for errors — the one warm
  colour anywhere in the frame.
- **prompt.sh** — the same two-line prompt for zsh and bash.
- **meta.json** — the one-line description and quote `tstyles` shows when
  you pick it.

Not in this folder: background images live flat-named on the
[`gifs` branch](https://github.com/fcreme/TerminalStyles/tree/gifs) and are
fetched into your cache on first use, so `main` stays binary-free.

## Preview

```
.. TerminalStyles
| _
```

`docs/screenshots/skyline.png` is **rendered**, not captured, by
`scripts/make-preview.py` — see the note in `styles/koholint/README.md`.
