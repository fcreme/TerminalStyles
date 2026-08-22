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
        It 'never looks for a settings.json it cannot have' {
            # It used to fail here with "Could not locate Windows Terminal
            # settings.json" -- an error about a file the user was never going
            # to have. Then it refused outright, which was more conservative
            # than the facts warranted: the color knobs preview fine over OSC.
            # What must stay true is that no settings.json is touched.
            Mock Get-TerminalKind { 'AppleTerminal' }
            Mock Show-UpdateNoticeIfAvailable {}
            Mock Find-WTSettingsPath { throw 'must not look for a settings.json off Windows Terminal' }
            Mock Write-SettingsAtomic { throw 'must not write a settings.json off Windows Terminal' }
            Mock Write-Host {}
            Mock Start-Sleep {}
            # Fails on the console read rather than on settings.json -- there is
            # no keyboard in a test run. Any settings.json access would throw
            # from the mocks above instead, which is what is under test.
            try { Invoke-TerminalStyleTune -StyleName 'eva' } catch { }
            Should -Invoke Find-WTSettingsPath -Times 0
            Should -Invoke Write-SettingsAtomic -Times 0
        }

        It 'warns that opacity and font will not preview' {
            # Setting expectations matters more here than usual: two of the five
            # knobs move on screen and three do not, and a user who does not know
            # that will read the stillness as the tuner being broken.
            Mock Get-TerminalKind { 'AppleTerminal' }
            Mock Show-UpdateNoticeIfAvailable {}
            Mock Write-Host {}
            Mock Start-Sleep {}
            try { Invoke-TerminalStyleTune -StyleName 'eva' } catch { }
            Should -Invoke Write-Host -ParameterFilter { "$Object" -match 'only a new window shows them' }
        }
    }
}
