# `tstyles register` Subcommand Implementation Plan (v0.2.2)

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Ship `TerminalStyles 0.2.2` adding the `tstyles register` subcommand. Auto-writes `Import-Module TerminalStyles -DisableNameChecking` (wrapped in the existing `# ===== TerminalStyles BEGIN/END =====` markers) to BOTH PowerShell engines' `$PROFILE` files. Closes the manual-edit gap documented in Sub-project C.

**Architecture:** New module-private `Invoke-TerminalStylesRegister` function discovers `pwsh.exe` and `powershell.exe`, queries each for its `$PROFILE`, detects existing loader blocks via the same regex `Invoke-TerminalStylesUninstall` uses, prompts once for confirmation across all targets, then writes idempotently. Wired into `Invoke-TerminalStyle`'s subcommand dispatch and the tab completer. Reuses the existing `$Force` switch on the public command for the "replace existing block" path.

**Tech Stack:** PowerShell 5.1+. Pester 5.x. No new dependencies.

**Spec:** `docs/superpowers/specs/2026-05-27-tstyles-register-design.md`

---

## File Structure

Five files modified / created.

- **Modify:** `tstyles.ps1` — add `Invoke-TerminalStylesRegister` (~80 lines), add 1 dispatch line in `Invoke-TerminalStyle`, add `'register'` to the tab completer's subcommands list.
- **Create:** `tests/Invoke-TerminalStylesRegister.Tests.ps1` — 3 tests (fresh profile, idempotent re-run, `-Force` replace).
- **Modify:** `README.md` — add a one-line mention of `tstyles register` in the `## Install` section, add `tstyles register` row to the Subcommands listing.
- **Modify:** `TerminalStyles.psd1` — `ModuleVersion 0.2.1 → 0.2.2`, update `ReleaseNotes`.
- **No change:** `install.ps1`, `apply.ps1`, `scripts/publish.ps1`, the other test files, `docs/RELEASING.md`.

**Task ordering** keeps CI green at every commit boundary:

1. **Task 1:** Add the `Invoke-TerminalStylesRegister` function (defined but NOT yet dispatched from `tstyles`) + 3 Pester tests against the function in isolation. Tests 50 → 53.
2. **Task 2:** Wire the function into `Invoke-TerminalStyle`'s subcommand dispatch + add `'register'` to the tab completer. After this commit, `tstyles register` works end-to-end.
3. **Task 3:** README rewrite (Install section + Subcommands listing).
4. **Task 4:** Bump `ModuleVersion` to `0.2.2` + update `ReleaseNotes`.
5. **Task 5:** Push + publish + smoke-test from clean shell + tag `v0.2.2`.

---

## Task 1: Add `Invoke-TerminalStylesRegister` function + its test file

**Files:**
- Modify: `tstyles.ps1` (insert new function near `Invoke-TerminalStylesUpdate` and `Invoke-TerminalStylesUninstall`)
- Create: `tests/Invoke-TerminalStylesRegister.Tests.ps1`

Function exists but isn't called from the CLI dispatch yet. Task 2 wires it in. The 3 Pester tests invoke it directly via `InModuleScope`.

- [ ] **Step 1: Insert `Invoke-TerminalStylesRegister` into `tstyles.ps1`**

Open `tstyles.ps1`. Find the existing function `Invoke-TerminalStylesUninstall`. Insert the new function IMMEDIATELY ABOVE `Invoke-TerminalStylesUninstall` (uninstall is the natural neighbor — same domain of $PROFILE editing).

Exact text to insert (then the existing `function Invoke-TerminalStylesUninstall {` line follows immediately):

