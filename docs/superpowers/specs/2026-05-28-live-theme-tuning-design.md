# `tstyles tune` — Live Theme Tuning — Design

**Date:** 2026-05-28
**Status:** Approved (pending implementation)
**Author:** Felipe
**Target version:** `0.3.0` (minor — new subcommand + new files, purely additive)
**Builds on:** [user-styles dir (v0.2.1)](2026-05-27-user-styles-dir-design.md), the picker's two-channel live-preview model in `tstyles.ps1`

## Problem

The picker lets you switch between 16 bundled themes, but you can't *adjust* one. A theme might be perfect except it's a touch too bright, the colors too saturated for a long session, the window too opaque, or the font not your favorite. Today the only way to change those is to hand-edit `scheme.json` / `theme.json` and reload — no live feedback, no easy save.

`tstyles tune` adds an interactive, real-time tuning screen: arrow-key sliders for **brightness**, **saturation**, **opacity**, **font face**, and **font size**, previewed live in the current tab (colors retint instantly via OSC, exactly like the picker). On confirm you save the result as a style in your user-styles dir — either overwriting the theme you tuned (a user-dir shadow that wins over the bundled one) or as a new named variant. The adjustments are remembered so you can reopen and keep tuning.

## Goals

- New `tstyles tune` subcommand:
  - `tstyles tune` — tune the currently active style (via `Get-CurrentStyleName`).
  - `tstyles tune <name>` — tune a specific style (resolved via `Get-StyleDir`; user-dir wins over bundled).
- Five live knobs: **brightness** (−100…+100), **saturation** (−100…+100), **opacity** (0…100%), **font face** (cycle installed monospace fonts), **font size** (6…36).
- **Two-channel live preview** mirroring the picker:
  - Brightness + saturation → recompute the scheme in memory, retint instantly via **OSC escape sequences** (no file write, no WT reload).
  - Opacity + font → **debounced `settings.json` write** + WT reload (rapid nudges collapse to one write).
- **Esc** reverts `settings.json` to the exact original bytes (byte-exact, picker parity). **R** resets all knobs to neutral.
- On **Enter**, prompt **Save / Save As**:
  - *Save* → overwrite the tuned style's name in the user-styles dir (shadows the bundled one).
  - *Save As* → write under a new name.
