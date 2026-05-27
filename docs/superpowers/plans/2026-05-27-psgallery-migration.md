# PSGallery Migration UX Implementation Plan (Sub-project C, v0.2.0)

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Ship `TerminalStyles 0.2.0` with: (1) state-file relocation so the published module survives version upgrades, (2) README rewrite leading with `Install-PSResource`, (3) `tstyles update`/`uninstall` delegating to PSResourceGet when applicable. Final piece of the A/B/C arc.

**Architecture:** Split `$script:TStylesRoot` into `$TStylesModuleRoot` (read-only code/styles) + `$TStylesDataRoot` (writable, at `%LOCALAPPDATA%\TerminalStyles\`). Add a one-time idempotent migration helper. Add `Get-TerminalStylesInstallKind` (path comparison: `$ModuleRoot == %LOCALAPPDATA%\TerminalStyles` → 'Bootstrap', else 'PSResourceGet'). Update flow control in `Invoke-TerminalStylesUpdate`, `Invoke-TerminalStylesUninstall`, and `Test-UpdateAvailable` to branch on install kind. README rewrite is mechanical paragraph replacement.

**Tech Stack:** PowerShell 5.1+ (single-source). Pester 5.x. `Update-PSResource` / `Uninstall-PSResource` (PSResourceGet, preinstalled on pwsh 7.4+). No new dependencies.

**Spec:** `docs/superpowers/specs/2026-05-27-psgallery-migration-design.md`

---

## File Structure

Six files modified, two created. Production code is one file (tstyles.ps1) + manifest version bump.

- **Modify:** `tstyles.ps1` — split root variable, add 2 helper functions, rewrite Get-StyleBundledBackground / Test-StyleResolved / Test-UpdateAvailable / Invoke-TerminalStylesUpdate / Invoke-TerminalStylesUninstall. ~250 lines touched.
- **Modify:** `TerminalStyles.psd1` — `ModuleVersion` `0.1.0` → `0.2.0`, update `ReleaseNotes`.
- **Modify:** `README.md` — 4 paragraph sections rewritten (Install / Updating / Uninstalling / Known limitations).
- **Modify:** `tests/Get-SchemeSwatch.Tests.ps1` — dual-root var setup.
- **Modify:** `tests/Test-UpdateAvailable.Tests.ps1` — dual-root setup + mock `Get-TerminalStylesInstallKind`.
- **Modify:** `tests/Apply-StyleDirect-Backup.Tests.ps1` — dual-root setup + mock `Get-TerminalStylesInstallKind`.
- **Create:** `tests/Get-TerminalStylesInstallKind.Tests.ps1` — 3 new tests for the new helper.
- **No change:** `apply.ps1`, `install.ps1`, `scripts/publish.ps1`, `scripts/capture-screenshots.ps1`, `.github/workflows/test.yml`, `docs/RELEASING.md`.

**Task ordering** (CI green at every commit boundary):

1. **Task 1:** Add `Get-TerminalStylesInstallKind` (pure addition, no callers yet) + new test file. Tests 43 → 46.
2. **Task 2:** The big refactor — dual-root split + migration helper + cache-dir relocation for backgrounds. Updates 3 existing test files for dual-root setup + mock install-kind. Tests still 46 passing.
3. **Task 3:** Delegate `Invoke-TerminalStylesUpdate` and `Invoke-TerminalStylesUninstall` based on install kind. `Test-UpdateAvailable` short-circuit for PSResourceGet.
4. **Task 4:** README rewrite (4 sections).
5. **Task 5:** Bump `ModuleVersion` to `0.2.0` + update `ReleaseNotes`.
6. **Task 6:** Push + publish 0.2.0 + smoke-test from clean shell + tag v0.2.0.

---

## Task 1: Add `Get-TerminalStylesInstallKind` helper + its test file

**Files:**
- Modify: `tstyles.ps1` (insert new function near other helpers, around line 100, before `Test-UpdateAvailable`)
- Create: `tests/Get-TerminalStylesInstallKind.Tests.ps1`

Pure addition. The function isn't called from production code yet (Task 3 wires it in). Tests verify it independently.

- [ ] **Step 1: Insert `Get-TerminalStylesInstallKind` into `tstyles.ps1`**

Open `tstyles.ps1`. Find the existing function `Test-UpdateAvailable` (currently around line 100, after `Get-StyleBundledBackground`). Insert this new function IMMEDIATELY ABOVE `Test-UpdateAvailable`:

```powershell
function Get-TerminalStylesInstallKind {
    # Returns 'Bootstrap' if the module loaded from %LOCALAPPDATA%\TerminalStyles\
    # (the iwr-installer path), else 'PSResourceGet' (PSModulePath-based install).
    # Used by Invoke-TerminalStylesUpdate / Invoke-TerminalStylesUninstall to
    # delegate to the right mechanism, and by Test-UpdateAvailable to skip the
    # SHA-based check entirely for PSResourceGet installs.
    #
    # Note: $script:TStylesModuleRoot is set during module load. For installs
    # made before the dual-root refactor (sub-project C), the variable still
    # has the right value because the init block sets it from $PSScriptRoot.
    $bootstrapDir = Join-Path $env:LOCALAPPDATA 'TerminalStyles'
    if ($script:TStylesModuleRoot -eq $bootstrapDir) { return 'Bootstrap' }
    return 'PSResourceGet'
}
```

Use the `Edit` tool with `Test-UpdateAvailable` (the line `function Test-UpdateAvailable {`) as the anchor. Prepend the new function (plus a blank line separator) before it.

**Important:** This function references `$script:TStylesModuleRoot`, which doesn't exist yet — it's added in Task 2's refactor. To keep CI green between Tasks 1 and 2, also add a forward-declaration of the variable at the top of the file. Specifically, find the current init block:

```powershell
$script:TStylesRoot = $PSScriptRoot
if (-not $script:TStylesRoot) {
    $script:TStylesRoot = Split-Path $MyInvocation.MyCommand.Path -Parent
}
$script:TStylesCurrent = Join-Path $script:TStylesRoot 'current-style.ps1'
```

And replace it with:

```powershell
$script:TStylesRoot = $PSScriptRoot
if (-not $script:TStylesRoot) {
    $script:TStylesRoot = Split-Path $MyInvocation.MyCommand.Path -Parent
}
# Alias for the dual-root refactor coming in sub-project C. For now both
# point at the same dir; Task 2 splits them properly.
$script:TStylesModuleRoot = $script:TStylesRoot
$script:TStylesCurrent = Join-Path $script:TStylesRoot 'current-style.ps1'
```

This is a temporary shim — Task 2 removes the alias and does the real split.

- [ ] **Step 2: Create `tests/Get-TerminalStylesInstallKind.Tests.ps1`**

Create the new file with this exact content:

```powershell
# Pester 5 tests for Get-TerminalStylesInstallKind.
#
# The function decides whether the module was installed via PSResourceGet
# (e.g., Install-PSResource into ~/Documents/PowerShell/Modules/) or via
# the iwr|iex bootstrap installer (always lands at %LOCALAPPDATA%\TerminalStyles\).
# The downstream consumers (Invoke-TerminalStylesUpdate, Invoke-TerminalStylesUninstall,
# Test-UpdateAvailable) branch their behavior on the result.
#
# Pure path comparison; no external calls. The function is module-private,
# so all tests run inside InModuleScope.
#
# Run: Invoke-Pester -Path tests
# Requires: Pester 5+

#Requires -Modules @{ ModuleName = 'Pester'; ModuleVersion = '5.0.0' }

BeforeAll {
    $repoRoot = Split-Path $PSScriptRoot -Parent
    Import-Module (Join-Path $repoRoot 'TerminalStyles.psd1') -Force -DisableNameChecking *> $null
}

Describe 'Get-TerminalStylesInstallKind' {
    InModuleScope TerminalStyles {
        It "returns 'Bootstrap' when ModuleRoot equals %LOCALAPPDATA%\TerminalStyles" {
            $script:TStylesModuleRoot = Join-Path $env:LOCALAPPDATA 'TerminalStyles'
            Get-TerminalStylesInstallKind | Should -Be 'Bootstrap'
        }

        It "returns 'PSResourceGet' when ModuleRoot is under a PSModulePath dir" {
            # Simulate a typical PSResourceGet install path
            $script:TStylesModuleRoot = Join-Path $env:USERPROFILE 'Documents\PowerShell\Modules\TerminalStyles\0.2.0'
            Get-TerminalStylesInstallKind | Should -Be 'PSResourceGet'
        }

        It "returns 'PSResourceGet' when ModuleRoot is any path that isn't the bootstrap dir" {
            $script:TStylesModuleRoot = 'C:\arbitrary\unrelated\path'
            Get-TerminalStylesInstallKind | Should -Be 'PSResourceGet'
        }
    }
}
```

- [ ] **Step 3: Run the new test file**

```powershell
pwsh -NoProfile -Command "Invoke-Pester -Path .\tests\Get-TerminalStylesInstallKind.Tests.ps1 -Output Detailed"
```

Expected: 3 tests pass, 0 failed.

- [ ] **Step 4: Run the full suite to confirm nothing broke**

```powershell
pwsh -NoProfile -Command "Invoke-Pester -Path .\tests -Output Minimal 2>&1 | Select-Object -Last 3"
```

Expected: `Tests Passed: 46, Failed: 0, ...` (43 existing + 3 new).

- [ ] **Step 5: Commit**

```bash
git add tstyles.ps1 tests/Get-TerminalStylesInstallKind.Tests.ps1
git commit -m "$(cat <<'EOF'
Add Get-TerminalStylesInstallKind helper + tests

New module-private helper that path-compares $script:TStylesModuleRoot
against %LOCALAPPDATA%\TerminalStyles\ to decide whether the module
was installed via the iwr|iex bootstrap (returns 'Bootstrap') or via
PSResourceGet (returns 'PSResourceGet'). Pure path comparison; no
PSResourceGet API call needed.

The function isn't wired into production code yet -- sub-project C's
Task 3 makes tstyles update/uninstall branch on it. This commit adds
the function and 3 Pester tests in isolation, plus a shim variable
$script:TStylesModuleRoot (alias of $script:TStylesRoot) so the
function compiles. Task 2 splits the roots properly.

Spec: docs/superpowers/specs/2026-05-27-psgallery-migration-design.md
EOF
)"
```

---

## Task 2: Dual-root refactor + state migration

**Files:**
- Modify: `tstyles.ps1` (init block, Get-StyleBundledBackground, Test-StyleResolved, all `$script:TStylesRoot` callers)
- Modify: `tests/Get-SchemeSwatch.Tests.ps1` (dual-root setup + mock)
- Modify: `tests/Test-UpdateAvailable.Tests.ps1` (dual-root setup + mock)
- Modify: `tests/Apply-StyleDirect-Backup.Tests.ps1` (dual-root setup + mock)

The structural change. Split `$script:TStylesRoot` into `$script:TStylesModuleRoot` (read-only code/styles) and `$script:TStylesDataRoot` (writable state at `%LOCALAPPDATA%\TerminalStyles\`). Update every call site. Add the one-time migration helper.

- [ ] **Step 1: Replace the init block in `tstyles.ps1`**

Find this block at the top of `tstyles.ps1` (after Task 1's shim, currently around lines 12-21):

```powershell
$script:TStylesRoot = $PSScriptRoot
if (-not $script:TStylesRoot) {
    $script:TStylesRoot = Split-Path $MyInvocation.MyCommand.Path -Parent
}
# Alias for the dual-root refactor coming in sub-project C. For now both
# point at the same dir; Task 2 splits them properly.
$script:TStylesModuleRoot = $script:TStylesRoot
$script:TStylesCurrent = Join-Path $script:TStylesRoot 'current-style.ps1'

# === Auto-load the currently selected style's profile.ps1 ===
if (Test-Path -LiteralPath $script:TStylesCurrent) {
    . $script:TStylesCurrent
}
```

Replace with:

```powershell
$script:TStylesModuleRoot = $PSScriptRoot
if (-not $script:TStylesModuleRoot) {
    $script:TStylesModuleRoot = Split-Path $MyInvocation.MyCommand.Path -Parent
}
# Stable per-user data dir. Survives module version upgrades (PSResourceGet
# installs a new version to a sibling dir; state stays here). For bootstrap-
# installed users, this happens to equal $script:TStylesModuleRoot --
# backward-compatible by design.
$script:TStylesDataRoot = Join-Path $env:LOCALAPPDATA 'TerminalStyles'
if (-not (Test-Path -LiteralPath $script:TStylesDataRoot)) {
    New-Item -ItemType Directory -Path $script:TStylesDataRoot -Force | Out-Null
}
$script:TStylesCurrent = Join-Path $script:TStylesDataRoot 'current-style.ps1'

# One-time data-layout migration for users upgrading from pre-0.2.0.
# Idempotent; gated by a marker file.
Invoke-TerminalStylesStateMigration

# === Auto-load the currently selected style's profile.ps1 ===
if (Test-Path -LiteralPath $script:TStylesCurrent) {
    . $script:TStylesCurrent
}
```

The old `$script:TStylesRoot` variable is gone after this step. Any function still using it will throw at runtime (good — the audit in subsequent steps catches them).

- [ ] **Step 2: Add `Invoke-TerminalStylesStateMigration` helper**

Insert this function in `tstyles.ps1` IMMEDIATELY ABOVE `Get-TerminalStylesInstallKind` (which Task 1 inserted just above `Test-UpdateAvailable`):

```powershell
function Invoke-TerminalStylesStateMigration {
    # Migrates pre-0.2.0 data layout to 0.2.0:
    #   - Cached background.<ext> files move from $ModuleRoot\styles\<name>\
    #     to $DataRoot\cache\<name>\.
    #   - .no-background negative-cache markers move similarly.
    # Idempotent. Skips work if the marker file exists.
    $marker = Join-Path $script:TStylesDataRoot '.migrated-0.2.0'
    if (Test-Path -LiteralPath $marker) { return }

    $stylesDir = Join-Path $script:TStylesModuleRoot 'styles'
    if (-not (Test-Path -LiteralPath $stylesDir)) {
        # No styles dir to migrate from. Mark done so we don't re-check.
        try { New-Item -ItemType File -Path $marker -Force | Out-Null } catch { }
        return
    }

    foreach ($styleDir in Get-ChildItem -LiteralPath $stylesDir -Directory) {
        $styleName = $styleDir.Name
        $cacheDir = Join-Path $script:TStylesDataRoot "cache\$styleName"

        # Move cached background files
        foreach ($ext in 'gif','png','jpg','jpeg') {
            $src = Join-Path $styleDir.FullName "background.$ext"
            if (Test-Path -LiteralPath $src) {
                if (-not (Test-Path -LiteralPath $cacheDir)) {
                    try { New-Item -ItemType Directory -Path $cacheDir -Force | Out-Null } catch { }
                }
                $dest = Join-Path $cacheDir "background.$ext"
                try {
                    Move-Item -LiteralPath $src -Destination $dest -Force -ErrorAction Stop
                } catch {
                    # Source might be read-only (PSGallery install with stale
                    # bundled file from manual user copy). Acceptable -- the
                    # bundled file stays readable in place.
                }
            }
        }

        # Move negative-cache marker
        $srcMarker = Join-Path $styleDir.FullName '.no-background'
        if (Test-Path -LiteralPath $srcMarker) {
            if (-not (Test-Path -LiteralPath $cacheDir)) {
                try { New-Item -ItemType Directory -Path $cacheDir -Force | Out-Null } catch { }
            }
            try {
                Move-Item -LiteralPath $srcMarker -Destination (Join-Path $cacheDir '.no-background') -Force -ErrorAction Stop
            } catch { }
        }
    }

    try { New-Item -ItemType File -Path $marker -Force | Out-Null } catch { }
}
```

- [ ] **Step 3: Rewrite `Get-StyleBundledBackground` to use the cache dir**

Find the existing function (currently around lines 45-98):

```powershell
function Get-StyleBundledBackground {
    # ... existing 3-tier resolution ...
    param([Parameter(Mandatory)][string]$StyleDir)

    # 1. Local file already present
    foreach ($ext in 'gif','png','jpg','jpeg') {
        $candidate = Join-Path $StyleDir "background.$ext"
        if (Test-Path -LiteralPath $candidate) { return $candidate }
    }

    # 2. Negative cache (we've tried and the remote has nothing for this style)
    $noBgMarker = Join-Path $StyleDir '.no-background'
    if (Test-Path -LiteralPath $noBgMarker) { return $null }

    # 3. Lazy-fetch from the gifs branch
    $styleName = Split-Path -Leaf $StyleDir
    $remoteBase = "https://raw.githubusercontent.com/fcreme/TerminalStyles/gifs/$styleName"
    $prevProgress = $ProgressPreference
    $ProgressPreference = 'SilentlyContinue'
    try {
        foreach ($ext in 'gif','png','jpg','jpeg') {
            $url = "$remoteBase.$ext"
            $local = Join-Path $StyleDir "background.$ext"
            try {
                Invoke-WebRequest -Uri $url -OutFile $local -UseBasicParsing -TimeoutSec 10 -ErrorAction Stop
                if ((Get-Item -LiteralPath $local -ErrorAction SilentlyContinue).Length -gt 0) {
                    return $local
                } else {
                    Remove-Item -LiteralPath $local -Force -ErrorAction SilentlyContinue
                }
            } catch {
                if (Test-Path -LiteralPath $local) { Remove-Item -LiteralPath $local -Force -ErrorAction SilentlyContinue }
            }
        }
    } finally {
        $ProgressPreference = $prevProgress
    }

    # All extensions failed -- write negative-cache marker
    try {
        New-Item -ItemType File -Path $noBgMarker -Force | Out-Null
    } catch { }
    return $null
}
```

Replace with:

```powershell
function Get-StyleBundledBackground {
    # Three-tier resolution:
    #   1. Bundled file under $StyleDir (module root, read-only-ish on PSGallery)
    #   2. Cached file under $DataRoot\cache\<name>\ (writable, persistent)
    #   3. Lazy-fetch from gifs branch -> write to $DataRoot\cache\<name>\
    #
    # The negative-cache marker (.no-background) lives in the cache dir, never
    # in the bundled dir, so we can write it on PSGallery installs.
    param([Parameter(Mandatory)][string]$StyleDir)

    # 1. Bundled (under module root)
    foreach ($ext in 'gif','png','jpg','jpeg') {
        $bundled = Join-Path $StyleDir "background.$ext"
        if (Test-Path -LiteralPath $bundled) { return $bundled }
    }

    $styleName = Split-Path -Leaf $StyleDir
    $cacheDir  = Join-Path $script:TStylesDataRoot "cache\$styleName"

    # 2. Cached (under data root)
    foreach ($ext in 'gif','png','jpg','jpeg') {
        $cached = Join-Path $cacheDir "background.$ext"
        if (Test-Path -LiteralPath $cached) { return $cached }
    }
    if (Test-Path -LiteralPath (Join-Path $cacheDir '.no-background')) { return $null }

    # 3. Lazy-fetch into cache
    if (-not (Test-Path -LiteralPath $cacheDir)) {
        New-Item -ItemType Directory -Path $cacheDir -Force | Out-Null
    }
    $remoteBase = "https://raw.githubusercontent.com/fcreme/TerminalStyles/gifs/$styleName"
    $prevProgress = $ProgressPreference
    $ProgressPreference = 'SilentlyContinue'
    try {
        foreach ($ext in 'gif','png','jpg','jpeg') {
            $url = "$remoteBase.$ext"
            $local = Join-Path $cacheDir "background.$ext"
            try {
                Invoke-WebRequest -Uri $url -OutFile $local -UseBasicParsing -TimeoutSec 10 -ErrorAction Stop
                if ((Get-Item -LiteralPath $local -ErrorAction SilentlyContinue).Length -gt 0) {
                    return $local
                } else {
                    Remove-Item -LiteralPath $local -Force -ErrorAction SilentlyContinue
                }
            } catch {
                if (Test-Path -LiteralPath $local) { Remove-Item -LiteralPath $local -Force -ErrorAction SilentlyContinue }
            }
        }
    } finally {
        $ProgressPreference = $prevProgress
    }

    # All extensions failed -- write negative-cache marker in CACHE dir
    try {
        New-Item -ItemType File -Path (Join-Path $cacheDir '.no-background') -Force | Out-Null
    } catch { }
    return $null
}
```

- [ ] **Step 4: Rewrite `Test-StyleResolved` to check both bundled and cache locations**

Find the existing function (currently around lines 308-322):

```powershell
function Test-StyleResolved {
    # ... existing body checking $StyleDir for backgrounds and .no-background ...
    param([Parameter(Mandatory)][string]$StyleDir)
    foreach ($ext in 'gif','png','jpg','jpeg') {
        if (Test-Path -LiteralPath (Join-Path $StyleDir "background.$ext")) { return $true }
    }
    if (Test-Path -LiteralPath (Join-Path $StyleDir '.no-background')) { return $true }
    return $false
}
```

Replace with:

```powershell
function Test-StyleResolved {
    # A style is "resolved" if we know its background state -- either a
    # bundled background.<ext> exists under $StyleDir (module root), or a
    # cached background.<ext>/.no-background exists under $DataRoot\cache\<name>\.
    param([Parameter(Mandatory)][string]$StyleDir)
    foreach ($ext in 'gif','png','jpg','jpeg') {
        if (Test-Path -LiteralPath (Join-Path $StyleDir "background.$ext")) { return $true }
    }
    $styleName = Split-Path -Leaf $StyleDir
    $cacheDir = Join-Path $script:TStylesDataRoot "cache\$styleName"
    foreach ($ext in 'gif','png','jpg','jpeg') {
        if (Test-Path -LiteralPath (Join-Path $cacheDir "background.$ext")) { return $true }
    }
    if (Test-Path -LiteralPath (Join-Path $cacheDir '.no-background')) { return $true }
    return $false
}
```

- [ ] **Step 5: Audit and fix every remaining `$script:TStylesRoot` reference**

Run:

```powershell
pwsh -NoProfile -Command "Select-String -Path .\tstyles.ps1 -Pattern '\$script:TStylesRoot' -SimpleMatch"
```

Each match must be replaced. Use this rubric:

| Context (what's being joined) | Replacement |
|---|---|
| `'styles'` (bundled themes folder) | `$script:TStylesModuleRoot` |
| `"styles\..."` (anything inside bundled themes) | `$script:TStylesModuleRoot` |
| `'.installed-sha'` | `$script:TStylesDataRoot` |
| `'.last-update-check'` | `$script:TStylesDataRoot` |
| Anything else state-related | `$script:TStylesDataRoot` |

Specifically, the expected hits and their fixes:

- `Test-UpdateAvailable` (currently around lines 110, 117) → both `$shaFile` and `$stampFile` use `$script:TStylesDataRoot`.
- `Invoke-TerminalStylesUpdate` (around line 155) → `$shaFile = Join-Path $script:TStylesDataRoot '.installed-sha'`.
- `Get-AvailableStyles` (around line 287) → `$stylesDir = Join-Path $script:TStylesModuleRoot 'styles'`.
- `Show-CurrentStyle` (around line 404) → `Join-Path $script:TStylesModuleRoot "styles\$current\scheme.json"`.
- `Apply-StyleDirect` (around line 468) → `$styleDir = Join-Path $script:TStylesModuleRoot "styles\$StyleName"`.
- `Invoke-TerminalStyle` picker setup (around line 630) → `$stylesDir = Join-Path $script:TStylesModuleRoot 'styles'`.
- Tab completer (around line 1042) → `$stylesDir = Join-Path $script:TStylesModuleRoot 'styles'`.

After this step, re-run the audit:

```powershell
pwsh -NoProfile -Command "Select-String -Path .\tstyles.ps1 -Pattern '\$script:TStylesRoot' -SimpleMatch"
```

Expected: **0 matches**. If any remain, fix them.

- [ ] **Step 6: Update the three existing Pester test files**

For each of `tests/Get-SchemeSwatch.Tests.ps1`, `tests/Test-UpdateAvailable.Tests.ps1`, `tests/Apply-StyleDirect-Backup.Tests.ps1`, replace the `BeforeEach` (or per-test) `$script:TStylesRoot = $TestDrive` line with the dual-root setup. Most tests will need both vars plus the install-kind mock so tests aren't affected by the new branching.

**For `tests/Get-SchemeSwatch.Tests.ps1`:** This test doesn't actually use `$script:TStylesRoot` in BeforeEach (it computes `$repoRoot` directly via `Split-Path $PSScriptRoot -Parent` and passes it to `Get-SchemeSwatch` via parameters inside `InModuleScope`). **No changes needed.** Re-run the test to confirm.

**For `tests/Test-UpdateAvailable.Tests.ps1`:** Find the existing `BeforeEach` inside the `InModuleScope`:

```powershell
        BeforeEach {
            $script:TStylesRoot = $TestDrive
            $stampFile = Join-Path $TestDrive '.last-update-check'
            $shaFile   = Join-Path $TestDrive '.installed-sha'
            Remove-Item $stampFile -ErrorAction SilentlyContinue
            Remove-Item $shaFile   -ErrorAction SilentlyContinue
        }
```

Replace with:

```powershell
        BeforeEach {
            $script:TStylesModuleRoot = $TestDrive
            $script:TStylesDataRoot   = $TestDrive
            # Mock the install-kind detection: tests assume Bootstrap behavior
            # (PSResourceGet would short-circuit Test-UpdateAvailable to $null,
            # breaking every assertion below).
            Mock Get-TerminalStylesInstallKind { 'Bootstrap' }
            $stampFile = Join-Path $TestDrive '.last-update-check'
            $shaFile   = Join-Path $TestDrive '.installed-sha'
            Remove-Item $stampFile -ErrorAction SilentlyContinue
            Remove-Item $shaFile   -ErrorAction SilentlyContinue
        }
```

**For `tests/Apply-StyleDirect-Backup.Tests.ps1`:** Find the existing `BeforeEach` inside the `InModuleScope`:

```powershell
        BeforeEach {
            $script:TStylesRoot = $TestDrive
            ...
        }
```

Replace the `$script:TStylesRoot` line with:

```powershell
            $script:TStylesModuleRoot = $TestDrive
            $script:TStylesDataRoot   = $TestDrive
            # Mock install-kind: tests for the bootstrap-only flow.
            Mock Get-TerminalStylesInstallKind { 'Bootstrap' }
```

(The rest of the `BeforeEach` body is unchanged.)

- [ ] **Step 7: Run the full Pester suite**

```powershell
pwsh -NoProfile -Command "Invoke-Pester -Path .\tests -Output Minimal 2>&1 | Select-Object -Last 3"
```

Expected: `Tests Passed: 46, Failed: 0, ...`

If `Test-UpdateAvailable` tests fail with "the term 'Get-TerminalStylesInstallKind' is not recognized", the Mock line is outside `InModuleScope`. Move it inside.

If `Apply-StyleDirect` tests fail with `Find-WTSettingsPath not found` or similar, an unrelated mock was lost. Check the `BeforeEach` block is fully intact (all 5 mocks present).

- [ ] **Step 8: Sanity-test the migration helper manually**

In a scratch pwsh tab:

```powershell
# Set up a fake "pre-0.2.0 layout" with a bundled background and a no-background marker
$tmp = Join-Path $env:TEMP "tstyles-mig-test-$([guid]::NewGuid())"
New-Item -ItemType Directory -Path "$tmp\styles\eva" -Force | Out-Null
'fake-eva-gif' | Set-Content "$tmp\styles\eva\background.gif" -Encoding UTF8 -NoNewline
New-Item -ItemType Directory -Path "$tmp\styles\sober" -Force | Out-Null
New-Item -ItemType File -Path "$tmp\styles\sober\.no-background" -Force | Out-Null

# Point the module at this fake layout (both roots in the same dir)
. .\tstyles.ps1 *> $null
$script:TStylesModuleRoot = $tmp
$script:TStylesDataRoot   = $tmp

# Run the migration
Invoke-TerminalStylesStateMigration

# Verify
Test-Path "$tmp\cache\eva\background.gif"       # True
Test-Path "$tmp\cache\sober\.no-background"     # True
Test-Path "$tmp\styles\eva\background.gif"      # False -- moved
Test-Path "$tmp\styles\sober\.no-background"    # False -- moved
Test-Path "$tmp\.migrated-0.2.0"                # True

# Re-run; should be a no-op
Invoke-TerminalStylesStateMigration
# (no errors, no changes)

# Cleanup
Remove-Item $tmp -Recurse -Force
```

Expected: all `Test-Path` assertions match the expected booleans. Re-run is silent.

- [ ] **Step 9: Commit**

```bash
git add tstyles.ps1 tests/Test-UpdateAvailable.Tests.ps1 tests/Apply-StyleDirect-Backup.Tests.ps1
git commit -m "$(cat <<'EOF'
Dual-root refactor: split $script:TStylesRoot + migrate state to $DataRoot

The single $script:TStylesRoot becomes two:
  - $script:TStylesModuleRoot ($PSScriptRoot): bundled code + styles,
    read-only-ish on PSGallery installs.
  - $script:TStylesDataRoot (%LOCALAPPDATA%\TerminalStyles\): writable
    state (current-style.ps1, .installed-sha, .last-update-check, and
    cached background images under cache/<name>/), persistent across
    version upgrades.

For bootstrap-installed users, both roots resolve to the same
%LOCALAPPDATA%\TerminalStyles\ -- backward-compatible by design.

Get-StyleBundledBackground and Test-StyleResolved updated to use the
new cache dir for lazy-fetched backgrounds. Negative-cache markers
move with them.

Invoke-TerminalStylesStateMigration runs once on module load to move
pre-0.2.0 cached files from $ModuleRoot\styles\<name>\ to
$DataRoot\cache\<name>\. Idempotent; marker-gated.

Test files updated for the dual-root variables and to mock
Get-TerminalStylesInstallKind to 'Bootstrap' so the existing throttle
tests aren't short-circuited by the PSResourceGet path.

Spec: docs/superpowers/specs/2026-05-27-psgallery-migration-design.md
EOF
)"
```

---

## Task 3: Delegate `Invoke-TerminalStylesUpdate` / `Invoke-TerminalStylesUninstall` / `Test-UpdateAvailable`

**Files:**
- Modify: `tstyles.ps1` (rewrite three functions: `Invoke-TerminalStylesUpdate`, `Invoke-TerminalStylesUninstall`, short-circuit in `Test-UpdateAvailable`)

`Get-TerminalStylesInstallKind` (added in Task 1) is now wired into production code.

- [ ] **Step 1: Add PSResourceGet short-circuit to `Test-UpdateAvailable`**

Find the existing function body in `tstyles.ps1` (currently around lines 100-152). Add three lines at the very top of the function body (right after the comment block, before `$shaFile = ...`):

The new lines:

```powershell
    # PSResourceGet installs update via Update-PSResource, not git. Skip
    # the SHA-based check entirely; the user runs `tstyles update` whenever.
    if ((Get-TerminalStylesInstallKind) -eq 'PSResourceGet') { return $null }
