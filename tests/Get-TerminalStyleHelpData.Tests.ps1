# Pester 5 tests for Get-TerminalStyleHelpData (the help data: single source
# of truth). Drift guard: every dispatched subcommand must have an entry.
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
            # Canonical dispatched subcommands. 'ls' is an alias of 'list' and is
            # NOT a separate topic, so it is intentionally excluded.
            $dispatched = @('list','current','random','tune','register','update','uninstall','help')
            $topics = (Get-TerminalStyleHelpData).Name
            foreach ($cmd in $dispatched) { $topics | Should -Contain $cmd }
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
