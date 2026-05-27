# TerminalStyles Module Restructure Implementation Plan (Sub-project A)

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Wrap `tstyles.ps1` as a proper PowerShell module (`TerminalStyles.psd1` + `TerminalStyles.psm1`) without restructuring the existing code. Switch `install.ps1` and the Pester tests from dot-source to `Import-Module`. Foundation for the upcoming PSGallery publish (sub-project B).

**Architecture:** `TerminalStyles.psm1` is a one-line dot-source of the existing `tstyles.ps1`. `TerminalStyles.psd1` is the manifest that exports `Invoke-TerminalStyle`, `Invoke-TerminalStylesUpdate`, and the `tstyles` alias. Install loader changes from `. "...\tstyles.ps1"` to `Import-Module "...\TerminalStyles.psd1" -DisableNameChecking`. Same-tab handoff uses `-Force -Global` so the import propagates into the caller's session through `iwr | iex`. Pester tests wrap module-private function calls in `InModuleScope TerminalStyles { ... }`.

**Tech Stack:** PowerShell 5.1+. Pester 5.x (already installed via CI's `Install-PSResource`). No new dependencies.

**Spec:** `docs/superpowers/specs/2026-05-27-module-restructure-design.md`

---

## File Structure

Two new files at the repo root; three test files modified; one install script modified. The existing `tstyles.ps1` is byte-unchanged.

- **Create:** `TerminalStyles.psd1` — module manifest with `RootModule = 'TerminalStyles.psm1'`, exports list, metadata.
- **Create:** `TerminalStyles.psm1` — single-line dot-source wrapper around `tstyles.ps1`.
- **Modify:** `install.ps1` — two surgical edits (loader heredoc body; same-tab handoff at end).
- **Modify:** `tests/Get-SchemeSwatch.Tests.ps1` — `Import-Module` + `InModuleScope` migration.
- **Modify:** `tests/Test-UpdateAvailable.Tests.ps1` — same pattern.
- **Modify:** `tests/Apply-StyleDirect-Backup.Tests.ps1` — same pattern.
- **No change:** `tstyles.ps1`, `apply.ps1`, `README.md`, `.github/workflows/test.yml`, anything under `styles/`.

**Task ordering** keeps CI green at every commit boundary:

1. Create the module files. After this commit, `Import-Module .\TerminalStyles.psd1` works locally but tests still dot-source and install.ps1 still dot-sources. Everything green.
2. Migrate the Pester tests to `Import-Module` + `InModuleScope`. Tests now exercise the module; install.ps1 still dot-sources but tstyles.ps1 hasn't moved, so the installed copy still loads via dot-source line in $PROFILE. CI green.
3. Update `install.ps1`. New installs (and `tstyles update`) get the `Import-Module` loader; existing tabs already loaded keep working. CI green.
4. End-to-end test + push.

---

## Task 1: Create the module manifest and entry file

**Files:**
- Create: `TerminalStyles.psd1`
- Create: `TerminalStyles.psm1`

After this task, you can `Import-Module .\TerminalStyles.psd1 -DisableNameChecking` from the repo root and `tstyles` becomes a working alias in that session. The existing `tstyles.ps1` is unchanged.

- [ ] **Step 1: Generate a stable GUID for the manifest**

Run once and copy the output:

```powershell
pwsh -NoProfile -Command '[guid]::NewGuid().ToString()'
```

Expected output: something like `a1b2c3d4-e5f6-7890-abcd-ef1234567890`. **This GUID is pinned for the life of the module — never change it after the first commit.** PowerShell uses it to uniquely identify the module across installs and PSGallery entries.

- [ ] **Step 2: Create `TerminalStyles.psd1`**

Create the file at `C:\Users\felip\dotfiles\TerminalStyles.psd1` with this exact content, **substituting the GUID from Step 1**:

```powershell
@{
    RootModule        = 'TerminalStyles.psm1'
    ModuleVersion     = '0.1.0'
    GUID              = 'PASTE-GUID-FROM-STEP-1-HERE'
    Author            = 'Felipe Cremerius'
    CompanyName       = 'fcreme'
    Copyright         = '(c) 2026 Felipe Cremerius. MIT.'
    Description       = 'Windows Terminal themes for PowerShell -- 16 bundled styles with arrow-key live-preview picker.'
    PowerShellVersion = '5.1'

    FunctionsToExport = @('Invoke-TerminalStyle', 'Invoke-TerminalStylesUpdate')
    AliasesToExport   = @('tstyles')
    CmdletsToExport   = @()
    VariablesToExport = @()

    PrivateData = @{
        PSData = @{
            Tags         = @('WindowsTerminal', 'Themes', 'Color', 'Prompt', 'pwsh')
            LicenseUri   = 'https://github.com/fcreme/TerminalStyles/blob/main/LICENSE'
            ProjectUri   = 'https://github.com/fcreme/TerminalStyles'
            ReleaseNotes = 'Initial module structure (sub-project A of the PSGallery migration). No behavior changes from the prior dot-sourced install.'
        }
    }
}
```

Notes:
- `CmdletsToExport` / `VariablesToExport` set to `@()` (empty array), not `@('*')`. PSGallery rejects wildcards, and explicit empty arrays speed up module auto-loading.
- Use the en-dash-free description (`--` instead of `—`) — manifests are evaluated in invariant culture and some downlevel parsers choke on non-ASCII.

- [ ] **Step 3: Create `TerminalStyles.psm1`**

Create the file at `C:\Users\felip\dotfiles\TerminalStyles.psm1` with this exact content:

```powershell
# TerminalStyles module entry. Dot-sources tstyles.ps1 to bring its
# functions and the `tstyles` alias into module scope. The manifest
# (TerminalStyles.psd1) controls what's exported to consumers.
#
# tstyles.ps1 stays unchanged so that apply.ps1 (a standalone script)
# can keep using the same library directly, and so that the existing
# test fixtures stay familiar.

. (Join-Path $PSScriptRoot 'tstyles.ps1')
```

That's the entire file. Three lines of comment + one line of code.

- [ ] **Step 4: Verify the manifest parses**

```powershell
pwsh -NoProfile -Command "Test-ModuleManifest .\TerminalStyles.psd1 | Format-List Name, Version, RootModule, ExportedFunctions, ExportedAliases"
```

Expected output:

```
Name              : TerminalStyles
Version           : 0.1.0
RootModule        : TerminalStyles.psm1
ExportedFunctions : {[Invoke-TerminalStyle, Invoke-TerminalStyle], [Invoke-TerminalStylesUpdate, Invoke-TerminalStylesUpdate]}
ExportedAliases   : {[tstyles, tstyles]}
```

If you see a parser error, the most likely cause is the GUID format (it must be a parseable `[guid]`). If `ExportedFunctions` is empty, check that the functions exist in `tstyles.ps1` — they're declared but the manifest can't see them until the module is actually imported (which `Test-ModuleManifest` doesn't do; it just parses metadata).

- [ ] **Step 5: Verify the module imports and the alias works**

```powershell
pwsh -NoProfile -Command "Import-Module .\TerminalStyles.psd1 -DisableNameChecking; Get-Command -Module TerminalStyles | Format-Table Name, CommandType, ModuleName -AutoSize"
```

Expected output (order may vary):

```
Name                         CommandType ModuleName
----                         ----------- ----------
Invoke-TerminalStyle            Function TerminalStyles
Invoke-TerminalStylesUpdate     Function TerminalStyles
tstyles                            Alias TerminalStyles
```

If `tstyles` is missing from the alias list, the `Set-Alias` at the bottom of `tstyles.ps1` (line 1034) ran in module scope but wasn't re-exported. Add `Export-ModuleMember -Alias tstyles` to `TerminalStyles.psm1` and re-test.

- [ ] **Step 6: Verify tab completion is registered**

```powershell
pwsh -NoProfile -Command "Import-Module .\TerminalStyles.psd1 -DisableNameChecking; TabExpansion2 -inputScript 'tstyles l' -cursorColumn 9 | ForEach-Object CompletionMatches | ForEach-Object CompletionText"
```

Expected output:

```
list
```

(The completer might also suggest `lain` if that style exists — that's fine; the test passes as long as `list` appears.)

If nothing is output, the `Register-ArgumentCompleter` call at `tstyles.ps1:1039` didn't survive the module import. PowerShell's argument completers are global by default, so this should work — but verify.

- [ ] **Step 7: Commit**

```bash
git add TerminalStyles.psd1 TerminalStyles.psm1
git commit -m "$(cat <<'EOF'
Add TerminalStyles.psd1 manifest and TerminalStyles.psm1 entry

Two new files at the repo root that wrap the existing tstyles.ps1
as a proper PowerShell module:

- TerminalStyles.psd1: manifest exporting Invoke-TerminalStyle,
  Invoke-TerminalStylesUpdate, and the `tstyles` alias.
- TerminalStyles.psm1: one-line dot-source wrapper around the
  unchanged tstyles.ps1.

tstyles.ps1 is byte-unchanged; install.ps1 and the Pester tests
still use the dot-source path in this commit (they migrate to
Import-Module in follow-up commits).

Spec: docs/superpowers/specs/2026-05-27-module-restructure-design.md
EOF
)"
```

---

## Task 2: Migrate Pester tests to `Import-Module` + `InModuleScope`

**Files:**
- Modify: `tests/Get-SchemeSwatch.Tests.ps1`
- Modify: `tests/Test-UpdateAvailable.Tests.ps1`
- Modify: `tests/Apply-StyleDirect-Backup.Tests.ps1`

All three test files currently do `. (Join-Path $repoRoot 'tstyles.ps1') *> $null` in `BeforeAll`. Migrate each to `Import-Module ... TerminalStyles.psd1 -Force -DisableNameChecking *> $null`, then wrap module-private function calls in `InModuleScope TerminalStyles { ... }`.

**Why `InModuleScope`?** After the manifest is applied, only `Invoke-TerminalStyle` and `Invoke-TerminalStylesUpdate` are visible outside the module. The tests call `Get-SchemeSwatch`, `Test-UpdateAvailable`, `Apply-StyleDirect`, `Find-WTSettingsPath`, etc. — all module-private. `InModuleScope` runs a scriptblock in the module's runspace where those private functions are visible. It's also where `Mock` calls have to live: mocks set outside `InModuleScope` don't intercept calls made from inside the module.

- [ ] **Step 1: Migrate `tests/Get-SchemeSwatch.Tests.ps1`**

Replace the entire file contents with:

```powershell
# Pester 5 tests for Get-SchemeSwatch (module-private).
#
# Module-restructure migration: dot-source replaced with Import-Module,
# Get-SchemeSwatch calls wrapped in InModuleScope so the test can see
# the module-private function.
#
# Guards against the two swatch bugs caught manually before the test
# was written:
#   1. "All themes look like rainbows": prior picks (brightRed / yellow /
#      brightGreen / brightCyan / brightPurple) sat in semantically fixed
#      hue slots, so every theme rendered the same red->yellow->green->
#      cyan->purple sequence regardless of palette. Now caught by the
#      cross-theme distinguishability assertion.
#   2. Collapsed cells: themes with cursorColor == foreground (sober,
#      gitbash) or cursorColor == brightRed (eva) used to render only 4
#      unique colors instead of 5. Now caught by the per-theme unique-
#      colors assertion.
#
# Run: Invoke-Pester (Join-Path $PSScriptRoot 'tests')
# Requires: Pester 5+

#Requires -Modules @{ ModuleName = 'Pester'; ModuleVersion = '5.0.0' }

BeforeDiscovery {
    $repoRoot = Split-Path $PSScriptRoot -Parent
    $themeNames = @(
        Get-ChildItem -Path (Join-Path $repoRoot 'styles') -Directory |
            Where-Object { Test-Path (Join-Path $_.FullName 'scheme.json') } |
            ForEach-Object { $_.Name } | Sort-Object
    )
}

BeforeAll {
    $repoRoot = Split-Path $PSScriptRoot -Parent
    Import-Module (Join-Path $repoRoot 'TerminalStyles.psd1') -Force -DisableNameChecking *> $null
}

Describe 'Get-SchemeSwatch' {
    Context 'For theme <_>' -ForEach $themeNames {
        BeforeAll {
            $themeName = $_
            $repoRoot  = Split-Path $PSScriptRoot -Parent
            $rgbs = InModuleScope TerminalStyles -Parameters @{ ThemeName = $themeName; RepoRoot = $repoRoot } {
                param($ThemeName, $RepoRoot)
                $schemePath = Join-Path $RepoRoot "styles\$ThemeName\scheme.json"
                $scheme = [System.IO.File]::ReadAllText($schemePath, [System.Text.UTF8Encoding]::new($false)) | ConvertFrom-Json
                $swatch = Get-SchemeSwatch -Scheme $scheme
                [regex]::Matches($swatch, '\[48;2;(\d+;\d+;\d+)m') | ForEach-Object { $_.Groups[1].Value }
            }
        }

        It 'produces exactly 5 colored cells' {
            $rgbs.Count | Should -Be 5
        }

        It 'has 5 unique cell colors (no collisions)' {
            ($rgbs | Select-Object -Unique).Count | Should -Be 5
        }
    }

    Context 'Across all themes' {
        It 'every pair of themes produces a byte-distinct swatch' {
            $repoRoot = Split-Path $PSScriptRoot -Parent
            $signatures = InModuleScope TerminalStyles -Parameters @{ ThemeNames = $themeNames; RepoRoot = $repoRoot } {
                param($ThemeNames, $RepoRoot)
                $sigs = @{}
                foreach ($name in $ThemeNames) {
                    $schemePath = Join-Path $RepoRoot "styles\$name\scheme.json"
                    $scheme = [System.IO.File]::ReadAllText($schemePath, [System.Text.UTF8Encoding]::new($false)) | ConvertFrom-Json
                    $swatch = Get-SchemeSwatch -Scheme $scheme
                    $rgbs = [regex]::Matches($swatch, '\[48;2;(\d+;\d+;\d+)m') | ForEach-Object { $_.Groups[1].Value }
                    $sigs[$name] = $rgbs -join '|'
                }
                $sigs
            }
            $names = @($themeNames)
            $collisions = @()
            for ($i = 0; $i -lt $names.Count; $i++) {
                for ($j = $i + 1; $j -lt $names.Count; $j++) {
                    if ($signatures[$names[$i]] -eq $signatures[$names[$j]]) {
                        $collisions += "$($names[$i]) == $($names[$j])"
                    }
                }
            }
            $collisions | Should -BeNullOrEmpty
        }
    }
}
```

Key migration changes:
- `BeforeAll` swaps dot-source for `Import-Module -Force`.
- The inline `Get-ThemeSwatchRGBs` helper is gone; its logic moved into `InModuleScope -Parameters @{...}` blocks so it can call `Get-SchemeSwatch` directly.
- `-Parameters @{...}` passes test-scope variables (`$themeName`, `$repoRoot`) into the module scope explicitly. `InModuleScope` scriptblocks don't see the outer scope's variables otherwise.

- [ ] **Step 2: Run the migrated swatch test**

```powershell
pwsh -NoProfile -Command "Invoke-Pester -Path .\tests\Get-SchemeSwatch.Tests.ps1 -Output Detailed"
```

Expected: 33 tests pass (2 per theme × 16 themes + 1 cross-theme).

If you see `The term 'Get-SchemeSwatch' is not recognized`, the `InModuleScope` wrapping was applied incorrectly. Re-check the per-theme `BeforeAll` and the cross-theme `It` — both must put the `Get-SchemeSwatch` call inside an `InModuleScope` block.

- [ ] **Step 3: Migrate `tests/Test-UpdateAvailable.Tests.ps1`**

Replace the entire file contents with:

```powershell
# Pester 5 tests for Test-UpdateAvailable (the 24h-throttled update check).
#
# Module-restructure migration: dot-source replaced with Import-Module,
# all test bodies wrapped in InModuleScope TerminalStyles so the mocks
# intercept module-internal calls and Test-UpdateAvailable resolves.
#
# Locks in the throttle invariants from
# docs/superpowers/specs/2026-05-27-update-check-throttle-design.md:
#   - Fresh stamp short-circuits the API call entirely (no IRM invocation).
#   - Stale / missing stamp triggers the API call and writes a fresh stamp.
#   - Corrupt stamp falls through and self-heals (overwritten with valid value).
#   - API failure still writes the stamp -- the bug that motivated the spec
#     was an offline machine retrying the 2s timeout on every invocation.
#   - Update-available returns abbreviated 7-char SHA pair.
#
# Run: Invoke-Pester -Path tests
# Requires: Pester 5+

#Requires -Modules @{ ModuleName = 'Pester'; ModuleVersion = '5.0.0' }

BeforeAll {
    $repoRoot = Split-Path $PSScriptRoot -Parent
    Import-Module (Join-Path $repoRoot 'TerminalStyles.psd1') -Force -DisableNameChecking *> $null
}

Describe 'Test-UpdateAvailable' {
    InModuleScope TerminalStyles {
        BeforeEach {
            $script:TStylesRoot = $TestDrive
            $stampFile = Join-Path $TestDrive '.last-update-check'
            $shaFile   = Join-Path $TestDrive '.installed-sha'
            Remove-Item $stampFile -ErrorAction SilentlyContinue
            Remove-Item $shaFile   -ErrorAction SilentlyContinue
        }

        It 'returns $null and skips the API when the stamp is fresh (< 24h)' {
            $fresh = (Get-Date).AddMinutes(-30).ToString('o', [System.Globalization.CultureInfo]::InvariantCulture)
            [System.IO.File]::WriteAllText($stampFile, $fresh, [System.Text.UTF8Encoding]::new($false))

            Mock Invoke-RestMethod { throw 'API should NOT be called inside the throttle window' }

            $result = Test-UpdateAvailable

            $result | Should -BeNullOrEmpty
            Should -Invoke Invoke-RestMethod -Times 0
        }

        It 'fires the API call when the stamp is stale (> 24h)' {
            $stale = (Get-Date).AddHours(-25).ToString('o', [System.Globalization.CultureInfo]::InvariantCulture)
            [System.IO.File]::WriteAllText($stampFile, $stale, [System.Text.UTF8Encoding]::new($false))
            [System.IO.File]::WriteAllText($shaFile, ('a' * 40), [System.Text.UTF8Encoding]::new($false))

            Mock Invoke-RestMethod { @{ sha = ('a' * 40) } }

            $result = Test-UpdateAvailable

            $result | Should -BeNullOrEmpty
            Should -Invoke Invoke-RestMethod -Times 1
            Test-Path $stampFile | Should -BeTrue
        }

        It 'fires the API call when no stamp file exists' {
            [System.IO.File]::WriteAllText($shaFile, ('a' * 40), [System.Text.UTF8Encoding]::new($false))

            Mock Invoke-RestMethod { @{ sha = ('a' * 40) } }

            $result = Test-UpdateAvailable

            $result | Should -BeNullOrEmpty
            Should -Invoke Invoke-RestMethod -Times 1
            Test-Path $stampFile | Should -BeTrue
        }

        It 'self-heals on corrupt stamp (unparseable contents)' {
            [System.IO.File]::WriteAllText($stampFile, 'garbage not a date', [System.Text.UTF8Encoding]::new($false))
            [System.IO.File]::WriteAllText($shaFile, ('a' * 40), [System.Text.UTF8Encoding]::new($false))

            Mock Invoke-RestMethod { @{ sha = ('a' * 40) } }

            { Test-UpdateAvailable } | Should -Not -Throw

            Should -Invoke Invoke-RestMethod -Times 1
            $written = [System.IO.File]::ReadAllText($stampFile, [System.Text.UTF8Encoding]::new($false))
            { [datetime]::Parse($written, [System.Globalization.CultureInfo]::InvariantCulture, [System.Globalization.DateTimeStyles]::RoundtripKind) } | Should -Not -Throw
        }

        It 'still writes the stamp when the API call fails' {
            [System.IO.File]::WriteAllText($shaFile, ('a' * 40), [System.Text.UTF8Encoding]::new($false))

            Mock Invoke-RestMethod { throw 'simulated network failure' }

            $result = Test-UpdateAvailable

            $result | Should -BeNullOrEmpty
            Test-Path $stampFile | Should -BeTrue
        }

        It 'returns the abbreviated SHA pair when remote SHA differs from installed' {
            $stale = (Get-Date).AddHours(-25).ToString('o', [System.Globalization.CultureInfo]::InvariantCulture)
            [System.IO.File]::WriteAllText($stampFile, $stale, [System.Text.UTF8Encoding]::new($false))
            [System.IO.File]::WriteAllText($shaFile, '0000000000000000000000000000000000000000', [System.Text.UTF8Encoding]::new($false))

            Mock Invoke-RestMethod { @{ sha = 'abc123def4567aaaaaaaaaaaaaaaaaaaaaaaaaaa' } }

            $result = Test-UpdateAvailable

            $result | Should -Not -BeNullOrEmpty
            $result.Installed | Should -Be '0000000'
            $result.Remote    | Should -Be 'abc123d'
        }
    }
}
```

The migration: everything inside `Describe` is wrapped in one `InModuleScope TerminalStyles { ... }` block. `BeforeEach` is inside the InModuleScope block, so `$script:TStylesRoot = $TestDrive` actually modifies the module's `$script:TStylesRoot` variable (the one `Test-UpdateAvailable` reads). Mocks are also inside, so they intercept the module's `Invoke-RestMethod` calls.

- [ ] **Step 4: Run the migrated throttle test**

```powershell
pwsh -NoProfile -Command "Invoke-Pester -Path .\tests\Test-UpdateAvailable.Tests.ps1 -Output Detailed"
```

Expected: 6 tests pass.

If a test fails with "Cannot find an overload for 'Invoke-RestMethod'" or similar, the mock setup didn't reach the module. Confirm the `InModuleScope TerminalStyles { ... }` actually wraps the `Mock Invoke-RestMethod` line.

- [ ] **Step 5: Migrate `tests/Apply-StyleDirect-Backup.Tests.ps1`**

Replace the entire file contents with:

```powershell
# Pester 5 tests for Apply-StyleDirect's rolling settings.json.bak.
#
# Module-restructure migration: dot-source replaced with Import-Module,
# all test bodies wrapped in InModuleScope TerminalStyles so mocks
# intercept module-internal Find-WTSettingsPath / Merge-StyleIntoSettings
# / Write-SettingsFile / Copy-Item / Write-Host calls and Apply-StyleDirect
# resolves.
#
# Locks in the backup invariants from
# docs/superpowers/specs/2026-05-27-direct-apply-backup-design.md:
#   - .bak captures the PRIOR state (not the merged state).
#   - .bak rolls (overwrites) on every direct apply.
#   - Copy-Item failure prints a yellow warning and lets the function
#     continue past the failure -- doesn't block the apply.
#   - .bak is written next to settings.json as "<settingsPath>.bak"
#     (not in a temp dir, not anywhere else).
#
# Run: Invoke-Pester -Path tests
# Requires: Pester 5+

#Requires -Modules @{ ModuleName = 'Pester'; ModuleVersion = '5.0.0' }

BeforeAll {
    $repoRoot = Split-Path $PSScriptRoot -Parent
    Import-Module (Join-Path $repoRoot 'TerminalStyles.psd1') -Force -DisableNameChecking *> $null
}

Describe 'Apply-StyleDirect backup behavior' {
    InModuleScope TerminalStyles {
        BeforeEach {
            $script:TStylesRoot = $TestDrive

            $script:fakeSettings = Join-Path $TestDrive 'fake-settings.json'
            $initialContent = '{"profiles":{"list":[{"name":"PowerShell","guid":"{x}"}]}}'
            [System.IO.File]::WriteAllText($script:fakeSettings, $initialContent, [System.Text.UTF8Encoding]::new($false))

            $script:styleDir = Join-Path $TestDrive 'styles\fakeStyle'
            New-Item -ItemType Directory -Path $script:styleDir -Force | Out-Null
            [System.IO.File]::WriteAllText(
                (Join-Path $script:styleDir 'scheme.json'),
                '{"name":"fakeScheme"}',
                [System.Text.UTF8Encoding]::new($false)
            )

            Mock Find-WTSettingsPath        { $script:fakeSettings }
            Mock Show-UpdateNoticeIfAvailable {}
            Mock Get-CurrentWTProfileName   { 'PowerShell' }
            Mock Merge-StyleIntoSettings    { param($Settings) $Settings }
            Mock Write-SettingsFile         {}
        }

        It 'writes settings.json.bak with the prior contents before merging' {
            $initial = [System.IO.File]::ReadAllText($script:fakeSettings, [System.Text.UTF8Encoding]::new($false))

            Apply-StyleDirect -StyleName 'fakeStyle' -Target 'PowerShell'

            $bak = "$script:fakeSettings.bak"
            Test-Path $bak | Should -BeTrue
            [System.IO.File]::ReadAllText($bak, [System.Text.UTF8Encoding]::new($false)) | Should -Be $initial
        }

        It 'rolls the .bak file on a second invocation' {
            Apply-StyleDirect -StyleName 'fakeStyle' -Target 'PowerShell'
            $bak = "$script:fakeSettings.bak"
            $firstBakHash = (Get-FileHash $bak).Hash

            [System.IO.File]::WriteAllText(
                $script:fakeSettings,
                '{"profiles":{"list":[{"name":"DIFFERENT","guid":"{y}"}]}}',
                [System.Text.UTF8Encoding]::new($false)
            )

            Apply-StyleDirect -StyleName 'fakeStyle' -Target 'PowerShell'
            $secondBakHash = (Get-FileHash $bak).Hash

            $secondBakHash | Should -Not -Be $firstBakHash
        }

        It 'prints yellow warning and continues when Copy-Item throws' {
            Mock Copy-Item { throw 'simulated permission denied' } `
                -ParameterFilter { $Destination -like '*.bak' }
            Mock Write-Host { }

            { Apply-StyleDirect -StyleName 'fakeStyle' -Target 'PowerShell' } | Should -Not -Throw

            Should -Invoke Write-Host -ParameterFilter {
                $ForegroundColor -eq 'Yellow' -and "$Object" -match 'could not write backup'
            } -Times 1

            Should -Invoke Write-SettingsFile -Times 1
        }

        It 'writes the backup as <settingsPath>.bak (not anywhere else)' {
            $expectedBak = "$script:fakeSettings.bak"

            Mock Copy-Item { } -ParameterFilter {
                $LiteralPath -eq $script:fakeSettings -and $Destination -eq $expectedBak -and $Force
            }

            Apply-StyleDirect -StyleName 'fakeStyle' -Target 'PowerShell'

            Should -Invoke Copy-Item -Times 1 -ParameterFilter {
                $LiteralPath -eq $script:fakeSettings -and $Destination -eq $expectedBak -and $Force
            }
        }
    }
}
```

Same pattern: outer `Describe` contains a single `InModuleScope TerminalStyles { ... }` that wraps `BeforeEach` and all `It` blocks. The mocks (`Find-WTSettingsPath`, `Show-UpdateNoticeIfAvailable`, etc.) are set in `BeforeEach` so they apply to each test fresh.

- [ ] **Step 6: Run the migrated backup test**

```powershell
pwsh -NoProfile -Command "Invoke-Pester -Path .\tests\Apply-StyleDirect-Backup.Tests.ps1 -Output Detailed"
```

Expected: 4 tests pass.

- [ ] **Step 7: Run the full suite**

```powershell
pwsh -NoProfile -Command "Invoke-Pester -Path .\tests -Output Detailed"
```

Expected: 43 tests pass (33 swatch + 6 throttle + 4 backup), 0 failed.

- [ ] **Step 8: Commit**

```bash
git add tests/Get-SchemeSwatch.Tests.ps1 tests/Test-UpdateAvailable.Tests.ps1 tests/Apply-StyleDirect-Backup.Tests.ps1
git commit -m "$(cat <<'EOF'
Migrate Pester tests to Import-Module + InModuleScope

