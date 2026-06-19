# Install Hardening Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Harden the `iwr|iex` bootstrap installer — validate the downloaded archive, assert the module landed, make the `$PROFILE` write atomic + first-touch backed-up, and verify the execution-policy change — behind a new unit-test seam.

**Architecture:** Reorder `install.ps1` so all functions precede a single `$TStylesInstallNoRun`-guarded main flow (mirroring `apply.ps1`'s `$TStylesApplyNoRun` seam), add four small self-contained helper functions, modify `Register-LoaderInProfile` and `Resolve-ExecutionPolicy`, and cover the pure functions with a new Pester file. The bootstrap delivers `install.ps1` alone, so every helper stays in-file.

**Tech Stack:** PowerShell (Windows PowerShell 5.1 and PowerShell 7+), Pester 5, `System.IO.Compression` for ZIP inspection.

## Global Constraints

- Changes confined to `install.ps1` and the new `tests/Install-Hardening.Tests.ps1`. No other file changes.
- Must run on **Windows PowerShell 5.1 AND PowerShell 7+** (`install.ps1` has `#Requires -Version 5.1`).
- All file writes are **UTF-8 with no BOM** (`[System.Text.UTF8Encoding]::new($false)`).
- Installer console output stays **pure 7-bit ASCII** — no emoji, no box-drawing, no em-dashes (use `--`).
- Test seam mirrors `apply.ps1`: tests set `$TStylesInstallNoRun = $true` then dot-source `install.ps1`.
- All new throw messages end with actionable guidance (typically "re-run the installer").
- Pester tests: `#Requires -Modules @{ ModuleName = 'Pester'; ModuleVersion = '5.0.0' }`.
- Run tests with: `Invoke-Pester -Path .\tests\Install-Hardening.Tests.ps1 -Output Detailed`.

---

## File Structure

- **Modify: `install.ps1`** — reorder (functions above a guarded main), add `Assert-ValidArchive`, `Assert-InstallLanded`, `Write-TextFileAtomic`, `Test-PolicyResolved`; modify `Register-LoaderInProfile` and `Resolve-ExecutionPolicy`; wire validations into the guarded main flow.
- **Create: `tests/Install-Hardening.Tests.ps1`** — Pester 5 coverage for the pure functions, dot-sourcing `install.ps1` via the seam. Grows one `Describe` block per task.

---

### Task 1: Test seam (reorder + `$TStylesInstallNoRun` guard)

Moves all of `install.ps1`'s functions above its imperative flow and wraps the flow in a no-run guard, so tests can dot-source the script for its functions without triggering a real download/install. No behavior change for a normal `iwr|iex` run.

**Files:**
- Modify: `install.ps1` (reorder; wrap imperative blocks `170-251` and `371-410` in a guard; move `chcp`/encoding/preference setup inside it)
- Test: `tests/Install-Hardening.Tests.ps1` (create)

**Interfaces:**
- Consumes: nothing.
- Produces: a dot-sourceable `install.ps1` that, when `$TStylesInstallNoRun` is truthy, defines all functions (`Write-InstallBanner`, `Write-InstallStep`, `Write-InstallPanel`, `Get-ShellInfo`, `Register-LoaderInProfile`, `Resolve-ExecutionPolicy`) and does **not** run the installer.

Target file structure after the reorder:

```
#Requires -Version 5.1                       (stays at top)
$repo/$branch/$installDir/$zipUrl/$runId/     (pure var defs -- stay at top level)
$tempZip/$tempDir/$loader* definitions
--- function definitions (ALL of them, in this order) ---
  Write-InstallBanner, Write-InstallStep, Write-InstallPanel
  Get-ShellInfo, Register-LoaderInProfile, Resolve-ExecutionPolicy
  (new functions added by later tasks land here too)
--- guarded main ---
if (-not $TStylesInstallNoRun) {
    <chcp + encoding + $ErrorActionPreference + $ProgressPreference>
    Write-InstallBanner
    <download 173-175> <extract 178-184> <install 186-235>
    <record SHA 237-251> <register loop 371-390> <panel 392-400> <handoff 402-410>
}
```

- [ ] **Step 1: Write the failing test** — create `tests/Install-Hardening.Tests.ps1`:

```powershell
#Requires -Modules @{ ModuleName = 'Pester'; ModuleVersion = '5.0.0' }
# Pester 5 tests for install.ps1 hardening. The installer is dot-sourced
# with $TStylesInstallNoRun = $true so its functions load WITHOUT running
# the download/install flow -- mirrors apply.ps1's $TStylesApplyNoRun seam.

Describe 'install.ps1 test seam' {
    BeforeAll {
        $script:installPath = Join-Path (Split-Path $PSScriptRoot -Parent) 'install.ps1'
        $TStylesInstallNoRun = $true
        . $script:installPath   # if the guard fails, this would attempt a network download
    }

    It 'loads functions without running the installer' {
        Get-Command Get-ShellInfo            -CommandType Function -ErrorAction SilentlyContinue | Should -Not -BeNullOrEmpty
        Get-Command Register-LoaderInProfile -CommandType Function -ErrorAction SilentlyContinue | Should -Not -BeNullOrEmpty
        Get-Command Resolve-ExecutionPolicy  -CommandType Function -ErrorAction SilentlyContinue | Should -Not -BeNullOrEmpty
    }
}
```

- [ ] **Step 2: Run test to verify it fails**

Run: `Invoke-Pester -Path .\tests\Install-Hardening.Tests.ps1 -Output Detailed`
Expected: FAIL — dot-sourcing the current `install.ps1` runs the installer (no guard), which attempts `Invoke-WebRequest` and errors/hangs, or the `It` never asserts cleanly.

- [ ] **Step 3: Reorder `install.ps1`**

Move the three flow helpers (`Get-ShellInfo`, `Register-LoaderInProfile`, `Resolve-ExecutionPolicy`, currently `257-369`) up so they sit immediately after the output helpers (`Write-InstallPanel` ends at `168`). Then wrap the two imperative regions (`170-251` and `371-410`) in one guard, moving the side-effecting setup inside it. The top of the guarded block becomes:

```powershell
# Main flow. Guarded so tests can dot-source this script for its functions
# (set $TStylesInstallNoRun = $true) without running the installer. A normal
# `iwr | iex` run never sets the var, so main runs.
if (-not $TStylesInstallNoRun) {

    # Force UTF-8 console output as defense-in-depth (see header note).
    $null = & chcp 65001 2>&1
    [Console]::OutputEncoding = [System.Text.UTF8Encoding]::new($false)
    $ErrorActionPreference = 'Stop'
    $ProgressPreference     = 'SilentlyContinue'

    Write-InstallBanner
    # ... (everything from the old line 173 through the old line 410) ...
}
```

Leave the `$repo`/`$branch`/`$installDir`/`$zipUrl`/`$runId`/`$tempZip`/`$tempDir` and `$loaderBegin`/`$loaderEnd`/`$loaderBody` definitions at top level (pure, side-effect-free). The closing `}` goes after the same-tab handoff block (old `402-410`).

- [ ] **Step 4: Run test to verify it passes**

Run: `Invoke-Pester -Path .\tests\Install-Hardening.Tests.ps1 -Output Detailed`
Expected: PASS (1 test).

- [ ] **Step 5: Run the full suite to confirm no regressions**

Run: `Invoke-Pester -Path .\tests -Output Detailed`
Expected: all existing tests still PASS.

- [ ] **Step 6: Commit**

```bash
git add install.ps1 tests/Install-Hardening.Tests.ps1
git commit -m "refactor(install): add \$TStylesInstallNoRun test seam"
```

---

### Task 2: `Assert-ValidArchive`

Validates the downloaded ZIP before extraction: non-empty, openable as a ZIP, and contains the module manifest.

**Files:**
- Modify: `install.ps1` (add function among the function defs)
- Test: `tests/Install-Hardening.Tests.ps1` (add `Describe`)

**Interfaces:**
- Consumes: nothing.
- Produces: `Assert-ValidArchive -Path <string>` — throws on empty/invalid/non-TerminalStyles archive; returns nothing on success.

- [ ] **Step 1: Write the failing tests** — append to `tests/Install-Hardening.Tests.ps1`:

```powershell
Describe 'Assert-ValidArchive' {
    BeforeAll {
        $script:installPath = Join-Path (Split-Path $PSScriptRoot -Parent) 'install.ps1'
        $TStylesInstallNoRun = $true
        . $script:installPath
        Add-Type -AssemblyName System.IO.Compression.FileSystem

        function script:New-ZipFrom {
            param([string[]]$Entries, [string]$ZipPath)
            $src = Join-Path $TestDrive ('src-' + [guid]::NewGuid().Guid.Substring(0,8))
            foreach ($e in $Entries) {
                $full = Join-Path $src $e
                New-Item -ItemType Directory -Force -Path (Split-Path $full -Parent) | Out-Null
                Set-Content -LiteralPath $full -Value 'x' -NoNewline
            }
            [System.IO.Compression.ZipFile]::CreateFromDirectory($src, $ZipPath)
        }
    }

    It 'passes for a valid archive containing the manifest' {
        $zip = Join-Path $TestDrive 'good.zip'
        New-ZipFrom -Entries @('TerminalStyles-main/TerminalStyles.psd1') -ZipPath $zip
        { Assert-ValidArchive -Path $zip } | Should -Not -Throw
    }

    It 'throws for a zero-byte file' {
        $empty = Join-Path $TestDrive 'empty.zip'
        New-Item -ItemType File -Path $empty | Out-Null
        { Assert-ValidArchive -Path $empty } | Should -Throw -ExpectedMessage '*empty*'
    }

    It 'throws for a non-ZIP file' {
        $bogus = Join-Path $TestDrive 'bogus.zip'
        Set-Content -LiteralPath $bogus -Value '<html>404: Not Found</html>'
        { Assert-ValidArchive -Path $bogus } | Should -Throw -ExpectedMessage '*not a valid ZIP*'
    }

    It 'throws for a ZIP without the module manifest' {
        $zip = Join-Path $TestDrive 'nomanifest.zip'
        New-ZipFrom -Entries @('TerminalStyles-main/README.md') -ZipPath $zip
        { Assert-ValidArchive -Path $zip } | Should -Throw -ExpectedMessage '*does not look like TerminalStyles*'
    }
}
```

- [ ] **Step 2: Run to verify it fails**

Run: `Invoke-Pester -Path .\tests\Install-Hardening.Tests.ps1 -Output Detailed`
Expected: FAIL — `Assert-ValidArchive` is not defined.

- [ ] **Step 3: Add the function** — among the function defs in `install.ps1`:

```powershell
# --- Validate a downloaded archive before extracting ---
function Assert-ValidArchive {
    param([Parameter(Mandatory)][string]$Path)

    if (-not (Test-Path -LiteralPath $Path) -or ((Get-Item -LiteralPath $Path).Length -eq 0)) {
        throw "Download was empty or missing. This is usually a transient network issue -- re-run the installer."
    }

    Add-Type -AssemblyName System.IO.Compression.FileSystem
    $zip = $null
    try {
        $zip = [System.IO.Compression.ZipFile]::OpenRead($Path)
    } catch {
        throw "Downloaded file is not a valid ZIP archive (partial download or network error) -- re-run the installer."
    }
    try {
        $hasManifest = @($zip.Entries | Where-Object { $_.FullName -match 'TerminalStyles\.psd1$' }).Count -gt 0
    } finally {
        $zip.Dispose()
    }
    if (-not $hasManifest) {
        throw "Downloaded archive does not look like TerminalStyles (module manifest not found) -- re-run the installer."
    }
}
```

- [ ] **Step 4: Run to verify it passes**

Run: `Invoke-Pester -Path .\tests\Install-Hardening.Tests.ps1 -Output Detailed`
Expected: PASS (5 tests total).

- [ ] **Step 5: Commit**

```bash
git add install.ps1 tests/Install-Hardening.Tests.ps1
git commit -m "feat(install): validate downloaded archive before extract"
```

---

### Task 3: `Assert-InstallLanded`

Asserts the module manifest exists at `$installDir` after the `Move-Item`, catching the "partial `Remove-Item` left the dir, so the move nested the source" failure.

**Files:**
- Modify: `install.ps1` (add function)
- Test: `tests/Install-Hardening.Tests.ps1` (add `Describe`)

**Interfaces:**
- Consumes: nothing.
- Produces: `Assert-InstallLanded -InstallDir <string>` — throws if `TerminalStyles.psd1` is missing at the root; returns nothing on success.

- [ ] **Step 1: Write the failing tests** — append:

```powershell
Describe 'Assert-InstallLanded' {
    BeforeAll {
        $script:installPath = Join-Path (Split-Path $PSScriptRoot -Parent) 'install.ps1'
        $TStylesInstallNoRun = $true
        . $script:installPath
    }

    It 'passes when the manifest is present' {
        $dir = Join-Path $TestDrive 'landed'
        New-Item -ItemType Directory -Force -Path $dir | Out-Null
        Set-Content -LiteralPath (Join-Path $dir 'TerminalStyles.psd1') -Value '@{}'
        { Assert-InstallLanded -InstallDir $dir } | Should -Not -Throw
    }

    It 'throws when the manifest is missing (nested/broken install)' {
        $dir = Join-Path $TestDrive 'broken'
        New-Item -ItemType Directory -Force -Path (Join-Path $dir 'TerminalStyles-main') | Out-Null
        { Assert-InstallLanded -InstallDir $dir } | Should -Throw -ExpectedMessage '*did not complete*'
    }
}
```

- [ ] **Step 2: Run to verify it fails**

Run: `Invoke-Pester -Path .\tests\Install-Hardening.Tests.ps1 -Output Detailed`
Expected: FAIL — `Assert-InstallLanded` is not defined.

- [ ] **Step 3: Add the function** — in `install.ps1`:

```powershell
# --- Assert the module actually landed after the install move ---
function Assert-InstallLanded {
    param([Parameter(Mandatory)][string]$InstallDir)
    $manifest = Join-Path $InstallDir 'TerminalStyles.psd1'
    if (-not (Test-Path -LiteralPath $manifest)) {
        throw ("Install did not complete: '$manifest' is missing. A leftover file lock on " +
               "'$InstallDir' (another PowerShell tab, OneDrive, or antivirus) may have blocked " +
               "the update. Close other PowerShell windows and re-run the installer.")
    }
}
```

- [ ] **Step 4: Run to verify it passes**

Run: `Invoke-Pester -Path .\tests\Install-Hardening.Tests.ps1 -Output Detailed`
Expected: PASS (7 tests total).

- [ ] **Step 5: Commit**

```bash
git add install.ps1 tests/Install-Hardening.Tests.ps1
git commit -m "feat(install): assert module landed after install move"
```

---

### Task 4: `Write-TextFileAtomic`

Atomic UTF-8 (no BOM) text write via a temp sibling + replace, with a best-effort non-atomic fallback. Used by `Register-LoaderInProfile` in Task 5.

**Files:**
- Modify: `install.ps1` (add function)
- Test: `tests/Install-Hardening.Tests.ps1` (add `Describe`)

**Interfaces:**
- Consumes: nothing.
- Produces: `Write-TextFileAtomic -Path <string> -Content <string>` — writes `$Content` to `$Path` as UTF-8 no-BOM, leaving no temp file behind on success.

- [ ] **Step 1: Write the failing tests** — append:

```powershell
Describe 'Write-TextFileAtomic' {
    BeforeAll {
        $script:installPath = Join-Path (Split-Path $PSScriptRoot -Parent) 'install.ps1'
        $TStylesInstallNoRun = $true
        . $script:installPath
        $script:enc = [System.Text.UTF8Encoding]::new($false)
    }

    It 'writes the exact content to a new file' {
        $p = Join-Path $TestDrive 'new.txt'
        Write-TextFileAtomic -Path $p -Content "hello`r`nworld"
        [System.IO.File]::ReadAllText($p, $script:enc) | Should -Be "hello`r`nworld"
    }

    It 'writes UTF-8 with no BOM' {
        $p = Join-Path $TestDrive 'nobom.txt'
        Write-TextFileAtomic -Path $p -Content 'abc'
        $bytes = [System.IO.File]::ReadAllBytes($p)
        ($bytes.Length -ge 3 -and $bytes[0] -eq 0xEF -and $bytes[1] -eq 0xBB -and $bytes[2] -eq 0xBF) | Should -BeFalse
    }

    It 'overwrites an existing file' {
        $p = Join-Path $TestDrive 'over.txt'
        Set-Content -LiteralPath $p -Value 'old'
        Write-TextFileAtomic -Path $p -Content 'new'
        [System.IO.File]::ReadAllText($p, $script:enc) | Should -Be 'new'
    }

    It 'leaves no temp file behind' {
        $dir = Join-Path $TestDrive 'tmpcheck'
        New-Item -ItemType Directory -Force -Path $dir | Out-Null
        $p = Join-Path $dir 'f.txt'
        Write-TextFileAtomic -Path $p -Content 'data'
        @(Get-ChildItem -LiteralPath $dir -Filter '*.tmp-*' -Force).Count | Should -Be 0
    }
}
```

- [ ] **Step 2: Run to verify it fails**

Run: `Invoke-Pester -Path .\tests\Install-Hardening.Tests.ps1 -Output Detailed`
Expected: FAIL — `Write-TextFileAtomic` is not defined.

- [ ] **Step 3: Add the function** — in `install.ps1`:

```powershell
# --- Atomic UTF-8 (no BOM) text write: temp sibling + replace ---
function Write-TextFileAtomic {
    param(
        [Parameter(Mandatory)][string]$Path,
        [Parameter(Mandatory)][string]$Content
    )
    $enc = [System.Text.UTF8Encoding]::new($false)
    $dir = Split-Path -Parent $Path
    $tmp = Join-Path $dir ('.' + (Split-Path -Leaf $Path) + '.tmp-' + ([guid]::NewGuid().Guid.Substring(0,8)))
    [System.IO.File]::WriteAllText($tmp, $Content, $enc)
    try {
        if (Test-Path -LiteralPath $Path) {
            [System.IO.File]::Replace($tmp, $Path, $null)   # atomic; consumes $tmp
        } else {
            [System.IO.File]::Move($tmp, $Path)
        }
    } catch {
        # Fallback: best-effort direct write (non-atomic). Surface once.
        Write-Host "  Note: atomic write unavailable on this volume; writing directly." -ForegroundColor DarkGray
        [System.IO.File]::WriteAllText($Path, $Content, $enc)
        Remove-Item -LiteralPath $tmp -Force -ErrorAction SilentlyContinue
    }
}
```

- [ ] **Step 4: Run to verify it passes**

Run: `Invoke-Pester -Path .\tests\Install-Hardening.Tests.ps1 -Output Detailed`
Expected: PASS (11 tests total).

- [ ] **Step 5: Commit**

```bash
git add install.ps1 tests/Install-Hardening.Tests.ps1
git commit -m "feat(install): add atomic UTF-8 text writer"
```

---

### Task 5: `Register-LoaderInProfile` — atomic write + first-touch backup

Replaces the raw profile write with `Write-TextFileAtomic`, and backs up the profile **once** the first time we add our loader to a profile that has pre-existing user content and no existing loader block. Re-registers (block already present) make no new backup.

**Files:**
- Modify: `install.ps1` (`Register-LoaderInProfile`)
- Test: `tests/Install-Hardening.Tests.ps1` (add `Describe`)

**Interfaces:**
- Consumes: `Write-TextFileAtomic` (Task 4).
- Produces: `Register-LoaderInProfile` (signature unchanged: `-ProfilePath -Label -InstallDir -LoaderBegin -LoaderEnd -LoaderBody`) — now writes atomically and creates `<ProfilePath>.bak-<yyyyMMdd-HHmmss>` on first touch of user content.

- [ ] **Step 1: Write the failing tests** — append:

```powershell
Describe 'Register-LoaderInProfile backup rule' {
    BeforeAll {
        $script:installPath = Join-Path (Split-Path $PSScriptRoot -Parent) 'install.ps1'
        $TStylesInstallNoRun = $true
        . $script:installPath
        $script:begin = '# ===== TerminalStyles BEGIN ====='
        $script:end   = '# ===== TerminalStyles END ====='
        $script:body  = "$script:begin`r`nImport-Module `"`$env:LOCALAPPDATA\TerminalStyles\TerminalStyles.psd1`" -DisableNameChecking`r`n$script:end"
    }
    BeforeEach {
        # Fresh per-test install fixture with an empty styles dir (no migration match)
        $script:fixture = Join-Path $TestDrive ('inst-' + [guid]::NewGuid().Guid.Substring(0,8))
        New-Item -ItemType Directory -Force -Path (Join-Path $script:fixture 'styles') | Out-Null
        $script:profileDir = Join-Path $script:fixture 'profile'
        New-Item -ItemType Directory -Force -Path $script:profileDir | Out-Null
        $script:profilePath = Join-Path $script:profileDir 'Microsoft.PowerShell_profile.ps1'
    }
    function script:CountBaks {
        @(Get-ChildItem -LiteralPath $script:profileDir -Filter '*.ps1.bak-*' -Force).Count
    }

    It 'creates no backup for a fresh (nonexistent) profile' {
        Register-LoaderInProfile -ProfilePath $script:profilePath -Label 'PowerShell 7' `
            -InstallDir $script:fixture -LoaderBegin $script:begin -LoaderEnd $script:end -LoaderBody $script:body
        Test-Path -LiteralPath $script:profilePath | Should -BeTrue
        CountBaks | Should -Be 0
    }

    It 'backs up once when touching a profile with pre-existing user content' {
        Set-Content -LiteralPath $script:profilePath -Value "# my custom prompt`r`nSet-Alias ll Get-ChildItem"
        Register-LoaderInProfile -ProfilePath $script:profilePath -Label 'PowerShell 7' `
            -InstallDir $script:fixture -LoaderBegin $script:begin -LoaderEnd $script:end -LoaderBody $script:body
        CountBaks | Should -Be 1
        $bak = Get-ChildItem -LiteralPath $script:profileDir -Filter '*.ps1.bak-*' -Force | Select-Object -First 1
        (Get-Content -LiteralPath $bak.FullName -Raw) | Should -Match 'my custom prompt'
    }

    It 'makes no new backup when a loader block is already present' {
        Set-Content -LiteralPath $script:profilePath -Value "# existing`r`n`r`n$script:body`r`n"
        Register-LoaderInProfile -ProfilePath $script:profilePath -Label 'PowerShell 7' `
            -InstallDir $script:fixture -LoaderBegin $script:begin -LoaderEnd $script:end -LoaderBody $script:body
        CountBaks | Should -Be 0
    }
}
```

- [ ] **Step 2: Run to verify it fails**

Run: `Invoke-Pester -Path .\tests\Install-Hardening.Tests.ps1 -Output Detailed`
Expected: FAIL — the second test fails because the current function never backs up the non-migration case (CountBaks is 0, expected 1).

- [ ] **Step 3: Modify the function** — replace the body of `Register-LoaderInProfile` so the read captures the original content, computes the block pattern early, adds the first-touch backup, and writes atomically:

```powershell
function Register-LoaderInProfile {
    param(
        [Parameter(Mandatory)][string]$ProfilePath,
        [Parameter(Mandatory)][string]$Label,
        [Parameter(Mandatory)][string]$InstallDir,
        [Parameter(Mandatory)][string]$LoaderBegin,
        [Parameter(Mandatory)][string]$LoaderEnd,
        [Parameter(Mandatory)][string]$LoaderBody
    )

    $profileDir = Split-Path $ProfilePath -Parent
    if (-not (Test-Path -LiteralPath $profileDir)) {
        New-Item -ItemType Directory -Force -Path $profileDir | Out-Null
    }

    # UTF-8 explicit (WinPS 5.1's Get-Content -Raw defaults to ANSI codepage).
    $existing = if (Test-Path -LiteralPath $ProfilePath) {
        [System.IO.File]::ReadAllText($ProfilePath, [System.Text.UTF8Encoding]::new($false))
    } else { '' }
    $originalContent = $existing

    $escBegin = [regex]::Escape($LoaderBegin)
    $escEnd   = [regex]::Escape($LoaderEnd)
    $blockPattern = "(?ms)$escBegin.*?$escEnd\r?\n?"

    $migrated = $false
    if ($existing.Trim().Length -gt 0) {
        $styleDirs = Get-ChildItem -LiteralPath (Join-Path $InstallDir 'styles') -Directory -ErrorAction SilentlyContinue
        foreach ($s in $styleDirs) {
            $sp = Join-Path $s.FullName 'profile.ps1'
            if (Test-Path -LiteralPath $sp) {
                $styleContent = [System.IO.File]::ReadAllText($sp, [System.Text.UTF8Encoding]::new($false))
                if ($styleContent.TrimEnd() -eq $existing.TrimEnd()) {
                    $bak = "$ProfilePath.bak-$(Get-Date -Format 'yyyyMMdd-HHmmss')"
                    Copy-Item -LiteralPath $ProfilePath -Destination $bak -Force
                    Write-Host "  Detected '$($s.Name)' style in $Label profile -- migrating into TerminalStyles." -ForegroundColor Yellow
                    Write-Host "  Original profile backed up to: $bak" -ForegroundColor Gray
                    Copy-Item -LiteralPath $sp -Destination (Join-Path $InstallDir 'current-style.ps1') -Force
                    $existing = ''
                    $migrated = $true
                    break
                }
            }
        }
    }

    # First-touch backup: the first time we add our loader to a profile that
    # has pre-existing user content and no loader block yet, preserve it.
    # Skip when we already migrated (that path backed up) or when our block
    # is already present (a re-register only swaps our own block).
    if (-not $migrated -and $originalContent.Trim().Length -gt 0 -and ($originalContent -notmatch $blockPattern)) {
        $bak = "$ProfilePath.bak-$(Get-Date -Format 'yyyyMMdd-HHmmss')"
        Copy-Item -LiteralPath $ProfilePath -Destination $bak -Force
        Write-Host "  Backed up your existing $Label profile to: $bak" -ForegroundColor Gray
    }

    if ($existing -match $blockPattern) {
        $existing = [regex]::Replace($existing, $blockPattern, '')
    }

    $final = ($existing.TrimEnd() + "`r`n`r`n" + $LoaderBody + "`r`n").TrimStart()
    Write-TextFileAtomic -Path $ProfilePath -Content $final
}
```

- [ ] **Step 4: Run to verify it passes**

Run: `Invoke-Pester -Path .\tests\Install-Hardening.Tests.ps1 -Output Detailed`
Expected: PASS (14 tests total).

- [ ] **Step 5: Commit**

```bash
git add install.ps1 tests/Install-Hardening.Tests.ps1
git commit -m "feat(install): atomic + first-touch-backed-up profile write"
```

---

### Task 6: `Test-PolicyResolved` + `Resolve-ExecutionPolicy` verification

Extracts the policy decision into a pure, testable helper, then rewires `Resolve-ExecutionPolicy` to re-query after `Set-ExecutionPolicy` and only claim success when the policy actually changed — plus a non-interactive guard around `Read-Host`. The shell-out itself stays integration-only.

**Files:**
- Modify: `install.ps1` (add `Test-PolicyResolved`; modify `Resolve-ExecutionPolicy`)
- Test: `tests/Install-Hardening.Tests.ps1` (add `Describe`)

**Interfaces:**
- Consumes: nothing.
- Produces: `Test-PolicyResolved -Policy <string>` → `$true` if the policy permits the loader (not `Restricted`/`AllSigned`/empty), else `$false`. `Resolve-ExecutionPolicy` (signature unchanged).

- [ ] **Step 1: Write the failing tests** — append:

```powershell
Describe 'Test-PolicyResolved' {
    BeforeAll {
        $script:installPath = Join-Path (Split-Path $PSScriptRoot -Parent) 'install.ps1'
        $TStylesInstallNoRun = $true
        . $script:installPath
    }

    It 'returns true for policies that allow scripts' {
        foreach ($p in 'RemoteSigned','Bypass','Unrestricted') {
            Test-PolicyResolved -Policy $p | Should -BeTrue
        }
    }

    It 'returns false for blocking or empty policies' {
        foreach ($p in 'Restricted','AllSigned','') {
            Test-PolicyResolved -Policy $p | Should -BeFalse
        }
        Test-PolicyResolved -Policy $null | Should -BeFalse
    }

    It 'tolerates surrounding whitespace' {
        Test-PolicyResolved -Policy "  RemoteSigned `r`n" | Should -BeTrue
        Test-PolicyResolved -Policy "  Restricted  "       | Should -BeFalse
    }
}
```

- [ ] **Step 2: Run to verify it fails**

Run: `Invoke-Pester -Path .\tests\Install-Hardening.Tests.ps1 -Output Detailed`
Expected: FAIL — `Test-PolicyResolved` is not defined.

- [ ] **Step 3: Add `Test-PolicyResolved` and rewrite `Resolve-ExecutionPolicy`** — in `install.ps1`:

```powershell
# --- Pure decision: does this effective policy permit the loader to run? ---
function Test-PolicyResolved {
    param([string]$Policy)
    return (-not [string]::IsNullOrWhiteSpace($Policy)) -and
           ($Policy.Trim() -notin @('Restricted', 'AllSigned'))
}

# --- Offer to fix Restricted/AllSigned execution policy for an engine ---
function Resolve-ExecutionPolicy {
    param(
        [Parameter(Mandatory)][string]$Exe,
        [Parameter(Mandatory)][string]$Label,
        [string]$EffectivePolicy
    )
    $cmd = Get-Command -Name $Exe -ErrorAction SilentlyContinue
    if (-not $cmd) { return }
    if (Test-PolicyResolved -Policy $EffectivePolicy) { return }   # already fine

    Write-Host ""
    Write-Host "  ! Script execution is disabled for $Label (effective policy: $($EffectivePolicy.Trim()))." -ForegroundColor Yellow
    Write-Host "    Without changing this, the TerminalStyles loader cannot run on shell startup." -ForegroundColor Yellow

    if (-not [Environment]::UserInteractive) {
        Write-Host "    Non-interactive session -- skipping the prompt. To fix, run in ${Label}:" -ForegroundColor DarkGray
        Write-Host "      Set-ExecutionPolicy -Scope CurrentUser RemoteSigned" -ForegroundColor Cyan
        return
    }

    $ans = Read-Host "    Set CurrentUser policy to RemoteSigned for $Label? [Y/n]"
    if (-not ([string]::IsNullOrWhiteSpace($ans) -or $ans -match '^(?i)y')) {
        Write-Host "    Skipped. To fix later, run in ${Label}:" -ForegroundColor DarkGray
        Write-Host "      Set-ExecutionPolicy -Scope CurrentUser RemoteSigned" -ForegroundColor Cyan
        return
    }

    try {
        # Set + re-query in one launch; the last non-empty line is the new policy.
        $out = & $cmd.Source -NoProfile -NonInteractive -Command `
            'Set-ExecutionPolicy -Scope CurrentUser RemoteSigned -Force; Get-ExecutionPolicy -Scope CurrentUser'
        $newPolicy = @($out | Where-Object { "$_".Trim() } | Select-Object -Last 1)[0]
        if (Test-PolicyResolved -Policy "$newPolicy") {
            Write-Host "    Done. CurrentUser policy is now $("$newPolicy".Trim()) for $Label." -ForegroundColor Green
        } else {
            Write-Host "    The policy did not change (still '$("$newPolicy".Trim())')." -ForegroundColor Red
            Write-Host "    A machine-wide policy (LocalMachine / GPO) may be blocking CurrentUser overrides." -ForegroundColor Yellow
            Write-Host "    Run this manually, elevated if needed:" -ForegroundColor Yellow
            Write-Host "      Set-ExecutionPolicy -Scope CurrentUser RemoteSigned" -ForegroundColor Cyan
        }
    } catch {
        Write-Host "    Could not set policy automatically: $_" -ForegroundColor Red
        Write-Host "    A machine-wide policy (LocalMachine / GPO) may be blocking CurrentUser overrides." -ForegroundColor Yellow
        Write-Host "    Run this manually, elevated if needed:" -ForegroundColor Yellow
        Write-Host "      Set-ExecutionPolicy -Scope CurrentUser RemoteSigned" -ForegroundColor Cyan
    }
}
```

- [ ] **Step 4: Run to verify it passes**

Run: `Invoke-Pester -Path .\tests\Install-Hardening.Tests.ps1 -Output Detailed`
Expected: PASS (17 tests total).

- [ ] **Step 5: Commit**

```bash
git add install.ps1 tests/Install-Hardening.Tests.ps1
git commit -m "feat(install): verify execution-policy change took effect"
```

---

### Task 7: Wire validations into the guarded main flow

Calls the new asserts at the right points in the imperative flow: validate the download before extract, confirm removal succeeded before the move, and assert the module landed after the move. This is an integration change to the guarded main; it is covered by the full suite plus a manual smoke.

**Files:**
- Modify: `install.ps1` (guarded main flow — download/install region)
- Test: none new (integration; verified by the full suite + manual)

**Interfaces:**
- Consumes: `Assert-ValidArchive` (Task 2), `Assert-InstallLanded` (Task 3).
- Produces: nothing.

- [ ] **Step 1: Add `Assert-ValidArchive` after the download** — in the guarded main, change the download region (old `173-181`) to:

```powershell
    # --- Download ---
    Write-InstallStep "Downloading"
    Invoke-WebRequest -Uri $zipUrl -OutFile $tempZip -UseBasicParsing
    Assert-ValidArchive -Path $tempZip
    Write-InstallStep "Downloading" -Check

    # --- Extract ---
    Write-InstallStep "Extracting"
    if (Test-Path -LiteralPath $tempDir) { Remove-Item -LiteralPath $tempDir -Recurse -Force }
    Expand-Archive -Path $tempZip -DestinationPath $tempDir -Force
    Write-InstallStep "Extracting" -Check
