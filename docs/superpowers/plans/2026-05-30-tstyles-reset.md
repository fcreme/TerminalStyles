# `tstyles reset` Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Ship `TerminalStyles 0.6.0` adding `tstyles reset [-Target <name>]` — revert a Windows Terminal profile to its unstyled default by stripping the fields TerminalStyles writes, removing the orphan color scheme, and restoring the user's prompt.

**Architecture:** A new `Reset-StyleDirect` mirrors `Apply-StyleDirect`'s proven direct-mutation path (find settings → roll `.bak` → mutate → `Write-SettingsFile` → clear prompt) but strips instead of merges. The profile-field lists are extracted to module-scoped constants (`$script:TStylesBgFields` / `$script:TStylesThemeFields`) so apply and reset share one source of truth. Wired via a `reset` subcommand + tab-completer entry + help entry.

**Tech Stack:** PowerShell 5.1+. Pester 5.x. No new dependencies.

**Spec:** `docs/superpowers/specs/2026-05-30-tstyles-reset-design.md`

---

## File Structure

- **Modify:** `tstyles.ps1`
  - Add the two field-list constants near the top (with the other `$script:` state).
  - Refactor `Merge-StyleIntoSettings` to reference `$script:TStylesBgFields` (behavior-preserving).
  - Add `Reset-StyleDirect` (before `# === Public command ===`).
  - Add a `reset` dispatch line in `Invoke-TerminalStyle`; add `'reset'` to the completer; add a `reset` entry to `Get-TerminalStyleHelpData`.
- **Create:** `tests/Reset-StyleDirect.Tests.ps1`, `tests/Invoke-TerminalStyle-ResetDispatch.Tests.ps1`.
- **Modify:** `README.md` (Subcommands row + a reset note), `TerminalStyles.psd1` (version + ReleaseNotes).

**Task ordering keeps CI green at every commit:** constants + Merge refactor (Task 1), Reset-StyleDirect + tests (Task 2), dispatch/completer/help + tests (Task 3), README/version (Task 4), publish (Task 5).

---

## Task 1: Extract shared field-list constants (DRY)

