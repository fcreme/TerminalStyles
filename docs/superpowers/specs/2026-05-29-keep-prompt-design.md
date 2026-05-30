# `-KeepPrompt`: Apply a Style's Visuals Without Touching Your Prompt (Design)

**Date:** 2026-05-29
**Status:** Approved (brainstorming)
**Target version:** TerminalStyles 0.5.0

## Goal

Applying a style does two separable things: it writes the **visuals** (color
scheme, cursor, font, opacity, background) into Windows Terminal's
`settings.json`, and it installs the style's **prompt/banner** by copying the
style's `profile.ps1` to `current-style.ps1` (dot-sourced on shell start). The
second part overrides whatever prompt the user already has — which is a problem
for the large population running **Oh My Posh** or **Starship**: they want a
theme's palette/background but not its prompt, and today applying a style
clobbers their prompt (whichever of the two defines `function global:prompt`
last in `$PROFILE` wins).

Add a `-KeepPrompt` flag that applies the full visual look while leaving the
prompt entirely alone, so a custom prompt engine stays in control.

`apply.ps1` already exposes this exact capability as `-NoProfile`
(`apply.ps1:21,236`). This design brings it to the interactive `tstyles <name>`
command and **standardizes the name to `-KeepPrompt`** across both surfaces
(with `-NoProfile` kept as a back-compatible alias on `apply.ps1`).

## Non-goals (YAGNI)

- **Not** the interactive picker or `tstyles random` — the picker is for
  previewing the *full* look; `-KeepPrompt` is a deliberate direct-apply choice.
- No new "colors-only minus background/font" mode — `-KeepPrompt` applies the
  complete visual look (palette, cursor, font, opacity, background) and only
  skips the prompt (this was the explicit scope decision).
- No scheme-name-based active-style detection (see Known limitation).

## Behavior

`tstyles eva -KeepPrompt`:
- All visuals apply exactly as a normal `tstyles eva` (palette, cursor, font,
  opacity, background) — `Merge-StyleIntoSettings` is untouched.
- **No TerminalStyles prompt is imposed.** Any existing `current-style.ps1` is
  removed, eva's `profile.ps1` is not copied, and the live dot-source is
  skipped. Result: a deterministic "no TerminalStyles prompt" state — your Oh
  My Posh / Starship / default prompt stays in full control, regardless of what
  you applied before.

`apply.ps1 -KeepPrompt` (or the back-compat `-NoProfile`): visuals apply; the
profile-install block is skipped (its existing `-NoProfile` behavior, unchanged).

## Architecture

### `tstyles <name> -KeepPrompt` (the new surface)

1. **`Invoke-TerminalStyle`** gains `[switch]$KeepPrompt` and threads it into the
   direct-apply dispatch:
   ```powershell
   Apply-StyleDirect -StyleName $Arg -Target $Target `
       -BackgroundImage $BackgroundImage -BackgroundImageProvided $bgProvided `
       -KeepPrompt:$KeepPrompt
   ```
2. **`Apply-StyleDirect`** gains `[switch]$KeepPrompt`. Its existing prompt block
   (`tstyles.ps1:684-690`) changes from:
   ```powershell
   if ($isPwshTarget) {
       if (Test-Path -LiteralPath $styleProfile) {
           Copy-Item -LiteralPath $styleProfile -Destination $script:TStylesCurrent -Force
       } elseif (Test-Path -LiteralPath $script:TStylesCurrent) {
           Remove-Item -LiteralPath $script:TStylesCurrent -Force
       }
   }
   ```
   to:
   ```powershell
   if ($isPwshTarget) {
       if (-not $KeepPrompt -and (Test-Path -LiteralPath $styleProfile)) {
           Copy-Item -LiteralPath $styleProfile -Destination $script:TStylesCurrent -Force
       } elseif (Test-Path -LiteralPath $script:TStylesCurrent) {
           Remove-Item -LiteralPath $script:TStylesCurrent -Force
       }
   }
   ```
   With `-KeepPrompt`, the first branch is false, so it always takes the
   "remove `current-style.ps1` if present" branch — clearing any prior
   TerminalStyles prompt. The subsequent live dot-source
   (`tstyles.ps1:698-700`) is naturally skipped because `current-style.ps1` no
   longer exists (its `Test-Path` guard is false). No change needed there.

### `apply.ps1` (rename existing flag, keep alias)

- Param `[switch]$NoProfile` → `[switch][Alias('NoProfile')]$KeepPrompt`
  (`apply.ps1:21`). Existing `-NoProfile` callers keep working via the alias.
