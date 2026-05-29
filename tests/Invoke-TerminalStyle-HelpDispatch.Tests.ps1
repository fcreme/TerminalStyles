# Pester 5 tests: `tstyles help [command]` routes to Show-TerminalStyleHelp,
# and the tab completer offers 'help'.
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

Describe 'tstyles help dispatch' {
    InModuleScope TerminalStyles {
        It 'routes bare `help` to Show-TerminalStyleHelp with no command' {
            Mock Show-TerminalStyleHelp {}
            Mock Show-UpdateNoticeIfAvailable {}
            Invoke-TerminalStyle -Arg 'help'
            Should -Invoke Show-TerminalStyleHelp -Times 1 -ParameterFilter { -not $Command }
        }
        It 'routes `help <command>` with the command name' {
            Mock Show-TerminalStyleHelp {}
            Mock Show-UpdateNoticeIfAvailable {}
            Invoke-TerminalStyle -Arg 'help' -SubArg 'tune'
            Should -Invoke Show-TerminalStyleHelp -Times 1 -ParameterFilter { $Command -eq 'tune' }
        }
    }
}

Describe 'tstyles help tab completion' {
    It "offers 'help' as a subcommand" {
        $repoRoot = Split-Path $PSScriptRoot -Parent
        Import-Module (Join-Path $repoRoot 'TerminalStyles.psd1') -Force -DisableNameChecking *> $null
        $matches = (TabExpansion2 -inputScript 'tstyles hel' -cursorColumn 11).CompletionMatches.CompletionText
        $matches | Should -Contain 'help'
    }
}