```

- [ ] **Step 2: Guard the remove, then assert landing around the move** — change the install region (old `213-216`) to:

```powershell
    if (Test-Path -LiteralPath $installDir) {
        Remove-Item -LiteralPath $installDir -Recurse -Force
        if (Test-Path -LiteralPath $installDir) {
            throw ("Could not fully remove the previous install at '$installDir' (a file lock may " +
                   "be held by another PowerShell tab, OneDrive, or antivirus). Close other " +
                   "PowerShell windows and re-run the installer.")
        }
    }
    Move-Item -LiteralPath $extractedRoot.FullName -Destination $installDir
    Assert-InstallLanded -InstallDir $installDir
```

- [ ] **Step 3: Run the full suite to confirm no regressions**

Run: `Invoke-Pester -Path .\tests -Output Detailed`
Expected: all tests PASS (existing suite + the 17 new install-hardening tests).

- [ ] **Step 4: Manual smoke (local, one-shot)**

In a pwsh 7 tab from the repo root, dot-source-free run against the local script with a deliberately bad URL to confirm the validation message, then a normal run:

```powershell
# Bad-download path: should print the clear "not a valid ZIP" / "empty" message and stop.
$env:TMP | Out-Null   # (sanity)
# (Manual: temporarily point $zipUrl at a non-zip URL in a scratch copy, run, observe message.)

