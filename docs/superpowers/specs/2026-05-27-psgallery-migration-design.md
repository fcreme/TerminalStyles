# PSGallery Migration UX — Design (Sub-project C)

**Date:** 2026-05-27
**Status:** Approved (pending implementation)
**Author:** Felipe
**Part of:** PowerShell Gallery migration (sub-project C of A/B/C)
**Builds on:** [Sub-project A: module restructure](2026-05-27-module-restructure-design.md), [Sub-project B: first publish](2026-05-27-psgallery-first-publish-design.md)
**Target version:** `0.2.0` (minor bump — behavior change for data layout, transparent migration, no public-surface break)

## Problem

After Sub-projects A and B, `TerminalStyles 0.1.0` is published to PSGallery and any modern pwsh user can `Install-PSResource -Name TerminalStyles`. But:

1. **The README still tells everyone to `iwr | iex`** — the documented install path doesn't match the published-and-better one.
2. **State files break on PSResourceGet version upgrade.** `$script:TStylesRoot = $PSScriptRoot` puts `current-style.ps1`, `.installed-sha`, `.last-update-check`, and cached background images inside the per-version module directory. When `Update-PSResource` installs `0.1.1`, it lands in a sibling directory; the 0.1.0 directory (with all the user's state) is orphaned.
3. **`tstyles update`/`uninstall`** still run the iwr-based bootstrap flow. For PSGallery-installed users, this would redownload over the bootstrap location, not update the PSGallery copy.

Sub-project C addresses all three together so the user-facing story holds end-to-end: the README points at PSGallery, the published module's state persists across upgrades, and `tstyles update`/`uninstall` work correctly regardless of install path.

## Goals

- State files (`current-style.ps1`, `.installed-sha`, `.last-update-check`, cached `background.<ext>` files) live in a stable per-user data directory (`%LOCALAPPDATA%\TerminalStyles\`) that survives version upgrades.
- The data layout migrates transparently on first import of `0.2.0` for existing iwr-installed users — no manual action required, cached backgrounds are preserved.
- The README leads with `Install-PSResource -Name TerminalStyles`; the `iwr | iex` bootstrap is demoted to a fallback subsection for users without PSResourceGet.
- `tstyles update` and `tstyles uninstall` detect the install kind (PSResourceGet vs Bootstrap) and delegate to the appropriate mechanism (`Update-PSResource` / `Uninstall-PSResource` vs the existing iwr-based flow).
- `tstyles uninstall` preserves user state by default (so users can switch install paths without losing their active style). Add `-DeleteData` for a full wipe when actually desired.
- All 43 existing Pester tests continue to pass (with minor updates for the dual-root variable rename).
- 0.2.0 ships to PSGallery via the existing `scripts/publish.ps1` flow.

## Non-goals

- **No automated migration of $PROFILE.** Bootstrap users have an `Import-Module "$env:LOCALAPPDATA\TerminalStyles\TerminalStyles.psd1" -DisableNameChecking` line; PSGallery users add `Import-Module TerminalStyles -DisableNameChecking` themselves. Documented in README; no `tstyles register` subcommand.
- **No `tstyles migrate` subcommand** for active "switch install path." Users do it manually (`tstyles uninstall` → switch install method → install via the other path).
- **No version-aware notice for PSResourceGet users.** `Test-UpdateAvailable` (the throttled background check) keeps its today's SHA-comparison logic for Bootstrap users and returns `$null` for PSResourceGet users. PSGallery users update via `Update-PSResource` whenever they want; no daily notice. Could add `Find-PSResource`-based check in a future spec — YAGNI for now.
- **No `Apply-StyleDirect` rename** to satisfy approved-verb conventions. Still requires `-DisableNameChecking`. Future spec.
- **No GitHub Actions auto-publish.** Sub-project B explicitly opted for manual publish; that stays.
- **No automation for users with BOTH installs** (a Bootstrap install AND a PSGallery install simultaneously). Whichever loaded wins, the other is orphaned silently. README documents this.

## Sub-project context

Final piece of the A/B/C arc:

| Sub-project | Scope | Status |
|---|---|---|
| A | Module restructure (local-only) | Shipped (Sub-project A spec implemented) |
| B | First PSGallery publish | Shipped — `TerminalStyles 0.1.0` live |
| **C** (this spec) | State relocation + README rewrite + update/uninstall delegation | Pending |

After C ships as `0.2.0`, the user story is: `Install-PSResource -Name TerminalStyles` is the primary install; bootstrap installer is a documented fallback; updates and uninstalls Just Work for either install path.

## Architecture

Three pillars, all in one shipping cycle:

1. **Split `$script:TStylesRoot` into two roots.** `$script:TStylesModuleRoot` for read-only code/styles, `$script:TStylesDataRoot` for writable state. Transparent for Bootstrap users (both roots resolve to `%LOCALAPPDATA%\TerminalStyles\`); fixed for PSResourceGet users (state lives at `%LOCALAPPDATA%\TerminalStyles\`, code at `~\Documents\…\TerminalStyles\<version>\`).
2. **README install-section rewrite.** PSGallery primary, bootstrap fallback. Update sections also explain the auto-delegation in `tstyles update`/`uninstall`.
3. **Install-kind detection + delegation in `Invoke-TerminalStylesUpdate` / `Invoke-TerminalStylesUninstall`.** Path comparison (`$ModuleRoot == %LOCALAPPDATA%\TerminalStyles`) → Bootstrap; otherwise → PSResourceGet.

## File-by-file changes

### `tstyles.ps1`

**Initialization block (around lines 12-21)** — split the single root into two:

```powershell
# OLD:
$script:TStylesRoot = $PSScriptRoot
if (-not $script:TStylesRoot) {
    $script:TStylesRoot = Split-Path $MyInvocation.MyCommand.Path -Parent
}
$script:TStylesCurrent = Join-Path $script:TStylesRoot 'current-style.ps1'

# Auto-load
if (Test-Path -LiteralPath $script:TStylesCurrent) {
    . $script:TStylesCurrent
}

# NEW:
$script:TStylesModuleRoot = $PSScriptRoot
if (-not $script:TStylesModuleRoot) {
    $script:TStylesModuleRoot = Split-Path $MyInvocation.MyCommand.Path -Parent
}
# Data dir: stable across version upgrades, writable, shared between
# PSResourceGet-installed and bootstrap-installed copies. For bootstrap
# users this happens to equal $script:TStylesModuleRoot (backward-
# compatible); for PSResourceGet users it's a separate dir.
$script:TStylesDataRoot = Join-Path $env:LOCALAPPDATA 'TerminalStyles'
if (-not (Test-Path -LiteralPath $script:TStylesDataRoot)) {
    New-Item -ItemType Directory -Path $script:TStylesDataRoot -Force | Out-Null
}
$script:TStylesCurrent = Join-Path $script:TStylesDataRoot 'current-style.ps1'

# One-time data-layout migration for existing iwr-installed users
# whose cached backgrounds live inside the bundled styles/ dir.
# Idempotent; writes a marker file so it doesn't re-run.
Invoke-TerminalStylesStateMigration

# Auto-load the active style
if (Test-Path -LiteralPath $script:TStylesCurrent) {
    . $script:TStylesCurrent
}
```

**Reference rewrites** (mechanical find-and-replace):

| Old code | New code | Locations (approximate) |
|---|---|---|
| `Join-Path $script:TStylesRoot 'styles'` | `Join-Path $script:TStylesModuleRoot 'styles'` | `Get-AvailableStyles` (line ~287), `Apply-StyleDirect` (~468), `Invoke-TerminalStyle` picker setup (~630), tab completer (~1042) |
| `$script:TStylesRoot` for `.installed-sha` / `.last-update-check` | `$script:TStylesDataRoot` | `Test-UpdateAvailable` (~110, ~117), `Invoke-TerminalStylesUpdate` (~155) |
| Bare `$script:TStylesRoot` (state context) | `$script:TStylesDataRoot` | `Get-CurrentStyleName` (~297), `Test-StyleResolved` (~315) — wait, these reference `styles/` (module). Re-audit. |
| `$script:TStylesCurrent` (already an absolute path constant) | unchanged; now resolves to `$DataRoot\current-style.ps1` | several |

Full audit will be done in the implementation plan; spec captures the intent.

**`Get-StyleBundledBackground`** — cache writes go to `$DataRoot\cache\<name>\` instead of `$StyleDir\` (module-rooted):

```powershell
function Get-StyleBundledBackground {
    # Three-tier resolution:
    #   1. Bundled file under $ModuleRoot\styles\<name>\ (read-only)
    #   2. Cached file under $DataRoot\cache\<name>\ (writable, persistent)
    #   3. Lazy-fetch from gifs branch -> write to $DataRoot\cache\<name>\
    #
    # Negative cache marker (.no-background) lives in $DataRoot\cache\<name>\.
    param([Parameter(Mandatory)][string]$StyleDir)  # $StyleDir is under $ModuleRoot\styles\

    # 1. Bundled
    foreach ($ext in 'gif','png','jpg','jpeg') {
        $bundled = Join-Path $StyleDir "background.$ext"
        if (Test-Path -LiteralPath $bundled) { return $bundled }
    }

    # Cache dir for this style
    $styleName = Split-Path -Leaf $StyleDir
    $cacheDir  = Join-Path $script:TStylesDataRoot "cache\$styleName"

    # 2. Cached
    foreach ($ext in 'gif','png','jpg','jpeg') {
        $cached = Join-Path $cacheDir "background.$ext"
        if (Test-Path -LiteralPath $cached) { return $cached }
    }
    if (Test-Path -LiteralPath (Join-Path $cacheDir '.no-background')) { return $null }

    # 3. Lazy-fetch
    if (-not (Test-Path -LiteralPath $cacheDir)) {
        New-Item -ItemType Directory -Path $cacheDir -Force | Out-Null
    }
    $remoteBase = "https://raw.githubusercontent.com/fcreme/TerminalStyles/gifs/$styleName"
    # ... existing fetch loop, writing to $cacheDir instead of $StyleDir ...
    # ... existing negative-cache marker write to $cacheDir\.no-background ...
}
```

**`Test-StyleResolved`** — checks the cache dir, not the module's styles dir:

```powershell
function Test-StyleResolved {
    param([Parameter(Mandatory)][string]$StyleDir)
    $styleName = Split-Path -Leaf $StyleDir
    # Bundled?
    foreach ($ext in 'gif','png','jpg','jpeg') {
        if (Test-Path -LiteralPath (Join-Path $StyleDir "background.$ext")) { return $true }
    }
    # Cached?
    $cacheDir = Join-Path $script:TStylesDataRoot "cache\$styleName"
    foreach ($ext in 'gif','png','jpg','jpeg') {
        if (Test-Path -LiteralPath (Join-Path $cacheDir "background.$ext")) { return $true }
    }
    if (Test-Path -LiteralPath (Join-Path $cacheDir '.no-background')) { return $true }
    return $false
}
```

**New helper: `Get-TerminalStylesInstallKind`** — detect install path:

```powershell
function Get-TerminalStylesInstallKind {
    # Returns 'Bootstrap' if the module loaded from %LOCALAPPDATA%\TerminalStyles\
    # (the iwr-installer path), else 'PSResourceGet' (PSModulePath-based install).
    # Used by Invoke-TerminalStylesUpdate / Invoke-TerminalStylesUninstall to
    # delegate to the right mechanism.
    $bootstrapDir = Join-Path $env:LOCALAPPDATA 'TerminalStyles'
    if ($script:TStylesModuleRoot -eq $bootstrapDir) { return 'Bootstrap' }
    return 'PSResourceGet'
}
```

**New helper: `Invoke-TerminalStylesStateMigration`** — one-time data-layout migration:

```powershell
function Invoke-TerminalStylesStateMigration {
    # Migrates pre-0.2.0 data layout to 0.2.0:
    #   - Cached background.<ext> files move from $ModuleRoot\styles\<name>\
    #     to $DataRoot\cache\<name>\.
    #   - .no-background markers move similarly.
    # Idempotent. Skips work if marker exists.
    $marker = Join-Path $script:TStylesDataRoot '.migrated-0.2.0'
    if (Test-Path -LiteralPath $marker) { return }

    $stylesDir = Join-Path $script:TStylesModuleRoot 'styles'
    if (-not (Test-Path -LiteralPath $stylesDir)) {
        # No styles dir to migrate from (clean PSGallery install). Mark done.
        New-Item -ItemType File -Path $marker -Force | Out-Null
        return
    }

    foreach ($styleDir in Get-ChildItem -LiteralPath $stylesDir -Directory) {
        $styleName = $styleDir.Name
        $cacheDir = Join-Path $script:TStylesDataRoot "cache\$styleName"

        # Move backgrounds
        foreach ($ext in 'gif','png','jpg','jpeg') {
            $src = Join-Path $styleDir.FullName "background.$ext"
            if (Test-Path -LiteralPath $src) {
                if (-not (Test-Path -LiteralPath $cacheDir)) {
                    New-Item -ItemType Directory -Path $cacheDir -Force | Out-Null
                }
                $dest = Join-Path $cacheDir "background.$ext"
                try {
                    Move-Item -LiteralPath $src -Destination $dest -Force -ErrorAction Stop
                } catch {
                    # If the source dir is read-only (PSGallery install), skip --
                    # there's nothing to migrate there. For bootstrap installs the
                    # source dir is writable.
                }
            }
        }

        # Move negative-cache markers
        $srcMarker = Join-Path $styleDir.FullName '.no-background'
        if (Test-Path -LiteralPath $srcMarker) {
            if (-not (Test-Path -LiteralPath $cacheDir)) {
                New-Item -ItemType Directory -Path $cacheDir -Force | Out-Null
            }
            try {
                Move-Item -LiteralPath $srcMarker -Destination (Join-Path $cacheDir '.no-background') -Force -ErrorAction Stop
            } catch { }
        }
    }

    New-Item -ItemType File -Path $marker -Force | Out-Null
}
```

**`Invoke-TerminalStylesUpdate`** — delegate based on install kind:

```powershell
function Invoke-TerminalStylesUpdate {
    [CmdletBinding()]
    param([switch]$Force)

    Write-Host ""
    Write-Host "Updating TerminalStyles..." -ForegroundColor Cyan

    switch (Get-TerminalStylesInstallKind) {
        'PSResourceGet' {
            try {
                Update-PSResource -Name TerminalStyles -TrustRepository -ErrorAction Stop
                Write-Host ""
                Write-Host "Update complete. To use the new version in THIS session," -ForegroundColor Yellow
                Write-Host "open a new tab, or run:" -ForegroundColor Yellow
                Write-Host "  Import-Module TerminalStyles -Force -DisableNameChecking" -ForegroundColor Cyan
            } catch {
                Write-Host "Update failed: $_" -ForegroundColor Red
                Write-Host "You can retry manually:" -ForegroundColor Yellow
                Write-Host "  Update-PSResource -Name TerminalStyles -TrustRepository" -ForegroundColor Cyan
            }
        }
        'Bootstrap' {
            # Existing iwr-based update flow — unchanged.
            # ... existing body ...
        }
    }
}
```

**`Invoke-TerminalStylesUninstall`** — delegate based on install kind, with optional `-DeleteData`:

```powershell
function Invoke-TerminalStylesUninstall {
    [CmdletBinding()]
    param(
        [switch]$DeleteData      # also remove %LOCALAPPDATA%\TerminalStyles\ (user state)
    )

    # ... existing confirm prompt ...

    $kind = Get-TerminalStylesInstallKind
    Write-Host "  Detected install kind: $kind" -ForegroundColor Gray

    switch ($kind) {
        'PSResourceGet' {
            try {
                Uninstall-PSResource -Name TerminalStyles -ErrorAction Stop
                Write-Host "  Removed module via Uninstall-PSResource" -ForegroundColor Green
            } catch {
                Write-Host "  Uninstall-PSResource failed: $_" -ForegroundColor Red
            }
            # Strip $PROFILE loader (existing logic — unchanged)
        }
        'Bootstrap' {
            # Strip $PROFILE loaders (existing logic — unchanged)
            # Remove install-managed files ONLY; preserve data dir unless -DeleteData
            $installDir = Join-Path $env:LOCALAPPDATA 'TerminalStyles'
            $installManagedItems = @(
                'tstyles.ps1', 'apply.ps1', 'install.ps1',
                'TerminalStyles.psd1', 'TerminalStyles.psm1',
                'styles', 'scripts',
                'README.md', 'LICENSE'
            )
            foreach ($item in $installManagedItems) {
                $path = Join-Path $installDir $item
                if (Test-Path -LiteralPath $path) {
                    Remove-Item -LiteralPath $path -Recurse -Force -ErrorAction SilentlyContinue
                }
            }
            Write-Host "  Removed install-managed files from $installDir" -ForegroundColor Green
            Write-Host "  Preserved user state (current-style.ps1, cache/, .last-update-check, .installed-sha)" -ForegroundColor Gray
        }
    }

    if ($DeleteData) {
        $dataDir = Join-Path $env:LOCALAPPDATA 'TerminalStyles'
        if (Test-Path -LiteralPath $dataDir) {
            Remove-Item -LiteralPath $dataDir -Recurse -Force
            Write-Host "  Removed $dataDir (full wipe via -DeleteData)" -ForegroundColor Green
        }
    } else {
        Write-Host ""
        Write-Host "  User state preserved at $((Join-Path $env:LOCALAPPDATA 'TerminalStyles'))" -ForegroundColor Gray
        Write-Host "  Pass -DeleteData to remove that too." -ForegroundColor Gray
    }

    # ... existing closing messages ...
}
```

**`Test-UpdateAvailable`** — short-circuit to `$null` for PSResourceGet users:

```powershell
function Test-UpdateAvailable {
    # For PSResourceGet installs, the SHA-based check isn't meaningful
    # (users update via Update-PSResource, not git). Skip the API call
    # entirely and let users run `tstyles update` whenever they want.
    if ((Get-TerminalStylesInstallKind) -eq 'PSResourceGet') { return $null }

    # ... existing Bootstrap-path body (24h throttle + SHA compare) ...
}
```

**`Set-Alias` and `Register-ArgumentCompleter`** at the bottom of `tstyles.ps1` — unchanged.

**Manifest bump**: `TerminalStyles.psd1` `ModuleVersion = '0.1.0'` → `'0.2.0'`. `ReleaseNotes` updated to describe the data-layout migration + update/uninstall delegation.

### `README.md`

**Replace `## Install` section** (currently lines ~36-43):

```markdown
## Install

```powershell
Install-PSResource -Name TerminalStyles
Import-Module TerminalStyles -DisableNameChecking
```

Add the `Import-Module` line to your `$PROFILE` so it loads on every
new shell tab. Then:

```powershell
tstyles
```

Arrow keys preview each style live, Enter keeps it, Esc cancels.

### Alternate: bootstrap installer

For setups without [PSResourceGet](https://learn.microsoft.com/en-us/powershell/module/microsoft.powershell.psresourceget/)
(rare on modern Windows; ships natively in pwsh 7.4+), use the
bootstrap one-liner installer instead. It also auto-registers the
loader in your `$PROFILE`:

```powershell
iwr -useb https://raw.githubusercontent.com/fcreme/TerminalStyles/main/install.ps1 | iex
```

This downloads to `%LOCALAPPDATA%\TerminalStyles\`. The bootstrap
install and the PSGallery install can coexist — whichever is loaded
in your `$PROFILE` wins.
```

**Replace `## Updating` section** (currently lines ~300-336):

```markdown
## Updating

```powershell
tstyles update
```

`tstyles update` detects how the module was installed and delegates
to the right mechanism:

- **PSGallery (`Install-PSResource`)** → runs `Update-PSResource -Name TerminalStyles`.
- **Bootstrap (`iwr | iex`)** → re-runs the bootstrap one-liner.

After update, open a new tab (or `Import-Module TerminalStyles -Force -DisableNameChecking`) for the new version to take effect.

### How the update check works

For **bootstrap** installs only, `tstyles` issues at most one
unauthenticated HTTP GET per 24 hours per machine to
`api.github.com/repos/fcreme/TerminalStyles/commits/main` (capped at
2 seconds) and prints a one-line yellow notice if your install is
behind. PSGallery-installed copies skip this check entirely — run
`tstyles update` whenever you want; `Update-PSResource` handles the
version comparison internally.

The 24h throttle is tracked in
`%LOCALAPPDATA%\TerminalStyles\.last-update-check`.
```

**Replace `## Uninstalling` section** (currently lines ~338-363):

```markdown
## Uninstalling

```powershell
tstyles uninstall
```

`tstyles uninstall` detects how the module was installed and delegates:

- **PSGallery** → runs `Uninstall-PSResource -Name TerminalStyles` +
  strips the `Import-Module` loader from your `$PROFILE`.
- **Bootstrap** → removes the install-managed files from
  `%LOCALAPPDATA%\TerminalStyles\` (script files, bundled styles)
  and strips the loader.

**Either path preserves your user state by default** — your active
style (`current-style.ps1`), update-check throttle, and cached
background images stay at `%LOCALAPPDATA%\TerminalStyles\`. This
means you can reinstall (either path) and pick up where you left off.

To also remove the user state, pass `-DeleteData`:

```powershell
tstyles uninstall -DeleteData
```

Neither path modifies Windows Terminal's `settings.json` — your
current color scheme / cursor / background stays whatever it was
last set to.
```

**Append a short note under `## Known limitations`** about install-path coexistence and the data dir:

```markdown
- **User state lives at `%LOCALAPPDATA%\TerminalStyles\`** regardless
  of install method. This dir holds your active style, cached
  background images, and the update-check throttle. It survives
  uninstall (unless you pass `-DeleteData`) and version upgrades.
- **Bootstrap + PSGallery installs can coexist.** If you've run both,
  whichever your `$PROFILE` loads first wins; the other is orphaned
  silently. To clean up: `tstyles uninstall` removes whichever is
  currently loaded; run it twice to clean both, switching shells
  between runs if needed.
```

### Pester tests

All three test files set `$script:TStylesRoot = $TestDrive` in `BeforeEach`. After the dual-root split, they become:

```powershell
$script:TStylesModuleRoot = $TestDrive
$script:TStylesDataRoot   = $TestDrive
# Mock install-kind detection. Without this, Get-TerminalStylesInstallKind
# would compare $TestDrive to %LOCALAPPDATA%\TerminalStyles, not match,
# and return 'PSResourceGet' -- which makes Test-UpdateAvailable
# short-circuit to $null and breaks the throttle tests.
Mock Get-TerminalStylesInstallKind { 'Bootstrap' }
```

Same `$TestDrive` for both — exercises the iwr-style case where the two roots coincide. The `Mock` keeps tests deterministic regardless of where `$TestDrive` happens to land on the CI runner.

Add a new file `tests/Get-TerminalStylesInstallKind.Tests.ps1` (3 tests: ModuleRoot == `%LOCALAPPDATA%\TerminalStyles` → Bootstrap; ModuleRoot under PSModulePath → PSResourceGet; pure path comparison so no need to mock `Get-PSResource`). Small but high-leverage for the delegation logic.

Total Pester after Sub-project C: 43 existing + 3 new = 46.

### `apply.ps1`

**No change.** It's a standalone script with its own copies of `Find-WTSettingsPath` etc. It doesn't use `$script:TStylesRoot`. Out of scope.

### `install.ps1`

**No change.** It's the bootstrap installer. After 0.2.0, fresh bootstrap installs end up with the new tstyles.ps1, which uses `$DataRoot` correctly out of the box. No installer-side migration needed.

### `scripts/publish.ps1`

**No change.** Allowlist already includes everything needed. Publishing 0.2.0 is just a manifest version bump + run the existing script.

### `scripts/capture-screenshots.ps1`

**No change** (it doesn't reference state files).

## Data flow

### New PSGallery user (post-0.2.0)

1. `Install-PSResource -Name TerminalStyles` → installs to `~\Documents\…\TerminalStyles\0.2.0\`.
2. User adds `Import-Module TerminalStyles -DisableNameChecking` to `$PROFILE`.
3. On import: `$ModuleRoot = ~\Documents\…\TerminalStyles\0.2.0\`. `$DataRoot = %LOCALAPPDATA%\TerminalStyles\` (auto-created). `Invoke-TerminalStylesStateMigration` runs: no `$ModuleRoot\styles\<name>\background.<ext>` files exist (fresh PSGallery install ships no cached backgrounds) → migration is a no-op. Marker file written.
4. User runs `tstyles`. Picker launches. Theme selected → `current-style.ps1` written to `$DataRoot`. Background lazy-fetched to `$DataRoot\cache\<theme>\`.
5. Later, `tstyles update` → detects PSResourceGet → runs `Update-PSResource -Name TerminalStyles`. New version installs to a sibling dir; user opens new tab, `$DataRoot` state is intact.
6. `tstyles uninstall` → detects PSResourceGet → runs `Uninstall-PSResource` + strips `$PROFILE` loader. `$DataRoot` is preserved (user could `Install-PSResource` again and get their style back).

### Existing iwr-installed user upgrading to 0.2.0

1. User runs `tstyles update` on 0.1.0 → detects Bootstrap → re-runs `iwr | iex`. New `tstyles.ps1` lands at `%LOCALAPPDATA%\TerminalStyles\`. `current-style.ps1` preserved (installer's existing logic).
2. User opens new tab, `$PROFILE` runs `Import-Module $env:LOCALAPPDATA\TerminalStyles\TerminalStyles.psd1 -DisableNameChecking`.
3. On import: `$ModuleRoot = $DataRoot = %LOCALAPPDATA%\TerminalStyles\`. `Invoke-TerminalStylesStateMigration` runs: finds cached `background.<ext>` files under `$ModuleRoot\styles\<name>\` → moves each to `$DataRoot\cache\<name>\background.<ext>` (same root path, just to the `cache/` subdir). Marker file written.
4. User runs `tstyles list`. Same UX as before. Themes resolve through the new cache dir transparently.
5. `tstyles update` keeps working on the Bootstrap path. `tstyles uninstall` (without `-DeleteData`) leaves the user state intact.

### Iwr user switching to PSGallery

1. `tstyles uninstall` → Bootstrap path, removes install-managed files from `%LOCALAPPDATA%\TerminalStyles\`. Strips `$PROFILE` loader. Preserves `current-style.ps1` + `cache/` + state files.
2. `Install-PSResource -Name TerminalStyles`.
3. Add `Import-Module TerminalStyles -DisableNameChecking` to `$PROFILE`.
4. New shell tab loads the PSGallery copy. On import, `$DataRoot` still has the preserved state — user's previous theme is active immediately.

## Error handling

| Failure | Behavior |
|---|---|
| `$env:LOCALAPPDATA` unset or empty | Module initialization throws. Diagnostic: "`$env:LOCALAPPDATA` not set; can't determine data dir." User has bigger problems. |
| `$DataRoot` not writable | `New-Item` at init throws. Caught by `$ErrorActionPreference = 'Stop'` higher up. Module fails to import with a clear error. |
| `Invoke-TerminalStylesStateMigration` source-dir read-only (PSGallery install with stale leftover `background.<ext>` from a manual user copy) | Catch swallows `Move-Item` errors silently. The bundled file is still readable in place; it'll just not move to cache. Acceptable. |
| Migration partial (process killed mid-move) | Idempotent on re-run — no marker written, so it retries. Successfully-moved files are skipped (source doesn't exist). |
| `Update-PSResource` fails (network, repo not trusted) | Caught; user sees error + manual recovery command (`Update-PSResource -Name TerminalStyles -TrustRepository`). |
| `Uninstall-PSResource` fails (module locked) | Caught; user sees error. Loader strip still runs (independent step). |
| User has BOTH installs and runs `tstyles uninstall` | Cleans up the LOADED one only. README documents that they may need to run it twice (switching shells) to clean both. |
| User runs `tstyles uninstall -DeleteData` after switching to PSGallery, but bootstrap loader is still in WinPS 5.1 `$PROFILE` (uninstall ran from pwsh 7) | Loader strip runs against both engines' `$PROFILE` per existing logic. Same as today. |
| `Get-TerminalStylesInstallKind` returns wrong value (extremely unlikely, would mean `$ModuleRoot` doesn't match either expected pattern) | Wrong delegate runs. Update/uninstall fails with the wrong error. User can recover manually. Documented in troubleshooting (in `docs/RELEASING.md`'s maintainer notes, not user-facing). |

## Testing

Manual:

- **Fresh PSGallery install on a clean machine (or fresh shell):**
  ```powershell
  Install-PSResource -Name TerminalStyles -Scope CurrentUser -TrustRepository
  Import-Module TerminalStyles -DisableNameChecking
  tstyles
  ```
  Picker opens. Pick a theme → `current-style.ps1` lands at `%LOCALAPPDATA%\TerminalStyles\`. Verify with `Get-ChildItem %LOCALAPPDATA%\TerminalStyles\`.

- **Upgrade existing iwr install** (on the maintainer's machine, which has 0.1.0 bootstrap-installed via `iwr | iex`):
  ```powershell
  tstyles update          # delegates to Bootstrap path, re-runs iwr|iex with new 0.2.0
  . $PROFILE              # re-imports the upgraded module
  ```
  Then verify: `Get-ChildItem %LOCALAPPDATA%\TerminalStyles\cache\` exists with subdirs containing the moved backgrounds. `Get-ChildItem %LOCALAPPDATA%\TerminalStyles\styles\<theme>\` no longer has `background.<ext>` (moved out by migration).

- **Switch from bootstrap to PSGallery:**
  ```powershell
  tstyles uninstall       # preserves data
  Install-PSResource -Name TerminalStyles
  # Add Import-Module to $PROFILE manually
  Import-Module TerminalStyles -DisableNameChecking
  tstyles current         # should show the previously-active theme
  ```

- **`-DeleteData` full wipe:**
  ```powershell
  tstyles uninstall -DeleteData
  Test-Path %LOCALAPPDATA%\TerminalStyles  # False
  ```

- **`tstyles update` on PSGallery install:**
  After Sub-project C ships and is installed via PSGallery, bump version to 0.2.1 manually, publish. Then `tstyles update` should delegate to `Update-PSResource` and bring in 0.2.1. Verify with `Get-Module TerminalStyles | Select Version`.

Automated:

- Existing 43 Pester tests updated for dual-root variables and pass.
- New `tests/Get-TerminalStylesInstallKind.Tests.ps1` (3 tests): same path → Bootstrap; PSModulePath dir → PSResourceGet; round-trip with `InModuleScope`.

Total after Sub-project C: ~46 tests.

## Known limitations (carrying forward)

- **`Apply-StyleDirect` non-approved verb** still requires `-DisableNameChecking` on import. Future spec renames it.
- **No `Find-PSResource`-based version check** in the daily notice for PSGallery users. They run `tstyles update` blindly; the underlying `Update-PSResource` is a no-op if no update is available.
- **Manual $PROFILE registration** for PSGallery users (we don't auto-write the loader). README documents the one line to add. Could add a `tstyles register` subcommand in a future spec.
- **Both-installs simultaneous orphan.** No active reconciliation. Users have to clean up manually if they care.
- **Migration is one-way.** Once `cache/` exists, the old `styles/<name>/background.<ext>` paths are no longer checked first (after the migration marker is written). Reverting to a pre-0.2.0 version would not re-find the backgrounds at their old location. Not a real concern (no one downgrades).