- Saved styles are **materialized full styles** in `%LOCALAPPDATA%\TerminalStyles\styles\<name>\` (`scheme.json` + `theme.json` + `profile.ps1` + `tune.json`), so they appear in `list`, the picker, `tstyles <name>`, and tab-completion — and survive updates.
- A `tune.json` records the deltas + base style so **reopening resumes the sliders** and you can reset back toward the base.
- A tuned style **inherits its base style's background** automatically.
- Extract the picker's inline OSC-packet builder into a shared `Get-SchemeOscPacket` helper (used by both picker and tuner).
- All existing Pester tests keep passing; add tests for the new pure helpers + save logic.
- 0.3.0 ships to PSGallery.

## Non-goals

- **No per-knob reset** — `R` resets everything. (YAGNI; revisit if requested.)
- **No paged/multi-screen UI** — all five knobs on one screen.
- **No arbitrary hex color editing** of individual slots — tuning is global brightness/saturation, not a full palette editor. (A palette editor is a separate, much larger feature.)
- **No hue rotation / temperature / contrast** knobs in v1 — brightness + saturation cover the stated "intensity" need. Easy to add later given the HSL pipeline.
- **No "press T in the picker" shortcut** in v1 — `tstyles tune` is the only entry point. The shortcut is a documented future follow-up that would call the same routine.
- **No font preview rendering** beyond setting `font.face` live — we can't render a font sample in the swatch; the live terminal IS the preview.
- **No exhaustive system-font list** — we intersect installed fonts with a curated monospace allowlist (see Font enumeration). Listing every installed family is out of scope (GDI+ can't reliably detect pitch, and 300 entries is unusable).
- **No editing of the bundled style files in place** — bundled themes live in the module dir, which is replaced on every update (and may be read-only on PSGallery). All saves go to the user-styles dir.
- **No completer for the 2nd positional** (style name after `tune`) in v1 — optional polish, noted in Known limitations.

## Architecture

Five new module-private functions in `tstyles.ps1`, one extraction, plus dispatch + completer wiring.

### New: `Get-AdjustedScheme` (pure)

The keystone. No I/O — takes a scheme object and two integer deltas, returns a **new** scheme object with each hex slot recomputed via HSL. Heavily unit-tested.

```powershell
function Get-AdjustedScheme {
    # Returns a NEW scheme object (does not mutate $Scheme) with every hex
    # color slot adjusted by the given brightness/saturation deltas, applied
    # in HSL space. Brightness is additive in L; saturation is multiplicative
    # in S. Both clamp to [0,1]. The scheme 'name' and any non-color props
    # pass through untouched. Missing slots are skipped; malformed hex is
    # passed through unchanged.
    param(
        [Parameter(Mandatory)]$Scheme,
        [int]$Brightness = 0,   # -100..+100
        [int]$Saturation = 0    # -100..+100
    )

    # Color slots WT schemes use. Order doesn't matter here.
    $slots = @('background','foreground','cursorColor','selectionBackground',
               'black','red','green','yellow','blue','purple','cyan','white',
               'brightBlack','brightRed','brightGreen','brightYellow',
               'brightBlue','brightPurple','brightCyan','brightWhite')

    $out = [pscustomobject]@{}
    foreach ($prop in $Scheme.PSObject.Properties) {
        $name = $prop.Name
        $val  = $prop.Value
        if ($name -in $slots -and $val -is [string] -and $val -match '^#?[0-9a-fA-F]{6}$') {
            $val = Convert-HexAdjust -Hex $val -Brightness $Brightness -Saturation $Saturation
        }
        $out | Add-Member -NotePropertyName $name -NotePropertyValue $val -Force
    }
    return $out
}
```

`Convert-HexAdjust` (private helper) does `hex → RGB → HSL → adjust → RGB → hex`:

- `L' = clamp(L + ($Brightness / 100) * 0.5, 0, 1)` — additive; ±100 shifts halfway to black / white.
- `S' = clamp(S * (1 + $Saturation / 100), 0, 1)` — multiplicative; −100 = grayscale, +100 = 2× (clamped).
- Preserves the leading `#` presence of the input.

### Extracted: `Get-SchemeOscPacket`

The picker currently builds OSC color packets **inline** (~line 1155 of `tstyles.ps1`, inside the 400-line `Invoke-TerminalStyle`). Extract verbatim into a shared function so the tuner reuses it:

```powershell
function Get-SchemeOscPacket {
    # Returns a single string of OSC escape sequences that, when written to
    # stdout, instantly retints the terminal's fg/bg/cursor/selection + the
    # 16-color palette to $Scheme. No settings.json write, no WT reload.
    param([Parameter(Mandatory)]$Scheme)
    $BEL = [char]7; $E = [char]27
    $palette = 'black','red','green','yellow','blue','purple','cyan','white',
               'brightBlack','brightRed','brightGreen','brightYellow',
               'brightBlue','brightPurple','brightCyan','brightWhite'
    $sb = [System.Text.StringBuilder]::new()
    if ($Scheme.foreground)          { [void]$sb.Append("$E]10;$($Scheme.foreground)$BEL") }
    if ($Scheme.background)          { [void]$sb.Append("$E]11;$($Scheme.background)$BEL") }
    if ($Scheme.cursorColor)         { [void]$sb.Append("$E]12;$($Scheme.cursorColor)$BEL") }
    if ($Scheme.selectionBackground) { [void]$sb.Append("$E]17;$($Scheme.selectionBackground)$BEL") }
    for ($p = 0; $p -lt $palette.Count; $p++) {
        $c = $Scheme.($palette[$p])
        if ($c) { [void]$sb.Append("$E]4;${p};${c}$BEL") }
    }
    return $sb.ToString()
}
```

