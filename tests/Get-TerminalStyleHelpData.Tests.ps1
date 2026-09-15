# Pester 5 tests for Get-TerminalStyleHelpData (the help data: single source
# of truth). Drift guard: every dispatched subcommand must have an entry, and
# every entry must name a dispatched subcommand. The list comes from the module
# (tstyles.ps1's $script:TStylesSubcommands); a copy typed in here is the thing
# that went ten-of-fourteen behind without a test ever going red.
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

Describe 'Get-TerminalStyleHelpData' {
    InModuleScope TerminalStyles {
        It 'has a help entry for every dispatched subcommand' {
            # Read the canonical list rather than keeping a third copy of it.
            # tstyles.ps1 owns $script:TStylesSubcommands, the completer and
            # Test-StyleNameValid already read it, and the literal that used to
            # stand here was the copy that drifted: it named ten of the fourteen,
            # so `delete`, `profiles`, `shell-init` and `shell-remove` -- and any
            # subcommand added after it was typed -- could ship undocumented and
            # this assertion, the one the file header calls the drift guard,
            # still passed. 'ls' is an alias of 'list' and is NOT a separate
            # topic, so it is the one name excluded.
            $dispatched = @($script:TStylesSubcommands | Where-Object { $_ -ne 'ls' })
            $dispatched.Count | Should -BeGreaterThan 1 -Because 'an empty list would assert nothing'
            $topics = (Get-TerminalStyleHelpData).Name
            foreach ($cmd in $dispatched) { $topics | Should -Contain $cmd }

            # The other half of the same symmetry: a topic for a command the
            # dispatcher no longer runs is help describing a command that does
            # not exist, which is the same defect pointing the other way.
            $topics | Where-Object { $_ -notin $dispatched } | Should -BeNullOrEmpty `
                -Because 'every help topic must name a subcommand that still dispatches'
        }
        It 'gives every entry a Name, Usage, and Summary' {
            foreach ($e in (Get-TerminalStyleHelpData)) {
                $e.Name    | Should -Not -BeNullOrEmpty
                $e.Usage   | Should -Not -BeNullOrEmpty
                $e.Summary | Should -Not -BeNullOrEmpty
            }
        }
        It 'the tune entry carries KEYS and EXAMPLES' {
            $tune = (Get-TerminalStyleHelpData) | Where-Object Name -eq 'tune'
            $tune.Keys     | Should -Not -BeNullOrEmpty
            $tune.Examples | Should -Contain 'tstyles tune eva'
        }
    }
}
