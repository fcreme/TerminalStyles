# Pester 5 tests: `tstyles tune <name>` routes to Invoke-TerminalStyleTune
# with the right style name, and the tab completer offers 'tune'.
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

Describe 'tstyles tune dispatch' {
    InModuleScope TerminalStyles {
        It 'routes `tune <name>` to Invoke-TerminalStyleTune with the style name' {
            Mock Invoke-TerminalStyleTune {}
            Mock Show-UpdateNoticeIfAvailable {}
            Invoke-TerminalStyle -Arg 'tune' -SubArg 'eva'
            Should -Invoke Invoke-TerminalStyleTune -Times 1 -ParameterFilter { $StyleName -eq 'eva' }
        }
        It 'routes bare `tune` with no name' {
            Mock Invoke-TerminalStyleTune {}
            Mock Show-UpdateNoticeIfAvailable {}
            Invoke-TerminalStyle -Arg 'tune'
            Should -Invoke Invoke-TerminalStyleTune -Times 1
        }
    }
}

Describe 'tstyles tune tab completion' {
    It "offers 'tune' as a subcommand" {
        $repoRoot = Split-Path $PSScriptRoot -Parent
        Import-Module (Join-Path $repoRoot 'TerminalStyles.psd1') -Force -DisableNameChecking *> $null
        $matches = (TabExpansion2 -inputScript 'tstyles tun' -cursorColumn 11).CompletionMatches.CompletionText
        $matches | Should -Contain 'tune'
    }
}
