# `tstyles register` Subcommand — Design

**Date:** 2026-05-27
**Status:** Approved (pending implementation)
**Author:** Felipe
**Target version:** `0.2.2` (patch — purely additive)
**Builds on:** [Sub-project C: PSGallery migration UX](2026-05-27-psgallery-migration-design.md)

## Problem

After `Install-PSResource -Name TerminalStyles`, PSGallery users have to manually edit `$PROFILE` to add `Import-Module TerminalStyles -DisableNameChecking` so the module loads on every new shell tab. The README documents this (and we listed it as a known limitation in Sub-project C). It's friction the bootstrap installer doesn't have — `iwr | iex` auto-registers the loader in BOTH PowerShell engines' `$PROFILE` files.

A `tstyles register` subcommand closes the gap: PSGallery users (after the one-time `Install-PSResource` + `Import-Module` in their current shell) run `tstyles register` once and the loader is auto-added to both engines' `$PROFILE` files. Same outcome as the bootstrap installer, just a different entry point.

## Goals

- `tstyles register` adds the `Import-Module TerminalStyles -DisableNameChecking` line to BOTH `pwsh 7` and `Windows PowerShell 5.1` `$PROFILE` files (mirrors bootstrap installer behavior).
- The added block is wrapped in the existing `# ===== TerminalStyles BEGIN =====` / `# ===== TerminalStyles END =====` markers so `tstyles uninstall`'s regex strip continues to work unchanged.
- Idempotent: if the loader block already exists in a given engine's `$PROFILE`, the command says "already registered, skipping" rather than duplicating.
- `-Force` flag replaces an existing block (useful if loader content ever needs to change in a future version).
- Single confirm prompt up front shows what will be written and to which files, so the user sees the action before any disk write.
- README's `## Install` section updated to mention `tstyles register` as a one-line alternative to manually editing `$PROFILE`.
- All 50 existing Pester tests continue to pass; add 3 new tests for the register function.
- 0.2.2 ships to PSGallery.

## Non-goals

- **No auto-run** of `tstyles register` from anywhere. Surprise side effects are exactly what we want to avoid. The user explicitly invokes it.
- **No `tstyles unregister`** as a separate command. `tstyles uninstall` already strips the loader block via the same regex.
- **No `-Quiet` flag** for unattended scripted setup. YAGNI; can be added later if a real use case appears.
- **No detection of "you already invoke Import-Module in `$PROFILE` outside our markers"** (a manual edit the user made). If they did it manually, our regex won't find it and we'll add a second block. They can clean up. Niche edge case.
- **No multi-line `Get-Command` warning suppression** for the `-DisableNameChecking` flag. The flag handles that.
- **No changes to bootstrap installer's `$PROFILE` registration** (`install.ps1` already does this). The bootstrap installer's loader points at the explicit `%LOCALAPPDATA%\TerminalStyles\TerminalStyles.psd1` path; `tstyles register` uses the short module name (resolved via `PSModulePath`). These are NOT compatible — running `tstyles register` after a bootstrap install would add a SECOND loader block. Mitigation: detect existing block (any content between BEGIN/END markers) and skip with a clear message that the install kind already manages the loader.

## Architecture

One new function + 3 small integration changes.

### New: `Invoke-TerminalStylesRegister`

Module-private. Inserted near the other `Invoke-TerminalStyles*` functions in `tstyles.ps1` (next to `Invoke-TerminalStylesUpdate` / `Invoke-TerminalStylesUninstall`).