```

Insert immediately after the function's leading comment block, before:

```powershell
    $shaFile   = Join-Path $script:TStylesDataRoot '.installed-sha'
```

(`$shaFile` and `$stampFile` references should already use `$script:TStylesDataRoot` from Task 2.)

- [ ] **Step 2: Rewrite `Invoke-TerminalStylesUpdate` for delegation**

Find the existing function (around lines 145-192). Replace **the entire function body** (keep the function signature `function Invoke-TerminalStylesUpdate { [CmdletBinding()] param([switch]$Force)`) with:

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
            # Re-run the iwr installer one-liner. Existing behavior, preserved
            # so users who installed via iwr|iex keep updating that way.

            # Cheap check first: if we already have the current main SHA, skip
            # the ~10MB ZIP download entirely. -Force overrides.
            $shaFile = Join-Path $script:TStylesDataRoot '.installed-sha'
            if (-not $Force -and (Test-Path -LiteralPath $shaFile)) {
                try {
                    $installed = ([System.IO.File]::ReadAllText($shaFile, [System.Text.UTF8Encoding]::new($false))).Trim()
                    $resp = Invoke-RestMethod `
                        -Uri 'https://api.github.com/repos/fcreme/TerminalStyles/commits/main' `
                        -Headers @{ 'User-Agent' = 'TerminalStyles-UpdateCheck' } `
                        -TimeoutSec 5 -ErrorAction Stop
                    if ($resp.sha -and $resp.sha -eq $installed) {
                        Write-Host "Already up to date ($($installed.Substring(0,7))). Use -Force to reinstall anyway." -ForegroundColor Green
                        return
                    }
                } catch {
                    # Network failure -- fall through to full download.
                }
            }

            # Suppress IWR progress bar (dominant cost on WinPS 5.1).
            $prevProgress = $ProgressPreference
            $ProgressPreference = 'SilentlyContinue'
            try {
                $installerScript = (Invoke-WebRequest -Uri 'https://raw.githubusercontent.com/fcreme/TerminalStyles/main/install.ps1' -UseBasicParsing).Content
                Invoke-Expression $installerScript
                Write-Host ""
                Write-Host "Update complete. To use the new tstyles code in THIS session," -ForegroundColor Yellow
                Write-Host "open a new pwsh tab, or run:" -ForegroundColor Yellow
                Write-Host "  . `$PROFILE" -ForegroundColor Cyan
            } catch {
                Write-Host "Update failed: $_" -ForegroundColor Red
                Write-Host "You can retry manually:" -ForegroundColor Yellow
                Write-Host "  iwr -useb https://raw.githubusercontent.com/fcreme/TerminalStyles/main/install.ps1 | iex" -ForegroundColor Cyan
            } finally {
                $ProgressPreference = $prevProgress
            }
        }
    }
}
```

- [ ] **Step 3: Rewrite `Invoke-TerminalStylesUninstall` for delegation + `-DeleteData`**

Find the existing function (around lines 547-596). Replace the entire function with:

```powershell
function Invoke-TerminalStylesUninstall {
    [CmdletBinding()]
    param(
        [switch]$DeleteData    # also remove %LOCALAPPDATA%\TerminalStyles\ (user state)
    )

    $dataDir = Join-Path $env:LOCALAPPDATA 'TerminalStyles'
    $kind = Get-TerminalStylesInstallKind

    Write-Host ""
    Write-Host "This will uninstall TerminalStyles (detected: $kind):" -ForegroundColor Yellow
    switch ($kind) {
        'PSResourceGet' {
            Write-Host "  - Uninstall-PSResource -Name TerminalStyles" -ForegroundColor Yellow
        }
        'Bootstrap' {
            Write-Host "  - Remove install-managed files from $dataDir" -ForegroundColor Yellow
        }
    }
    Write-Host "  - Strip the loader block from pwsh 7 and Windows PowerShell 5.1 `$PROFILE files" -ForegroundColor Yellow
    if ($DeleteData) {
        Write-Host "  - DELETE the entire $dataDir (user state: active style, cached GIFs, throttle stamp)" -ForegroundColor Red
    } else {
        Write-Host "  - PRESERVE user state ($dataDir contents -- pass -DeleteData to wipe)" -ForegroundColor Gray
    }
    Write-Host "  - Will NOT modify Windows Terminal's settings.json." -ForegroundColor Yellow
    Write-Host ""
    $ans = Read-Host "Continue? [y/N]"
    if ($ans -notmatch '^(?i)y') {
        Write-Host "Cancelled." -ForegroundColor Gray
        return
    }

    # 1. Remove the module / install-managed files
    switch ($kind) {
        'PSResourceGet' {
            try {
                Uninstall-PSResource -Name TerminalStyles -ErrorAction Stop
                Write-Host "  Removed module via Uninstall-PSResource" -ForegroundColor Green
            } catch {
                Write-Host "  Uninstall-PSResource failed: $_" -ForegroundColor Red
            }
        }
        'Bootstrap' {
            $installManagedItems = @(
                'tstyles.ps1', 'apply.ps1', 'install.ps1',
                'TerminalStyles.psd1', 'TerminalStyles.psm1',
                'styles', 'scripts',
                'README.md', 'LICENSE'
            )
            foreach ($item in $installManagedItems) {
                $path = Join-Path $dataDir $item
                if (Test-Path -LiteralPath $path) {
                    Remove-Item -LiteralPath $path -Recurse -Force -ErrorAction SilentlyContinue
                }
            }
            Write-Host "  Removed install-managed files from $dataDir" -ForegroundColor Green
        }
    }

    # 2. Strip the loader from both PowerShell engines' $PROFILE
    foreach ($exe in 'pwsh.exe', 'powershell.exe') {
        $cmd = Get-Command -Name $exe -ErrorAction SilentlyContinue
        if (-not $cmd) { continue }
        $profilePath = & $cmd.Source -NoProfile -NonInteractive -Command 'Write-Output $PROFILE' 2>$null
        if (-not $profilePath) { continue }
        $profilePath = $profilePath.Trim()
        if (-not (Test-Path -LiteralPath $profilePath)) { continue }

        $content = [System.IO.File]::ReadAllText($profilePath, [System.Text.UTF8Encoding]::new($false))
        $newContent = [regex]::Replace($content, '(?ms)# ===== TerminalStyles BEGIN =====.*?# ===== TerminalStyles END =====\r?\n?', '')
        if ($newContent -ne $content) {
            [System.IO.File]::WriteAllText($profilePath, $newContent, [System.Text.UTF8Encoding]::new($false))
            Write-Host "  Removed loader from $profilePath" -ForegroundColor Green
        }
    }

    # 3. Optionally remove user state
    if ($DeleteData) {
        if (Test-Path -LiteralPath $dataDir) {
            Remove-Item -LiteralPath $dataDir -Recurse -Force
            Write-Host "  Removed $dataDir (full wipe via -DeleteData)" -ForegroundColor Green
        }
    } else {
        Write-Host ""
        Write-Host "  User state preserved at $dataDir" -ForegroundColor Gray
        Write-Host "  Pass -DeleteData to remove that too." -ForegroundColor Gray
    }

    Write-Host ""
    Write-Host "TerminalStyles uninstalled." -ForegroundColor Cyan
    Write-Host "Open a new pwsh tab to confirm the loader is gone." -ForegroundColor Gray
    Write-Host "Your settings.json was NOT modified. If you want a default look back," -ForegroundColor Gray
    Write-Host "restore a settings.json.bak-* backup or edit it via WT Settings -> Open JSON file." -ForegroundColor Gray
    Write-Host ""
}
```

- [ ] **Step 4: Run the full Pester suite**

```powershell
pwsh -NoProfile -Command "Invoke-Pester -Path .\tests -Output Minimal 2>&1 | Select-Object -Last 3"
```

Expected: `Tests Passed: 46, Failed: 0, ...`. The existing throttle tests mock `Get-TerminalStylesInstallKind { 'Bootstrap' }` so the new short-circuit in `Test-UpdateAvailable` doesn't fire.

If a test fails with "Update-PSResource is not recognized" or similar, it's likely the test environment lacks PSResourceGet. Add a `Mock Update-PSResource` and `Mock Uninstall-PSResource` to the relevant test setup. **Unlikely** because the existing tests don't exercise update/uninstall delegation.

- [ ] **Step 5: Commit**

```bash
git add tstyles.ps1
git commit -m "$(cat <<'EOF'
Delegate tstyles update/uninstall + skip update-check for PSResourceGet

