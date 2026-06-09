# Pester 5 tests: Windows Terminal settings.json discovery must honor the live
# build's path before the static candidate list.
#
# Regression guard: Find-WTSettingsPath (module) and Find-SettingsPath (apply.ps1)
# returned the first existing path from a fixed Stable > Preview > unpackaged list,
# so a user running WT Preview (with Stable also installed) had every
# apply/reset/tune/picker operation silently mutate STABLE's settings.json. WT
# sets $env:WT_SETTINGS_PATH to the live session's settings.json; honor it first.
# Run: Invoke-Pester -Path tests
#Requires -Modules @{ ModuleName = 'Pester'; ModuleVersion = '5.0.0' }

Describe 'Find-WTSettingsPath (module)' {
    BeforeAll {
        $repoRoot = Split-Path $PSScriptRoot -Parent
        Import-Module (Join-Path $repoRoot 'TerminalStyles.psd1') -Force -DisableNameChecking *> $null
    }
    BeforeEach { $script:savedWtsp = $env:WT_SETTINGS_PATH }
    AfterEach  { $env:WT_SETTINGS_PATH = $script:savedWtsp }

    It 'prefers $env:WT_SETTINGS_PATH when it points at an existing file' {
        $live = Join-Path $TestDrive 'live-settings.json'
        [System.IO.File]::WriteAllText($live, '{}', [System.Text.UTF8Encoding]::new($false))
        $env:WT_SETTINGS_PATH = $live
        (InModuleScope TerminalStyles { Find-WTSettingsPath }) | Should -Be $live
    }

    It 'ignores $env:WT_SETTINGS_PATH when the file does not exist' {
        $env:WT_SETTINGS_PATH = Join-Path $TestDrive 'does-not-exist.json'
        $result = InModuleScope TerminalStyles { Find-WTSettingsPath }
        $result | Should -Not -Be $env:WT_SETTINGS_PATH
    }
}

Describe 'apply.ps1 Find-SettingsPath' {
    BeforeAll {
        $script:applyPath = Join-Path (Split-Path $PSScriptRoot -Parent) 'apply.ps1'
        $TStylesApplyNoRun = $true
        . $script:applyPath
    }
    BeforeEach { $script:savedWtsp = $env:WT_SETTINGS_PATH }
    AfterEach  { $env:WT_SETTINGS_PATH = $script:savedWtsp }

    It 'prefers $env:WT_SETTINGS_PATH when it points at an existing file' {
        $live = Join-Path $TestDrive 'live2.json'
        [System.IO.File]::WriteAllText($live, '{}', [System.Text.UTF8Encoding]::new($false))
        $env:WT_SETTINGS_PATH = $live
        Find-SettingsPath | Should -Be $live
    }
}