All three test files switched from dot-sourcing tstyles.ps1 to
Import-Module TerminalStyles.psd1 -Force. Function calls that
exercise module-private surface (Get-SchemeSwatch, Test-UpdateAvailable,
Apply-StyleDirect, Find-WTSettingsPath, Merge-StyleIntoSettings,
Write-SettingsFile, Show-UpdateNoticeIfAvailable, Get-CurrentWTProfileName)
are now wrapped in InModuleScope TerminalStyles { ... } so the test
sees the private surface and mocks intercept module-internal calls.

All 43 tests still pass.
EOF
)"
```

---

## Task 3: Switch `install.ps1` from dot-source to `Import-Module`

**Files:**
- Modify: `install.ps1` (two surgical edits — `$loaderBody` heredoc + same-tab handoff)

After this task, fresh installs and `tstyles update` runs both use the new `Import-Module` loader. Existing tabs already loaded keep working until the user opens a new tab.

- [ ] **Step 1: Update `$loaderBody`**

Open `install.ps1`. Find this block (currently around lines 32-36):

```powershell
$loaderBody  = @"
$loaderBegin
. "`$env:LOCALAPPDATA\TerminalStyles\tstyles.ps1"
$loaderEnd
"@
```

Replace with:

```powershell
$loaderBody  = @"
$loaderBegin
Import-Module "`$env:LOCALAPPDATA\TerminalStyles\TerminalStyles.psd1" -DisableNameChecking
$loaderEnd
"@
```

The `-DisableNameChecking` flag suppresses the warning about `Apply-StyleDirect` (which uses the non-approved verb `Apply`). The function is module-private and never reaches the user, but the warning fires during import.

- [ ] **Step 2: Update the same-tab handoff at the end of the script**

Find the existing block at the end of `install.ps1`:

```powershell
# --- Same-tab handoff ---
# Dot-source the freshly-installed tstyles.ps1 into the current scope
# so the user can type `tstyles` immediately without opening a new tab.
# `iwr | iex` runs this whole installer in the caller's scope, so a
# dot-source from here exposes Invoke-TerminalStyle (the function
# behind the `tstyles` command) to that scope too.
$installedLib = Join-Path $installDir 'tstyles.ps1'
if (Test-Path -LiteralPath $installedLib) {
    . $installedLib *> $null
}
```

Replace with:

```powershell
# --- Same-tab handoff ---
# Import the freshly-installed module into the GLOBAL scope (not the
# script's child scope) so the `tstyles` command is available in the
# caller's session immediately. Without -Global, the import would be
# scoped to this script and disappear when install.ps1 returns.
$installedManifest = Join-Path $installDir 'TerminalStyles.psd1'
if (Test-Path -LiteralPath $installedManifest) {
    Import-Module $installedManifest -Force -Global -DisableNameChecking *> $null
}
```

- [ ] **Step 3: Smoke-test the installer (reinstall over existing install)**

```powershell
pwsh -NoProfile -File .\install.ps1
```

Expected:
- Full installer UI renders correctly (banner, step list, panel — verified by the earlier install-UX work).
- No errors during the per-shell loader registration steps.
- The dim "Also wired up for Windows PowerShell 5.1" line still appears if both engines are present.

After the installer finishes, verify the new `$PROFILE` line:

```powershell
pwsh -NoProfile -Command "Select-String -Path \$PROFILE -Pattern 'Import-Module.*TerminalStyles\.psd1'"
```

Expected: at least one match showing the new loader line. **No matches for the old dot-source line** (verify with):

```powershell
pwsh -NoProfile -Command "Select-String -Path \$PROFILE -Pattern '\\. ""\\\$env:LOCALAPPDATA.*tstyles\\.ps1'"
```

Expected: no matches.

- [ ] **Step 4: Verify same-tab handoff works with the new module loader**

Same pattern as the install-ux plan's Task 3 Step 2:

```powershell
pwsh -NoProfile -Command "& { . .\install.ps1; Get-Command tstyles | Format-List Name, CommandType, ModuleName }"
```

Expected: `tstyles` (Alias, Module TerminalStyles) — the module was imported globally and is visible to the caller.

If `Get-Command tstyles` returns nothing, the `-Global` flag isn't doing what's expected. Possible causes:
- `Import-Module $installedManifest -Force -Global` failed silently (try removing `*> $null` to see errors)
- The `$installedManifest` path is wrong (verify with `Write-Host "DEBUG: $installedManifest"` above the `Test-Path` line)
- The `*> $null` is swallowing a real error; try `2>&1` instead.

- [ ] **Step 5: Verify a fresh tab gets `tstyles` via the new loader**

Open a new pwsh tab in Windows Terminal. Type:

```powershell
Get-Command tstyles | Format-List Name, CommandType, ModuleName
```

Expected: `tstyles` (Alias, Module TerminalStyles). The new `$PROFILE` `Import-Module` line ran on tab startup and brought `tstyles` into scope.

Also verify tab completion still works:

```powershell
tstyles l<TAB>
```

Expected: completes to `list`.

- [ ] **Step 6: Commit**

```bash
git add install.ps1
git commit -m "$(cat <<'EOF'
install.ps1: switch from dot-source to Import-Module