**Files:**
- Modify: `tstyles.ps1` (add 2 constants; refactor `Merge-StyleIntoSettings`'s inline `$bgFields`)

The bundled `theme.json` files were verified during design: all 16 write the identical 13-key set. Extract the lists so apply and reset can't drift.

- [ ] **Step 1: Add the constants**

In `tstyles.ps1`, find the existing module-state line (near the top, ~line 24):

```powershell
$script:TStylesCurrent = Join-Path $script:TStylesDataRoot 'current-style.ps1'
```

Insert AFTER it:

```powershell

# Profile fields TerminalStyles writes onto a Windows Terminal profile entry.
# Single source of truth shared by Merge-StyleIntoSettings (apply) and
# Reset-StyleDirect (reset), so the two can't drift. Verified as the union of
# keys across all 16 bundled styles/*/theme.json files.
$script:TStylesBgFields    = @('backgroundImage', 'backgroundImageOpacity',
                               'backgroundImageStretchMode', 'backgroundImageAlignment')
$script:TStylesThemeFields = @('colorScheme', 'tabTitle', 'tabColor', 'cursorShape',
                               'useAcrylic', 'opacity', 'experimental.retroTerminalEffect',
                               'font', 'padding') + $script:TStylesBgFields
```

- [ ] **Step 2: Refactor `Merge-StyleIntoSettings` to use the constant**

In `Merge-StyleIntoSettings`, find (~line 373):

```powershell
    $bgFields = @('backgroundImage', 'backgroundImageOpacity', 'backgroundImageStretchMode', 'backgroundImageAlignment')
    foreach ($prop in $theme.PSObject.Properties) {
```

Replace with:

```powershell
    $bgFields = $script:TStylesBgFields
    foreach ($prop in $theme.PSObject.Properties) {
```

(Behavior-preserving — same four field names, now from the shared constant.)

- [ ] **Step 3: Verify the module loads + full suite (no regressions)**

Run: `pwsh -NoProfile -Command "Import-Module .\TerminalStyles.psd1 -Force -DisableNameChecking; 'ok: module loaded'"`
Expected: `ok: module loaded`.

Run: `pwsh -NoProfile -Command "Invoke-Pester -Path .\tests -Output Minimal 2>&1 | Select-Object -Last 3"`
Expected: `Failed: 0` (115 total — the apply/merge tests still pass with the refactor).

- [ ] **Step 4: Confirm the constant is wired**

Run: `pwsh -NoProfile -Command "Import-Module .\TerminalStyles.psd1 -Force -DisableNameChecking; & (Get-Module TerminalStyles) { $script:TStylesThemeFields.Count }"`
Expected: `13`.

- [ ] **Step 5: Commit**

```bash
git add tstyles.ps1
git commit -m "$(cat <<'EOF'
Extract TerminalStyles profile-field lists to shared constants

$script:TStylesBgFields + $script:TStylesThemeFields are the single source of
truth for which profile fields TerminalStyles writes (verified as the union
across all 16 bundled theme.json files: 13 fields). Merge-StyleIntoSettings
now references $script:TStylesBgFields instead of an inline list. Prep for
`tstyles reset`, which strips $script:TStylesThemeFields. Behavior-preserving.

Spec: docs/superpowers/specs/2026-05-30-tstyles-reset-design.md

Co-Authored-By: Claude Opus 4.8 <noreply@anthropic.com>
EOF
)"
```

---

## Task 2: `Reset-StyleDirect`

**Files:**
- Modify: `tstyles.ps1` (add `Reset-StyleDirect` before `# === Public command ===`)
- Test: `tests/Reset-StyleDirect.Tests.ps1`

- [ ] **Step 1: Write the failing tests**

Create `tests/Reset-StyleDirect.Tests.ps1`:

```powershell
# Pester 5 tests for Reset-StyleDirect: strips the TerminalStyles field set
# from a profile, removes the orphan scheme, clears current-style.ps1.
# Run: Invoke-Pester -Path tests
#Requires -Modules @{ ModuleName = 'Pester'; ModuleVersion = '5.0.0' }

BeforeDiscovery {
    $repoRoot = Split-Path $PSScriptRoot -Parent
    Import-Module (Join-Path $repoRoot 'TerminalStyles.psd1') -Force -DisableNameChecking *> $null
}
BeforeAll {
    $repoRoot = Split-Path $PSScriptRoot -Parent
    Import-Module (Join-Path $repoRoot 'TerminalStyles.psd1') -Force -DisableNameChecking *> $null
}

Describe 'Reset-StyleDirect' {
    InModuleScope TerminalStyles {
        BeforeEach {
            $script:TStylesCurrent = Join-Path $TestDrive 'current-style.ps1'
            $script:fakeSettings   = Join-Path $TestDrive 'fake-settings.json'

            # A profile styled by TerminalStyles (colorScheme + font + bg + a
            # hand-set field 'tabTitle' we expect to ALSO be stripped, plus a
            # truly foreign field 'historySize' we expect to SURVIVE), and a
            # scheme named 'eva' in schemes[].
            $settingsObj = [pscustomobject]@{
                schemes  = @([pscustomobject]@{ name = 'eva' }, [pscustomobject]@{ name = 'other' })
                profiles = [pscustomobject]@{
                    list = @([pscustomobject]@{
                        name = 'PowerShell'; guid = '{x}'
                        colorScheme = 'eva'; opacity = 80; cursorShape = 'vintage'
                        font = [pscustomobject]@{ face = 'Cascadia Code' }
                        backgroundImage = 'C:\bg.gif'; tabTitle = 'EVA'
                        historySize = 9001
                    })
                }
            }
            [System.IO.File]::WriteAllText($script:fakeSettings,
                ($settingsObj | ConvertTo-Json -Depth 32), [System.Text.UTF8Encoding]::new($false))

            Mock Find-WTSettingsPath          { $script:fakeSettings }
            Mock Show-UpdateNoticeIfAvailable {}
            Mock Get-CurrentWTProfileName     { 'PowerShell' }
            # Capture what gets written so we can assert on the mutated object.
            Mock Write-SettingsFile           { param($Path, $Settings) $script:written = $Settings }
        }

        It 'strips every TerminalStyles field from the target profile' {
            Reset-StyleDirect -Target 'PowerShell'
            $p = $script:written.profiles.list | Where-Object name -eq 'PowerShell'
            foreach ($f in @('colorScheme','opacity','cursorShape','font','backgroundImage','tabTitle')) {
                $p.PSObject.Properties.Match($f).Count | Should -Be 0
            }
        }
        It 'leaves foreign (non-TerminalStyles) profile fields intact' {
            Reset-StyleDirect -Target 'PowerShell'
            $p = $script:written.profiles.list | Where-Object name -eq 'PowerShell'
            $p.historySize | Should -Be 9001
            $p.name        | Should -Be 'PowerShell'
        }
        It 'removes the orphan scheme from schemes[]' {
            Reset-StyleDirect -Target 'PowerShell'
            @($script:written.schemes | Where-Object name -eq 'eva').Count | Should -Be 0
            @($script:written.schemes | Where-Object name -eq 'other').Count | Should -Be 1
        }
        It 'keeps a scheme still referenced by another profile' {
            # Add a second profile that also uses 'eva'.
            $obj = [System.IO.File]::ReadAllText($script:fakeSettings, [System.Text.UTF8Encoding]::new($false)) | ConvertFrom-Json
            $obj.profiles.list += [pscustomobject]@{ name = 'Other'; guid = '{y}'; colorScheme = 'eva' }
            [System.IO.File]::WriteAllText($script:fakeSettings, ($obj | ConvertTo-Json -Depth 32), [System.Text.UTF8Encoding]::new($false))

            Reset-StyleDirect -Target 'PowerShell'
            @($script:written.schemes | Where-Object name -eq 'eva').Count | Should -Be 1
        }
        It 'clears an existing current-style.ps1' {
            [System.IO.File]::WriteAllText($script:TStylesCurrent, '# old prompt', [System.Text.UTF8Encoding]::new($false))
            Reset-StyleDirect -Target 'PowerShell'
            Test-Path -LiteralPath $script:TStylesCurrent | Should -BeFalse
        }
        It 'writes the rolling settings.json.bak with the prior contents' {
            $prior = [System.IO.File]::ReadAllText($script:fakeSettings, [System.Text.UTF8Encoding]::new($false))
            Reset-StyleDirect -Target 'PowerShell'
            $bak = "$script:fakeSettings.bak"
            Test-Path $bak | Should -BeTrue
            [System.IO.File]::ReadAllText($bak, [System.Text.UTF8Encoding]::new($false)) | Should -Be $prior
        }
    }
}
```

- [ ] **Step 2: Run the tests to verify they FAIL**

Run: `pwsh -NoProfile -Command "Invoke-Pester -Path .\tests\Reset-StyleDirect.Tests.ps1 -Output Detailed"`
Expected: FAIL — `Reset-StyleDirect` is not defined (CommandNotFoundException).

- [ ] **Step 3: Implement `Reset-StyleDirect`**

Insert immediately before the `# === Public command ===` line in `tstyles.ps1`:

```powershell
function Reset-StyleDirect {
    # `tstyles reset [-Target <name>]` -- revert a WT profile to its unstyled
    # default: strip the fields TerminalStyles writes, remove the now-orphan
    # color scheme, and clear current-style.ps1 (restore the user's prompt).
    # Inverse of Apply-StyleDirect. Writes a rolling .bak first.
    param([string]$Target)

    Show-UpdateNoticeIfAvailable

    $settingsPath = Find-WTSettingsPath
    if (-not $settingsPath) {
        Write-Error "Could not locate Windows Terminal settings.json."
        return
    }

    $originalJson = [System.IO.File]::ReadAllText($settingsPath, [System.Text.UTF8Encoding]::new($false))
    $settings = $originalJson | ConvertFrom-Json

    if (-not $Target) { $Target = Get-CurrentWTProfileName -Settings $settings }
    if (-not $Target) {
        Write-Error "Could not auto-detect a Windows Terminal profile to reset. Try: tstyles reset -Target '<name>'"
        return
    }

    # Rolling backup (same safety net as Apply-StyleDirect).
    $bakPath = "$settingsPath.bak"
    try {
        Copy-Item -LiteralPath $settingsPath -Destination $bakPath -Force -ErrorAction Stop
        Write-Host "Backed up settings to: $bakPath" -ForegroundColor Gray
    } catch {
        Write-Host "Warning: could not write backup ($_); proceeding anyway." -ForegroundColor Yellow
    }

    # Resolve the profile entry (same resolution as Merge-StyleIntoSettings).
    $entry = if ($Target -eq 'defaults') {
        if ($settings.profiles.PSObject.Properties.Match('defaults').Count) { $settings.profiles.defaults } else { $null }
    } else {
        $settings.profiles.list | Where-Object name -eq $Target | Select-Object -First 1
    }
    if (-not $entry) {
        Write-Host "Profile '$Target' not found in settings.json -- nothing to reset." -ForegroundColor Yellow
        return
    }

    # Capture the scheme name before stripping (for orphan cleanup).
    $schemeName = if ($entry.PSObject.Properties.Match('colorScheme').Count) { $entry.colorScheme } else { $null }

    # Strip every TerminalStyles field that is present on the entry.
    $strippedAny = $false
    foreach ($field in $script:TStylesThemeFields) {
        if ($entry.PSObject.Properties.Match($field).Count) {
            $entry.PSObject.Properties.Remove($field)
            $strippedAny = $true
        }
    }

    # Remove the orphan scheme unless another profile still references it.
    if ($schemeName -and $settings.PSObject.Properties.Match('schemes').Count) {
        $allProfiles = @()
        if ($settings.profiles.PSObject.Properties.Match('defaults').Count) { $allProfiles += $settings.profiles.defaults }
        $allProfiles += @($settings.profiles.list)
        $stillUsed = @($allProfiles | Where-Object {
            $_.PSObject.Properties.Match('colorScheme').Count -and $_.colorScheme -eq $schemeName
        }).Count -gt 0
        if (-not $stillUsed) {
            $settings.schemes = @($settings.schemes | Where-Object { $_.name -ne $schemeName })
        }
    }

    Write-SettingsFile -Path $settingsPath -Settings $settings

    # Clear the active style's prompt so the user's own prompt returns.
    if (Test-Path -LiteralPath $script:TStylesCurrent) {
        Remove-Item -LiteralPath $script:TStylesCurrent -Force
    }

    Write-Host ""
    if ($strippedAny) {
        Write-Host "  Reset '$Target' to its unstyled default." -ForegroundColor Green
    } else {
        Write-Host "  '$Target' had no TerminalStyles fields -- already plain." -ForegroundColor Gray
    }
    Write-Host "  Open a new tab to restore your default prompt." -ForegroundColor DarkGray
    Write-Host ""
}
```

- [ ] **Step 4: Run the tests to verify they PASS**

Run: `pwsh -NoProfile -Command "Invoke-Pester -Path .\tests\Reset-StyleDirect.Tests.ps1 -Output Detailed"`
Expected: PASS — 6 tests, 0 failed.

- [ ] **Step 5: Full suite (no regressions)**

Run: `pwsh -NoProfile -Command "Invoke-Pester -Path .\tests -Output Minimal 2>&1 | Select-Object -Last 3"`
Expected: `Failed: 0` (121 total: 115 + 6 new).

- [ ] **Step 6: Commit**

```bash
git add tstyles.ps1 tests/Reset-StyleDirect.Tests.ps1
git commit -m "$(cat <<'EOF'
Add Reset-StyleDirect (revert a profile to unstyled)

Strips $script:TStylesThemeFields from the target profile, removes the
now-orphan color scheme from schemes[] (unless another profile still
references it), clears current-style.ps1 to restore the user's prompt, and
writes a rolling .bak first. Inverse of Apply-StyleDirect; not dispatched
from the CLI yet -- Task 3 wires it.

Spec: docs/superpowers/specs/2026-05-30-tstyles-reset-design.md

Co-Authored-By: Claude Opus 4.8 <noreply@anthropic.com>
EOF
)"
```

---

## Task 3: Wire `reset` into dispatch + completer + help

**Files:**
- Modify: `tstyles.ps1` (dispatch line + completer + `Get-TerminalStyleHelpData` entry)
- Test: `tests/Invoke-TerminalStyle-ResetDispatch.Tests.ps1`

- [ ] **Step 1: Write the failing tests**

Create `tests/Invoke-TerminalStyle-ResetDispatch.Tests.ps1`:

```powershell
# Pester 5 tests: `tstyles reset` routes to Reset-StyleDirect; completer offers
# 'reset'; help data has a 'reset' topic.
# Run: Invoke-Pester -Path tests
#Requires -Modules @{ ModuleName = 'Pester'; ModuleVersion = '5.0.0' }

BeforeDiscovery {
    $repoRoot = Split-Path $PSScriptRoot -Parent
    Import-Module (Join-Path $repoRoot 'TerminalStyles.psd1') -Force -DisableNameChecking *> $null
}
BeforeAll {
    $repoRoot = Split-Path $PSScriptRoot -Parent
    Import-Module (Join-Path $repoRoot 'TerminalStyles.psd1') -Force -DisableNameChecking *> $null
}

Describe 'tstyles reset dispatch' {
    InModuleScope TerminalStyles {
        It 'routes `reset` to Reset-StyleDirect' {
            Mock Reset-StyleDirect {}
            Mock Show-UpdateNoticeIfAvailable {}
            Invoke-TerminalStyle -Arg 'reset'
            Should -Invoke Reset-StyleDirect -Times 1
        }
        It 'passes -Target through to Reset-StyleDirect' {
            Mock Reset-StyleDirect {}
            Mock Show-UpdateNoticeIfAvailable {}
            Invoke-TerminalStyle -Arg 'reset' -Target 'Ubuntu'
            Should -Invoke Reset-StyleDirect -Times 1 -ParameterFilter { $Target -eq 'Ubuntu' }
        }
        It 'has a reset entry in the help data' {
            (Get-TerminalStyleHelpData).Name | Should -Contain 'reset'
        }
    }
}

Describe 'tstyles reset tab completion' {
    It "offers 'reset' as a subcommand" {
        $repoRoot = Split-Path $PSScriptRoot -Parent
        Import-Module (Join-Path $repoRoot 'TerminalStyles.psd1') -Force -DisableNameChecking *> $null
        $matches = (TabExpansion2 -inputScript 'tstyles res' -cursorColumn 11).CompletionMatches.CompletionText
        $matches | Should -Contain 'reset'
    }
}
```

- [ ] **Step 2: Run the tests to verify they FAIL**

Run: `pwsh -NoProfile -Command "Invoke-Pester -Path .\tests\Invoke-TerminalStyle-ResetDispatch.Tests.ps1 -Output Detailed"`
Expected: FAIL — `reset` is not dispatched, not in the completer, and has no help entry.

- [ ] **Step 3: Add the dispatch line**

In `tstyles.ps1`, find (~line 1651):

```powershell
    if ($Arg -eq 'random')               { Invoke-RandomStyle;              return }
```

Insert AFTER it:

```powershell
    if ($Arg -eq 'reset')                { Reset-StyleDirect -Target $Target; return }
```

- [ ] **Step 4: Add `'reset'` to the completer**

Find (~line 2065):

```powershell
    $subcommands = @('help', 'list', 'current', 'random', 'register', 'tune', 'update', 'uninstall')
```

Replace with:

```powershell
    $subcommands = @('help', 'list', 'current', 'random', 'register', 'reset', 'tune', 'update', 'uninstall')
```

- [ ] **Step 5: Add a `reset` entry to `Get-TerminalStyleHelpData`**

In `Get-TerminalStyleHelpData`, find the `random` entry:

```powershell
        [pscustomobject]@{
            Name = 'random'; Usage = 'random'; Summary = 'Apply a random style'
            Detail = @("Picks a random style and applies it immediately.")
            Keys = @(); Examples = @('tstyles random')
        }
```

Insert immediately AFTER it (before the `tune` entry):

```powershell
        [pscustomobject]@{
            Name = 'reset'; Usage = 'reset [-Target <name>]'; Summary = 'Revert a profile to its unstyled default'
            Detail = @("Strips the colors, cursor, font, opacity, and background a style added",
                       "to the target profile, and restores your own prompt. The inverse of",
                       "applying a style. Writes a settings.json.bak first.")
            Keys = @(); Examples = @('tstyles reset', "tstyles reset -Target 'Ubuntu'")
        }
```

- [ ] **Step 6: Run the tests + full suite**

Run: `pwsh -NoProfile -Command "Invoke-Pester -Path .\tests\Invoke-TerminalStyle-ResetDispatch.Tests.ps1 -Output Detailed"` → PASS, 4 tests.

Run: `pwsh -NoProfile -Command "Invoke-Pester -Path .\tests -Output Minimal 2>&1 | Select-Object -Last 3"` → `Failed: 0` (125 total).

- [ ] **Step 7: Sanity-check help renders the new topic**

Run: `pwsh -NoProfile -Command "Import-Module .\TerminalStyles.psd1 -Force -DisableNameChecking; & (Get-Module TerminalStyles) { Show-TerminalStyleHelp -Command reset }"`
Expected: prints the reset detail (usage `reset [-Target <name>]`, the description, and the two examples), no error.

- [ ] **Step 8: Commit**

```bash
git add tstyles.ps1 tests/Invoke-TerminalStyle-ResetDispatch.Tests.ps1
git commit -m "$(cat <<'EOF'
Wire `tstyles reset` into dispatch + completer + help

Adds the `reset` dispatch line routing to Reset-StyleDirect (passing -Target),
'reset' in the tab-completer subcommands, and a `reset` topic in
Get-TerminalStyleHelpData (the drift-guard test now covers it). After this,
`tstyles reset` works end-to-end.

Spec: docs/superpowers/specs/2026-05-30-tstyles-reset-design.md

Co-Authored-By: Claude Opus 4.8 <noreply@anthropic.com>
EOF
)"
```

---

## Task 4: README + version bump to 0.6.0

**Files:**
- Modify: `README.md`, `TerminalStyles.psd1`

- [ ] **Step 1: Add the `reset` row to the Subcommands listing**

In `README.md`, find:

```
tstyles random                    # Pick a random style and apply it
```

Insert AFTER it:

```
tstyles reset                     # Revert the active profile to its unstyled default
```

- [ ] **Step 2: Add a "Resetting a profile" subsection**

In `README.md`, find the `## Styles` heading. Insert the following BEFORE it (write the inner ```powershell fence literally — the «BEGIN/END INSERT» markers are delimiters, do NOT write them):

«BEGIN INSERT»
### Resetting a profile

To undo theming and return a profile to Windows Terminal's plain default:

```powershell
tstyles reset                  # the active profile
tstyles reset -Target 'Ubuntu' # a specific profile
```

This strips the colors, cursor, font, opacity, and background a style added,
removes the now-unused color scheme, and restores your own prompt (open a new
tab to see it). It's the inverse of applying a style, and writes a
`settings.json.bak` first. Fields you set on the profile by hand are left alone.

«END INSERT»

(Leave a blank line before `## Styles`.)

- [ ] **Step 3: Bump the version**

In `TerminalStyles.psd1`, find:

```powershell
    ModuleVersion     = '0.5.0'
```

Replace with:

```powershell
    ModuleVersion     = '0.6.0'
```

- [ ] **Step 4: Update ReleaseNotes**

In `TerminalStyles.psd1`, Read the current `ReleaseNotes = '...'` line (begins `v0.5.0: ...`). Replace that entire single-quoted value with:

```powershell
            ReleaseNotes = 'v0.6.0: new `tstyles reset [-Target <name>]` subcommand reverts a Windows Terminal profile to its unstyled default -- strips the colors, cursor, font, opacity, and background a style added, removes the orphan color scheme, and restores your own prompt. The inverse of applying a style; writes a settings.json.bak first. Purely additive.'
```

(Preserve the `ReleaseNotes = '...'` structure; this value has no apostrophes needing `''` escaping.)

- [ ] **Step 5: Verify manifest + README**

Run: `pwsh -NoProfile -Command "Test-ModuleManifest .\TerminalStyles.psd1 | Format-List Name, Version, ExportedFunctions, ExportedAliases"`
Expected: `Version : 0.6.0`; exported functions `Invoke-TerminalStyle`, `Invoke-TerminalStylesUpdate`; alias `tstyles`.

Run: `pwsh -NoProfile -Command "(Select-String -Path .\README.md -Pattern 'tstyles reset').Count"`
Expected: `3` or higher.

- [ ] **Step 6: Final full suite**

Run: `pwsh -NoProfile -Command "Invoke-Pester -Path .\tests -Output Minimal 2>&1 | Select-Object -Last 3"`
Expected: `Failed: 0` (125 total).

- [ ] **Step 7: Commit**

```bash
git add README.md TerminalStyles.psd1
git commit -m "$(cat <<'EOF'
Document `tstyles reset` + bump to 0.6.0

README: Subcommands row + a "Resetting a profile" subsection. Manifest:
ModuleVersion 0.5.0 -> 0.6.0 and updated ReleaseNotes.

Spec: docs/superpowers/specs/2026-05-30-tstyles-reset-design.md

Co-Authored-By: Claude Opus 4.8 <noreply@anthropic.com>
EOF
)"
```

---

## Task 5: Push + publish 0.6.0 + tag

**Files:** None local. PSGallery + git remote. **User-handled** — publish needs the maintainer's API key at `publish.ps1`'s hidden prompt. Tag + push are agent-doable.

- [ ] **Step 1:** Merge the feature branch to main + push (finishing-a-development-branch).
- [ ] **Step 2:** Dry-run: `pwsh -NoProfile -File .\scripts\publish.ps1 -WhatIf` → `Staged TerminalStyles 0.6.0 ...`; eyeball staged files.
- [ ] **Step 3:** Publish (maintainer, hidden key): `pwsh -NoProfile -File .\scripts\publish.ps1` → `Published TerminalStyles 0.6.0 to PSGallery.`
- [ ] **Step 4:** Verify: `Find-PSResource -Name TerminalStyles -Repository PSGallery -Version '*' | Sort-Object Version -Descending | Select-Object -First 4 Name, Version | Format-Table` → 0.6.0 newest.
- [ ] **Step 5:** Tag: `git tag v0.6.0; git push origin v0.6.0`.
- [ ] **Step 6:** Smoke-test in Windows Terminal: `tstyles eva` then `tstyles reset` → profile returns to default colors/cursor/font/background + your own prompt (new tab).

---

## Self-Review Notes

**Spec coverage:**

- Strip the known TerminalStyles field set → Task 1 (constant) + Task 2 (`Reset-StyleDirect` strip loop). Field set verified as the 13-key union across all 16 bundled theme.json.
- Read profile's colorScheme, remove orphan scheme (guarded by still-referenced check) → Task 2.
- Clear current-style.ps1 (restore prompt) → Task 2.
- Rolling .bak first, no confirm prompt → Task 2.
- Target resolution (passed / Get-CurrentWTProfileName / error) → Task 2.
- Shared field-list constants (DRY, apply + reset) → Task 1 (+ Merge refactor).
- Dispatch `reset` + completer + help entry → Task 3.
- Edge cases (no entry / already plain / non-found settings / shared scheme) → Task 2 impl + tests.
- README + version 0.6.0 + ReleaseNotes → Task 4. Publish/tag → Task 5.
- Known limitations (current/list show none; hand edits preserved) → Task 2 test ("foreign fields intact") + Task 4 README note.

**Placeholder scan:** No TBD/TODO. Every code step has complete code; every command has expected output. The only `<...>` is user-facing prose (`<name>`).

**Type/signature consistency:**

- `$script:TStylesBgFields` / `$script:TStylesThemeFields` — defined Task 1; consumed by `Merge-StyleIntoSettings` (Task 1) and `Reset-StyleDirect` (Task 2). Same names.
- `Reset-StyleDirect -Target <string>` — defined Task 2; dispatched with `-Target $Target` (Task 3); tests reference the same signature.
- Test counts: Task 2 → 121 (115 + 6); Task 3 → 125 (+4). Consistent.

**Judgment calls flagged:**

- The strip set includes `tabTitle`/`tabColor`/`useAcrylic`/`experimental.retroTerminalEffect`/`padding` — confirmed during design as fields apply writes (all 16 bundled theme.json share the 13-key set), so reset must strip them to fully invert apply. A profile field NOT in this set (e.g. `historySize`) is left intact (tested).
- The scheme-removal "still referenced?" check scans defaults + every profile in the list, so a shared scheme isn't yanked (tested).
- Tests override `$script:TStylesCurrent` to a `$TestDrive` path (it's set at module load) and mock `Write-SettingsFile` to capture the mutated settings object for assertions.