```powershell
function Invoke-TerminalStylesRegister {
    # Adds `Import-Module TerminalStyles -DisableNameChecking` to both
    # PowerShell engines' $PROFILE files, wrapped in the same
    # # ===== TerminalStyles BEGIN ===== / END markers that
    # Invoke-TerminalStylesUninstall knows how to strip.
    #
    # Idempotent: skips an engine whose $PROFILE already has the block.
    # -Force replaces the existing block (strip + re-add).
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
    $shells = @(
        @{ Exe = 'pwsh.exe';       Label = 'PowerShell 7' },
        @{ Exe = 'powershell.exe'; Label = 'Windows PowerShell 5.1' }
    )
    $targets = @()
    foreach ($s in $shells) {
        $cmd = Get-Command -Name $s.Exe -ErrorAction SilentlyContinue
        if (-not $cmd) { continue }
        $profilePath = & $cmd.Source -NoProfile -NonInteractive -Command 'Write-Output $PROFILE' 2>$null
        if (-not $profilePath) { continue }
        $profilePath = "$profilePath".Trim()
        if (-not $profilePath) { continue }
        $targets += [pscustomobject]@{
            Label       = $s.Label
            ProfilePath = $profilePath
            Exists      = Test-Path -LiteralPath $profilePath
            HasLoader   = $false
        }
    }

    if (-not $targets) {
        Write-Host ""
        Write-Host "Neither pwsh.exe nor powershell.exe was found on PATH. Nothing to do." -ForegroundColor Yellow
        return
    }

    # Detect existing loader block per target
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

    # Write the block per target (strip first for -Force path)
    foreach ($t in $toWrite) {
        $profileDir = Split-Path -Parent $t.ProfilePath
        if ($profileDir -and -not (Test-Path -LiteralPath $profileDir)) {
            New-Item -ItemType Directory -Path $profileDir -Force | Out-Null
        }

        $existing = if ($t.Exists) {
            [System.IO.File]::ReadAllText($t.ProfilePath, [System.Text.UTF8Encoding]::new($false))
        } else { '' }

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

Use Edit with anchor `function Invoke-TerminalStylesUninstall {` (unique in the file). Prepend the new function plus a blank line.

- [ ] **Step 2: Create `tests/Invoke-TerminalStylesRegister.Tests.ps1`**

Create the new file at `C:\Users\felip\dotfiles\tests\Invoke-TerminalStylesRegister.Tests.ps1` with this exact content:

```powershell
# Pester 5 tests for Invoke-TerminalStylesRegister.
#
# Function adds `Import-Module TerminalStyles -DisableNameChecking` to
# both PowerShell engines' $PROFILE files (wrapped in BEGIN/END markers
# so uninstall can strip it). Tests cover:
#   1. Fresh $PROFILE -> block added
#   2. Existing loader -> skipped (idempotent)
#   3. -Force with existing -> block replaced (still exactly one block)
#
# Mocks: Get-Command (engine discovery), the engine-launch invocation
# (returns a $TestDrive path), and Read-Host (returns '' = default Y).
# Single-engine setup keeps the tests deterministic.
#
# Run: Invoke-Pester -Path tests
# Requires: Pester 5+

#Requires -Modules @{ ModuleName = 'Pester'; ModuleVersion = '5.0.0' }

BeforeDiscovery {
    $repoRoot = Split-Path $PSScriptRoot -Parent
    Import-Module (Join-Path $repoRoot 'TerminalStyles.psd1') -Force -DisableNameChecking *> $null
}

BeforeAll {
    $repoRoot = Split-Path $PSScriptRoot -Parent
    Import-Module (Join-Path $repoRoot 'TerminalStyles.psd1') -Force -DisableNameChecking *> $null
}

Describe 'Invoke-TerminalStylesRegister' {
    InModuleScope TerminalStyles {
        BeforeEach {
            # Mock single-engine discovery: only pwsh.exe is "available".
            $script:fakeProfile = Join-Path $TestDrive 'fake-profile.ps1'
            Mock Get-Command -ParameterFilter { $Name -eq 'pwsh.exe' } -MockWith {
                [pscustomobject]@{ Source = 'C:\fake\pwsh.exe' }
            }
            Mock Get-Command -ParameterFilter { $Name -eq 'powershell.exe' } -MockWith { $null }
            # Mock the engine launch that queries $PROFILE; capture the call and
            # return our $TestDrive fake-profile path.
            $script:fakeProfileForMock = $script:fakeProfile
            Mock Invoke-Command {} # no-op for any incidental Invoke-Command (defensive)
            # The function uses `& $cmd.Source -NoProfile -NonInteractive -Command '...'`.
            # We can't easily mock the `&` call operator, but we CAN mock the launch by
            # intercepting Start-Process or similar. Simpler approach: redirect via the
            # function's actual mechanism. PowerShell mocks `& <command>` calls when the
            # command name (here 'C:\fake\pwsh.exe') is mockable. Since the path is fake
            # and we mocked Get-Command, the function will get the mocked $cmd.Source
            # and try to invoke it. To avoid the actual invocation, mock the call via
            # a wrapper:
            #
            # Workaround: instead of mocking & directly, we set up the function to
            # see a real path. But the test scope doesn't need a real pwsh; we just
            # need $cmd.Source to resolve to *something* and the subsequent invocation
            # to return our path.
            #
            # Pragmatic approach: directly inject into the function's scope by
            # mocking the entire path-discovery step. Since that's not cleanly
            # mockable here, we override the function's effective behavior by
            # mocking Test-Path / WriteAllText etc. -- BUT a cleaner test design is
            # to mock at the System.IO.File level:
            #
            # ... see actual test code below for the chosen pattern.
            Mock Read-Host { '' }  # default Y on confirm prompt
        }

        It 'writes the loader block to a fresh $PROFILE' {
            # Direct approach: skip the engine-discovery complexity by mocking the
            # function's internal targets list. We can't mock module-internal local
            # vars, BUT we can ensure the discovery code path runs once with the
            # mocks above and asserts on the resulting file state.

            # Workaround: tee the engine-launch via a temporary alias for $cmd.Source.
            # Since mocking the call operator (&) is non-trivial in Pester, simulate
            # by pre-creating the conditions: a single-engine discovery that returns
            # our fake profile path. We do this by making the function use a TEMPORARY
            # override of the engine list. Easiest: extract no logic, just verify
            # END STATE after running:

            # Pre-condition: fakeProfile doesn't exist
            Test-Path -LiteralPath $script:fakeProfile | Should -BeFalse

            # We can't easily run the real function with mocked engine launches in
            # Pester 5 without major fixture work. Instead, test the WRITE path
            # directly by extracting the write logic into a callable form, OR by
            # accepting that this test verifies the LOADER BODY CONSTANT and the
            # WRITE FORMAT via a synthetic call. Approach: call the function with
            # a temporary script-scope override of $shells via a parameter passthrough
            # (which the production function doesn't accept).

            # Cleanest: refactor the function so it accepts a -Targets parameter for
            # testability. (Plan author decision: add `-Targets` switch to function
            # signature, defaulting to internal discovery. Tests pass in synthetic
            # targets.)

            # For now this test asserts on the WRITE path via direct invocation with
            # a hand-built target list. If the function doesn't support this, the
            # test should be marked Skip until refactored.

            Set-ItResult -Skipped -Because 'Test scaffolding requires function refactor to accept -Targets; see test file notes.'
        }

        It 'is idempotent: re-running with existing loader skips' {
            Set-ItResult -Skipped -Because 'Same scaffolding limitation as test 1.'
        }

        It '-Force replaces an existing loader block' {
            Set-ItResult -Skipped -Because 'Same scaffolding limitation as test 1.'
        }
    }
}
```

**Important note about this test file**: Pester 5's mocking model can't cleanly intercept the `& $cmd.Source` call-operator invocation that `Invoke-TerminalStylesRegister` uses to query each engine's `$PROFILE`. The cleanest way to make this testable is to refactor the function so it accepts a `-Targets` parameter (an array of objects with `ProfilePath`, `Exists`, `HasLoader`), defaulting to internal discovery when not passed. Tests then pass in synthetic targets pointing at `$TestDrive`.

**This refactor is part of Task 1.** Update the function signature in Step 1 to:

```powershell
[CmdletBinding()]
param(
    [switch]$Force,
    [object[]]$Targets   # internal/test injection; null = discover real engines
)
```

And inside the function, before the engine-discovery loop, add:

```powershell
    if (-not $Targets) {
        # ... existing discovery loop, populating $targets ...
    } else {
        $targets = @($Targets)
    }
```

(With this refactor, the test file becomes much cleaner — see Step 2b for the rewritten version.)

- [ ] **Step 2a: Refactor `Invoke-TerminalStylesRegister` to accept `-Targets`**

Update the function's `param` block to include the new parameter:

```powershell
    [CmdletBinding()]
    param(
        [switch]$Force,
        [object[]]$Targets   # internal/test injection; null = discover real engines
    )
```

And wrap the engine-discovery block with a conditional:

```powershell
    if (-not $Targets) {
        # Discover both engines, get $PROFILE per engine
        $shells = @(
            @{ Exe = 'pwsh.exe';       Label = 'PowerShell 7' },
            @{ Exe = 'powershell.exe'; Label = 'Windows PowerShell 5.1' }
        )
        $targets = @()
        foreach ($s in $shells) {
            $cmd = Get-Command -Name $s.Exe -ErrorAction SilentlyContinue
            if (-not $cmd) { continue }
            $profilePath = & $cmd.Source -NoProfile -NonInteractive -Command 'Write-Output $PROFILE' 2>$null
            if (-not $profilePath) { continue }
            $profilePath = "$profilePath".Trim()
            if (-not $profilePath) { continue }
            $targets += [pscustomobject]@{
                Label       = $s.Label
                ProfilePath = $profilePath
                Exists      = Test-Path -LiteralPath $profilePath
                HasLoader   = $false
            }
        }
    } else {
        $targets = @($Targets)
        # For test-injected targets, ensure required fields exist
        foreach ($t in $targets) {
            if ($null -eq $t.Exists)    { $t | Add-Member -NotePropertyName Exists    -NotePropertyValue (Test-Path -LiteralPath $t.ProfilePath) -Force }
            if ($null -eq $t.HasLoader) { $t | Add-Member -NotePropertyName HasLoader -NotePropertyValue $false -Force }
            if ($null -eq $t.Label)     { $t | Add-Member -NotePropertyName Label     -NotePropertyValue 'PowerShell' -Force }
        }
    }
```

The rest of the function (loader-detection, prompt, write) stays unchanged.

- [ ] **Step 2b: Replace the test file with the working version**

Now that the function accepts `-Targets`, replace the test file content with:

```powershell
# Pester 5 tests for Invoke-TerminalStylesRegister.
#
# Function adds `Import-Module TerminalStyles -DisableNameChecking` to
# both PowerShell engines' $PROFILE files (wrapped in BEGIN/END markers
# so uninstall can strip it). Tests use the function's -Targets
# parameter to inject a synthetic single-target list pointing at
# $TestDrive, bypassing the real engine discovery.
#
# Run: Invoke-Pester -Path tests
# Requires: Pester 5+

#Requires -Modules @{ ModuleName = 'Pester'; ModuleVersion = '5.0.0' }

BeforeDiscovery {
    $repoRoot = Split-Path $PSScriptRoot -Parent
    Import-Module (Join-Path $repoRoot 'TerminalStyles.psd1') -Force -DisableNameChecking *> $null
}

BeforeAll {
    $repoRoot = Split-Path $PSScriptRoot -Parent
    Import-Module (Join-Path $repoRoot 'TerminalStyles.psd1') -Force -DisableNameChecking *> $null
}

Describe 'Invoke-TerminalStylesRegister' {
    InModuleScope TerminalStyles {
        BeforeEach {
            $script:fakeProfile = Join-Path $TestDrive 'fake-profile.ps1'
            $script:loaderBegin = '# ===== TerminalStyles BEGIN ====='
            $script:loaderEnd   = '# ===== TerminalStyles END ====='
            $script:blockPattern = "(?ms)$([regex]::Escape($script:loaderBegin)).*?$([regex]::Escape($script:loaderEnd))\r?\n?"
            Mock Read-Host { '' }  # default Y on confirm prompt
        }

        It 'writes the loader block to a fresh $PROFILE' {
            # Pre-condition: fakeProfile doesn't exist
            Test-Path -LiteralPath $script:fakeProfile | Should -BeFalse

            $target = [pscustomobject]@{
                Label       = 'PowerShell 7'
                ProfilePath = $script:fakeProfile
                Exists      = $false
                HasLoader   = $false
            }
            Invoke-TerminalStylesRegister -Targets @($target)

            Test-Path -LiteralPath $script:fakeProfile | Should -BeTrue
            $content = [System.IO.File]::ReadAllText($script:fakeProfile, [System.Text.UTF8Encoding]::new($false))
            $content | Should -Match $script:blockPattern
            $content | Should -Match 'Import-Module TerminalStyles -DisableNameChecking'
        }

        It 'is idempotent: re-running with existing loader skips' {
            # Pre-populate with a BEGIN/END block
            $existingContent = "# my existing profile`r`n`r`n$script:loaderBegin`r`nImport-Module TerminalStyles -DisableNameChecking`r`n$script:loaderEnd`r`n"
            [System.IO.File]::WriteAllText($script:fakeProfile, $existingContent, [System.Text.UTF8Encoding]::new($false))
            $before = [System.IO.File]::ReadAllText($script:fakeProfile, [System.Text.UTF8Encoding]::new($false))

            $target = [pscustomobject]@{
                Label       = 'PowerShell 7'
                ProfilePath = $script:fakeProfile
                Exists      = $true
                HasLoader   = $true
            }
            Invoke-TerminalStylesRegister -Targets @($target)

            # Content unchanged
            $after = [System.IO.File]::ReadAllText($script:fakeProfile, [System.Text.UTF8Encoding]::new($false))
            $after | Should -Be $before
            # Exactly one BEGIN/END block (no duplicates)
            ([regex]::Matches($after, $script:blockPattern)).Count | Should -Be 1
        }

        It '-Force replaces an existing loader block' {
            # Pre-populate with a BEGIN/END block whose body is DIFFERENT (legacy format)
            $oldBody = "$script:loaderBegin`r`n. `"`$env:LOCALAPPDATA\TerminalStyles\tstyles.ps1`"`r`n$script:loaderEnd"
            $existingContent = "# my existing profile`r`n`r`n$oldBody`r`n"
            [System.IO.File]::WriteAllText($script:fakeProfile, $existingContent, [System.Text.UTF8Encoding]::new($false))

            $target = [pscustomobject]@{
                Label       = 'PowerShell 7'
                ProfilePath = $script:fakeProfile
                Exists      = $true
                HasLoader   = $true
            }
            Invoke-TerminalStylesRegister -Force -Targets @($target)

            $after = [System.IO.File]::ReadAllText($script:fakeProfile, [System.Text.UTF8Encoding]::new($false))
            # Exactly one BEGIN/END block
            ([regex]::Matches($after, $script:blockPattern)).Count | Should -Be 1
            # The new body is the canonical PSGallery loader (NOT the legacy dot-source)
            $after | Should -Match 'Import-Module TerminalStyles -DisableNameChecking'
            $after | Should -Not -Match 'LOCALAPPDATA\\TerminalStyles\\tstyles\.ps1'
        }
    }
}
```

(3 tests. The function's `-Targets` parameter makes them clean and deterministic.)

- [ ] **Step 3: Run the new test file**

```powershell
pwsh -NoProfile -Command "Invoke-Pester -Path .\tests\Invoke-TerminalStylesRegister.Tests.ps1 -Output Detailed"
```

Expected: 3 tests pass, 0 failed.

- [ ] **Step 4: Run the full suite**

```powershell
pwsh -NoProfile -Command "Invoke-Pester -Path .\tests -Output Minimal 2>&1 | Select-Object -Last 3"
```

Expected: `Tests Passed: 53, Failed: 0, ...` (50 existing + 3 new).

- [ ] **Step 5: Commit**

```bash
git add tstyles.ps1 tests/Invoke-TerminalStylesRegister.Tests.ps1
git commit -m "$(cat <<'EOF'
Add Invoke-TerminalStylesRegister function + tests

New module-private function adds `Import-Module TerminalStyles
-DisableNameChecking` (wrapped in the existing BEGIN/END markers) to
both PowerShell engines' $PROFILE files. Idempotent (skip if already
registered); -Force replaces.

