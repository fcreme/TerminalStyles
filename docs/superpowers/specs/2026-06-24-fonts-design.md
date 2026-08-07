# On-demand coding-font installer — design

**Date:** 2026-06-24
**Status:** Approved (pending spec review)
**Component:** `tstyles.ps1` (+ a new `fonts.json` manifest), TerminalStyles PowerShell module

## Context

`tstyles tune` already cycles fonts in real time, but only over fonts **already
installed** on the machine (`Get-MonospaceFontList` enumerates installed monospace
families). There is no way to obtain a font the user doesn't have. The request:
let users get great coding fonts from within TerminalStyles, and improve the font
UX generally.

Key constraints learned during design:
- Per-user font install on Windows 10 1809+ needs **no admin** (copy to
  `%LOCALAPPDATA%\Microsoft\Windows\Fonts` + register under `HKCU`).
- The **PSGallery install path cannot run install-time logic** (PowerShell modules
  have no install hook). Only the bootstrap `install.ps1` runs code at install. So
  any "fonts arrive automatically" behavior must not depend on install-time hooks,
  or it would silently skip every PSGallery user.
- Windows Terminal can only preview a font that is **already installed** — so
  "installable fonts in the tuner" inherently means install-then-preview.

## Goal

Let users install curated coding fonts on demand from official sources, apply them,
and have them appear automatically in the existing tuner — consistently across both
install paths, opt-in, and without bloating install.

## Scope / non-goals

**In scope:**
- A curated font catalog manifest (`fonts.json`) pointing at official upstream downloads.
- A shared install core (catalog → download+verify → per-user install).
- A `tstyles font` command (list + `tstyles font <name>` install+apply).
- A one-time, opt-in first-run prompt offering to install the recommended set.
- Tests for all testable units; cross-engine (PS 7 + Windows PowerShell 5.1).

**Out of scope (future):**
- Font uninstall.
- Nerd Font patched variants (very large archives).
- In-tuner one-keypress install (the tuner's untested ReadKey loop should be made
  testable first, mirroring the picker work).
- Saving the chosen font into a tuned style (`tstyles tune` already bakes fonts).

**The tuner needs no changes:** once a font is installed (via the command or the
first-run prompt), it appears automatically in the tuner's existing live cycling,
because the tuner enumerates installed fonts.

## The catalog — `fonts.json`

Shipped with the module (repo root), added to the `publish.ps1` allowlist. Tiny.

Schema (one object per offered font):
```json
{
  "fonts": [
    {
      "name": "JetBrains Mono",
      "family": "JetBrains Mono",
      "license": "OFL-1.1",
      "url": "https://github.com/JetBrains/JetBrainsMono/releases/download/v2.304/JetBrainsMono-2.304.zip",
      "sha256": "<lowercase-hex>",
      "files": ["fonts/ttf/JetBrainsMono-Regular.ttf", "fonts/ttf/JetBrainsMono-Bold.ttf"]
    }
  ]
}
```
- `name` — catalog key + display name (matches `tstyles font <name>` and tab-completion).
- `family` — the value written to Windows Terminal's `font.face`, and what
  `Test-FontInstalled` checks.
- `license` — informational (shown in the list); only OFL/Apache/permissive fonts
  are offered.
- `url` — the **official, version-pinned** upstream download (a `.zip` or a direct
  `.ttf`/`.otf`).
- `sha256` — integrity gate for the download.
- `files` — archive-internal paths of the font files to install (omit/ignored for a
  direct-file `url`).

**Starter set** (all permissive, official downloads): JetBrains Mono, Fira Code,
Cascadia Code, Hack, Source Code Pro, IBM Plex Mono. Extend by adding rows — no code
change.

## Components / module boundaries (small, testable units)

- `Get-FontCatalog` — read + parse `fonts.json` from the module dir; validate
  required fields; return the list of font entries. Test seam: `-Path`.
- `Test-FontInstalled` — is `family` among installed families? Reuses
  `InstalledFontCollection`. Test seam: `-Installed <string[]>`; case-insensitive.