```powershell
function Invoke-TerminalStylesRegister {
    # Adds `Import-Module TerminalStyles -DisableNameChecking` to both
    # PowerShell engines' $PROFILE files, wrapped in the same
    # BEGIN/END markers Invoke-TerminalStylesUninstall already knows
    # how to strip. Idempotent: skips an engine whose $PROFILE already
    # has the block. -Force replaces it.
    [CmdletBinding()]
    param([switch]$Force)

    $loaderBegin = '# ===== TerminalStyles BEGIN ====='
    $loaderEnd   = '# ===== TerminalStyles END ====='
    $loaderBody  = @"
$loaderBegin
Import-Module TerminalStyles -DisableNameChecking
$loaderEnd
"@

    # Discover both engines, get $PROFILE per engine
    $targets = @()   # array of pscustomobject @{ Label = 'pwsh 7'; ProfilePath = '...' }
    foreach ($exe in @(
        @{ Exe = 'pwsh.exe';       Label = 'PowerShell 7' },
        @{ Exe = 'powershell.exe'; Label = 'Windows PowerShell 5.1' }
    )) {
        $cmd = Get-Command -Name $exe.Exe -ErrorAction SilentlyContinue
        if (-not $cmd) { continue }
        $profilePath = & $cmd.Source -NoProfile -NonInteractive -Command 'Write-Output $PROFILE' 2>$null
        if (-not $profilePath) { continue }
        $targets += [pscustomobject]@{
            Label       = $exe.Label
            ProfilePath = $profilePath.Trim()
            Exists      = Test-Path -LiteralPath $profilePath.Trim()
            HasLoader   = $false
        }
    }

    # Check for existing loader block per target
    $blockPattern = "(?ms)$([regex]::Escape($loaderBegin)).*?$([regex]::Escape($loaderEnd))\r?\n?"
    foreach ($t in $targets) {
        if ($t.Exists) {
            $content = [System.IO.File]::ReadAllText($t.ProfilePath, [System.Text.UTF8Encoding]::new($false))
            $t.HasLoader = ($content -match $blockPattern)
        }
    }

    # Decide what to do per target
    $toWrite = @()
    foreach ($t in $targets) {
        if ($t.HasLoader -and -not $Force) {
            Write-Host "  Already registered in $($t.ProfilePath) (use -Force to replace)" -ForegroundColor Gray
            continue
        }
        $toWrite += $t
    }

    if (-not $toWrite) {
        Write-Host ""
        Write-Host "Nothing to do." -ForegroundColor Yellow
        return
    }

    # Single confirm prompt covering all targets
    Write-Host ""
    Write-Host "Will register the TerminalStyles loader in:" -ForegroundColor Cyan
    foreach ($t in $toWrite) {
        Write-Host "  $($t.Label): $($t.ProfilePath)" -ForegroundColor Gray
    }
    Write-Host ""
    Write-Host "The loader is one line wrapped in BEGIN/END markers:" -ForegroundColor Gray
    Write-Host "  Import-Module TerminalStyles -DisableNameChecking" -ForegroundColor Cyan
    Write-Host ""
    $ans = Read-Host "Continue? [Y/n]"
    if ($ans -match '^(?i)n') {
        Write-Host "Cancelled." -ForegroundColor Gray
        return
    }

    # Write the block per target (idempotently strip + re-add for -Force)
    foreach ($t in $toWrite) {
        $profileDir = Split-Path -Parent $t.ProfilePath
        if ($profileDir -and -not (Test-Path -LiteralPath $profileDir)) {
            New-Item -ItemType Directory -Path $profileDir -Force | Out-Null
        }

        $existing = if ($t.Exists) {
            [System.IO.File]::ReadAllText($t.ProfilePath, [System.Text.UTF8Encoding]::new($false))
        } else { '' }

        # Strip any existing block (-Force path) before appending
        if ($existing -match $blockPattern) {
            $existing = [regex]::Replace($existing, $blockPattern, '')
        }

        $final = ($existing.TrimEnd() + "`r`n`r`n" + $loaderBody + "`r`n").TrimStart()
        [System.IO.File]::WriteAllText($t.ProfilePath, $final, [System.Text.UTF8Encoding]::new($false))

        Write-Host "  Registered in $($t.ProfilePath)" -ForegroundColor Green
    }

    Write-Host ""
    Write-Host "TerminalStyles will auto-load on every new shell tab." -ForegroundColor Cyan
    Write-Host "To verify in this session: Import-Module TerminalStyles -Force -DisableNameChecking" -ForegroundColor Gray
    Write-Host ""
}
```

### Subcommand dispatch (in `Invoke-TerminalStyle`)

Find the subcommand dispatch block (around line 580 in the current `tstyles.ps1`):