Not wired into the `tstyles` CLI dispatch yet -- Task 2 of the
register plan does that.

Function takes a -Targets parameter for testability: tests pass in
a synthetic single-target list pointing at $TestDrive, bypassing the
real engine discovery (Get-Command + & $cmd.Source) which Pester 5
can't cleanly mock. Real callers don't pass -Targets and get the
normal two-engine discovery.

3 new Pester tests cover the fresh-write, idempotent-skip, and
-Force-replace paths.

Spec: docs/superpowers/specs/2026-05-27-tstyles-register-design.md
EOF
)"
```

---

## Task 2: Wire `register` into the subcommand dispatch + tab completer

**Files:**
- Modify: `tstyles.ps1` (one new dispatch line + add `'register'` to tab completer)

After this task, `tstyles register` actually works from the CLI.

- [ ] **Step 1: Add the dispatch line in `Invoke-TerminalStyle`**

Find the subcommand dispatch block in `tstyles.ps1` (currently around line 580). Look for the line containing `if ($Arg -eq 'uninstall')`. The block looks like:

```powershell
    if ($Update -or $Arg -eq 'update')   { Invoke-TerminalStylesUpdate -Force:$Force; return }
    if ($Arg -eq 'list' -or $Arg -eq 'ls') { Show-StyleList;                return }
    if ($Arg -eq 'current')              { Show-CurrentStyle;               return }
    if ($Arg -eq 'random')               { Invoke-RandomStyle;              return }
    if ($Arg -eq 'uninstall')            { Invoke-TerminalStylesUninstall;  return }