The picker's loop is then refactored to call `Get-SchemeOscPacket $schemes[$i]` where it previously inlined the builder. **Behavior-preserving** — a test asserts the extracted output matches the previous bytes.

### New: `Get-MonospaceFontList`

```powershell
function Get-MonospaceFontList {
    # Returns an ordered, de-duplicated list of monospace font family names
    # to cycle in the tuner: the curated allowlist intersected with what's
    # actually installed, with $Current guaranteed present (and first) so the
    # tuner always starts on the style's existing font.
    param([string]$Current)
    Add-Type -AssemblyName System.Drawing -ErrorAction SilentlyContinue
    $installed = @()
    try {
        $installed = [System.Drawing.Text.InstalledFontCollection]::new().Families.Name
    } catch { }
    $allow = @('Cascadia Mono','Cascadia Code','Consolas','JetBrains Mono',
               'Fira Code','Hack','Source Code Pro','DejaVu Sans Mono',
               'Lucida Console','Courier New')
    $list = @($allow | Where-Object { $_ -in $installed })
    if (-not $list) { $list = @('Consolas') }   # universal Windows fallback
    if ($Current -and $Current -notin $list) { $list = @($Current) + $list }
    elseif ($Current) { $list = @($Current) + @($list | Where-Object { $_ -ne $Current }) }
    return @($list | Select-Object -Unique)
}
```

### New: `Save-TunedStyle`

```powershell
function Save-TunedStyle {
    # Materializes a tuned style into the user-styles dir. Writes scheme.json
    # (adjusted, name = $SaveName), theme.json (base theme + opacity/font),
    # profile.ps1 (copied from base if present), and tune.json (deltas+base).
    # Inherits the base's background by recording $Base in tune.json (see
    # background inheritance below).
    param(
        [Parameter(Mandatory)]$AdjustedScheme,
        [Parameter(Mandatory)][string]$SaveName,
        [Parameter(Mandatory)][string]$BaseStyleDir,
        [Parameter(Mandatory)][string]$BaseName,
        [int]$Brightness, [int]$Saturation, [int]$Opacity,
        [string]$FontFace, [int]$FontSize
    )
    # ... writes the four files to $DataRoot\styles\$SaveName\ ...
}
```

### New: `Invoke-TerminalStyleTune` (the interactive loop)

Structure mirrors the picker:

1. Resolve the style dir (arg or current). Error out if none / no `settings.json`.
2. Establish the tuner's **working base scheme** and seed the knobs:
   - If the style has a `tune.json`, it's a previously-tuned style. Resolve its recorded `base` (via `Get-StyleDir`) and load *that* style's **pristine** `scheme.json` as the working base; seed the sliders from the stored deltas. Live recompute is always `Get-AdjustedScheme(workingBase, currentDeltas)` — so the baked `scheme.json` is never re-adjusted on top of itself (no double-application), and `R` → neutral returns to the true base look.
   - If the recorded `base` can't be resolved (deleted/renamed), fall back: use the style's own (baked) `scheme.json` as the working base with neutral sliders.
   - If there's no `tune.json` (tuning a pristine bundled/user style), the working base is the style's own `scheme.json` and sliders start neutral (brightness 0, saturation 0, opacity from theme or 100, font from theme or default, size from theme or 12).
3. Snapshot original `settings.json` bytes for byte-exact Esc revert.
4. Render loop (non-blocking, debounce-tailed like the picker):
   - **Up/Down** moves the selected knob; redraw the menu immediately.
   - **Left/Right** adjusts the selected knob's value; redraw.
     - For brightness/saturation changes: recompute `Get-AdjustedScheme`, write its `Get-SchemeOscPacket` to stdout (instant retint), update the preview swatch.
     - For opacity/font changes: set `$pendingApply = $true` (debounced settings.json write on queue drain).
   - **R** resets all knobs to neutral; recompute + repaint.
   - **Enter** → drain pending apply, then run the Save/Save-As prompt.
   - **Esc** → restore original bytes, "Reverted.", return.
   - On idle with a pending apply: merge the adjusted scheme + theme (opacity/font) into `settings.json` via `Merge-StyleIntoSettings` and write (this is the channel that brings opacity/font live).
