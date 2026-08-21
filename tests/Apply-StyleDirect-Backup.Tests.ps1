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

BeforeDiscovery {
    $repoRoot = Split-Path $PSScriptRoot -Parent
    Import-Module (Join-Path $repoRoot 'TerminalStyles.psd1') -Force -DisableNameChecking *> $null
}

BeforeAll {
    $repoRoot = Split-Path $PSScriptRoot -Parent
    Import-Module (Join-Path $repoRoot 'TerminalStyles.psd1') -Force -DisableNameChecking *> $null
}

Describe 'Apply-StyleDirect backup behavior' {
    InModuleScope TerminalStyles {
        BeforeEach {
            $script:TStylesModuleRoot = $TestDrive
            $script:TStylesDataRoot   = $TestDrive
            # Mock install-kind: tests for the bootstrap-only flow.
            Mock Get-TerminalStylesInstallKind { 'Bootstrap' }

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

            # Pin the terminal to Windows Terminal: these assertions are about the
            # settings.json merge path, which only runs on WT. Without this the
            # suite would take the OSC branch whenever it runs on macOS/Linux.
            Mock Find-WTSettingsPath        { $script:fakeSettings }
            Mock Get-TerminalKind { 'WindowsTerminal' }
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