```powershell
    if ($Update -or $Arg -eq 'update')   { Invoke-TerminalStylesUpdate -Force:$Force; return }
    if ($Arg -eq 'list' -or $Arg -eq 'ls') { Show-StyleList;                return }
    if ($Arg -eq 'current')              { Show-CurrentStyle;               return }
    if ($Arg -eq 'random')               { Invoke-RandomStyle;              return }
    if ($Arg -eq 'uninstall')            { Invoke-TerminalStylesUninstall;  return }
```

Add one line for `register`:

```powershell
    if ($Arg -eq 'register')             { Invoke-TerminalStylesRegister -Force:$Force; return }
```

(Reusing the `$Force` param — `tstyles register -Force` works the same way `tstyles update -Force` does.)

### Tab completer

Find the subcommand list in `Register-ArgumentCompleter` (currently `@('list', 'current', 'random', 'update', 'uninstall')`):

```powershell
    $subcommands = @('list', 'current', 'random', 'register', 'update', 'uninstall')
```

(Alphabetical-ish — `register` slots between `random` and `update`.)

## File-by-file changes

- **Modify:** `tstyles.ps1`
  - Add `Invoke-TerminalStylesRegister` function (~80 lines).
  - Add one dispatch line in `Invoke-TerminalStyle`.
  - Add `'register'` to the tab completer's subcommands list.
- **Create:** `tests/Invoke-TerminalStylesRegister.Tests.ps1` — 3 tests:
  1. Fresh `$PROFILE` (no loader) → block added with BEGIN/END markers.
  2. Existing loader → skipped (no rewrite, no duplicate block).
  3. `-Force` with existing loader → block replaced (single block, not stacked).
- **Modify:** `README.md`
  - `## Install` section: after the `Install-PSResource` + `Import-Module` line, add a one-line note that `tstyles register` auto-adds the `Import-Module` to `$PROFILE` for both engines.
  - `## Subcommands` listing: add `tstyles register` row.
- **Modify:** `TerminalStyles.psd1` — `ModuleVersion 0.2.1 → 0.2.2`, update `ReleaseNotes`.

No changes to: `install.ps1` (bootstrap already registers; coexistence handled by the "skip if already registered" check), `apply.ps1`, `scripts/publish.ps1`, the other test files, `docs/RELEASING.md`.

## Data flow

### Fresh PSGallery user, two-step setup