Two edits in install.ps1 swap the dot-source loader pattern for the
PowerShell module pattern:

1. The $PROFILE loader heredoc now writes:
     Import-Module "$env:LOCALAPPDATA\TerminalStyles\TerminalStyles.psd1" -DisableNameChecking
   instead of:
     . "$env:LOCALAPPDATA\TerminalStyles\tstyles.ps1"

2. The same-tab handoff at end-of-script now does:
     Import-Module $installedManifest -Force -Global -DisableNameChecking
   instead of:
     . $installedLib

The -Global flag in the handoff is critical: without it, when
install.ps1 runs via `iwr | iex` in the user's session, the import
would be scoped to install.ps1's child scope and disappear on return.

-DisableNameChecking suppresses the warning about Apply-StyleDirect
(non-approved verb). The function is module-private and never reaches
consumers; rename in a future spec.

Spec: docs/superpowers/specs/2026-05-27-module-restructure-design.md
EOF
)"
```

---

## Task 4: End-to-end test + push

**Files:** None modified. Validation + push.

- [ ] **Step 1: Confirm branch state**

```bash
git status
git log --oneline origin/main..HEAD
```

Expected: working tree clean. Commits in order (most recent first):

1. `install.ps1: switch from dot-source to Import-Module` (Task 3)
2. `Migrate Pester tests to Import-Module + InModuleScope` (Task 2)
3. `Add TerminalStyles.psd1 manifest and TerminalStyles.psm1 entry` (Task 1)
4. `Spec: TerminalStyles as a PowerShell module (sub-project A)` (already on main from brainstorming)

- [ ] **Step 2: Final local test sweep**

```powershell
pwsh -NoProfile -Command "Invoke-Pester -Path .\tests -Output Detailed"
```

Expected: 43 tests passed.

```powershell
pwsh -NoProfile -Command "Test-ModuleManifest .\TerminalStyles.psd1 | Format-List Name, Version, RootModule, ExportedFunctions, ExportedAliases"
```

Expected: manifest parses cleanly, exports show `Invoke-TerminalStyle`, `Invoke-TerminalStylesUpdate`, alias `tstyles`.

- [ ] **Step 3: Push**

```bash
git push origin main
```

Expected: `<prior-sha>..<HEAD-sha>  main -> main`.

- [ ] **Step 4: True end-to-end run via the one-liner**

In a fresh Windows Terminal pwsh tab (not your dev shell):

```powershell
iwr -useb https://raw.githubusercontent.com/fcreme/TerminalStyles/main/install.ps1 | iex
```

Expected:
1. Full installer UI renders (banner, steps, panel) — should look identical to before this sub-project, since the UX work was done in a prior plan.
2. After the panel, type `tstyles` immediately. The picker launches.
3. Press Esc to exit the picker.

```powershell
Get-Module TerminalStyles | Format-List Name, Version, Path
```

Expected: shows the module loaded from `%LOCALAPPDATA%\TerminalStyles\TerminalStyles.psd1`, Version `0.1.0`.

```powershell
Get-Command -Module TerminalStyles | Format-Table Name, CommandType -AutoSize
```

Expected:

```
Name                         CommandType
----                         -----------
Invoke-TerminalStyle            Function
Invoke-TerminalStylesUpdate     Function
tstyles                            Alias
```

If anything in the end-to-end is broken (most likely `tstyles` not recognized after install, or `Get-Module TerminalStyles` empty), check:
- `Get-Content $PROFILE` — does the new `Import-Module` line exist?
- Does `Test-Path "$env:LOCALAPPDATA\TerminalStyles\TerminalStyles.psd1"` return `True`?
- Does `Import-Module "$env:LOCALAPPDATA\TerminalStyles\TerminalStyles.psd1"` (run manually) work?

- [ ] **Step 5: CI green check**

The push triggers `.github/workflows/test.yml`. Check the new run:
- Browser: https://github.com/fcreme/TerminalStyles/actions
- Or `gh run list --limit 1` if authenticated.

Expected: the new run is green. The CI runs the full Pester suite (now 43 tests against the module structure).

If CI is red, common causes:
- `Test-ModuleManifest` fails on the CI runner (different PowerShell version): unlikely on `windows-latest`, but check the manifest's `PowerShellVersion = '5.1'`.
- `InModuleScope TerminalStyles` fails because the module wasn't imported in `BeforeAll`: read the failing test's BeforeAll to confirm.
- Pester 5 not picking up the module: ensure `Import-Module ... -Force` is there (not just `Import-Module ...`).

---

## Self-Review Notes

Spec coverage:

- Create `TerminalStyles.psd1` → Task 1 Step 2.
- Create `TerminalStyles.psm1` → Task 1 Step 3.
- Verify the module imports and exports the right surface → Task 1 Steps 4-6.
- `install.ps1` `$loaderBody` change → Task 3 Step 1.
- `install.ps1` same-tab handoff with `-Global` → Task 3 Step 2.
- Three Pester test migrations → Task 2 Steps 1, 3, 5.
- All 43 tests pass → Task 2 Step 7 + Task 4 Step 2.
- End-to-end live test via `iwr | iex` → Task 4 Step 4.
- CI green → Task 4 Step 5.

Spec items deliberately deferred (matches plan):
- PSGallery publishing → Sub-project B (not in this plan).
- `tstyles update` → `Update-PSResource` migration → Sub-project C.
- README install command rewrite → Sub-project C.
- State-file relocation → Sub-project B.
- `Apply-StyleDirect` rename → future spec.
- Module signing → Sub-project B.

Type / signature consistency:

- Module name `TerminalStyles` used everywhere (manifest, psm1 dot-source path comments, install.ps1, all three test BeforeAll).
- Manifest version `0.1.0` is in Task 1 Step 2 only; future tasks don't reference a version.
- `-DisableNameChecking` flag used consistently (manifest comments aside, every `Import-Module` call has it).
- `-Force` only on handoff and test imports (not on the $PROFILE loader — which doesn't need force because it runs once per tab startup).
- `-Global` only on the handoff (not on tests — tests don't need to leak imports outside their scope).
- `$installedManifest` / `$installedLib` / `$installedLibrary` — used `$installedManifest` consistently (matches the variable rename from `$installedLib`).
- `InModuleScope TerminalStyles` — same exact string everywhere.

No placeholders. All code blocks contain the actual content to paste. All verification commands have expected output.

One judgment call worth flagging:
- **Task 2's three test-file rewrites are full file replacements**, not surgical edits. The original test files are short (~50-130 lines each) and the structural change (wrapping in `InModuleScope`) is pervasive enough that a full rewrite is cleaner than dozens of small Edit calls. The plan provides the complete new file content for each.