```

Add ONE line for `register` between `random` and `uninstall` (alphabetical-ish ordering):

```powershell
    if ($Update -or $Arg -eq 'update')   { Invoke-TerminalStylesUpdate -Force:$Force; return }
    if ($Arg -eq 'list' -or $Arg -eq 'ls') { Show-StyleList;                return }
    if ($Arg -eq 'current')              { Show-CurrentStyle;               return }
    if ($Arg -eq 'random')               { Invoke-RandomStyle;              return }
    if ($Arg -eq 'register')             { Invoke-TerminalStylesRegister -Force:$Force; return }
    if ($Arg -eq 'uninstall')            { Invoke-TerminalStylesUninstall;  return }
```

Use Edit with the existing `random` and `uninstall` lines as anchor (or use a larger surrounding block to make the match unique).

- [ ] **Step 2: Add `'register'` to the tab completer's subcommands list**

Find the `Register-ArgumentCompleter` block at the bottom of `tstyles.ps1` (the `$subcommands` variable is the target):

```powershell
    $subcommands = @('list', 'current', 'random', 'update', 'uninstall')
```

Replace with:

```powershell
    $subcommands = @('list', 'current', 'random', 'register', 'update', 'uninstall')
```

(Alphabetical: `register` slots between `random` and `update`.)

- [ ] **Step 3: Sanity-check `tstyles register` is now callable**

```powershell
pwsh -NoProfile -Command "Import-Module .\TerminalStyles.psd1 -Force -DisableNameChecking; Get-Command tstyles | Format-List Name, CommandType; Write-Host '---'; Write-Host 'Tab completion for tstyles r:'; TabExpansion2 -inputScript 'tstyles r' -cursorColumn 9 | ForEach-Object CompletionMatches | ForEach-Object CompletionText"
```

Expected:
- `Name : tstyles` + CommandType: Alias
- Tab completion includes `random` AND `register` (and possibly `rain` if any theme starts with 'r').

If `register` doesn't appear, the tab completer change didn't take. Re-check Step 2.

- [ ] **Step 4: Run the full Pester suite**

```powershell
pwsh -NoProfile -Command "Invoke-Pester -Path .\tests -Output Minimal 2>&1 | Select-Object -Last 3"
```

Expected: `Tests Passed: 53, Failed: 0, ...`

- [ ] **Step 5: Commit**

```bash
git add tstyles.ps1
git commit -m "$(cat <<'EOF'
Wire `tstyles register` into Invoke-TerminalStyle dispatch + tab completer

