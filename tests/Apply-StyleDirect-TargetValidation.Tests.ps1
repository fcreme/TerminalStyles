# Pester 5 tests: a -Target that names no real Windows Terminal profile must be
# refused BEFORE anything is written.
#
# The bug: Merge-StyleIntoSettings returns the settings untouched when the named
# profile does not exist (a guard added so a bad target could not orphan a color
# scheme), but Apply-StyleDirect wrote and reported success regardless. So a
# typo in -Target printed "Style applied" in green having applied nothing.
#
# The write was not harmless either. Write-SettingsFile re-serializes the PARSED
# object, and ConvertFrom-WTJson strips comments on the way in -- so a misspelled
# profile name silently and irreversibly deleted every JSONC comment the user had
# written in their settings.json.
#
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

Describe 'Apply-StyleDirect target validation' {
    InModuleScope TerminalStyles {
        BeforeEach {
            $script:TStylesModuleRoot = $TestDrive
            $script:TStylesDataRoot   = $TestDrive
            $script:TStylesCurrent    = Join-Path $TestDrive 'current-style.ps1'

            $script:styleDir = Join-Path $TestDrive 'styles/fakeStyle'
            New-Item -ItemType Directory -Path $script:styleDir -Force | Out-Null
            [System.IO.File]::WriteAllText((Join-Path $script:styleDir 'scheme.json'),
                '{"name":"fakeScheme"}', [System.Text.UTF8Encoding]::new($false))

            # A settings.json carrying a comment, so we can prove it survives.
            $script:fakeSettings = Join-Path $TestDrive 'fake-settings.json'
            $script:withComment = @'
{
    // the user's own note, which an apply must never eat
    "profiles": { "list": [ { "name": "PowerShell", "guid": "{x}" } ] }
}
'@
            [System.IO.File]::WriteAllText($script:fakeSettings, $script:withComment,
                [System.Text.UTF8Encoding]::new($false))

            Mock Find-WTSettingsPath          { $script:fakeSettings }
            Mock Get-TerminalKind             { 'WindowsTerminal' }
            Mock Show-UpdateNoticeIfAvailable {}
            Mock Write-Host                   {}
            Mock Write-Error                  {}
        }

        It 'refuses a profile name that does not exist' {
            Apply-StyleDirect -StyleName 'fakeStyle' -Target 'NoSuchProfile'
            Should -Invoke Write-Error -ParameterFilter { "$Message" -match "'NoSuchProfile' not found" }
        }

        It 'names the profiles that DO exist, so the typo is fixable' {
            Apply-StyleDirect -StyleName 'fakeStyle' -Target 'NoSuchProfile'
            Should -Invoke Write-Error -ParameterFilter {
                "$Message" -match 'defaults' -and "$Message" -match 'PowerShell'
            }
        }

        It 'does not claim the style was applied' {
            Apply-StyleDirect -StyleName 'fakeStyle' -Target 'NoSuchProfile'
            Should -Not -Invoke Write-Host -ParameterFilter { "$Object" -match 'Style applied' }
        }

        It 'leaves settings.json byte-for-byte untouched, comment included' {
            # The heart of it: no write at all, so the comment survives.
            Apply-StyleDirect -StyleName 'fakeStyle' -Target 'NoSuchProfile'
            $after = [System.IO.File]::ReadAllText($script:fakeSettings, [System.Text.UTF8Encoding]::new($false))
            $after | Should -Be $script:withComment
            $after | Should -Match "the user's own note"
        }

        It 'does not even write the rolling backup' {
            # Bailing before the backup keeps a good settings.json.bak from an
            # earlier, real apply from being overwritten by a typo.
            Apply-StyleDirect -StyleName 'fakeStyle' -Target 'NoSuchProfile'
            Test-Path -LiteralPath "$script:fakeSettings.bak" | Should -BeFalse
        }

        It 'still applies to a profile that does exist' {
            Mock Merge-StyleIntoSettings { param($Settings) $Settings }
            Mock Write-SettingsFile      {}
            Apply-StyleDirect -StyleName 'fakeStyle' -Target 'PowerShell'
            Should -Invoke Write-SettingsFile -Times 1 -Exactly
            Should -Not -Invoke Write-Error
        }

        It "still accepts the 'defaults' pseudo-target, which is never in the list" {
            Mock Merge-StyleIntoSettings { param($Settings) $Settings }
            Mock Write-SettingsFile      {}
            Apply-StyleDirect -StyleName 'fakeStyle' -Target 'defaults'
            Should -Invoke Write-SettingsFile -Times 1 -Exactly
            Should -Not -Invoke Write-Error
        }
    }
}