- The one usage `if ($hasProfile -and -not $NoProfile)` (`apply.ps1:236`)
  becomes `if ($hasProfile -and -not $KeepPrompt)`.
- **Behavior is preserved** (skip the profile-install block). `apply.ps1` is a
  standalone script with its own profile handling and an established `-NoProfile`
  contract; this design does NOT add the "remove existing `current-style.ps1`"
  step there, to keep that contract byte-stable. (See the asymmetry note.)

### Behavioral asymmetry (documented, intentional)

- `tstyles <name> -KeepPrompt` **removes** any existing `current-style.ps1`
  (deterministic clear — it's the interactive style-switcher, where you'd expect
  switching to colors-only to drop a prior style's prompt).
- `apply.ps1 -KeepPrompt`/`-NoProfile` **skips installing** the prompt without
  removing an existing file (its shipped `-NoProfile` behavior; preserved for
  back-compat).

Both achieve the user-facing goal — "this apply does not impose a TerminalStyles
prompt." The difference only shows when a prior `current-style.ps1` already
exists, and matches each tool's nature (interactive switcher vs. one-shot script).

## Error handling / edge cases

- **Style has no `profile.ps1`** (e.g. forest, sober): behavior is already
  "remove `current-style.ps1` if present"; `-KeepPrompt` produces the same
  result. No special case.
- **Not a pwsh target** (`$isPwshTarget` false): the whole prompt block is
  skipped today; `-KeepPrompt` is a no-op there. Unchanged.
- The flag never affects `Merge-StyleIntoSettings`, so visuals are identical
  with or without it.

## Known limitation (documented)

Active-style detection (`tstyles current`, the `*` in `tstyles list`) is
prompt-based — `Get-CurrentStyleName` byte-compares `current-style.ps1` against
each style's `profile.ps1`. A `-KeepPrompt` apply removes `current-style.ps1`,
so `current`/`list` will report no active style even though the style's colors
are live. This is acceptable for v1 (the `-KeepPrompt` user cares about the look,
not prompt-based detection). Scheme-name-based detection (reading the active
profile's `colorScheme` from `settings.json`) is a possible future enhancement,
out of scope here.

## Testing

Unlike the picker/tuner key loops, `Apply-StyleDirect` is a directly-invocable
function — so this gets real automated coverage. Add to (or alongside)
`tests/Apply-StyleDirect-Backup.Tests.ps1` a `-KeepPrompt` group:

1. **Visuals still apply with `-KeepPrompt`:** after `Apply-StyleDirect
   -KeepPrompt`, the target profile's `colorScheme` / scheme is written into the
   (test) `settings.json` exactly as without the flag.
2. **Prompt is not installed:** with `-KeepPrompt`, the style's `profile.ps1` is
   NOT copied to `$script:TStylesCurrent` (set to a `$TestDrive` path).
3. **Existing `current-style.ps1` is removed:** pre-create
   `$script:TStylesCurrent`; after `Apply-StyleDirect -KeepPrompt` it no longer
   exists.
4. **Regression (no flag):** without `-KeepPrompt`, a style with a `profile.ps1`
   still copies it to `$script:TStylesCurrent` (existing behavior intact).

For `apply.ps1`: a lightweight param check that the script accepts both
`-KeepPrompt` and `-NoProfile` (alias resolves) and that the profile-install
gate references the renamed variable — verified by review + a parse/param check
(the script's full run is integration-level, like the picker).

## Documentation & version

- **README:** a short note under "Use" (or "Scriptable / non-interactive")
  showing `tstyles eva -KeepPrompt` for Oh My Posh / Starship users; mention the
  `apply.ps1 -KeepPrompt` equivalent.
- **`tstyles help`:** the direct-apply / `<style>` description can mention
  `-KeepPrompt`; `apply.ps1 -?` surfaces it automatically.
- **TerminalStyles.psd1:** `ModuleVersion` 0.4.2 → 0.5.0 (a feature → minor bump,
  per `docs/RELEASING.md`); ReleaseNotes describing `-KeepPrompt`.

## Decisions / judgment calls

- **Name `-KeepPrompt`, alias `-NoProfile` on apply.ps1.** Chosen over reusing
  `-NoProfile` everywhere (collides with `pwsh -NoProfile`) and over `-NoPrompt`
  (mechanism vs. intent). Alias preserves apply.ps1 back-compat.
- **`tstyles` clears `current-style.ps1`; apply.ps1 preserves its skip-only
  behavior.** Asymmetry is intentional and documented (see above).
- **Direct-apply + apply.ps1 only**, not the picker/random (YAGNI).
- **Detection gap accepted for v1** (documented), not solved with scheme-based
  detection.