One new dispatch line in Invoke-TerminalStyle routes `tstyles register`
to Invoke-TerminalStylesRegister (added in the previous commit).
`tstyles register -Force` is supported via the existing -Force switch
on the public command.

Tab completer's $subcommands list gains 'register' so `tstyles r<TAB>`
includes it.

Spec: docs/superpowers/specs/2026-05-27-tstyles-register-design.md
EOF
)"
```

---

## Task 3: README — document `tstyles register`

**Files:**
- Modify: `README.md` (Install section + Subcommands listing)

Two small additions: a one-line mention in the Install flow, and a row in the Subcommands table.

- [ ] **Step 1: Add a `tstyles register` mention to the Install section**

Find this block in `README.md` (currently around lines 38-48):

```markdown
## Install

```powershell
Install-PSResource -Name TerminalStyles
Import-Module TerminalStyles -DisableNameChecking
```

Add the `Import-Module` line to your `$PROFILE` so it loads on every
new shell tab. Then:
```

Replace **the paragraph after the code block** with:

```markdown
## Install

```powershell
Install-PSResource -Name TerminalStyles
Import-Module TerminalStyles -DisableNameChecking
```

Add the `Import-Module` line to your `$PROFILE` so it loads on every
new shell tab — or run `tstyles register` once and it does that for
you (both pwsh 7 and Windows PowerShell 5.1 `$PROFILE` files, with a
confirm prompt first). Then:
```

- [ ] **Step 2: Add `tstyles register` to the Subcommands listing**

Find the existing Subcommands block (currently around lines 99-107):

```powershell
tstyles umbrella                  # Apply a specific style directly (no picker)
tstyles list                      # List all themes; '*' marks the active one
tstyles current                   # Print just the active style name
tstyles random                    # Pick a random style and apply it
tstyles update                    # PSGallery: Update-PSResource. Bootstrap: re-run installer.
tstyles uninstall                 # Remove module + strip $PROFILE loader. Preserves user state.
tstyles uninstall -DeleteData     # As above, plus delete %LOCALAPPDATA%\TerminalStyles\ entirely.
```

Add ONE line for `register` between `random` and `update`:

```powershell
tstyles umbrella                  # Apply a specific style directly (no picker)
tstyles list                      # List all themes; '*' marks the active one
tstyles current                   # Print just the active style name
tstyles random                    # Pick a random style and apply it
tstyles register                  # Auto-add `Import-Module TerminalStyles ...` to both $PROFILE files
tstyles update                    # PSGallery: Update-PSResource. Bootstrap: re-run installer.
tstyles uninstall                 # Remove module + strip $PROFILE loader. Preserves user state.
tstyles uninstall -DeleteData     # As above, plus delete %LOCALAPPDATA%\TerminalStyles\ entirely.
```

- [ ] **Step 3: Verify**

```powershell
pwsh -NoProfile -Command "Select-String -Path .\README.md -Pattern 'tstyles register'"
```

Expected: 2 matches (Install section paragraph + Subcommands listing).

- [ ] **Step 4: Commit**

```bash
git add README.md
git commit -m "$(cat <<'EOF'
README: document `tstyles register`

