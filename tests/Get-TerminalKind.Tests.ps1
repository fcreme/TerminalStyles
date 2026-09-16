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

        # ...and WezTerm's own markers must survive the same inheritance, which
        # they did not: WezTerm was identified by TERM_PROGRAM alone, BELOW the
        # ITERM_SESSION_ID gate, while exporting three unambiguous variables the
        # function never read. Any session carrying an inherited ITERM_SESSION_ID
        # -- a tmux server whose environment was captured under iTerm2, ssh with
        # SendEnv, a WezTerm window launched from an iTerm2 shell -- resolved to
        # 'ITerm2'.
        #
        # Measured on 0.8.28 through a real child-process environment, not just
        # this seam: with ITERM_SESSION_ID set alongside TERM_PROGRAM=WezTerm and
        # WEZTERM_PANE, the kind came back 'ITerm2' with Persist/Font/Padding/
        # BackgroundImage all $false -- so Publish-StyleWezTermConfig returned at
        # its `if ($Kind -ne 'WezTerm')` guard, wrote no Lua module, and printed
        # nothing. kitty, Alacritty and Ghostty were already protected by
        # own-marker checks placed above that gate; WezTerm, the one terminal off
        # Windows with a config writer, was not.
        It 'prefers <_> over an inherited ITERM_SESSION_ID' -ForEach @(
            'WEZTERM_PANE', 'WEZTERM_EXECUTABLE', 'WEZTERM_UNIX_SOCKET') {
            # Not named $env: that is the provider drive every other variable
            # here is deliberately avoiding.
            $table = @{ ITERM_SESSION_ID = 'w0t0p0:F1C2'; TERM_PROGRAM = 'WezTerm' }
            $table[$_] = '0'
            Get-TerminalKind -EnvTable $table | Should -Be 'WezTerm'
        }

        It 'still answers ITerm2 when only iTerm2 markers are present' {
            # The counterweight: the new check must not swallow a real iTerm2
            # session. Nothing here sets a WEZTERM_* variable.
            Get-TerminalKind -EnvTable @{ ITERM_SESSION_ID = 'w0t0p0'; TERM_PROGRAM = 'iTerm.app' } |
                Should -Be 'ITerm2'
        }

        It 'still lets Windows Terminal win over a WezTerm marker' {
            # WT_SESSION stays first: WT is the host actually rendering, and a
            # WEZTERM_* variable can be inherited into a WT tab exactly as
            # ITERM_SESSION_ID can.
            Get-TerminalKind -EnvTable @{ WT_SESSION = 'a-guid'; WEZTERM_PANE = '0' } |
                Should -Be 'WindowsTerminal'
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
