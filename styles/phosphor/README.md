# phosphor

One hue, sixteen brightnesses.

Early terminals could not choose a colour. The inside of the tube was
coated with a single phosphor and that was the whole palette: P1 green on
the VT220 and the IBM 5151, P3 amber on the Wyse. Emphasis was not a
different colour, it was more electrons.

So this style has no second colour. Twelve of the sixteen ANSI slots are
the same green at different intensities, and the four that are not —
`red`, `yellow` and their bright pairs — are amber, because a machine that
genuinely needed to signal alarm on a green tube is a machine with two
phosphors in it.

The other terminal-heritage styles are `gitbash`, which recreates a
specific program, and `sober`, which is deliberately colourless. This one
recreates the hardware.

## Includes

- **scheme.json** — 16 slots, 12 of them one green. The foreground measures
  14.71:1 on the background and 8.75:1 on the selection; every slot clears
  the 3:1 accent floor.
- **theme.json** — block cursor, padding 16, and the **only style in the
  set that turns `experimental.retroTerminalEffect` on**. Windows Terminal's
  scanline-and-glow filter is a poor fit for a photograph and exactly right
  for a tube. It is ignored everywhere else, which costs nothing.
- **profile.ps1** — title `PHOSPHOR`, one austere line: the folder in glow
  green between dim brackets, then an amber `>`. A real terminal had no
  decoration. PSReadLine takes the same one hue, with amber for errors.
- **prompt.sh** — the same single line for zsh and bash.
- **meta.json** — the one-line description and the quote, which is what a
  machine printed when it had nothing else to say.

Not in this folder: background images live flat-named on the
[`gifs` branch](https://github.com/fcreme/TerminalStyles/tree/gifs) and are
fetched into your cache on first use, so `main` stays binary-free. This
style's is a 256×256 solid `#020d02` — the same colour as the scheme
background, so the tube reads as a tube and any wallpaper inherited from
the previously-active style is wiped.

## Preview

```
[dotfiles]> _
```