Two small additions to match v0.2.2 behavior:

- ## Install section: mention `tstyles register` as a one-line
  alternative to manually adding Import-Module to $PROFILE.
- ## Subcommands listing: new row for `tstyles register`.

Spec: docs/superpowers/specs/2026-05-27-tstyles-register-design.md
EOF
)"
```

---

## Task 4: Bump `ModuleVersion` to `0.2.2` + update `ReleaseNotes`

**Files:**
- Modify: `TerminalStyles.psd1`

- [ ] **Step 1: Bump the version**

Find:
```powershell
    ModuleVersion     = '0.2.1'
```

Replace with:
```powershell
    ModuleVersion     = '0.2.2'
```

- [ ] **Step 2: Update `ReleaseNotes`**

Find:
```powershell
            ReleaseNotes = 'v0.2.1: user-added themes at %LOCALAPPDATA%\TerminalStyles\styles\<name>\ are now picked up alongside bundled themes AND survive any update path (bootstrap re-install, Update-PSResource). User-wins on name collision lets you locally override a bundled theme without forking. Purely additive -- zero behavior change if you don''t use the new user-styles dir.'
```

Replace with:
```powershell
            ReleaseNotes = 'v0.2.2: new `tstyles register` subcommand auto-writes the Import-Module loader to both PowerShell engines'' $PROFILE files (with a confirm prompt). Closes the manual-edit gap for PSGallery installs. Idempotent; -Force replaces. Purely additive -- existing behavior unchanged.'
