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
        # Not $matches: that is an automatic variable, replaced by every -match
        # in scope. Harmless as written -- the assertion follows immediately --
        # but one -match between these two lines would silently swap the
        # completion list for regex captures, and the failure would read as
        # "tab completion broke".
        $completions = (TabExpansion2 -inputScript 'tstyles hel' -cursorColumn 11).CompletionMatches.CompletionText
        $completions | Should -Contain 'help'
    }
}

Describe 'tstyles unknown-arg fallback' {
    InModuleScope TerminalStyles {
        It 'shows help and does NOT open the picker for an unknown arg' {
            Mock Show-TerminalStyleHelp {}
            Mock Show-UpdateNoticeIfAvailable {}
            Mock Get-AvailableStyles { @() }   # nothing matches the arg
            # Pin the terminal to Windows Terminal: these assertions are about the
            # settings.json merge path, which only runs on WT. Without this the
            # suite would take the OSC branch whenever it runs on macOS/Linux.
            Mock Find-WTSettingsPath { throw 'picker path must not be reached' }
            Mock Get-TerminalKind { 'WindowsTerminal' }
            { Invoke-TerminalStyle -Arg 'definitely-not-a-real-thing' } | Should -Not -Throw
            Should -Invoke Show-TerminalStyleHelp -Times 1
            Should -Not -Invoke Find-WTSettingsPath
        }
    }
}