Describe 'picker target validation' {
    # The sibling path. Everything above has been true of `tstyles <style>
    # -Target <typo>` since 0.8.17; none of it was true of `tstyles -Target
    # <typo>`, which opens the picker. That form went on stripping every
    # comment out of settings.json, applying nothing, printing "Style applied"
    # in green and recording the style -- so `tstyles current` and the `*` in
    # `tstyles list` afterwards both named a style Windows Terminal had never
    # been told about.
    #
    # Reachable two ways, and the first is one the tool itself suggests:
    # tstyles.ps1 prints "To target a Windows Terminal profile, use: tstyles
    # -Target '<name>'" after an unknown argument. The second is the Read-Host
    # that fires when auto-detection fails, whose answer was never validated
    # either.
    #
    # Drivable from Pester because the guard sits before the picker's
    # interactive-console check, so the call returns without ever reaching the
    # keyboard loop.
    InModuleScope TerminalStyles {
        BeforeEach {
            $script:TStylesModuleRoot = $TestDrive
            $script:TStylesDataRoot   = $TestDrive
            $script:TStylesCurrent    = Join-Path $TestDrive 'current-style.ps1'

            $script:pStyleDir = Join-Path $TestDrive 'styles/fakeStyle'
            New-Item -ItemType Directory -Path $script:pStyleDir -Force | Out-Null
            [System.IO.File]::WriteAllText((Join-Path $script:pStyleDir 'scheme.json'),
                '{"name":"fakeScheme"}', [System.Text.UTF8Encoding]::new($false))

            $script:pSettings = Join-Path $TestDrive 'picker-settings.json'
            $script:pWithComment = @'
{
    // the user's own note, which the picker must never eat
    "profiles": { "list": [ { "name": "PowerShell", "guid": "{x}" } ] },
    "schemes": []
}
'@
            [System.IO.File]::WriteAllText($script:pSettings, $script:pWithComment,
                [System.Text.UTF8Encoding]::new($false))

            Mock Find-WTSettingsPath       { $script:pSettings }
            Mock Get-TerminalKind          { 'WindowsTerminal' }
            Mock Invoke-FontFirstRunPrompt {}
            Mock Test-UpdateAvailable      { $null }
            Mock Write-Host                {}
            Mock Write-Error               {}
        }

        # What this Describe can and cannot assert, since getting it wrong once
        # is how four dead tests nearly landed here.
        #
        # Under Pester, [Console]::IsInputRedirected is true, so the picker's
        # interactive-console check returns before ANY write, backup, apply
        # message or style record. Assertions like "settings.json is
        # byte-identical" or "Style applied was not printed" therefore pass just
        # as happily with the bug present -- they are measuring the console
        # guard, not the target guard. The end-to-end comment loss was
        # reproduced on a pty instead, with WT simulated through the module's
        # own WT_SESSION / WT_SETTINGS_PATH seams: settings.json went from 2
        # JSONC comments to 0, no colorScheme was written, and "Style applied:
        # eva" printed in green.
        #
        # What IS observable here is the ORDER: a bad target must lose at the
        # target guard, and a good one must get past it to the console guard.
        # That discriminates fixed from broken in both directions.

        It 'refuses a profile name that does not exist, and names the real ones' {
            Invoke-TerminalStyle -Target 'NoSuchProfile'
            Should -Invoke Write-Error -ParameterFilter {
                "$Message" -match "'NoSuchProfile' not found" -and
                "$Message" -match 'defaults' -and "$Message" -match 'PowerShell'
            }
        }

        It 'refuses it BEFORE the picker starts, not after' {
            # The discriminating half. Without the guard the bad target sails
            # past here and the run dies at the console check instead -- which
            # on a real terminal is precisely where it would NOT have stopped,
            # and the write would have happened.
            Invoke-TerminalStyle -Target 'NoSuchProfile'
            Should -Not -Invoke Write-Host -ParameterFilter {
                "$Object" -match 'needs an interactive terminal'
            } -Because 'a bad target must lose at the target guard, before the picker is reached'
        }

        It 'lets a real profile through to the picker: <target>' -ForEach @(
            @{ target = 'PowerShell' }   # a name that is in profiles.list
            @{ target = 'defaults' }     # the pseudo-target, never in the list
        ) {
            # The other direction: the guard must not reject a valid target.
            #
            # This MUST NOT run with a real console attached. A valid target is
            # passed through by design, and with nothing redirected the console
            # check below does not fire either -- so the call goes straight into
            # the live picker loop: it clears the contributor's screen, hides
            # the cursor, rewrites the window title, blocks ~12s on ReadKey and
            # applies a style. CONTRIBUTING.md tells contributors to run this
            # suite locally, so an unguarded version of this test would hijack
            # their terminal and then fail, while staying green in CI where
            # everything is redirected.
            #
            # Skipped at RUN time, not with -Skip: a -Skip condition is
            # evaluated during discovery, where this one would not yet be known.
            if (-not ([Console]::IsInputRedirected -or [Console]::IsOutputRedirected)) {
                Set-ItResult -Skipped -Because 'a real console is attached; the picker would take it over'
                return
            }

            Invoke-TerminalStyle -Target $target

            # The assertion that holds in BOTH environments: validation did not
            # reject it. Reaching the console guard is the redirected-only
            # corollary, and is what proves it got that far rather than
            # stopping earlier.
            Should -Not -Invoke Write-Error
            Should -Invoke Write-Host -ParameterFilter {
                "$Object" -match 'needs an interactive terminal'
            }
        }
    }
}
