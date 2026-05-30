# `tstyles reset`: Revert a Profile to an Unstyled Default (Design)

**Date:** 2026-05-30
**Status:** Approved (brainstorming)
**Target version:** TerminalStyles 0.6.0

## Goal

Every TerminalStyles command puts a style *on* — apply, picker, random, tune,
`-KeepPrompt`. There is no first-class way to take one *off*. Today a user who
wants a clean, unstyled terminal back must hand-edit `settings.json` or hunt for
a `.bak` (the uninstall flow even says as much). Add `tstyles reset` to revert a
Windows Terminal profile to its unstyled default: strip the fields TerminalStyles
writes, drop the now-orphan color scheme, and restore the user's own prompt.

## Non-goals (YAGNI)

- **Not** a `.bak`-restore / undo-last-apply (explicitly rejected: that brings
  back whatever was there before — possibly another theme — and can't reach a
  clean state once the original is gone).
- **Not** apply.ps1 — `reset` is an interactive "undo my theming" action; the
  scriptable path doesn't need it for v1.
- **No** confirmation prompt — a rolling `.bak` is written first (recoverable),
  matching the existing `tstyles <name>` / `tstyles random` direct-apply UX.
- **Not** an aggressive "strip the profile entry down to name/guid" — reset only
  removes the specific fields TerminalStyles writes, so a user's hand-set profile
  fields are left untouched.

## Behavior

`tstyles reset` (active profile) or `tstyles reset -Target 'Ubuntu'`:
1. Writes the rolling `settings.json.bak` (same safety net as direct apply).
2. Strips the TerminalStyles field set from the target profile entry:
   `colorScheme`, `font`, `opacity`, `cursorShape`, and the four background
   fields (`backgroundImage`, `backgroundImageOpacity`,
   `backgroundImageStretchMode`, `backgroundImageAlignment`). Each is removed
   only if present (absent → no-op).
3. Reads the profile's current `colorScheme` name *before* stripping, then
   removes that named entry from `$Settings.schemes` — unless the name is empty
   or another profile still references it (safe cleanup, no orphan schemes).
4. Removes `current-style.ps1` so the user's own prompt is restored on the next
   shell (the same prompt-clear `-KeepPrompt` uses).
5. Prints a confirmation and notes that a new tab restores the default prompt.

After reset, the profile shows Windows Terminal's default colors/cursor/font/
background and the user's own prompt. `tstyles` commands still work.

## Architecture

### New function `Reset-StyleDirect`

Modeled on `Apply-StyleDirect` (the proven direct-mutation path — find settings,
roll `.bak`, mutate, `Write-SettingsFile`, handle prompt). Param `[string]$Target`.

Flow:
1. `Show-UpdateNoticeIfAvailable` (consistent preamble).
2. `$settingsPath = Find-WTSettingsPath`; error + return if not found (same
   message as apply).
3. Read settings (UTF8-no-BOM `ReadAllText` + `ConvertFrom-Json`); resolve
   `$Target` via the passed value, else `Get-CurrentWTProfileName` (same
   fallback as apply). If unresolved, the same auto-detect/Read-Host fallback as
   the picker, or error — match apply's behavior.
4. Write the rolling `.bak` (`Copy-Item "$settingsPath" "$settingsPath.bak"`,
   wrapped in the same try/catch-warns-and-continues as apply).
5. Resolve the profile entry: the `'defaults'` case (the `$Settings.profiles.defaults`
   object) or `$Settings.profiles.list | Where-Object name -eq $Target` — the
   same resolution `Merge-StyleIntoSettings` uses. If no entry, note "nothing to
   reset" and return.
6. Capture `$schemeName = $entry.colorScheme` (if present) before stripping.
7. Strip each field in the TerminalStyles theme-field set from `$entry`
   (`PSObject.Properties.Remove($name)` when present).
8. If `$schemeName` is non-empty AND no remaining profile (defaults or list)
   references it, remove it from `$Settings.schemes`.
