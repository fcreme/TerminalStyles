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
        # Not $matches: that is an automatic variable, replaced by every -match
        # in scope. Harmless as written -- the assertion follows immediately --
        # but one -match between these two lines would silently swap the
        # completion list for regex captures, and the failure would read as
        # "tab completion broke".
        $completions = (TabExpansion2 -inputScript 'tstyles res' -cursorColumn 11).CompletionMatches.CompletionText
        $completions | Should -Contain 'reset'
    }
}