Three behavior changes wire Get-TerminalStylesInstallKind (added in
Task 1) into the production flow:

1. Test-UpdateAvailable short-circuits to $null for PSResourceGet
   installs. The SHA-based check is meaningless when versions are
   managed by Update-PSResource; users just run `tstyles update`
   whenever they want.

2. Invoke-TerminalStylesUpdate branches:
   - PSResourceGet -> Update-PSResource -Name TerminalStyles
   - Bootstrap -> existing iwr|iex re-run flow

3. Invoke-TerminalStylesUninstall branches and adds -DeleteData:
   - PSResourceGet -> Uninstall-PSResource -Name TerminalStyles
   - Bootstrap -> remove install-managed files from
     %LOCALAPPDATA%\TerminalStyles\, preserving user state
     (current-style.ps1, cache/, .last-update-check) by default
   - Both paths strip the $PROFILE loader block
   - -DeleteData additionally removes %LOCALAPPDATA%\TerminalStyles\
     entirely (the user state wipe)

The confirm prompt now lists exactly what each path will do, so the
user sees what they're agreeing to.

Spec: docs/superpowers/specs/2026-05-27-psgallery-migration-design.md
EOF
)"
```

---

## Task 4: README rewrite

**Files:**
- Modify: `README.md` (4 paragraph sections: Install, Updating, Uninstalling, Known limitations)

Lead with `Install-PSResource`; demote `iwr | iex` to a fallback subsection. Update Updating/Uninstalling to describe delegation. Note the data dir behavior in Known limitations.

- [ ] **Step 1: Rewrite the `## Install` section**

