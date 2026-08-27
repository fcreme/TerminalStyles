# rain

> *"Still no sign of the others."*

Contemplative highland-storm aesthetic — slate-purple stormy sky, vivid
moss-green undertones, warm rust for the lone cloaked traveler.
Quieter than umbrella's drama, but more colorful than sober. Closer
in spirit to a Ghibli / Miyazaki rainscape than a sci-fi terminal.

## Includes

- **scheme.json** — slate-purple background, lavender-mist default text,
  rain-blue and moss-yellow accents, cloak-rust for errors.
- **theme.json** — vintage cursor (fits the pixel-art GIF), Cascadia
  Code **regular** weight (not semi-bold; the lighter weight reads
  more contemplative), padding 14, GIF at 0.4 opacity uniformToFill
  centered.
- **profile.ps1** — replaces `$PROFILE` with:
  - 2-line prompt: `[TRAVELER // RAIN] [LOC: <path>]` / `>`
  - Startup banner: a field-journal entry, three lines
  - PSReadLine syntax colors tuned to the palette (no screaming reds)
  - History-based inline predictions
  - Tab title set to `RAIN // HIGHLAND`
- **prompt.sh** — the same prompt and banner for zsh and bash.
- **background.gif** — the bundled highland-castle storm loop.
  Not in this folder: background images live flat-named on the
  [`gifs` branch](https://github.com/fcreme/TerminalStyles/tree/gifs) and are
  fetched into your cache on first use, so `main` stays binary-free.

## Best paired with

The bundled `background.gif` (pixel-art castle in steady rain), or any
slate-and-green pixel landscape: Ghibli scenes, RPG world maps,
Studio-Mappa-style atmosphere loops.

## Preview

```
+--------------------------------------------+
|  FIELD JOURNAL // DAY 47                   |
|  WEATHER: STEADY RAIN  ::  CEILING: 40m    |
|  STILL NO SIGN OF THE OTHERS.              |
+--------------------------------------------+

[TRAVELER // RAIN] [LOC: C:\Users\felip]
> _
```