1. `Install-PSResource -Name TerminalStyles` → module installed to `~\Documents\PowerShell\Modules\TerminalStyles\0.2.2\`.
2. `Import-Module TerminalStyles -DisableNameChecking` → module loaded in current tab; `tstyles` alias defined.
3. `tstyles register` → confirm prompt shows both `$PROFILE` paths; user hits Enter; loader block added to both pwsh 7 and WinPS 5.1 `$PROFILE` files.
4. User opens a new tab → `$PROFILE` runs → `Import-Module TerminalStyles -DisableNameChecking` auto-loads the module → `tstyles` works immediately.

### Bootstrap user runs `tstyles register`

1. Bootstrap user already has a loader block in `$PROFILE` (writes the explicit-path `Import-Module "$env:LOCALAPPDATA\TerminalStyles\TerminalStyles.psd1"` form).
2. `tstyles register` detects the existing block, prints "Already registered in $profilePath (use -Force to replace)", and skips.
3. If they pass `-Force`, the bootstrap-style loader gets replaced with the PSGallery-style loader (short module name). After a new tab, PSResourceGet's auto-load via PSModulePath wins — effectively transitioning the user from Bootstrap to PSGallery load path without going through `tstyles uninstall`.
4. Niche but valid escape hatch.

### Re-running on an already-registered PSGallery setup

1. `tstyles register` (no `-Force`) → both engines say "Already registered, skipping." Then "Nothing to do." Returns cleanly. Idempotent.

## Error handling

| Failure | Behavior |
|---|---|
| Neither `pwsh.exe` nor `powershell.exe` on PATH | `$targets` is empty → "Nothing to do." prints; return. (Effectively impossible on Windows.) |
| `$PROFILE` query via `& $cmd.Source -NoProfile -NonInteractive -Command 'Write-Output $PROFILE'` returns nothing | Skip that engine silently (already handled in the discovery loop). |
| `$PROFILE` parent dir doesn't exist (e.g., user has never touched `$PROFILE`) | Create it with `New-Item -ItemType Directory`. Matches `install.ps1`'s behavior. |
| `Read-Host` returns empty (just Enter) | Treated as Y (the default — confirm prompt is `[Y/n]`). |
| `Read-Host` returns N or `n` | Print "Cancelled." and return. No disk writes. |
| `$PROFILE` is read-only or AV blocks the write | `WriteAllText` throws → propagates via the function's CmdletBinding to the user. User sees the error and can retry / fix permissions. |
| User has `Import-Module TerminalStyles` somewhere in `$PROFILE` OUTSIDE the BEGIN/END markers (manual edit) | Our regex doesn't match → we add a second block. User now has two `Import-Module TerminalStyles` lines. Cosmetic (idempotent: PowerShell silently skips re-import) but ugly. Documented as out-of-scope; user can clean up manually. |
| `Get-Command pwsh.exe` returns the exe but `& $exe -Command '$PROFILE'` hangs (very unusual) | Inherits behavior from `install.ps1`'s identical pattern. Timeout-less; if pwsh hangs at this level, the user has bigger problems. |

## Testing

Manual:

- **Fresh PSGallery install, no prior $PROFILE loader:**
  ```powershell
  pwsh -NoProfile -Command "Install-PSResource -Name TerminalStyles -Scope CurrentUser -TrustRepository; Import-Module TerminalStyles -DisableNameChecking; tstyles register"
  ```
  Confirm prompt fires. After accepting, open a new tab → `tstyles` is available without manual import.

- **Idempotent re-run:** in the same setup, run `tstyles register` again. Expected: "Already registered in $profilePath" per engine, then "Nothing to do."

- **`-Force` replace:** `tstyles register -Force`. Expected: confirm prompt; after accepting, loader is replaced (the file's BEGIN/END block is the same content, just freshly written).

- **Skip on Cancel:** run `tstyles register`, type `n` at the prompt. Expected: "Cancelled." Verify `$PROFILE` unchanged.

Automated (new file `tests/Invoke-TerminalStylesRegister.Tests.ps1`):

1. **Fresh `$PROFILE`** — mock `Get-Command` to return a single engine; mock the engine's `$PROFILE` query to return a path in `$TestDrive`; mock `Read-Host` to return `''` (default Y). Call `Invoke-TerminalStylesRegister`. Assert: target file exists, contains BEGIN/END block, contains `Import-Module TerminalStyles -DisableNameChecking`.
2. **Existing loader (idempotent)** — pre-populate the target file with a BEGIN/END block. Call `Invoke-TerminalStylesRegister`. Assert: file content unchanged (still exactly one BEGIN/END block).
3. **`-Force` replace** — pre-populate with a BEGIN/END block whose body is DIFFERENT (e.g., `dot-source some path`). Call `Invoke-TerminalStylesRegister -Force`. Assert: file content has exactly one BEGIN/END block AND the body is now the canonical `Import-Module TerminalStyles -DisableNameChecking` line.

All three tests use `InModuleScope TerminalStyles { ... }` (the function is module-private). Mock `Get-Command` and the engine-launch invocation; mock `Read-Host` to return Y.

CI: extends the existing Pester run; total 50 → 53 tests.

## Known limitations

- **Manual outside-markers `Import-Module TerminalStyles` line not detected.** If a user has already added the import to `$PROFILE` themselves (outside our markers), `tstyles register` adds a second wrapped block. PowerShell silently no-ops the re-import, so it's cosmetic, but the user has two lines doing the same thing. Acceptable; can be cleaned up manually.
- **Loader content is hardcoded.** If future versions need to change the loader (e.g., add a flag), users who registered with an older version need to re-run `tstyles register -Force` to update. No auto-migration of in-place loaders.
- **`Read-Host` blocks for input.** Running `tstyles register` non-interactively (e.g., from CI) will hang. The `-Quiet` flag is explicitly non-goal in this spec; if someone needs scripted setup, they can write the same line manually OR pipe input. (Future: add `-Confirm:$false` support, since the function has `[CmdletBinding(SupportsShouldProcess)]` indirectly. Not in scope.)
- **No `tstyles unregister`.** Use `tstyles uninstall`. Documented in README's "Uninstalling" section already.