Find the existing block in `README.md` (currently around lines 36-55):

```markdown
## Install

Open a **PowerShell** tab in Windows Terminal (either Windows PowerShell
5.1 or PowerShell 7+ works) and run:

```powershell
iwr -useb https://raw.githubusercontent.com/fcreme/TerminalStyles/main/install.ps1 | iex
```

That's it. You don't need to clone anything. The installer:

1. Downloads the styles to `%LOCALAPPDATA%\TerminalStyles\`.
2. Registers a loader line in your `$PROFILE` for **every** PowerShell
   engine it finds on PATH (`pwsh.exe` and `powershell.exe`), so one run
   sets up both shells.
3. Detects if either engine's execution policy is `Restricted` /
   `AllSigned` and offers to set `CurrentUser` to `RemoteSigned` for you
   (it asks first — never silent).

Once the installer finishes, you can run `tstyles` immediately in the
same tab. Any other tabs already open (and the other PowerShell engine
if both are installed) will pick it up the next time they start.
```

Replace with:

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

This downloads to `%LOCALAPPDATA%\TerminalStyles\`, registers a
loader for every PowerShell engine it finds, and offers to fix
restrictive execution policies if needed. Once it finishes, run
`tstyles` immediately in the same tab.

The bootstrap install and the PSGallery install can coexist —
whichever your `$PROFILE` loads wins; the other is orphaned silently.
```

