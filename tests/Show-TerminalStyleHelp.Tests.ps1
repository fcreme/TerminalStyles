# Pester 5 tests for Show-TerminalStyleHelp (overview + per-command detail).
# Write-Host output is captured via the information stream (6>&1).
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

Describe 'Show-TerminalStyleHelp' {
    InModuleScope TerminalStyles {
        It 'overview lists every command name' {
            $out = Show-TerminalStyleHelp 6>&1 | Out-String
            foreach ($name in (Get-TerminalStyleHelpData).Name) {
                $out | Should -Match ([regex]::Escape($name))
            }
        }
        It 'overview shows USAGE and the docs link' {
            $out = Show-TerminalStyleHelp 6>&1 | Out-String
            $out | Should -Match 'USAGE'
            $out | Should -Match 'github\.com/fcreme/TerminalStyles'
        }
        It 'help <command> shows that command''s detail' {
            $out = Show-TerminalStyleHelp -Command 'tune' 6>&1 | Out-String
            $out | Should -Match 'brightness'
            $out | Should -Match 'Esc'
        }
        It 'command lookup is case-insensitive' {
            $out = Show-TerminalStyleHelp -Command 'TUNE' 6>&1 | Out-String
            $out | Should -Match 'brightness'
        }
        It 'unknown topic shows a not-found message and lists topics' {
            $out = Show-TerminalStyleHelp -Command 'frobnicate' 6>&1 | Out-String
            $out | Should -Match "No help topic 'frobnicate'"
            $out | Should -Match 'tune'
        }
        It 'renders a command with no KEYS (e.g. list) without error' {
            $out = Show-TerminalStyleHelp -Command 'list' 6>&1 | Out-String
            $out | Should -Match 'tstyles list'
            $out | Should -Match 'asterisk'   # from list's Detail
            $out | Should -Not -Match 'KEYS'  # list has Keys = @(), so no KEYS section
        }
    }
}