# Happy path: run the real installer and confirm "Downloading [ok]" / "Extracting [ok]",
# the Ready panel, and that `tstyles` works in the same tab.
```

Expected: corrupt-download path fails fast with an actionable message; happy path installs and `tstyles` is available.

- [ ] **Step 5: Commit**

```bash
git add install.ps1
git commit -m "feat(install): wire archive + install-landed validation into main flow"
```

---

## Self-Review

**Spec coverage:**
- Problem #1 (no download validation) → Task 2 + Task 7 step 1. ✓
- Problem #2 (Move-Item nesting) → Task 3 + Task 7 step 2. ✓
- Problem #3 ($PROFILE non-atomic/unbacked) → Task 4 + Task 5. ✓
- Problem #4 (exec-policy false success + non-interactive) → Task 6. ✓
- Structural blocker (test seam) → Task 1. ✓
- Goal "confined to install.ps1 + one test file" → all tasks touch only those. ✓

**Placeholder scan:** No TBD/TODO; every code step shows complete code. The one manual step (Task 7 step 4) is inherently manual (installer shells out / hits the network) and the spec explicitly lists installer end-to-end as manual-only; it gives concrete observations to confirm.

**Type/name consistency:** `Assert-ValidArchive(-Path)`, `Assert-InstallLanded(-InstallDir)`, `Write-TextFileAtomic(-Path,-Content)`, `Test-PolicyResolved(-Policy)`, `Register-LoaderInProfile(-ProfilePath,-Label,-InstallDir,-LoaderBegin,-LoaderEnd,-LoaderBody)` are used identically in their definitions, their tests, and their call sites. Temp-file glob `*.tmp-*` (Task 4 test) matches the `'.' + leaf + '.tmp-' + guid` name produced in Task 4. Backup glob `*.ps1.bak-*` (Task 5 test) matches the `"$ProfilePath.bak-<ts>"` name where `$ProfilePath` ends in `.ps1`.