- [ ] **Step 2: Rewrite the `## Updating` section**

Find the existing block (currently around lines 301-336):

```markdown
## Updating

`tstyles` checks `api.github.com` for new commits on `main` at most once
per day per machine and prints a one-line yellow notice if your install
is behind:

...lots of content...
```

Replace **the entire section** (from `## Updating` heading down to but NOT including the next `## Uninstalling` heading) with:

```markdown
## Updating

```powershell
tstyles update
```

`tstyles update` detects how the module was installed and delegates:

- **PSGallery (`Install-PSResource`)** → runs `Update-PSResource -Name TerminalStyles`.
- **Bootstrap (`iwr | iex`)** → re-runs the bootstrap one-liner.

After update, open a new tab (or run `Import-Module TerminalStyles -Force -DisableNameChecking`) for the new version to take effect.

### How the update check works

For **bootstrap** installs only, `tstyles` issues at most one
unauthenticated HTTP GET per 24 hours per machine to
`api.github.com/repos/fcreme/TerminalStyles/commits/main` (capped at
2 seconds), comparing the returned commit SHA against the one
recorded at install time in
`%LOCALAPPDATA%\TerminalStyles\.installed-sha`. The 24h throttle is
tracked in `%LOCALAPPDATA%\TerminalStyles\.last-update-check` and
applies even on failure. No authentication, no payload sent, no
analytics.

PSGallery-installed copies skip this check entirely — `Update-PSResource`
handles version comparison internally when you run `tstyles update`.

```

