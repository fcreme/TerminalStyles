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