- `Resolve-FontPackage` — given a font entry: download `url` to the cache, **verify
  SHA-256** (`Get-FileHash`), extract the listed `files` (`System.IO.Compression`).
  Returns the local paths of the font files ready to install. Cached under
  `%LOCALAPPDATA%\TerminalStyles\fonts\<name>\`. Hash mismatch / missing archive
  entry → throw (no partial state). Test seams: `-DownloadPath` (skip network) so a
  fixture archive + known hash can drive it.
- `Get-UserFontInstallPlan` (pure) — given font file paths, compute the destination
  paths in `%LOCALAPPDATA%\Microsoft\Windows\Fonts` and the HKCU registry value
  names (`"<face name> (TrueType)"` / `(OpenType)` by extension). Fully unit-testable.
- `Install-Font` — thin, side-effecting: copy files to the per-user font dir, write
  the HKCU registry values from the plan, best-effort `WM_FONTCHANGE` broadcast.
  Kept minimal; its decisions live in `Get-UserFontInstallPlan`.
- `Set-ProfileFont` — set the target profile's `font.face` (the `font` object WT
  uses, as `New-TunedThemeObject` does) in `settings.json` via the existing
  `Write-SettingsAtomic` (+ rolling `.bak`). Missing target → clean error, no write.
- `Show-FontList` — render the catalog with `✓` (installed) / `↓` (installable)
  markers + license + a hint. Test seam: injected catalog + installed list.
- `Invoke-TerminalStyleFont` — command dispatch for `tstyles font [name]`.
- `Test-ShouldPromptFonts` (pure) — first-run gate: marker absent AND interactive
  session. Test seam: `-MarkerPresent`, `-Interactive`.
- `Invoke-FontFirstRunPrompt` — thin: if `Test-ShouldPromptFonts`, ask
  `"Install a set of recommended coding fonts now? [y/N]"` (default No), install the
  catalog set on yes via the shared core, then write the marker (regardless of
  answer, so it never repeats).

## Install flow (`tstyles font <name>`)

1. `Get-FontCatalog`; resolve `<name>` (unknown → clean error listing valid names).
2. `Test-FontInstalled $family`: if present, skip to step 5.
3. `Resolve-FontPackage` — download → verify SHA-256 → extract.
4. `Install-Font` — per-user copy + HKCU registry + `WM_FONTCHANGE`.
5. `Set-ProfileFont` — apply `font.face = family` to the active profile; print the
   live-reload hint (open a new tab / reload).

`tstyles font` (no arg) → `Show-FontList` (plain list, v1; an interactive picker
reusing `Invoke-StylePickerLoop` is a later option).

## First-run opt-in prompt

- Trigger: the first time `tstyles` runs **interactively**, gated by a marker file
  `%LOCALAPPDATA%\TerminalStyles\.fonts-prompted` (same pattern as the update-check
  throttle markers). Fires at the top of `Invoke-TerminalStyle`.
- Prompt: `Install a set of recommended coding fonts now? [y/N]` — **default No**.
- On yes: install the starter catalog set via the shared core, reporting progress.
- Always write the marker afterward (yes or no) so it never repeats.
- Non-interactive sessions (CI, scripts) and the marker-present case skip silently.
- Works on both PSGallery and bootstrap installs (first-run runs regardless of how
  the module was installed).

## Cross-engine + safety

- All building blocks work on PowerShell 7 and Windows PowerShell 5.1
  (`Invoke-WebRequest`, `System.IO.Compression`, `Get-FileHash`, HKCU registry,
  `System.Drawing`).
- **SHA-256 verified before install** (carries the supply-chain discipline applied
  to the bootstrap installer). Fonts aren't executed, but integrity is still gated.
- Failure modes — unknown name, network error, hash mismatch, missing archive entry
  — produce a clear message and leave no partial install.
- Downloads cached under the data root for offline re-install (like the GIF cache).

## Testing strategy

- `Get-FontCatalog` — fixture manifest: valid parse; malformed/missing fields error.
- `Test-FontInstalled` — `-Installed` seam: case-insensitive present/absent.
- `Resolve-FontPackage` — build a tiny fixture `.zip` in `$TestDrive` with a known
  SHA-256: extracts listed files; wrong hash throws; missing entry throws;
  `-DownloadPath` bypasses network.
- `Get-UserFontInstallPlan` — pure: correct destination paths + registry value
  names (`(TrueType)` vs `(OpenType)` by extension).
- `Set-ProfileFont` — fixture settings: sets `font.face` on the target; missing
  target → no write / clean error; output is byte-safe UTF-8 no BOM.
- `Show-FontList` — marker logic (`✓`/`↓`) from injected catalog + installed list.
- `Test-ShouldPromptFonts` — gate truth table (marker × interactive).
- `Install-Font` and the actual `Read-Host`/registry writes are kept thin; their
  decision logic is extracted into the pure helpers above and tested there. The
  irreducible side effects get light coverage and manual verification.

## Assumed defaults (confirmed)

- `tstyles font` (no arg) = **plain list** for v1.
- First-run prompt fires on first interactive `tstyles` run, **default No**, once.

## Open items for the plan

- Pin exact upstream URLs + compute real SHA-256 values + the correct in-archive
  `files` paths for the 6 starter fonts (done during implementation against the live
  releases).
- Confirm the WT font object shape against `New-TunedThemeObject` (`font.face` /
  `font.weight`) so `Set-ProfileFont` matches the tuner.