- [ ] **Step 3: Rewrite the `## Uninstalling` section**

Find the existing block (currently around line 338 onwards, before `## Adding your own style`). Replace **the entire section** with:

```markdown
## Uninstalling

```powershell
tstyles uninstall
```

`tstyles uninstall` detects how the module was installed and delegates:

- **PSGallery** → runs `Uninstall-PSResource -Name TerminalStyles` +
  strips the `Import-Module` loader from your `$PROFILE`.
- **Bootstrap** → removes the install-managed files from
  `%LOCALAPPDATA%\TerminalStyles\` (script files, bundled styles) and
  strips the loader.

**Either path preserves your user state by default** — your active
style (`current-style.ps1`), update-check throttle, and cached
background images stay at `%LOCALAPPDATA%\TerminalStyles\`. You can
reinstall (either path) and pick up where you left off.

To also remove the user state, pass `-DeleteData`:

```powershell
tstyles uninstall -DeleteData
```

Neither path modifies Windows Terminal's `settings.json` — your
current color scheme / cursor / background stays whatever it was
last set to.

If you want a clean default look back, either restore a
`settings.json.bak-<timestamp>` file from
`%LOCALAPPDATA%\Packages\Microsoft.WindowsTerminal_8wekyb3d8bbwe\LocalState\`,
or open WT Settings → "Open JSON file" and edit by hand.

```

