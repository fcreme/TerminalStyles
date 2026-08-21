# Pester 5 tests for Invoke-TerminalStyleTune guard paths (pre-loop).
# The interactive key loop itself is verified manually (like the picker).
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

Describe 'Invoke-TerminalStyleTune guards' {
    InModuleScope TerminalStyles {
        BeforeEach {
            # The tuner writes opacity and font into settings.json, so it is
            # Windows-Terminal-only and returns early elsewhere with an
            # explanation. These tests are about the guards PAST that point, so
            # pin the terminal -- otherwise they assert nothing on macOS/Linux.
            Mock Get-TerminalKind { 'WindowsTerminal' }
        }

        It 'errors when no style name is given and no active style exists' {
            Mock Get-CurrentStyleName { $null }
            Mock Show-UpdateNoticeIfAvailable {}
            Mock Write-Error {}
            Invoke-TerminalStyleTune
            Should -Invoke Write-Error -Times 1 -ParameterFilter { "$Message" -match 'No active style' }
        }
        It 'errors when the named style cannot be resolved' {
            Mock Get-StyleDir { $null }
            Mock Show-UpdateNoticeIfAvailable {}
            Mock Write-Error {}
            Invoke-TerminalStyleTune -StyleName 'nope'
            Should -Invoke Write-Error -Times 1 -ParameterFilter { "$Message" -match "not found" }
        }
        It 'errors when settings.json cannot be located' {
            Mock Get-StyleDir { $TestDrive }
            # Pin the terminal to Windows Terminal: these assertions are about the
            # settings.json merge path, which only runs on WT. Without this the
            # suite would take the OSC branch whenever it runs on macOS/Linux.
            Mock Find-WTSettingsPath { $null }
            Mock Get-TerminalKind { 'WindowsTerminal' }
            Mock Show-UpdateNoticeIfAvailable {}
            Mock Write-Error {}
            # Provide a scheme.json so the base load would succeed past resolution.
            [System.IO.File]::WriteAllText((Join-Path $TestDrive 'scheme.json'), '{"name":"x"}', [System.Text.UTF8Encoding]::new($false))
            Invoke-TerminalStyleTune -StyleName 'x'
            Should -Invoke Write-Error -Times 1 -ParameterFilter { "$Message" -match 'settings.json' }
        }
    }
}

Describe 'Invoke-TerminalStyleTune outside Windows Terminal' {
    InModuleScope TerminalStyles {
        It 'explains why instead of failing to find a settings.json' {
            # The old behaviour surfaced "Could not locate Windows Terminal
            # settings.json" on a Mac -- an error about a file the user was
            # never going to have, and no hint that the command simply does not
            # apply there.
            Mock Get-TerminalKind { 'AppleTerminal' }
            Mock Show-UpdateNoticeIfAvailable {}
            Mock Find-WTSettingsPath { throw 'must not look for a settings.json off Windows Terminal' }
            Mock Write-Host {}
            { Invoke-TerminalStyleTune -StyleName 'eva' } | Should -Not -Throw
            Should -Invoke Write-Host -ParameterFilter { "$Object" -match 'needs Windows Terminal' }
        }
    }
}
