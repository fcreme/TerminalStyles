#Requires -Modules @{ ModuleName = 'Pester'; ModuleVersion = '5.0.0' }

BeforeDiscovery {
    $repoRoot = Split-Path $PSScriptRoot -Parent
    Import-Module (Join-Path $repoRoot 'TerminalStyles.psd1') -Force -DisableNameChecking *> $null
}
BeforeAll {
    $repoRoot = Split-Path $PSScriptRoot -Parent
    Import-Module (Join-Path $repoRoot 'TerminalStyles.psd1') -Force -DisableNameChecking *> $null
}

Describe 'Test-ShouldPromptFonts' {
    InModuleScope TerminalStyles {
        It 'prompts only when interactive and not previously prompted' {
            Test-ShouldPromptFonts -MarkerPresent $false -Interactive $true  | Should -BeTrue
            Test-ShouldPromptFonts -MarkerPresent $true  -Interactive $true  | Should -BeFalse
            Test-ShouldPromptFonts -MarkerPresent $false -Interactive $false | Should -BeFalse
            Test-ShouldPromptFonts -MarkerPresent $true  -Interactive $false | Should -BeFalse
        }
    }
}