- [ ] **Step 4: Append two notes to `## Known limitations`**

Find the existing `## Known limitations` section. Append these two bullets at the END of its bullet list:

```markdown
- **User state lives at `%LOCALAPPDATA%\TerminalStyles\`** regardless
  of install method. This dir holds your active style, cached
  background images, and the update-check throttle. It survives
  uninstall (unless you pass `-DeleteData`) and version upgrades.
- **Bootstrap + PSGallery installs can coexist.** If you've run both,
  whichever your `$PROFILE` loads first wins; the other is orphaned
  silently. To clean up: `tstyles uninstall` removes whichever is
  currently loaded; run it twice (switching shells between runs if
  needed) to clean both.
```

- [ ] **Step 5: Verify the changes**

```powershell
pwsh -NoProfile -Command "Select-String -Path .\README.md -Pattern 'Install-PSResource -Name TerminalStyles','Alternate: bootstrap installer','How the update check works','-DeleteData','User state lives at'"
```

Expected: at least 5 matches (one per key new phrase).

```powershell
pwsh -NoProfile -Command "Select-String -Path .\README.md -Pattern 'Open a \*\*PowerShell\*\* tab in Windows Terminal'"
```

Expected: **no matches** (the old install lead-in is gone).

- [ ] **Step 6: Commit**

```bash
git add README.md
git commit -m "$(cat <<'EOF'
README: lead with Install-PSResource, document delegation + -DeleteData

Four sections rewritten to match the v0.2.0 behavior:

- ## Install now leads with `Install-PSResource -Name TerminalStyles`;
  the iwr|iex one-liner is demoted to a fallback "Alternate: bootstrap
  installer" subsection.
- ## Updating explains that `tstyles update` detects the install kind
  and delegates (Update-PSResource for PSGallery, iwr|iex for
  bootstrap). The "How the update check works" subsection clarifies
  the 24h SHA check only fires for bootstrap installs.
- ## Uninstalling explains the same delegation plus the new
  -DeleteData flag (default preserves user state).
- ## Known limitations gains two notes: where user state lives and
  what happens if both install paths are present.

Spec: docs/superpowers/specs/2026-05-27-psgallery-migration-design.md
EOF
)"
```

---

## Task 5: Bump `ModuleVersion` to `0.2.0`

**Files:**
- Modify: `TerminalStyles.psd1`

Final code change before push + publish.

- [ ] **Step 1: Bump the version and update ReleaseNotes**

Find these two lines in `TerminalStyles.psd1`:

```powershell
    ModuleVersion     = '0.1.0'
```

Replace with:

```powershell
    ModuleVersion     = '0.2.0'
```

Find the `ReleaseNotes` line:

```powershell
            ReleaseNotes = 'Initial module structure (sub-project A of the PSGallery migration). No behavior changes from the prior dot-sourced install.'
```

Replace with:

```powershell
            ReleaseNotes = 'v0.2.0: state files relocated to %LOCALAPPDATA%\TerminalStyles\ (survives version upgrades). tstyles update / uninstall now delegate to Update-PSResource / Uninstall-PSResource for PSGallery-installed copies. README leads with Install-PSResource; iwr|iex bootstrap is now a documented fallback. Transparent migration of cached background images on first import.'
```

