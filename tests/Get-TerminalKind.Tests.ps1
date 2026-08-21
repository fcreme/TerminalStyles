# Pester 5 tests for Get-TerminalKind (module-private).
#
# Detection is pure env-var inspection, so every case is driven through the
# -EnvTable seam rather than by mutating the real $env: -- which would be
# order-dependent and would break the host session's own detection.
#
# Run: Invoke-Pester -Path tests
# Requires: Pester 5+

#Requires -Modules @{ ModuleName = 'Pester'; ModuleVersion = '5.0.0' }

BeforeDiscovery {
    $repoRoot = Split-Path $PSScriptRoot -Parent
    Import-Module (Join-Path $repoRoot 'TerminalStyles.psd1') -Force -DisableNameChecking *> $null
}
BeforeAll {
    $repoRoot = Split-Path $PSScriptRoot -Parent
    Import-Module (Join-Path $repoRoot 'TerminalStyles.psd1') -Force -DisableNameChecking *> $null
}

Describe 'Get-TerminalKind' {
    InModuleScope TerminalStyles {

        It 'detects Windows Terminal from WT_SESSION' {
            Get-TerminalKind -EnvTable @{ WT_SESSION = 'a-guid' } | Should -Be 'WindowsTerminal'
        }

        It 'detects Terminal.app from TERM_PROGRAM' {
            Get-TerminalKind -EnvTable @{ TERM_PROGRAM = 'Apple_Terminal' } | Should -Be 'AppleTerminal'
        }

        It 'detects iTerm2 from ITERM_SESSION_ID' {
            Get-TerminalKind -EnvTable @{ ITERM_SESSION_ID = 'w0t0p0' } | Should -Be 'ITerm2'
        }

        It 'detects iTerm2 from TERM_PROGRAM' {
            Get-TerminalKind -EnvTable @{ TERM_PROGRAM = 'iTerm.app' } | Should -Be 'ITerm2'
        }

        It 'detects Ghostty from GHOSTTY_RESOURCES_DIR' {
            Get-TerminalKind -EnvTable @{ GHOSTTY_RESOURCES_DIR = '/opt/ghostty' } | Should -Be 'Ghostty'
        }

        It 'detects WezTerm from TERM_PROGRAM' {
            Get-TerminalKind -EnvTable @{ TERM_PROGRAM = 'WezTerm' } | Should -Be 'WezTerm'
        }

        It 'detects kitty from KITTY_WINDOW_ID' {
            Get-TerminalKind -EnvTable @{ KITTY_WINDOW_ID = '1' } | Should -Be 'Kitty'
        }

        It 'detects Alacritty from ALACRITTY_WINDOW_ID' {
            Get-TerminalKind -EnvTable @{ ALACRITTY_WINDOW_ID = '1' } | Should -Be 'Alacritty'
        }

        It 'detects the VS Code integrated terminal' {
            Get-TerminalKind -EnvTable @{ TERM_PROGRAM = 'vscode' } | Should -Be 'VSCode'
        }

        It "returns 'Unknown' for a bare environment rather than guessing" {
            Get-TerminalKind -EnvTable @{} | Should -Be 'Unknown'
        }

        It "returns 'Unknown' for an unrecognized TERM_PROGRAM" {
            Get-TerminalKind -EnvTable @{ TERM_PROGRAM = 'SomeFutureTerm' } | Should -Be 'Unknown'
        }

        # Ordering matters: a Windows Terminal tab that has TERM_PROGRAM set
        # (inherited through SSH, a multiplexer, or a VS Code launch) must still
        # resolve as Windows Terminal, because WT is the host actually rendering.
        It 'prefers WT_SESSION over a conflicting TERM_PROGRAM' {
            Get-TerminalKind -EnvTable @{ WT_SESSION = 'a-guid'; TERM_PROGRAM = 'vscode' } |
                Should -Be 'WindowsTerminal'
        }

        # ITERM_SESSION_ID survives a TERM_PROGRAM clobber, so it wins over a
        # stale/foreign TERM_PROGRAM value.
        It 'prefers ITERM_SESSION_ID over a conflicting TERM_PROGRAM' {
            Get-TerminalKind -EnvTable @{ ITERM_SESSION_ID = 'w0t0p0'; TERM_PROGRAM = 'Apple_Terminal' } |
                Should -Be 'ITerm2'
        }

        It 'reads the live environment when no -EnvTable is supplied' {
            # Whatever is hosting the test run, the result must be one of the
            # known kinds -- never $null or an empty string.
            $kind = Get-TerminalKind
            $kind | Should -Not -BeNullOrEmpty
            @('WindowsTerminal','AppleTerminal','ITerm2','Ghostty','WezTerm',
              'Kitty','Alacritty','VSCode','Unknown') | Should -Contain $kind
        }
    }
}