9. `Write-SettingsFile`.
10. If `current-style.ps1` exists, remove it (restore the user's prompt). Print
    a confirmation + "open a new tab to restore your default prompt" note.

### Shared field-list constant (DRY)

`Merge-StyleIntoSettings` currently defines the background-field list inline
(`$bgFields`). Extract the field lists to module-scoped constants so apply and
reset share one source of truth and can't drift:

```powershell
$script:TStylesBgFields    = @('backgroundImage','backgroundImageOpacity',
                               'backgroundImageStretchMode','backgroundImageAlignment')
# The full set of profile fields TerminalStyles writes (and reset strips):
$script:TStylesThemeFields = @('colorScheme','font','opacity','cursorShape') + $script:TStylesBgFields
```

`Merge-StyleIntoSettings` is updated to reference `$script:TStylesBgFields` in
place of its inline `$bgFields` (behavior-preserving). `Reset-StyleDirect`
strips `$script:TStylesThemeFields`.

NOTE — verify against the bundled `theme.json` files during implementation: the
strip set must be the union of every field any bundled `theme.json` writes onto
a profile entry. The list above (colorScheme/font/opacity/cursorShape + 4 bg) is
the expected superset; the plan includes a step to grep the `styles/*/theme.json`
files and widen the constant if any other profile-level field is found (e.g.
`cursorColor`, `tabColor`), so reset fully inverts apply.

### Dispatch + completer + help

- `Invoke-TerminalStyle`: add `if ($Arg -eq 'reset') { Reset-StyleDirect -Target $Target; return }` in the subcommand block.
- Tab completer `$subcommands`: add `'reset'`.
- `Get-TerminalStyleHelpData`: add a `reset` entry (Usage `reset`, Summary
  "Revert a profile to its unstyled default", Detail + an example). The drift-
  guard test then requires it (good).

## Error handling / edge cases

- **Profile not a pwsh target:** still strips the visual fields; there's simply
  no `current-style.ps1` semantics tied to non-pwsh — the prompt clear runs the
  same (remove the file if present). No special case needed.
- **Profile already has none of the fields:** strip is a no-op; still writes the
  `.bak` and a "nothing to reset (already plain)" style note. Clean exit.
- **`settings.json` not found:** same error + return as apply.
- **Scheme referenced by another profile:** not removed (the reference check),
  so a shared scheme isn't yanked out from under another profile.
- **`.bak` write fails:** warn (yellow) and proceed, exactly as apply does.

## Known limitations (documented)

- After reset, `tstyles current` / the `*` in `tstyles list` report no active
  style — correct, because there is none (detection is prompt-based).
- Reset only removes the fields TerminalStyles writes. Profile fields the user
  set by hand are intentionally left intact (surgical, not a profile wipe).

## Testing

`Reset-StyleDirect` is directly invocable (like `Apply-StyleDirect`), so it gets
real automated coverage. New `tests/Reset-StyleDirect.Tests.ps1`, modeled on
`tests/Apply-StyleDirect-KeepPrompt.Tests.ps1` (override `$script:TStylesCurrent`
to a `$TestDrive` path; mock `Find-WTSettingsPath`, `Show-UpdateNoticeIfAvailable`,
`Get-CurrentWTProfileName`, `Write-SettingsFile`; build a fake settings object
with a styled profile + a scheme):

1. **Strips the theme fields:** a profile entry pre-populated with
   colorScheme/font/opacity/cursorShape/backgroundImage → after reset, none of
   those properties remain on the entry (assert via the object passed to
   `Write-SettingsFile`).
2. **Removes the orphan scheme:** the profile's `colorScheme` named scheme is
   gone from `$Settings.schemes` after reset.
3. **Keeps a shared scheme:** if a second profile also references that scheme,
   it is NOT removed.
4. **Clears current-style.ps1:** pre-create it → gone after reset.
5. **Writes the rolling .bak:** `.bak` exists with the prior contents (reuse the
   pattern from `Apply-StyleDirect-Backup.Tests.ps1`).
6. **Leaves hand-set fields alone:** a non-TerminalStyles field on the entry
   (e.g. `tabTitle`) survives reset.

Plus dispatch + completer tests (`tstyles reset` → `Reset-StyleDirect` with the
target; completer offers `reset`) and the help drift-guard naturally covers the
new `reset` topic.

## Documentation & version

- **README:** a short "Resetting / removing a style" note under Use, plus the
  Subcommands row `tstyles reset [-Target <name>]`. Cross-reference that it's the
  inverse of applying a style.
- **`tstyles help`:** `reset` entry via `Get-TerminalStyleHelpData`.
- **TerminalStyles.psd1:** `ModuleVersion` 0.5.0 → 0.6.0 (new subcommand →
  minor bump); ReleaseNotes.

## Decisions / judgment calls

- **Strip the known field set**, not a `.bak` restore (deterministic clean
  state) and not a name/guid-only wipe (surgical — preserves hand edits).
- **Remove the orphan scheme**, guarded by a "still referenced?" check.
- **No confirmation prompt**; rely on the rolling `.bak` (matches direct apply).
- **Extract the field lists to shared constants** so apply and reset can't drift
  — a small, in-scope cleanup of the code being touched.
- **tstyles only, not apply.ps1**, for v1 (YAGNI).