- [ ] **Step 2: Verify the manifest still parses**

```powershell
pwsh -NoProfile -Command "Test-ModuleManifest .\TerminalStyles.psd1 | Format-List Name, Version, ExportedFunctions, ExportedAliases"
```

Expected: `Version : 0.2.0` and the same exports as 0.1.0.

- [ ] **Step 3: Re-run the test suite as a final pre-publish check**

```powershell
pwsh -NoProfile -Command "Invoke-Pester -Path .\tests -Output Minimal 2>&1 | Select-Object -Last 3"
```

Expected: `Tests Passed: 46, Failed: 0, ...`

- [ ] **Step 4: Commit**

```bash
git add TerminalStyles.psd1
git commit -m "Bump version to 0.2.0 + update ReleaseNotes"
```

---

## Task 6: Push + publish 0.2.0 + smoke-test + tag

**Files:** None modified locally. PSGallery + git remote state changes.

Final sub-project C task. Controller-handled (needs API key for publish).

- [ ] **Step 1: Push all sub-project C commits to `origin/main`**

```bash
git status
git log --oneline origin/main..HEAD
```

Expected: working tree clean. Five commits ahead:

1. `Bump version to 0.2.0 + update ReleaseNotes` (Task 5)
2. `README: lead with Install-PSResource ...` (Task 4)
3. `Delegate tstyles update/uninstall + skip update-check for PSResourceGet` (Task 3)
4. `Dual-root refactor: split $script:TStylesRoot + migrate state to $DataRoot` (Task 2)
5. `Add Get-TerminalStylesInstallKind helper + tests` (Task 1)

```bash
git push origin main
```

Expected: `<prior-sha>..<HEAD-sha>  main -> main`.

- [ ] **Step 2: Publish via the established script**

```powershell
pwsh -NoProfile -File ./scripts/publish.ps1 -ApiKey '<the-api-key>'
```

Expected output:

```
Staged TerminalStyles 0.2.0 at:
  C:\Users\felip\dotfiles\out\TerminalStyles

Published TerminalStyles 0.2.0 to PSGallery.
Verify at: https://www.powershellgallery.com/packages/TerminalStyles/0.2.0
```

- [ ] **Step 3: Verify on PSGallery**

Wait ~30-60 seconds, then:

```powershell
pwsh -NoProfile -Command "Find-PSResource -Name TerminalStyles -Repository PSGallery -Version '*' | Sort-Object Version -Descending | Select-Object -First 3 | Format-Table Name, Version, Description"
```

Expected: `0.2.0` appears as the latest version. `0.1.0` also still present (PSGallery keeps version history).

- [ ] **Step 4: End-to-end smoke-test in a clean shell**

```powershell
pwsh -NoProfile -Command "Update-PSResource -Name TerminalStyles -TrustRepository; Import-Module TerminalStyles -Force -DisableNameChecking; Get-Module TerminalStyles | Format-List Name, Version, Path"
```

Expected: `Version : 0.2.0`, Path under `~\Documents\PowerShell\Modules\TerminalStyles\0.2.0\`.

If your maintainer machine already has 0.1.0 from Sub-project B's smoke-test, the `Update-PSResource` should bring it up to 0.2.0. If you don't have it, `Install-PSResource -Name TerminalStyles -TrustRepository` instead.

- [ ] **Step 5: Verify the new behavior works end-to-end**

In the same clean shell (PSResourceGet install):

```powershell
pwsh -NoProfile -Command "Import-Module TerminalStyles -Force -DisableNameChecking; tstyles list | Select-Object -First 3"
```

Expected: prints the first 3 themes (with swatches if your terminal supports truecolor).

Confirm the data dir was created/used:

```powershell
pwsh -NoProfile -Command "Test-Path \$env:LOCALAPPDATA\TerminalStyles"
```

Expected: `True`. Inspect contents:

```powershell
pwsh -NoProfile -Command "Get-ChildItem \$env:LOCALAPPDATA\TerminalStyles | Select-Object Name, LastWriteTime"
```

Expected: at least `.migrated-0.2.0` (the migration marker). For your maintainer machine which already has a bootstrap install, also: `current-style.ps1`, `.installed-sha`, `.last-update-check`, `cache/` (containing per-theme dirs with the moved-in background.<ext> files), `styles/` (the install-managed bundled themes), the script files.

- [ ] **Step 6: Tag v0.2.0**

```bash
git tag v0.2.0
git push --tags
```

Expected: `* [new tag]         v0.2.0 -> v0.2.0`.

---

## Self-Review Notes

Spec coverage:

- State-file relocation → Task 2.
- One-time migration helper → Task 2 (Invoke-TerminalStylesStateMigration).
- README install rewrite → Task 4 Step 1.
- README updating rewrite → Task 4 Step 2.
- README uninstalling rewrite → Task 4 Step 3.
- README known-limitations notes → Task 4 Step 4.
- tstyles update delegation → Task 3 Step 2.
- tstyles uninstall delegation + -DeleteData → Task 3 Step 3.
- Test-UpdateAvailable short-circuit for PSResourceGet → Task 3 Step 1.
- New Get-TerminalStylesInstallKind helper → Task 1.
- New Get-TerminalStylesInstallKind test file (3 tests) → Task 1 Step 2.
- Existing Pester test updates (dual-root + mock install-kind) → Task 2 Step 6.
- Version bump → Task 5.
- Publish 0.2.0 → Task 6.

Spec items not in plan (correctly absent per spec's non-goals):
- No $PROFILE auto-registration → no task.
- No `tstyles migrate` subcommand → no task.
- No `Find-PSResource`-based version check for PSGallery users → no task.

Type / signature consistency:

- `$script:TStylesModuleRoot` / `$script:TStylesDataRoot` / `$script:TStylesCurrent` — same exact spellings everywhere.
- `Get-TerminalStylesInstallKind` returns `'Bootstrap'` or `'PSResourceGet'` — same strings in helper, in delegations, in tests.
- `Invoke-TerminalStylesStateMigration` — same exact spelling.
- `-DeleteData` switch on `Invoke-TerminalStylesUninstall` — same spelling in code + README + spec.
- `.migrated-0.2.0` marker filename — same in helper + manual test.

No placeholders. All code blocks complete and runnable. All Pester test names matched to existing patterns.

Three judgment calls worth flagging:

- **Task 1 inserts a temporary shim variable** (`$script:TStylesModuleRoot = $script:TStylesRoot`) so Get-TerminalStylesInstallKind compiles between Tasks 1 and 2. Task 2 removes the shim. Without this, Task 1 commits would have a broken function that throws at module load. Acceptable transient state.
- **Task 2 is large (~250 lines touched)** but atomic — splitting it would leave the codebase in a half-refactored state. Subagent should handle in one shot; if blocked, retry with Sonnet (current default).
- **Task 6 Step 2 includes the API key inline** for automated execution by the controller. Subsequent maintainer-run publishes use the interactive prompt per `docs/RELEASING.md`. Same leak posture as Sub-project B (key already in conversation; key restricted to TerminalStyles glob).
