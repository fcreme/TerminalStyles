# umbrella

> *"Welcome to Umbrella Corporation. Status: FINE."*

Survival-horror classified-doc styling. Muted blood-red brackets and labels
over bone-white text, with a 3-line typewriter prompt and a startup
banner that reads like a save-room readout.

## Includes

- **scheme.json** — dark blood-red / bone-white Windows Terminal color scheme.
- **theme.json** — vintage cursor, Cascadia Code semi-bold, no retro/acrylic
  effects (lets the GIF carry the mood). GIF stretched to fill, centered.
- **profile.ps1** — replaces `$PROFILE` with:
  - 3-line prompt: `[UMBRELLA // OPERATOR: <user>]` / `[CWD: <path>]` / `>`
  - Startup banner with "CLEARANCE: PERSONAL :: STATUS: FINE"
  - PSReadLine syntax colors tuned to the palette
  - History-based inline predictions
  - Tab title set to `UMBRELLA TERMINAL`

## Best paired with

A dark, slow Resident-Evil-style GIF (RE2/RE4 remake scenes work well).
Pass any animated GIF to `apply.ps1` via `-BackgroundImage`.

## Preview

```
+------------------------------------------+
|  UMBRELLA CORP. // OPERATOR TERMINAL     |
|  CLEARANCE: PERSONAL  ::  STATUS: FINE   |
+------------------------------------------+

[UMBRELLA // OPERATOR: felip]
[CWD: C:\Users\felip]
> _
```