5. On confirm + save: `Save-TunedStyle`, then apply the saved style the same way `Apply-StyleDirect` finishes (copy `profile.ps1` → `current-style.ps1`, dot-source for live reload), and leave the adjusted look in `settings.json`.

### Save / Save As prompt

```
  Save tuned 'eva'?
    [1] Overwrite 'eva'        (shadows the bundled eva)
    [2] Save as a new name
    [Esc] keep tuning
  > 2
  New style name: eva-night
```

- Name validation: non-empty, matches `^[A-Za-z0-9._-]+$` (existing folder-name assumptions), trimmed; Esc at the name prompt returns to tuning.
- If the Save-As name matches a *bundled* style name, allow it (a user-dir shadow is intentional) but warn first: `That shadows bundled '<name>'. Continue? [y/N]`.
- **The recorded `base` carries through re-saves**: re-saving a reopened tuned style writes `tune.json.base` = the original base (not the tuned style's own name), so the base+deltas model stays stable across edits.

### Background inheritance

A tuned style has no GIF of its own (backgrounds live on the `gifs` branch keyed by bundled name). Rather than copy binaries, record `base` in `tune.json` and teach background resolution to fall back to the base:

- `Get-StyleBundledBackground` currently resolves bundled → cache → lazy-fetch by the style's own name. Add: if a style dir contains a `tune.json` with a `base`, and no background resolves for the style's own name, resolve the **base's** background instead (recurse once on the base name).
- Net effect: `eva-night` shows eva's animated background automatically. `Test-StyleResolved` updated in parallel so the picker doesn't show "...fetching" forever for tuned styles.

### Subcommand dispatch (in `Invoke-TerminalStyle`)

The public function takes a single `Position=0` `$Arg` today. Add a second positional for the style name after `tune`:

```powershell
    [Parameter(Position=0)][string]$Arg,
    [Parameter(Position=1)][string]$SubArg,   # NEW: e.g. style name for `tstyles tune <name>`
```

Dispatch line (between `random` and `register`, alphabetical-ish):

```powershell
    if ($Arg -eq 'tune')                 { Invoke-TerminalStyleTune -StyleName $SubArg; return }
```

Adding `Position=1` is backward-compatible: existing `tstyles <stylename>` still binds to `$Arg`.

### Tab completer

```powershell
    $subcommands = @('list', 'current', 'random', 'register', 'tune', 'update', 'uninstall')
```

## File-by-file changes

- **Modify:** `tstyles.ps1`
  - Add `Get-AdjustedScheme` + private `Convert-HexAdjust` (HSL math).
  - Add `Get-SchemeOscPacket` (extracted from picker) + refactor the picker to call it.
  - Add `Get-MonospaceFontList`.
  - Add `Save-TunedStyle`.
  - Add `Invoke-TerminalStyleTune`.
  - Extend `Get-StyleBundledBackground` + `Test-StyleResolved` with base fallback for tuned styles.
  - Add `$SubArg` (Position=1) param + the `tune` dispatch line in `Invoke-TerminalStyle`.
  - Add `'tune'` to the tab completer subcommands.
- **Create:** `tests/Get-AdjustedScheme.Tests.ps1` — color math.
- **Create:** `tests/Save-TunedStyle.Tests.ps1` — save layout + tune.json round-trip + Save/Save-As naming.
- **Create:** `tests/Get-MonospaceFontList.Tests.ps1` — allowlist intersection + current-font inclusion (mock the font collection).
- **Create:** `tests/Get-SchemeOscPacket.Tests.ps1` — extraction parity (matches previous inline bytes).
- **Modify:** `README.md` — `## Subcommands` row for `tstyles tune`, plus a short "Tuning a theme" subsection under `## Use`.
- **Modify:** `TerminalStyles.psd1` — `ModuleVersion 0.2.2 → 0.3.0`, update `ReleaseNotes`.

No changes to: `install.ps1`, `apply.ps1` (the tuner is a module/picker concern; apply.ps1 stays a one-shot non-interactive tool), `scripts/publish.ps1`, `docs/RELEASING.md`.

## Data model: `tune.json`

```json
{
  "schemaVersion": 1,
  "base": "eva",
  "brightness": -15,
  "saturation": 10,
  "opacity": 85,
  "fontFace": "Cascadia Mono",
  "fontSize": 11
}
```

- `base` — the style this was tuned from; drives background inheritance and "reset toward base."
- Knob deltas/values — seed the sliders on reopen.
- `schemaVersion` — forward-compat guard; unknown future versions read what they can, ignore the rest.

The materialized `scheme.json` holds the **baked** (already-adjusted) colors with a unique `name` (= the saved style name). The baked scheme is what Windows Terminal consumes between sessions (and what `list` / picker / `tstyles <name>` apply). On **reopen**, however, the tuner's source of truth is **`base` + `tune.json` deltas**: it reloads the pristine base scheme and re-derives, so the sliders are meaningful and re-deriving never double-applies onto the baked file. `tune.json` is the tuner's memory; `scheme.json` is the runtime cache.

## Data flow

### Tune a bundled theme, save as a new variant

1. `tstyles tune eva` → resolve `eva` (bundled). Load its scheme + theme. No `tune.json` → knobs start neutral.
2. Arrow to **Saturation**, Left a few times → in-memory `Get-AdjustedScheme` recomputes, `Get-SchemeOscPacket` written to stdout → terminal colors mute **instantly**.
3. Arrow to **Opacity**, Right → `$pendingApply` set; on the next idle tick, `Merge-StyleIntoSettings` writes `settings.json` → WT reloads with new acrylic opacity (a beat later).
4. Arrow to **Font face**, Right → cycles to "JetBrains Mono" → debounced `settings.json` write → WT reloads font.
5. **Enter** → "Save tuned 'eva'?" → choose **Save As** → "eva-night".
6. `Save-TunedStyle` writes `styles/eva-night/{scheme.json, theme.json, profile.ps1, tune.json}` to the user dir.
7. The adjusted look stays in `settings.json`; `current-style.ps1` updated + dot-sourced (prompt/banner = eva's). Done.
8. `tstyles list` now shows `eva` and `* eva-night`; `tstyles tune eva-night` resumes the sliders at −0/+? etc.

### Reopen a tuned style

1. `tstyles tune eva-night` → resolve `eva-night` (user dir). It has a `tune.json` (`base: eva`) → load **eva's pristine scheme** as the working base, seed sliders from the stored deltas (−15 / +10 / 85% / font / size).
2. Adjust further; live recompute is `Get-AdjustedScheme(evaPristine, currentDeltas)`. `R` → neutral returns to eva's original look. Re-save: **Save** overwrites `eva-night` and re-bakes from eva + the new deltas, keeping `tune.json.base = eva`.

### Cancel

1. Any time → **Esc** → `settings.json` restored to the exact snapshot bytes; window title restored; "Reverted." No files written to the user dir.

## Error handling

| Failure | Behavior |
|---|---|
| `tstyles tune` with no active/recognizable style | Error: `No active style detected. Try: tstyles tune <name>` and return before the loop. |
| `tstyles tune <name>` where `<name>` doesn't resolve | `Write-Error "Style '<name>' not found. Run 'tstyles list'."` |
| No WT `settings.json` found | `Write-Error` and return before the loop (picker parity). |
| Not inside Windows Terminal (`$env:WT_SESSION` unset) | Warn that live preview won't render; still allow tuning + save. |
| `System.Drawing` unavailable / font enumeration throws | `Get-MonospaceFontList` falls back to `@('Consolas')` + the current font. Tuner still works. |
| Malformed hex in a base scheme slot | `Convert-HexAdjust` passes it through unchanged; other slots still adjust. |
| User-dir write fails on save (permissions/AV) | Yellow warning; the adjusted look stays applied in `settings.json`; function returns without crashing. The user keeps the live result even if persistence failed. |
| Esc / exception mid-loop | `try/finally` restores original `settings.json` bytes and cursor/title visibility (picker pattern). |
| Save-As name invalid (empty / bad chars) | Re-prompt with a one-line reason; Esc at the name prompt returns to tuning. |
| Save-As name shadows a bundled name | Warn `That shadows bundled '<name>'. Continue? [y/N]`; proceed only on yes. |

## Testing

### Automated (Pester 5, `InModuleScope TerminalStyles`)

- **`Get-AdjustedScheme`** (core):
  - Brightness +100 pushes a mid-gray toward white; −100 toward black; 0 is identity.
  - Saturation −100 makes every slot gray (R=G=B); +100 increases vividness, clamped.
  - Clamps never produce out-of-range hex; output always 6-digit hex.
  - Missing slots skipped; non-color props (`name`) preserved verbatim; input object not mutated.
  - Malformed hex passed through unchanged.
- **`Get-SchemeOscPacket`**: output equals the byte string the picker produced inline before extraction (parity fixture).
- **`Get-MonospaceFontList`**: with a mocked installed set, returns allowlist ∩ installed; `$Current` always present and first; empty install → `Consolas` fallback.
- **`Save-TunedStyle`**: writes the four files to `$DataRoot\styles\<name>\`; `scheme.json` `name` == save name; `tune.json` round-trips all fields; Save (overwrite) vs Save-As (new name) land in the right folder. Mock `$DataRoot` to `$TestDrive`.

### Manual (inside Windows Terminal)

- `tstyles tune eva`: arrow through all five knobs; confirm colors retint instantly, opacity/font follow a beat later; Esc reverts byte-exact.
- Save As "eva-night"; confirm it appears in `tstyles list`, the picker, and `tstyles tune eva-night` resumes sliders.
- Confirm `eva-night` shows eva's background (inheritance).
- `tstyles tune` (no arg) on an active style; on a fresh shell with no active style → friendly error.

CI: extends the existing Pester run; new test files add to the suite total. CI still runs pwsh 7 on `windows-latest` (a WinPS 5.1 leg is a separate, out-of-scope improvement).

## Known limitations

- **Interactive loop is not unit-tested** — same as the picker. Coverage comes from the pure helpers (`Get-AdjustedScheme`, `Get-SchemeOscPacket`, `Get-MonospaceFontList`, `Save-TunedStyle`); the keypress loop is exercised manually.
- **Opacity/font lag a beat** — inherent to the platform (no OSC for those); they ride the debounced `settings.json` write, like the picker's non-color fields.
- **Monospace detection is allowlist-based** — a genuinely-installed mono font not on the curated list won't appear in the cycle. Mitigation: the style's current font is always included; the allowlist is easy to extend.
- **Reopen re-derives from the base, not the baked file** — the tuner reloads the pristine base scheme recorded in `tune.json` and re-applies the remembered deltas, so `R` returns to the true base look. If the recorded base style no longer exists (deleted/renamed), the tuner falls back to the saved baked scheme with neutral sliders.
- **No 2nd-positional tab completion** — `tstyles tune <TAB>` doesn't complete style names in v1 (only the `tune` subcommand itself completes). Future polish.
- **Background inheritance recurses one level** — a tuned style's base is expected to be a real (bundled or user) style with its own background, not another tuned style. Tuning a tuned style still works; background just resolves via the recorded base chain one hop.