```

(Note doubled single-quote `engines'' $PROFILE` for PowerShell string escaping.)

- [ ] **Step 3: Verify the manifest parses**

```powershell
pwsh -NoProfile -Command "Test-ModuleManifest .\TerminalStyles.psd1 | Format-List Name, Version, ExportedFunctions, ExportedAliases"
```

Expected: `Version : 0.2.2` with the same exports as 0.2.1.

- [ ] **Step 4: Final Pester run before publish**

```powershell
pwsh -NoProfile -Command "Invoke-Pester -Path .\tests -Output Minimal 2>&1 | Select-Object -Last 3"
```

Expected: `Tests Passed: 53, Failed: 0, ...`

- [ ] **Step 5: Commit**

```bash
git add TerminalStyles.psd1
git commit -m "Bump version to 0.2.2 + update ReleaseNotes"
```

---

## Task 5: Push + publish 0.2.2 + smoke-test + tag

**Files:** None modified locally. PSGallery + git remote state changes.

Controller-handled (needs the API key for publish).

- [ ] **Step 1: Confirm pending commits + push**

```bash
git status
git log --oneline origin/main..HEAD
git push origin main
```

Expected: working tree clean. 4 commits ahead (Task 4 / Task 3 / Task 2 / Task 1). Push succeeds.

- [ ] **Step 2: Publish 0.2.2 via the existing script**

```powershell
pwsh -NoProfile -File ./scripts/publish.ps1 -ApiKey '<the-api-key>'
```

Expected output:

```
Staged TerminalStyles 0.2.2 at:
  C:\Users\felip\dotfiles\out\TerminalStyles

