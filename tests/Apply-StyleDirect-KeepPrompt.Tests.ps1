# Pester 5 tests for Apply-StyleDirect -KeepPrompt: applies visuals but does
# not install the style's prompt (clears current-style.ps1 instead).
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

Describe 'Apply-StyleDirect -KeepPrompt' {
    InModuleScope TerminalStyles {
        BeforeEach {
            $script:TStylesModuleRoot = $TestDrive
            $script:TStylesDataRoot   = $TestDrive
            # $script:TStylesCurrent is computed at module load from the REAL
            # data root, so override it explicitly to a TestDrive path.
            $script:TStylesCurrent    = Join-Path $TestDrive 'current-style.ps1'

            Mock Get-TerminalStylesInstallKind { 'Bootstrap' }

            $script:fakeSettings = Join-Path $TestDrive 'fake-settings.json'
            [System.IO.File]::WriteAllText($script:fakeSettings,
                '{"profiles":{"list":[{"name":"PowerShell","guid":"{x}"}]}}',
                [System.Text.UTF8Encoding]::new($false))

            $script:styleDir = Join-Path $TestDrive 'styles\fakeStyle'
            New-Item -ItemType Directory -Path $script:styleDir -Force | Out-Null
            [System.IO.File]::WriteAllText((Join-Path $script:styleDir 'scheme.json'),
                '{"name":"fakeScheme"}', [System.Text.UTF8Encoding]::new($false))
            [System.IO.File]::WriteAllText((Join-Path $script:styleDir 'profile.ps1'),
                '# fakeStyle prompt', [System.Text.UTF8Encoding]::new($false))

            # Pin the terminal to Windows Terminal: these assertions are about the
            # settings.json merge path, which only runs on WT. Without this the
            # suite would take the OSC branch whenever it runs on macOS/Linux.
            Mock Find-WTSettingsPath          { $script:fakeSettings }
            Mock Get-TerminalKind { 'WindowsTerminal' }
            Mock Show-UpdateNoticeIfAvailable {}
            Mock Merge-StyleIntoSettings      { param($Settings) $Settings }
            Mock Write-SettingsFile           {}
        }

        # -Target 'defaults' makes $isPwshTarget true (so the prompt block runs)
        # without needing a pwsh-flavored profile entry.

        It 'with -KeepPrompt: does NOT copy the style profile to current-style.ps1' {
            Apply-StyleDirect -StyleName 'fakeStyle' -Target 'defaults' -KeepPrompt
            Test-Path -LiteralPath $script:TStylesCurrent | Should -BeFalse
        }
        It 'with -KeepPrompt: removes an existing current-style.ps1' {
            [System.IO.File]::WriteAllText($script:TStylesCurrent, '# old prompt',
                [System.Text.UTF8Encoding]::new($false))
            Apply-StyleDirect -StyleName 'fakeStyle' -Target 'defaults' -KeepPrompt
            Test-Path -LiteralPath $script:TStylesCurrent | Should -BeFalse
        }
        It 'with -KeepPrompt: still applies the visuals (Merge + Write run)' {
            Apply-StyleDirect -StyleName 'fakeStyle' -Target 'defaults' -KeepPrompt
            Should -Invoke Merge-StyleIntoSettings -Times 1
            Should -Invoke Write-SettingsFile -Times 1
        }
        It 'WITHOUT -KeepPrompt: copies the style profile to current-style.ps1 (regression)' {
            Apply-StyleDirect -StyleName 'fakeStyle' -Target 'defaults'
            Test-Path -LiteralPath $script:TStylesCurrent | Should -BeTrue
            (Get-Content -LiteralPath $script:TStylesCurrent -Raw).Trim() | Should -Be '# fakeStyle prompt'
        }
    }
}