Published TerminalStyles 0.2.2 to PSGallery.
Verify at: https://www.powershellgallery.com/packages/TerminalStyles/0.2.2
```

- [ ] **Step 3: Verify on PSGallery**

```powershell
pwsh -NoProfile -Command "Find-PSResource -Name TerminalStyles -Repository PSGallery -Version '*' | Sort-Object Version -Descending | Select-Object -First 4 | Format-Table Name, Version"
```

Expected: 0.2.2 appears as the latest, with 0.2.1, 0.2.0, 0.1.0 still present.

- [ ] **Step 4: Smoke-test `tstyles register` end-to-end from a clean shell**

```powershell
pwsh -NoProfile -Command "Update-PSResource -Name TerminalStyles -TrustRepository; Import-Module TerminalStyles -Force -DisableNameChecking; Get-Module TerminalStyles | Format-List Name, Version, Path; Write-Host '---'; Get-Command tstyles -CommandType All | Format-List Name, CommandType, ModuleName"
```

Expected: `Version : 0.2.2`, `tstyles` Alias from TerminalStyles. Confirms 0.2.2 is what loaded.

Then smoke-test the register flow (use `-Targets` with a temp profile so we don't touch the real `$PROFILE`):

```powershell
pwsh -NoProfile -Command "Import-Module TerminalStyles -Force -DisableNameChecking; \$tmpProfile = Join-Path \$env:TEMP 'register-smoke.ps1'; Remove-Item \$tmpProfile -ErrorAction SilentlyContinue; Write-Host '--- Running register against synthetic target ---'; \$target = [pscustomobject]@{ Label = 'PowerShell 7'; ProfilePath = \$tmpProfile; Exists = \$false; HasLoader = \$false }; (Get-Module TerminalStyles).Invoke({ param(\$t) Mock Read-Host { '' }; Invoke-TerminalStylesRegister -Targets @(\$t) }, \$target); Write-Host '--- Resulting file ---'; Get-Content \$tmpProfile; Remove-Item \$tmpProfile -ErrorAction SilentlyContinue"
```

(Note: the `Mock Read-Host` inside `.Invoke` may not work the same way as in a real Pester test scope — if it fails to mock, the prompt fires interactively. If that happens, just press Enter to accept. The test is verifying the file gets written; the prompt is incidental.)

Expected: the resulting file contains the BEGIN/END block with `Import-Module TerminalStyles -DisableNameChecking`.

Easier smoke-test if the above is fiddly: just call `tstyles register` interactively and verify the loader appears in your real `$PROFILE`. Since the existing bootstrap-installed loader is already there (you've been using TerminalStyles all session), `tstyles register` will say "Already registered, skipping" in both engines — itself a verification that the dispatch + discovery work.

- [ ] **Step 5: Tag v0.2.2**

```bash
git tag v0.2.2
git push --tags
```

Expected: `* [new tag]         v0.2.2 -> v0.2.2`.

---

## Self-Review Notes

Spec coverage:

- `tstyles register` subcommand → Task 2 (dispatch wiring) + Task 1 (implementation).
- BEGIN/END marker wrapping → Task 1 Step 1 (`$loaderBegin` / `$loaderEnd` constants in the function body).
- Idempotent skip if loader exists → Task 1 Step 1 (`HasLoader` check) + Task 1 Step 2b's test 2.
- `-Force` replaces existing block → Task 1 Step 1 (`-not $Force` skip condition) + Task 1 Step 2b's test 3.
- Single combined confirm prompt → Task 1 Step 1 (single `Read-Host` after listing all targets).
- Tab completer learns 'register' → Task 2 Step 2.
- README mentions `tstyles register` in Install section + Subcommands listing → Task 3.
- Version bump → Task 4.
- Publish + verify → Task 5.

Spec items deliberately not in plan (per spec non-goals):
- No `-Quiet` flag — explicit non-goal.
- No `tstyles unregister` — use `tstyles uninstall` (existing).
- No auto-run of `tstyles register` from anywhere — explicit non-goal.

Type / signature consistency:

- `Invoke-TerminalStylesRegister -Force -Targets <array>` — same signature used in function definition, dispatch line, and 3 tests.
- `$loaderBegin` / `$loaderEnd` constants — same string in function + tests.
- Regex pattern `(?ms)<begin>.*?<end>\r?\n?` — same construction in function + tests + (already in) `Invoke-TerminalStylesUninstall`.

No placeholders. All code blocks complete and runnable.

Three judgment calls worth flagging:

- **Task 1 introduces a `-Targets` parameter** to the function for test injection. This is a real testability improvement but does add surface area. The parameter is undocumented in the README (correct — internal/test injection only) and defaults to internal engine discovery. Real callers never pass it.
- **Task 5 Step 4's smoke test of `tstyles register` is awkward** because the function prompts for confirmation. The plan provides two options: a `.Invoke()` route with a mock that may not work, or just call it interactively and verify the "Already registered" path. Either is acceptable; the unit tests in Task 1 cover the actual write logic.
- **The plan inlines API key for publish** (Task 5 Step 2) just like Sub-projects B, C, D. Same leak posture; user has accepted this.
